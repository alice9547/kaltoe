import XCTest
@testable import Kaltoe

final class SnapshotTests: XCTestCase {
    private let clockIn = TestCalendar.date(9, 16)
    private var clockOut: Date { clockIn.addingTimeInterval(WorkRules.workDuration) }   // 18:16

    func testWaiting_whenNoRecord() {
        let now = TestCalendar.date(8, 0)
        XCTAssertEqual(SnapshotCalculator.make(clockIn: nil, now: now), .waiting(now: now))
    }

    func testClockOutIsClockInPlusNineHours() {
        let s = SnapshotCalculator.make(clockIn: clockIn, now: TestCalendar.date(12, 0))
        XCTAssertEqual(s.clockOut, TestCalendar.date(18, 16))
        XCTAssertEqual(s.clockIn, clockIn)
    }

    func testWorking_justOverTenMinutesLeft() {
        let now = clockOut.addingTimeInterval(-(WorkRules.almostDoneThreshold + 1))
        let s = SnapshotCalculator.make(clockIn: clockIn, now: now)
        XCTAssertEqual(s.phase, .working)
        XCTAssertEqual(s.remaining, WorkRules.almostDoneThreshold + 1, accuracy: 0.001)
        XCTAssertEqual(s.overtime, 0)
    }

    func testAlmostDone_exactlyTenMinutesLeft() {
        let now = clockOut.addingTimeInterval(-WorkRules.almostDoneThreshold)
        let s = SnapshotCalculator.make(clockIn: clockIn, now: now)
        XCTAssertEqual(s.phase, .almostDone)
        XCTAssertEqual(s.remaining, 600, accuracy: 0.001)
    }

    func testAlmostDone_oneSecondLeft() {
        let s = SnapshotCalculator.make(clockIn: clockIn, now: clockOut.addingTimeInterval(-1))
        XCTAssertEqual(s.phase, .almostDone)
        XCTAssertEqual(s.remaining, 1, accuracy: 0.001)
        XCTAssertLessThan(s.progress, 1)
    }

    func testDone_exactlyAtClockOut() {
        let s = SnapshotCalculator.make(clockIn: clockIn, now: clockOut)
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.overtime, 0)
        XCTAssertEqual(s.progress, 1, accuracy: 1e-9)
    }

    func testDone_overtime() {
        let s = SnapshotCalculator.make(clockIn: clockIn, now: clockOut.addingTimeInterval(754))
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(s.overtime, 754, accuracy: 0.001)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.progress, 1)
    }

    func testProgress_halfwayAndClamped() {
        let half = SnapshotCalculator.make(clockIn: clockIn, now: clockIn.addingTimeInterval(WorkRules.workDuration / 2))
        XCTAssertEqual(half.progress, 0.5, accuracy: 1e-9)
        // 시계가 출근 시각보다 앞서 있어도 0 아래로 내려가지 않는다.
        let before = SnapshotCalculator.make(clockIn: clockIn, now: clockIn.addingTimeInterval(-5))
        XCTAssertEqual(before.progress, 0)
    }
}
