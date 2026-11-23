import XCTest
@testable import Kaltoe

final class NotificationPlannerTests: XCTestCase {
    private let cal = TestCalendar.seoul

    func testPlansTwoNotificationsWithDateInIdentifier() {
        let clockIn = TestCalendar.date(9, 16)
        let plans = NotificationPlanner.plan(clockIn: clockIn, now: clockIn, calendar: cal)
        XCTAssertEqual(plans.map(\.identifier), ["kaltoe.clockOut.warning.2026-11-23", "kaltoe.clockOut.done.2026-11-23"])
        XCTAssertEqual(plans.map(\.fireDate), [TestCalendar.date(18, 6), TestCalendar.date(18, 16)])
        XCTAssertEqual(plans.map(\.body), ["퇴근 10분 전 — 지금 배포하면 안 됩니다",
                                           "Process finished with exit code 0 — 퇴근하세요"])
    }

    func testPastTimesAreNotScheduled() {
        let clockIn = TestCalendar.date(9, 16)
        let afterWarning = NotificationPlanner.plan(clockIn: clockIn, now: TestCalendar.date(18, 10), calendar: cal)
        XCTAssertEqual(afterWarning.map(\.identifier), ["kaltoe.clockOut.done.2026-11-23"])
        let afterDone = NotificationPlanner.plan(clockIn: clockIn, now: TestCalendar.date(18, 16), calendar: cal)
        XCTAssertTrue(afterDone.isEmpty)
    }
}
