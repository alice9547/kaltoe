import XCTest
@testable import Kaltoe

/// docs/spec.md 3절 단계 결정 표의 각 행과 경계.
final class SnapshotTests: XCTestCase {
    private func d(_ h: Int, _ m: Int, _ s: Int = 0) -> Date { TestCalendar.date(h, m, s) }
    private let clockIn = TestCalendar.date(9, 16)
    private let clockOut = TestCalendar.date(18, 16)          // 출근 + 9h
    private let lunchStart = TestCalendar.date(11, 30)
    private let lunchEnd = TestCalendar.date(13, 0)

    private func make(_ now: Date, clockIn: Date? = TestCalendar.date(9, 16), clockOut: Date? = TestCalendar.date(18, 16),
                      lunch: Bool = false, lunchStart: Date? = nil, lunchEnd: Date? = nil) -> WorkdaySnapshot {
        SnapshotCalculator.make(now: now, clockIn: clockIn, clockOut: clockOut,
                                lunchStart: lunch ? (lunchStart ?? self.lunchStart) : nil,
                                lunchEnd: lunch ? (lunchEnd ?? self.lunchEnd) : nil)
    }

    // MARK: waiting

    func testWaiting_flexibleWithoutRecord_hasNoTarget() {
        let now = d(8, 0)
        let s = SnapshotCalculator.make(now: now, clockIn: nil, clockOut: nil)
        XCTAssertEqual(s, .waiting(now: now))
        XCTAssertNil(s.target)
        XCTAssertEqual(s.remaining, 0)
    }

    func testWaiting_fixedBeforeStart_targetIsClockIn() {
        let s = SnapshotCalculator.make(now: d(8, 18), clockIn: d(8, 30), clockOut: d(17, 30))
        XCTAssertEqual(s.phase, .waiting)
        XCTAssertEqual(s.target, d(8, 30))
        XCTAssertEqual(s.remaining, 12 * 60, accuracy: 0.001)
        XCTAssertEqual(s.progress, 0)
        XCTAssertEqual(s.clockOut, d(17, 30))
        XCTAssertEqual(s.remainingToClockOut, 9 * 3600 + 12 * 60, accuracy: 0.001)
    }

    func testFixed_exactlyAtStart_isNoLongerWaiting() {
        XCTAssertEqual(SnapshotCalculator.make(now: d(8, 30), clockIn: d(8, 30), clockOut: d(17, 30)).phase, .working)
    }

    // MARK: working / almostDone / done (점심 미사용)

    func testClockOutIsClockInPlusWork() {
        let s = make(d(12, 0))
        XCTAssertEqual(s.clockOut, d(18, 16))
        XCTAssertEqual(s.clockIn, clockIn)
        XCTAssertEqual(s.target, clockOut)
        XCTAssertNil(s.lunchStart); XCTAssertNil(s.lunchEnd)
    }

    func testWorking_justOverTenMinutesLeft() {
        let s = make(clockOut.addingTimeInterval(-601))
        XCTAssertEqual(s.phase, .working)
        XCTAssertEqual(s.remaining, 601, accuracy: 0.001)
        XCTAssertEqual(s.remainingToClockOut, 601, accuracy: 0.001)
        XCTAssertEqual(s.overtime, 0)
    }

    func testAlmostDone_exactlyTenMinutesLeft() {
        let s = make(clockOut.addingTimeInterval(-600))
        XCTAssertEqual(s.phase, .almostDone)
        XCTAssertEqual(s.remaining, 600, accuracy: 0.001)
        XCTAssertEqual(s.target, clockOut)
    }

    func testDone_exactlyAtClockOut() {
        let s = make(clockOut)
        XCTAssertEqual(s.phase, .done)
        XCTAssertNil(s.target)
        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.remainingToClockOut, 0)
        XCTAssertEqual(s.overtime, 0)
        XCTAssertEqual(s.progress, 1, accuracy: 1e-9)
    }

    func testDone_overtime() {
        let s = make(clockOut.addingTimeInterval(754))
        XCTAssertEqual(s.phase, .done)
        XCTAssertEqual(s.overtime, 754, accuracy: 0.001)
        XCTAssertEqual(s.progress, 1)
    }

    func testProgress_halfwayAndClamped() {
        XCTAssertEqual(make(clockIn.addingTimeInterval(4.5 * 3600)).progress, 0.5, accuracy: 1e-9)
        XCTAssertEqual(make(clockIn.addingTimeInterval(-5)).phase, .waiting)
        XCTAssertEqual(make(clockIn.addingTimeInterval(-5)).progress, 0)
    }

    // MARK: 점심 (spec 3절 표)

    func testBeforeLunch_untilExactlyLunchStart() {
        let s = make(d(11, 29, 59), lunch: true)
        XCTAssertEqual(s.phase, .beforeLunch)
        XCTAssertEqual(s.target, lunchStart)
        XCTAssertEqual(s.remaining, 1, accuracy: 0.001)
        XCTAssertEqual(s.lunchStart, lunchStart); XCTAssertEqual(s.lunchEnd, lunchEnd)
        XCTAssertEqual(s.remainingToClockOut, clockOut.timeIntervalSince(d(11, 29, 59)), accuracy: 0.001)
    }

    func testLunch_exactlyAtLunchStart() {
        let s = make(lunchStart, lunch: true)
        XCTAssertEqual(s.phase, .lunch)
        XCTAssertEqual(s.target, lunchEnd)
        XCTAssertEqual(s.remaining, 90 * 60, accuracy: 0.001)
    }

    func testLunch_lastSecondBeforeLunchEnd_thenWorkingAtExactlyLunchEnd() {
        XCTAssertEqual(make(d(12, 59, 59), lunch: true).phase, .lunch)
        let s = make(lunchEnd, lunch: true)
        XCTAssertEqual(s.phase, .working)
        XCTAssertEqual(s.target, clockOut)
    }

    func testLunch_almostDoneAfterLunchStillWorks() {
        XCTAssertEqual(make(clockOut.addingTimeInterval(-600), lunch: true).phase, .almostDone)
        XCTAssertEqual(make(clockOut, lunch: true).phase, .done)
    }

    func testLunch_lunchWinsOverAlmostDone() {
        // 퇴근 직전에 점심이 겹치면(표의 순서) lunch 가 먼저다.
        let s = SnapshotCalculator.make(now: d(11, 40), clockIn: d(2, 50), clockOut: d(11, 50),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(s.phase, .lunch)
    }

    func testLunch_doneWinsOverLunch() {
        let s = SnapshotCalculator.make(now: d(11, 45), clockIn: d(2, 40), clockOut: d(11, 40),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(s.phase, .done)
    }

    func testLunch_beforeLunchProgressUsesWholeWorkSpan() {
        let s = SnapshotCalculator.make(now: d(9, 0), clockIn: d(8, 30), clockOut: d(17, 30),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(s.progress, 30.0 / 540.0, accuracy: 1e-9)
    }

    // 점심이 유효하지 않은 세 경우: 사용 안 함 / 출근이 점심 끝 이후 / 점심 시작이 퇴근 이후

    func testLunchInvalid_disabled() {
        let s = make(d(11, 40), lunch: false)
        XCTAssertEqual(s.phase, .working)
        XCTAssertNil(s.lunchStart); XCTAssertNil(s.lunchEnd)
    }

    func testLunchInvalid_clockInAtOrAfterLunchEnd() {
        // 출근 13:00 == 점심 끝 → clockIn < lunchEnd 가 거짓
        let s = SnapshotCalculator.make(now: d(13, 30), clockIn: d(13, 0), clockOut: d(22, 0),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(s.phase, .working)
        XCTAssertNil(s.lunchStart); XCTAssertNil(s.lunchEnd)
        // 출근이 점심 끝 1분 전이면 유효 (출근 12:59, 지금 13:00 → lunchEnd 이후라 working)
        let v = SnapshotCalculator.make(now: d(12, 59, 30), clockIn: d(12, 59), clockOut: d(22, 0),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(v.phase, .lunch)
    }

    func testLunchInvalid_lunchStartAtOrAfterClockOut() {
        // 퇴근 11:30 == 점심 시작 → lunchStart < clockOut 이 거짓
        let s = SnapshotCalculator.make(now: d(11, 0), clockIn: d(2, 30), clockOut: d(11, 30),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(s.phase, .working)
        XCTAssertNil(s.lunchStart)
        let v = SnapshotCalculator.make(now: d(11, 0), clockIn: d(2, 31), clockOut: d(11, 31),
                                        lunchStart: lunchStart, lunchEnd: lunchEnd)
        XCTAssertEqual(v.phase, .beforeLunch)
    }

    func testLunchValidity_pureFunction() {
        let lunch = (start: lunchStart, end: lunchEnd)
        XCTAssertNotNil(SnapshotCalculator.validLunch(clockIn: clockIn, clockOut: clockOut, lunch: lunch))
        XCTAssertNil(SnapshotCalculator.validLunch(clockIn: clockIn, clockOut: clockOut, lunch: nil))
        XCTAssertNil(SnapshotCalculator.validLunch(clockIn: lunchEnd, clockOut: clockOut, lunch: lunch))
        XCTAssertNil(SnapshotCalculator.validLunch(clockIn: clockIn, clockOut: lunchStart, lunch: lunch))
    }
}

/// 설정 + 출근 기록 → 출근·퇴근·점심 시각.
final class DayScheduleTests: XCTestCase {
    private let cal = TestCalendar.seoul
    private func d(_ h: Int, _ m: Int) -> Date { TestCalendar.date(h, m) }

    func testFixedMode_usesSettingsTimes_ignoringRecord() {
        var s = WorkSettings(); s.mode = .fixed
        let t = DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(10, 0), calendar: cal)
        XCTAssertEqual(t.clockIn, d(8, 30))
        XCTAssertEqual(t.clockOut, d(17, 30))
        let none = DaySchedule.times(settings: s, detectedClockIn: nil, now: d(7, 0), calendar: cal)
        XCTAssertEqual(none.clockIn, d(8, 30))
    }

    func testFixedMode_customTimes() {
        var s = WorkSettings(); s.mode = .fixed; s.fixedStart = TimeOfDay(10, 0); s.fixedEnd = TimeOfDay(19, 15)
        let t = DaySchedule.times(settings: s, detectedClockIn: nil, now: d(12, 0), calendar: cal)
        XCTAssertEqual(t.clockIn, d(10, 0)); XCTAssertEqual(t.clockOut, d(19, 15))
    }

    func testFlexibleMode_clockOutIsClockInPlusWorkMinutes() {
        var s = WorkSettings()
        XCTAssertEqual(DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(12, 0), calendar: cal).clockOut, d(18, 16))
        s.workMinutes = 480
        XCTAssertEqual(DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(12, 0), calendar: cal).clockOut, d(17, 16))
        s.workMinutes = 60
        XCTAssertEqual(DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(12, 0), calendar: cal).clockOut, d(10, 16))
        let none = DaySchedule.times(settings: s, detectedClockIn: nil, now: d(12, 0), calendar: cal)
        XCTAssertNil(none.clockIn); XCTAssertNil(none.clockOut)
    }

    func testLunchIncludedOnlyWhenEnabled() {
        var s = WorkSettings()
        XCTAssertNil(DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(12, 0), calendar: cal).lunch)
        s.lunchEnabled = true; s.lunchStart = TimeOfDay(12, 0); s.lunchEnd = TimeOfDay(13, 0)
        let l = DaySchedule.times(settings: s, detectedClockIn: d(9, 16), now: d(12, 0), calendar: cal).lunch
        XCTAssertEqual(l?.start, d(12, 0)); XCTAssertEqual(l?.end, d(13, 0))
    }
}
