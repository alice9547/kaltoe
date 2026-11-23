import XCTest
@testable import Kaltoe

final class NotificationPlannerTests: XCTestCase {
    private let cal = TestCalendar.seoul
    private func d(_ h: Int, _ m: Int) -> Date { TestCalendar.date(h, m) }

    private func times(in: Date = TestCalendar.date(9, 16), out: Date = TestCalendar.date(18, 16),
                       lunch: (Date, Date)? = nil) -> DaySchedule.Times {
        DaySchedule.Times(clockIn: `in`, clockOut: out, lunch: lunch.map { ($0.0, $0.1) })
    }

    private func ids(_ plans: [PlannedNotification]) -> [String] { plans.map(\.identifier) }

    func testPlansTwoNotificationsWithDateInIdentifier() {
        let plans = NotificationPlanner.plan(times: times(), settings: WorkSettings(), now: d(9, 16), calendar: cal)
        XCTAssertEqual(ids(plans), ["kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
        XCTAssertEqual(plans.map(\.fireDate), [d(18, 6), d(18, 16)])
        XCTAssertEqual(plans.map(\.body), ["퇴근 10분 전 — 지금 배포하면 안 됩니다",
                                           "Process finished with exit code 0 — 퇴근하세요"])
    }

    func testPastTimesAreNotScheduled() {
        let t = times()
        XCTAssertEqual(ids(NotificationPlanner.plan(times: t, settings: WorkSettings(), now: d(18, 10), calendar: cal)),
                       ["kaltoe.clockOut.done.2026-11-23"])
        XCTAssertTrue(NotificationPlanner.plan(times: t, settings: WorkSettings(), now: d(18, 16), calendar: cal).isEmpty)
    }

    func testLunchNotification_whenEnabledAndValid() {
        var s = WorkSettings(); s.lunchEnabled = true
        let t = times(lunch: (d(11, 30), d(13, 0)))
        let plans = NotificationPlanner.plan(times: t, settings: s, now: d(9, 16), calendar: cal)
        XCTAssertEqual(ids(plans), ["kaltoe.lunch.2026-11-23", "kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
        XCTAssertEqual(plans[0].fireDate, d(11, 30))
        XCTAssertEqual(plans[0].body, "점심 시간입니다 — npm install 점심")
    }

    func testLunchNotification_offWhenLunchDisabledOrToggleOff() {
        var s = WorkSettings()
        // 점심 시각이 주어져도 lunch.enabled 가 꺼져 있으면 (times.lunch 가 nil) 알림 없음
        XCTAssertFalse(ids(NotificationPlanner.plan(times: times(), settings: s, now: d(9, 16), calendar: cal)).contains("kaltoe.lunch.2026-11-23"))
        s.lunchEnabled = true; s.notifyLunch = false
        let t = times(lunch: (d(11, 30), d(13, 0)))
        XCTAssertFalse(ids(NotificationPlanner.plan(times: t, settings: s, now: d(9, 16), calendar: cal)).contains("kaltoe.lunch.2026-11-23"))
    }

    func testLunchNotification_skippedWhenLunchInvalid() {
        var s = WorkSettings(); s.lunchEnabled = true
        // 점심이 출근 전에 끝남 / 퇴근 후에 시작 → 유효하지 않음
        for lunch in [(d(8, 0), d(9, 0)), (d(19, 0), d(20, 0))] {
            let plans = NotificationPlanner.plan(times: times(lunch: lunch), settings: s, now: d(9, 16), calendar: cal)
            XCTAssertFalse(ids(plans).contains("kaltoe.lunch.2026-11-23"))
        }
    }

    func testLunchNotification_pastLunchStartExcluded() {
        var s = WorkSettings(); s.lunchEnabled = true
        let plans = NotificationPlanner.plan(times: times(lunch: (d(11, 30), d(13, 0))), settings: s, now: d(11, 30), calendar: cal)
        XCTAssertFalse(ids(plans).contains("kaltoe.lunch.2026-11-23"))
    }

    func testEndNotificationsFollowToggles() {
        var s = WorkSettings(); s.notifyBeforeEnd = false
        XCTAssertEqual(ids(NotificationPlanner.plan(times: times(), settings: s, now: d(9, 16), calendar: cal)),
                       ["kaltoe.clockOut.done.2026-11-23"])
        s.notifyBeforeEnd = true; s.notifyEnd = false
        XCTAssertEqual(ids(NotificationPlanner.plan(times: times(), settings: s, now: d(9, 16), calendar: cal)),
                       ["kaltoe.clockOut.warning.2026-11-23"])
        s.notifyBeforeEnd = false
        XCTAssertTrue(NotificationPlanner.plan(times: times(), settings: s, now: d(9, 16), calendar: cal).isEmpty)
    }

    func testNoClockIn_noPlans() {
        XCTAssertTrue(NotificationPlanner.plan(times: DaySchedule.Times(), settings: WorkSettings(), now: d(9, 0), calendar: cal).isEmpty)
    }

    func testIdentifiersCoverAllThreeForTheDay() {
        XCTAssertEqual(NotificationPlanner.identifiers(day: "2026-11-23"),
                       ["kaltoe.lunch.2026-11-23", "kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
    }
}
