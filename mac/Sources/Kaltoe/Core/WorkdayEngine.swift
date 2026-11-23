// 출근 시각을 감지·저장하고 매초 store.snapshot 을 갱신한다.
// 판단 로직은 ClockInRules / DaySchedule / SnapshotCalculator / PmsetRecovery 의 순수 함수에 있고,
// 이 클래스는 이벤트·설정 변경을 받아 상태를 들고 그 함수들을 부르는 얇은 배선이다.
import AppKit
import Combine

final class WorkdayEngine {
    /// 시스템 의존 지점. 기본값이 실제 구현이고, 테스트는 가짜를 주입한다.
    struct Environment {
        var now: () -> Date = { Date() }
        var calendar: Calendar = .autoupdatingCurrent
        var defaults: UserDefaults = .standard
        var isScreenLocked: () -> Bool = SystemInfo.isScreenLocked
        /// 사후 복구. 결과(실패·타임아웃이면 nil)를 메인 스레드에서 completion 으로 돌려준다.
        var recover: (_ earliestStart: Date, _ now: Date, _ completion: @escaping (Date?) -> Void) -> Void
            = PmsetRecovery.runLive
        var requestNotificationAuthorization: () -> Void = { NotificationService.shared.requestAuthorization() }
        /// 그날(day) 예약을 모두 취소하고 plans 를 다시 예약한다.
        var replaceNotifications: (_ day: String, _ plans: [PlannedNotification], _ calendar: Calendar) -> Void
            = { NotificationService.shared.replace(day: $0, with: $1, calendar: $2) }
    }

    private let store: WorkdayStore
    private let settingsStore: SettingsStore
    private let env: Environment
    private let storage: ClockInStorage

    // 상태 (메인 스레드에서만 접근)
    private var settings: WorkSettings
    private var dayKey = ""
    /// 유동 모드의 오늘 출근 기록. 고정 모드에서는 쓰지 않는다 (저장된 기록은 그대로 둔다).
    private var detectedClockIn: Date?
    private var activation: Date
    private var isLocked = false
    private var launchedAt: Date
    private var lastTick: Date
    /// 사후 복구가 끝나기 전에는 규칙 2 로 "지금"을 기록하지 않는다.
    private var recoveryPendingForDay: String?
    private var recoveryGeneration = 0
    private var started = false

    private var timer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    convenience init(store: WorkdayStore, settings: SettingsStore) {
        self.init(store: store, settings: settings, environment: Environment())
    }

    init(store: WorkdayStore, settings: SettingsStore, environment: Environment) {
        self.store = store
        self.settingsStore = settings
        self.env = environment
        self.settings = settings.settings
        self.storage = ClockInStorage(defaults: environment.defaults, calendar: environment.calendar)
        let now = environment.now()
        self.activation = now
        self.launchedAt = now
        self.lastTick = now
        // 설정이 바뀌면 즉시 다시 계산하고 알림을 다시 예약한다.
        settingsCancellable = settings.$settings.dropFirst().sink { [weak self] new in
            self?.applySettings(new)
        }
    }

    deinit {
        timer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    /// 감지와 1초 타이머를 시작한다. 메인 스레드에서 호출.
    func start() {
        bootstrap()
        installObservers()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 시작 처리

    func bootstrap() {
        let now = env.now()
        started = true
        settings = settingsStore.settings
        launchedAt = now
        activation = now
        lastTick = now
        isLocked = env.isScreenLocked()
        dayKey = ClockInRules.dayKey(now, calendar: env.calendar)

        storage.purge(now: now)
        env.requestNotificationAuthorization()

        if settings.mode == .flexible {
            loadRecordAndMaybeRecover(now: now)
        }
        refreshNotifications(now: now)
        publish(now: now)
    }

    /// 유동 모드: 오늘 기록을 읽고, 없고 earliestStart 이후면 사후 복구를 시작한다.
    private func loadRecordAndMaybeRecover(now: Date) {
        detectedClockIn = ClockInRules.validRecord(storage.load(for: now), now: now, calendar: env.calendar)
        if detectedClockIn == nil, now >= earliestStartToday(now) {
            startRecovery(now: now)
        }
    }

    private func earliestStartToday(_ now: Date) -> Date {
        ClockInRules.earliestClockIn(on: now, earliestStart: settings.earliestStart, calendar: env.calendar)
    }

    // MARK: - 설정 변경

    func applySettings(_ new: WorkSettings) {
        let old = settings
        settings = new
        guard started else { return }
        let now = env.now()

        if old.mode != new.mode {
            switch new.mode {
            case .fixed:
                // 고정 모드는 감지·복구를 하지 않는다. 진행 중이던 복구 결과는 버린다.
                recoveryPendingForDay = nil
            case .flexible:
                loadRecordAndMaybeRecover(now: now)
            }
        }
        if new.mode == .flexible { evaluate(now: now) }   // earliestStart 가 바뀌었을 수 있다
        refreshNotifications(now: now)
        publish(now: now)
    }

    // MARK: - 오늘 출근 다시 감지 (spec 2절 8번)

    /// 오늘 기록을 지우고 규칙 6(사후 복구)부터 다시 수행한다. 유동 모드에서만 동작.
    func redetectToday() {
        guard settings.mode == .flexible, recoveryPendingForDay == nil else { return }
        let now = env.now()
        syncDay(now: now)
        storage.remove(for: now)
        detectedClockIn = nil
        startRecovery(now: now)
        refreshNotifications(now: now)   // 지워진 출근 기준의 예약을 취소
        publish(now: now)
    }

    // MARK: - 이벤트

    /// 맥을 쓰기 시작함 (깨어남·세션 활성화·잠금 해제).
    func noteActivation() {
        let now = env.now()
        activation = now
        tick(now: now, countsAsTimerTick: false)
    }

    /// 잠자기 깨어남 계열 — 잠금 상태는 알림이 늦을 수 있으니 시스템에서 다시 읽는다.
    func noteWake() {
        isLocked = env.isScreenLocked()
        noteActivation()
    }

    func noteScreenLocked() {
        isLocked = true
        tick(now: env.now(), countsAsTimerTick: false)
    }

    func noteScreenUnlocked() {
        isLocked = false
        noteActivation()
    }

    func tick() {
        tick(now: env.now(), countsAsTimerTick: true)
    }

    private func tick(now: Date, countsAsTimerTick: Bool) {
        if countsAsTimerTick {
            // 타이머가 2초 이상 건너뜀 = 잠자기 후. 그 순간부터 쓰기 시작한 것으로 본다.
            if now.timeIntervalSince(lastTick) >= 2 {
                activation = now
                isLocked = env.isScreenLocked()
            }
            lastTick = now
        }
        syncDay(now: now)
        evaluate(now: now)
        publish(now: now)
    }

    // MARK: - 상태 전이

    /// 규칙 5: 날짜가 바뀌면 전날 기록을 버리고 새 날로 시작한다.
    private func syncDay(now: Date) {
        let key = ClockInRules.dayKey(now, calendar: env.calendar)
        guard key != dayKey else { return }
        dayKey = key
        detectedClockIn = settings.mode == .flexible
            ? ClockInRules.validRecord(storage.load(for: now), now: now, calendar: env.calendar) : nil
        recoveryPendingForDay = nil   // 진행 중이던 복구는 지난 날 것 — 결과가 와도 버린다.
        storage.purge(now: now)
        refreshNotifications(now: now)   // 고정 모드는 새 날 알림을 여기서 예약
    }

    /// 규칙 2·3·4: 유동 모드에서 기록이 없고 복구도 대기 중이 아니면 지금 기록할지 판단.
    private func evaluate(now: Date) {
        guard settings.mode == .flexible, detectedClockIn == nil, recoveryPendingForDay == nil else { return }
        if let t = ClockInRules.decide(now: now, activation: activation, isLocked: isLocked,
                                       earliestStart: settings.earliestStart, calendar: env.calendar) {
            record(t, now: now)
        }
    }

    /// 규칙 1: 하루 하나, 한번 정해지면 바뀌지 않는다 (다시 감지는 먼저 지운다).
    private func record(_ t: Date, now: Date) {
        guard detectedClockIn == nil else { return }
        guard storage.saveIfAbsent(t) else {
            detectedClockIn = storage.load(for: t)   // 다른 경로로 이미 저장됨 — 그 값을 따른다.
            return
        }
        detectedClockIn = t
        refreshNotifications(now: now)
    }

    private func times(at now: Date) -> DaySchedule.Times {
        DaySchedule.times(settings: settings, detectedClockIn: detectedClockIn,
                          now: now, calendar: env.calendar)
    }

    /// 그날 알림을 취소하고 현재 설정·출근 기록 기준으로 다시 예약한다.
    private func refreshNotifications(now: Date) {
        let plans = NotificationPlanner.plan(times: times(at: now), settings: settings,
                                             now: now, calendar: env.calendar)
        env.replaceNotifications(ClockInRules.dayKey(now, calendar: env.calendar), plans, env.calendar)
    }

    // MARK: - 사후 복구 (규칙 6)

    private func startRecovery(now: Date) {
        let day = dayKey
        let earliest = earliestStartToday(now)
        recoveryGeneration += 1
        let generation = recoveryGeneration
        recoveryPendingForDay = day
        env.recover(earliest, now) { [weak self] result in
            self?.finishRecovery(day: day, generation: generation, earliest: earliest, result: result)
        }
    }

    /// 메인 스레드에서 호출된다.
    func finishRecovery(day: String, generation: Int, earliest: Date, result: Date?) {
        // 날이 바뀌었거나, 고정 모드로 바뀌었거나, 그 뒤 새 복구가 시작됐으면 버린다.
        guard recoveryPendingForDay == day, generation == recoveryGeneration else { return }
        recoveryPendingForDay = nil
        let now = env.now()
        defer { publish(now: now) }
        // 실패·타임아웃이면 max(earliestStart, 앱 실행 시각). 이미 기록이 있으면 record 가 버린다.
        record(result ?? max(earliest, launchedAt), now: now)
    }

    // MARK: - 출력

    private func publish(now: Date) {
        store.snapshot = SnapshotCalculator.make(now: now, times: times(at: now))
    }

    // MARK: - 시스템 이벤트 연결

    private func installObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.noteWake()
            })
        }
        let dc = DistributedNotificationCenter.default()
        distributedObservers.append(dc.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.noteScreenUnlocked()
        })
        distributedObservers.append(dc.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.noteScreenLocked()
        })
    }
}
