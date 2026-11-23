import XCTest
@testable import Kaltoe

/// 이 맥의 실제 `pmset -g log` 줄(2026-11-23)을 줄여서 쓴다. 카테고리 뒤 공백은 탭 섞인 실제 형식 그대로.
final class PmsetRecoveryTests: XCTestCase {
    private let cal = TestCalendar.seoul
    private var nine: Date { TestCalendar.date(9, 0) }

    private let real = """
    2026-11-23 05:45:34 +0900 DarkWake            \tDarkWake from Deep Idle [CDNPB] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/Maintenance Using AC (Charge:80%)           
    2026-11-23 05:45:34 +0900 WakeDetails         \tDriverReason:NUB.SPMI0Sw3IRQ - DriverDetails:                              
    2026-11-23 05:45:34 +0900 WakeTime            \tWakeTime: 0.157 sec                                                        \t
    2026-11-23 08:02:28 +0900 Wake Requests       \t[process=dasd request=SleepService deltaSecs=1055 wakeAt=2026-11-23 08:20:03 info="x"]
    2026-11-23 08:18:49 +0900 DarkWake            \tDarkWake from Deep Idle [CDNPB] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/Maintenance Using AC (Charge:80%)           
    2026-11-23 08:55:00 +0900 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:80%)           
    2026-11-23 09:16:46 +0900 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:80%)           
    2026-11-23 09:16:46 +0900 WakeDetails         \tDriverReason:NUB.SPMI0Sw3IRQ - DriverDetails:                              
    2026-11-23 10:04:49 +0900 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using AC (Charge:80%) 25 secs
    2026-11-23 10:05:14 +0900 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion Using AC (Charge:80%)           
    2026-11-23 12:38:36 +0900 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty bluetooth-pcie/HID Activity Using AC (Charge:80%) 80 secs   
    2026-11-23 13:27:17 +0900 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity Using AC (Charge:80%)           
    Sleep/Wakes since boot:1166   Dark Wake Count in this sleep cycle:1
    """

    func testParser_adoptsFullWakeOnly() {
        let times = PmsetLogParser.fullWakeTimes(in: real)
        XCTAssertEqual(times, [
            TestCalendar.date(8, 55), TestCalendar.date(9, 16, 46), TestCalendar.date(10, 5, 14),
            TestCalendar.date(12, 38, 36), TestCalendar.date(13, 27, 17),
        ])
    }

    func testParser_excludesDarkWakeWakeRequestsAndDetails() {
        let log = """
        2026-11-23 09:10:00 +0900 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to something
        2026-11-23 09:10:00 +0900 Wake Requests       \t[process=powerd request=UserWake]
        2026-11-23 09:10:00 +0900 WakeDetails         \tDriverReason:x
        2026-11-23 09:10:00 +0900 WakeTime            \tWakeTime: 0.1 sec
        2026-11-23 09:10:00 +0900 Kernel Client Acks  \tDelays to Wake notifications: [x]
        """
        XCTAssertEqual(PmsetLogParser.fullWakeTimes(in: log), [])
    }

    func testParser_handlesSpaceSeparatorAndOtherOffsets() {
        let log = "2026-11-23 09:30:00 +0900 Wake \tFullWake from Normal Sleep\n2026-11-23 00:30:00 +0000 Wake    DarkWake to FullWake from Deep Idle [CDNVA]"
        let times = PmsetLogParser.fullWakeTimes(in: log)
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(times[0], TestCalendar.date(9, 30))
        XCTAssertEqual(times[1], TestCalendar.date(9, 30), "+0000 의 00:30 은 서울 09:30")
    }

    // 복구 시각 결정

    func testRecovery_picksFirstFullWakeAfterNine_excludingBeforeNine() {
        // 8:55 FullWake 는 9시 이전이므로 제외 → 09:16:46
        let t = PmsetRecovery.clockIn(fromLog: real, boot: nil, nineAM: nine, now: TestCalendar.date(15, 0))
        XCTAssertEqual(t, TestCalendar.date(9, 16, 46))
    }

    func testRecovery_ignoresFullWakesAfterNow() {
        let t = PmsetRecovery.clockIn(fromLog: real, boot: nil, nineAM: nine, now: TestCalendar.date(9, 10))
        XCTAssertEqual(t, nine, "9:10 시점엔 아직 9시 이후 FullWake 가 없다")
    }

    func testRecovery_darkWakeOnlyIsNotCandidate_noCandidateMeansNine() {
        let log = """
        2026-11-23 09:20:00 +0900 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to x
        2026-11-23 09:40:00 +0900 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to y
        """
        XCTAssertEqual(PmsetRecovery.clockIn(fromLog: log, boot: nil, nineAM: nine, now: TestCalendar.date(11, 0)), nine)
    }

    func testRecovery_emptyLogMeansNine() {
        XCTAssertEqual(PmsetRecovery.clockIn(fromLog: "", boot: nil, nineAM: nine, now: TestCalendar.date(11, 0)), nine)
    }

    func testRecovery_bootAfterNineIsCandidate_earliestWins() {
        let now = TestCalendar.date(15, 0)
        // 부팅 09:05 < 첫 FullWake 09:16:46 → 부팅 채택
        XCTAssertEqual(PmsetRecovery.clockIn(fromLog: real, boot: TestCalendar.date(9, 5), nineAM: nine, now: now),
                       TestCalendar.date(9, 5))
        // 부팅 09:30 > 09:16:46 → FullWake 채택
        XCTAssertEqual(PmsetRecovery.clockIn(fromLog: real, boot: TestCalendar.date(9, 30), nineAM: nine, now: now),
                       TestCalendar.date(9, 16, 46))
    }

    func testRecovery_bootBeforeNineIsNotCandidate() {
        let log = "2026-11-23 09:40:00 +0900 Wake \tDarkWake to FullWake from Deep Idle [CDNVA] : due to HID Activity"
        XCTAssertEqual(PmsetRecovery.clockIn(fromLog: log, boot: TestCalendar.date(7, 0), nineAM: nine, now: TestCalendar.date(11, 0)),
                       TestCalendar.date(9, 40))
    }
}
