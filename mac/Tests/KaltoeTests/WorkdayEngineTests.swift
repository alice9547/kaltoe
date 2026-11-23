import XCTest
@testable import Kaltoe

/// 엔진 배선 테스트: 시계·잠금·복구·알림을 가짜로 꽂아 규칙이 이어 붙은 모습을 확인한다.
final class WorkdayEngineTests: XCTestCase {
    private var clock = TestCalendar.date(8, 0)
    private var locked = false
    private var pendingRecovery: ((Date?) -> Void)?
    private var recoveryCalls = 0
    /// replaceNotifications 호출 기록 (day, plans)
    private var replaced: [(day: String, plans: [PlannedNotification])] = []
    private var scheduled: [[PlannedNotification]] { replaced.map(\.plans).filter { !$0.isEmpty } }
    private var settingsStore: SettingsStore!
    private var authRequests = 0
    private var defaults: UserDefaults!
    private var suite = ""
    private var store: WorkdayStore!

    override func setUp() {
        suite = "kaltoe.engine.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = WorkdayStore()
        settingsStore = SettingsStore(defaults: defaults)
        clock = TestCalendar.date(8, 0)
        locked = false
        pendingRecovery = nil
        recoveryCalls = 0
        replaced = []
        authRequests = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeEngine() -> WorkdayEngine {
        var env = WorkdayEngine.Environment()
        env.now = { [unowned self] in self.clock }
        env.calendar = TestCalendar.seoul
        env.defaults = defaults
        env.isScreenLocked = { [unowned self] in self.locked }
        env.recover = { [unowned self] _, _, completion in
            self.recoveryCalls += 1
            self.pendingRecovery = completion
        }
        env.requestNotificationAuthorization = { [unowned self] in self.authRequests += 1 }
        env.replaceNotifications = { [unowned self] day, plans, _ in self.replaced.append((day, plans)) }
        return WorkdayEngine(store: store, settings: settingsStore, environment: env)
    }

    private func change(_ edit: (inout WorkSettings) -> Void) {
        var s = settingsStore.settings
        edit(&s)
        XCTAssertEqual(settingsStore.update(s), [], "테스트가 유효한 설정만 넣어야 한다")
    }

    private func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) { clock = TestCalendar.date(h, m, s, day: day) }

    // MARK: 규칙 2 (실시간)

    func testUnlockAt916_clocksIn916() {
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(8, 59); locked = true; e.noteScreenLocked()      // 밤새 잠겨 있음
        at(9, 16); locked = false; e.noteScreenUnlocked()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16))
        XCTAssertEqual(store.snapshot.clockOut, TestCalendar.date(18, 16))
        XCTAssertEqual(store.snapshot.phase, .working)
        XCTAssertEqual(recoveryCalls, 0, "9시 전 실행이면 복구 불필요")
    }

    func testUsedFrom840ThroughNine_clocksInAtNine() {
        at(8, 40)
        let e = makeEngine(); e.bootstrap()        // 8:40 에 쓰기 시작
        at(8, 59, 59); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(9, 0, 0); e.tick()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 0))
    }

    func testLockedAt850_reunlockedAt920_clocksIn920() {
        at(8, 40)
        let e = makeEngine(); e.bootstrap()
        at(8, 50); locked = true; e.noteScreenLocked()
        at(9, 0); e.tick()                                  // 잠긴 채 9시 통과 — 기록 안 함
        at(9, 10); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(9, 20); locked = false; e.noteScreenUnlocked()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 20))
    }

    func testDarkWakeWhileLocked_isNotClockIn() {
        at(8, 0)
        let e = makeEngine(); e.bootstrap()
        locked = true; e.noteScreenLocked()
        at(9, 5); e.noteWake()                              // 잠긴 채 자동 깨어남
        at(9, 6); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
    }

    func testTimerGapOver2Seconds_refreshesActivation() {
        at(8, 40)
        let e = makeEngine(); e.bootstrap()
        at(8, 41); e.tick()
        // 잠자기: 타이머가 9:30 까지 건너뜀. 깨어난 순간부터 쓴 것으로 본다.
        at(9, 30); e.tick()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 30))
    }

    func testTimerGapWhileLocked_doesNotClockIn() {
        at(8, 40)
        let e = makeEngine(); e.bootstrap()
        locked = true
        at(9, 30); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
    }

    // MARK: 규칙 1

    func testRecordIsFixedForTheDay() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16))
        at(9, 40); locked = true; e.noteScreenLocked()
        at(10, 30); locked = false; e.noteScreenUnlocked()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16), "한번 정해지면 바뀌지 않는다")
    }

    func testRecordSurvivesRestart_withoutRecovery() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        at(11, 0)
        let relaunched = makeEngine(); relaunched.bootstrap()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16))
        XCTAssertEqual(recoveryCalls, 0)
        XCTAssertNotNil(defaults.object(forKey: "clockIn.2026-11-23"))
    }

    // MARK: 규칙 5

    func testMidnightReturnsToWaiting_andNewDayRecordsSeparately() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        XCTAssertEqual(store.snapshot.phase, .working)
        at(23, 59, 59); e.tick()
        at(0, 0, 1, day: 24); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertNil(store.snapshot.clockIn)
        at(9, 30, day: 24); e.noteActivation()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 30, day: 24))
        XCTAssertNotNil(defaults.object(forKey: "clockIn.2026-11-23"), "전날 기록은 14일 보관")
    }

    func testSleepAcrossMidnight_handledRightAfterWake() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        // 자는 동안 날짜가 바뀌고 7시에 깨어남 (잠금 상태)
        at(7, 0, day: 24); locked = true; e.noteWake()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertNil(store.snapshot.clockIn)
    }

    // MARK: 규칙 6 (사후 복구)

    func testRecovery_holdsRule2UntilFinished_thenRecordsRecoveredTime() {
        at(13, 0)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(store.snapshot.phase, .waiting, "복구 중엔 waiting")
        // 복구가 끝나기 전 잠금 해제·타이머가 와도 "지금"을 기록하지 않는다.
        at(13, 0, 5); e.noteScreenUnlocked()
        at(13, 0, 6); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertEqual(recoveryCalls, 1, "pmset 은 한 번만")

        at(13, 0, 8)
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.phase, .working)
        XCTAssertEqual(scheduled.count, 1)
    }

    func testRecovery_failureFallsBackToMaxOfNineAndLaunchTime() {
        at(13, 0)
        let e = makeEngine(); e.bootstrap()
        at(13, 0, 10)
        pendingRecovery?(nil)                      // 실패·타임아웃
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(13, 0))
    }

    func testRecovery_launchedWhileLocked_stillRecordsRecoveredTime() {
        at(13, 0); locked = true
        let e = makeEngine(); e.bootstrap()
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16, 46))
    }

    func testRecovery_resultIsDiscardedWhenDayChangedMeanwhile() {
        at(23, 59, 55)
        let e = makeEngine(); e.bootstrap()
        at(0, 0, 3, day: 24); e.tick()
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertNil(defaults.object(forKey: "clockIn.2026-11-24"))
    }

    func testRecovery_lateResultDoesNotOverwriteExistingRecord() {
        at(13, 0)
        let e = makeEngine(); e.bootstrap()
        let completion = pendingRecovery
        // 같은 날 다른 경로로 이미 저장된 기록이 있는 상태를 흉내
        XCTAssertTrue(ClockInStorage(defaults: defaults, calendar: TestCalendar.seoul).saveIfAbsent(TestCalendar.date(9, 40)))
        completion?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 40))
    }

    func testNoRecoveryBeforeNine() {
        at(8, 30)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(recoveryCalls, 0)
    }

    // MARK: 알림

    func testNotificationsScheduledOnceWhenClockInIsDecided() {
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(authRequests, 1)
        at(9, 16); e.noteActivation()
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].map(\.identifier),
                       ["kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
        let calls = replaced.count
        at(9, 17); e.tick(); e.noteActivation()
        XCTAssertEqual(replaced.count, calls, "기록이 정해진 뒤에는 다시 예약하지 않는다")
    }

    // MARK: 스냅샷 매초

    func testSnapshotUpdatesEveryTick_andPhasesAdvance() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        at(18, 6); e.tick()
        XCTAssertEqual(store.snapshot.phase, .almostDone)
        XCTAssertEqual(store.snapshot.remaining, 600, accuracy: 0.001)
        at(18, 16); e.tick()
        XCTAssertEqual(store.snapshot.phase, .done)
        at(18, 17); e.tick()
        XCTAssertEqual(store.snapshot.overtime, 60, accuracy: 0.001)
    }

    // MARK: 고정 모드

    func testFixedMode_usesSettingTimes_withoutDetectionStorageOrRecovery() {
        change { $0.mode = .fixed }
        at(13, 0)                                  // 감지했다면 복구가 돌 시각
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(recoveryCalls, 0)
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30))
        XCTAssertEqual(store.snapshot.clockOut, TestCalendar.date(17, 30))
        XCTAssertEqual(store.snapshot.phase, .working)
        e.noteScreenUnlocked(); at(13, 5); e.tick()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30), "컴퓨터 사용 여부와 무관")
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("clockIn.") }, "저장하지 않는다")
    }

    func testFixedMode_waitingBeforeStart_thenWorking_thenDone() {
        change { $0.mode = .fixed }
        at(7, 0)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertEqual(store.snapshot.target, TestCalendar.date(8, 30))
        at(8, 18); e.tick()
        XCTAssertEqual(store.snapshot.remaining, 12 * 60, accuracy: 0.001)
        at(8, 30); e.tick()
        XCTAssertEqual(store.snapshot.phase, .working)
        at(17, 20); e.tick()
        XCTAssertEqual(store.snapshot.phase, .almostDone)
        at(17, 30); e.tick()
        XCTAssertEqual(store.snapshot.phase, .done)
    }

    func testFixedMode_schedulesNotificationsAtLaunchAndOnNewDay() {
        change { $0.mode = .fixed }
        at(7, 0)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(scheduled.last?.map(\.fireDate), [TestCalendar.date(17, 20), TestCalendar.date(17, 30)])
        at(0, 0, 1, day: 24); e.tick()
        XCTAssertEqual(replaced.last?.day, "2026-11-24")
        XCTAssertEqual(scheduled.last?.map(\.fireDate), [TestCalendar.date(17, 20, day: 24), TestCalendar.date(17, 30, day: 24)])
    }

    // MARK: 유동 모드 설정 변경

    func testFlexible_workMinutesChangeRecalculatesImmediately() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        XCTAssertEqual(store.snapshot.clockOut, TestCalendar.date(18, 16))
        change { $0.workMinutes = 480 }
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16), "출근 기록은 그대로")
        XCTAssertEqual(store.snapshot.clockOut, TestCalendar.date(17, 16))
        XCTAssertEqual(scheduled.last?.map(\.fireDate), [TestCalendar.date(17, 6), TestCalendar.date(17, 16)])
        _ = e
    }

    func testFlexible_earliestStartChange_beforeRecord() {
        at(8, 30)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(8, 40)
        change { $0.earliestStart = TimeOfDay(8, 0) }       // 이미 지난 시각으로 낮추면 곧바로 기록
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30), "활성화 시각(8:30) 이후 첫 사용")
        _ = e
    }

    func testFlexible_earliestStartHigher_keepsWaitingUntilThen() {
        change { $0.earliestStart = TimeOfDay(10, 30) }
        at(10, 0)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(recoveryCalls, 0, "earliestStart 전에 실행했으니 복구 없음")
        at(10, 29); e.tick()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(10, 30); e.tick()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(10, 30), "그 전부터 쓰던 중이면 earliestStart")
        _ = e
    }

    // MARK: 모드 전환

    func testSwitchFlexibleToFixed_andBack_keepsDetectedRecord() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        at(10, 0)
        change { $0.mode = .fixed }
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30))
        change { $0.mode = .flexible }
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16), "저장된 기록이 되살아난다")
        XCTAssertEqual(recoveryCalls, 0)
        _ = e
    }

    func testSwitchFixedToFlexible_withoutRecord_startsRecovery() {
        change { $0.mode = .fixed }
        at(13, 0)
        let e = makeEngine(); e.bootstrap()
        XCTAssertEqual(recoveryCalls, 0)
        change { $0.mode = .flexible }
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(store.snapshot.phase, .waiting)
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16, 46))
        _ = e
    }

    func testRecoveryResultDiscardedAfterSwitchingToFixed() {
        at(13, 0)
        let e = makeEngine(); e.bootstrap()
        change { $0.mode = .fixed }
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30))
        XCTAssertNil(defaults.object(forKey: "clockIn.2026-11-23"), "고정 모드에서는 저장하지 않는다")
        _ = e
    }

    // MARK: 점심·알림 설정 반영

    func testLunchSettingsChangeAppliesImmediately() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        at(11, 40)
        e.tick()
        XCTAssertEqual(store.snapshot.phase, .working)
        change { $0.lunchEnabled = true }
        XCTAssertEqual(store.snapshot.phase, .lunch)
        XCTAssertEqual(store.snapshot.target, TestCalendar.date(13, 0))
        change { $0.lunchEnd = TimeOfDay(11, 35) }          // 점심 끝이 이미 지났다
        XCTAssertEqual(store.snapshot.phase, .working)
        _ = e
    }

    func testSettingsChangeReplacesNotificationsForToday() {
        let e = makeEngine(); e.bootstrap()
        at(9, 16); e.noteActivation()
        let before = replaced.count
        change { $0.lunchEnabled = true }
        XCTAssertEqual(replaced.count, before + 1)
        XCTAssertEqual(replaced.last?.day, "2026-11-23")
        XCTAssertEqual(replaced.last?.plans.map(\.identifier),
                       ["kaltoe.lunch.2026-11-23", "kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
        change { $0.notifyEnd = false; $0.notifyLunch = false }
        XCTAssertEqual(replaced.last?.plans.map(\.identifier), ["kaltoe.clockOut.warning.2026-11-23"])
        _ = e
    }

    // MARK: 오늘 출근 다시 감지

    func testRedetectToday_clearsRecordAndRunsRecovery() {
        let e = makeEngine(); e.bootstrap()
        at(9, 40); e.noteActivation()
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 40))
        at(11, 0)
        e.redetectToday()
        XCTAssertEqual(recoveryCalls, 1)
        XCTAssertEqual(store.snapshot.phase, .waiting)
        XCTAssertNil(defaults.object(forKey: "clockIn.2026-11-23"))
        XCTAssertEqual(replaced.last?.plans.isEmpty, true, "지워진 출근 기준의 예약은 취소")
        // 복구가 끝나기 전에는 규칙 2 가 "지금"을 기록하지 않는다
        at(11, 0, 5); e.noteScreenUnlocked()
        XCTAssertEqual(store.snapshot.phase, .waiting)
        at(11, 0, 8)
        pendingRecovery?(TestCalendar.date(9, 16, 46))
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 16, 46))
        XCTAssertNotNil(defaults.object(forKey: "clockIn.2026-11-23"))
        XCTAssertEqual(scheduled.last?.first?.fireDate, TestCalendar.date(18, 6, 46))
    }

    func testRedetectToday_failureFallsBackToMaxOfEarliestAndLaunch() {
        at(9, 5)
        let e = makeEngine(); e.bootstrap()
        pendingRecovery?(TestCalendar.date(9, 16))
        at(11, 0)
        e.redetectToday()
        pendingRecovery?(nil)
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(9, 5), "max(earliestStart 9:00, 앱 실행 9:05)")
        _ = e
    }

    func testRedetectToday_ignoredInFixedMode() {
        change { $0.mode = .fixed }
        at(11, 0)
        let e = makeEngine(); e.bootstrap()
        e.redetectToday()
        XCTAssertEqual(recoveryCalls, 0)
        XCTAssertEqual(store.snapshot.clockIn, TestCalendar.date(8, 30))
    }
}
