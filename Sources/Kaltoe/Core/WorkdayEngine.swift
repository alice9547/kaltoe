// 출근 시각을 감지·저장하고 매초 store.snapshot 을 갱신한다.
// 판단 로직은 ClockInRules / SnapshotCalculator / PmsetRecovery 의 순수 함수에 있고,
// 이 클래스는 이벤트를 받아 상태를 들고 그 함수들을 부르는 얇은 배선이다.
// TODO(conductor): [A↔B] App.swift 가 start() 를 부르면 store.snapshot 이 매초 갱신됨 — 통합 때 실제 화면에서 확인
import AppKit

final class WorkdayEngine {
    /// 시스템 의존 지점. 기본값이 실제 구현이고, 테스트는 가짜를 주입한다.
    struct Environment {
        var now: () -> Date = { Date() }
        var calendar: Calendar = .autoupdatingCurrent
        var defaults: UserDefaults = .standard
        var isScreenLocked: () -> Bool = SystemInfo.isScreenLocked
        /// 사후 복구. 결과(실패·타임아웃이면 nil)를 메인 스레드에서 completion 으로 돌려준다.
        var recover: (_ nineAM: Date, _ now: Date, _ completion: @escaping (Date?) -> Void) -> Void
            = PmsetRecovery.runLive
        var requestNotificationAuthorization: () -> Void = { NotificationService.shared.requestAuthorization() }
        var scheduleNotifications: (_ plans: [PlannedNotification], _ calendar: Calendar) -> Void
            = { NotificationService.shared.schedule($0, calendar: $1) }
    }

    private let store: WorkdayStore
    private let env: Environment
    private let storage: ClockInStorage

    // 상태 (메인 스레드에서만 접근)
    private var dayKey = ""
    private var clockIn: Date?
    private var activation: Date
    private var isLocked = false
    private var launchedAt: Date
    private var lastTick: Date
    /// 사후 복구가 끝나기 전에는 규칙 2 로 "지금"을 기록하지 않는다.
    private var recoveryPendingForDay: String?

    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    convenience init(store: WorkdayStore) {
        self.init(store: store, environment: Environment())
    }

    init(store: WorkdayStore, environment: Environment) {
        self.store = store
        self.env = environment
        self.storage = ClockInStorage(defaults: environment.defaults, calendar: environment.calendar)
        let now = environment.now()
        self.activation = now
        self.launchedAt = now
        self.lastTick = now
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
        launchedAt = now
        activation = now
        lastTick = now
        isLocked = env.isScreenLocked()
        dayKey = ClockInRules.dayKey(now, calendar: env.calendar)

        storage.purge(now: now)
        env.requestNotificationAuthorization()

        clockIn = ClockInRules.validRecord(storage.load(for: now), now: now, calendar: env.calendar)
        if let clockIn {
            // 같은 식별자로 덮어쓰므로 다시 불러도 중복 예약이 생기지 않는다.
            scheduleNotifications(clockIn: clockIn, now: now)
        } else if now >= ClockInRules.earliestClockIn(on: now, calendar: env.calendar) {
            startRecovery(now: now)
        }
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
        clockIn = ClockInRules.validRecord(storage.load(for: now), now: now, calendar: env.calendar)
        recoveryPendingForDay = nil   // 진행 중이던 복구는 지난 날 것 — 결과가 와도 버린다.
        storage.purge(now: now)
    }

    /// 규칙 2·3·4: 기록이 없고 복구도 대기 중이 아니면 지금 기록할지 판단.
    private func evaluate(now: Date) {
        guard clockIn == nil, recoveryPendingForDay == nil else { return }
        if let t = ClockInRules.decide(now: now, activation: activation,
                                       isLocked: isLocked, calendar: env.calendar) {
            record(t, now: now)
        }
    }

    /// 규칙 1: 하루 하나, 한번 정해지면 바뀌지 않는다.
    private func record(_ t: Date, now: Date) {
        guard clockIn == nil else { return }
        guard storage.saveIfAbsent(t) else {
            clockIn = storage.load(for: t)   // 다른 경로로 이미 저장됨 — 그 값을 따른다.
            return
        }
        clockIn = t
        scheduleNotifications(clockIn: t, now: now)
    }

    private func scheduleNotifications(clockIn: Date, now: Date) {
        let plans = NotificationPlanner.plan(clockIn: clockIn, now: now, calendar: env.calendar)
        env.scheduleNotifications(plans, env.calendar)
    }

    // MARK: - 사후 복구 (규칙 6)

    private func startRecovery(now: Date) {
        let day = dayKey
        let nine = ClockInRules.earliestClockIn(on: now, calendar: env.calendar)
        recoveryPendingForDay = day
        env.recover(nine, now) { [weak self] result in
            self?.finishRecovery(day: day, nineAM: nine, result: result)
        }
    }

    /// 메인 스레드에서 호출된다.
    func finishRecovery(day: String, nineAM: Date, result: Date?) {
        // 그 사이 날이 바뀌었으면(진행 중 표시가 지워졌으면) 버린다.
        guard recoveryPendingForDay == day else { return }
        recoveryPendingForDay = nil
        let now = env.now()
        defer { publish(now: now) }
        // 실시간 감지가 먼저 기록했다면 복구 결과는 버린다 (record 의 가드가 처리).
        // 실패·타임아웃이면 max(오늘 9시, 앱 실행 시각).
        let t = result ?? max(nineAM, launchedAt)
        record(t, now: now)
    }

    // MARK: - 출력

    private func publish(now: Date) {
        store.snapshot = SnapshotCalculator.make(clockIn: clockIn, now: now)
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
