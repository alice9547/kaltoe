import XCTest
@testable import Kaltoe

final class ClockInRulesTests: XCTestCase {
    private let cal = TestCalendar.seoul
    private func d(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23) -> Date { TestCalendar.date(h, m, s, day: day) }

    // MARK: 규칙 2

    func testRule2_unlockAt916_clocksIn916() {
        // 9:16 에 잠금 해제 → 09:16
        let t = ClockInRules.decide(now: d(9, 16), activation: d(9, 16), isLocked: false, calendar: cal)
        XCTAssertEqual(t, d(9, 16))
    }

    func testRule2_usedSince840_clocksInAtNine() {
        // 8:40 에 잠금 해제하고 9시까지 계속 사용 → 09:00
        let t = ClockInRules.decide(now: d(9, 0), activation: d(8, 40), isLocked: false, calendar: cal)
        XCTAssertEqual(t, d(9, 0))
    }

    func testRule2_lockedAndReunlockedAt920_clocksIn920() {
        // 8:40 에 쓰다가 잠그고 9:20 에 다시 해제 → 09:20 (활성화 시각이 9:20 으로 갱신됨)
        let t = ClockInRules.decide(now: d(9, 20), activation: d(9, 20), isLocked: false, calendar: cal)
        XCTAssertEqual(t, d(9, 20))
    }

    func testRule2_activationInFutureIsClampedToNow() {
        let t = ClockInRules.decide(now: d(9, 5), activation: d(9, 30), isLocked: false, calendar: cal)
        XCTAssertEqual(t, d(9, 5))
    }

    // MARK: 규칙 3·4

    func testRule3_beforeNine_noRecord() {
        XCTAssertNil(ClockInRules.decide(now: d(8, 59, 59), activation: d(8, 40), isLocked: false, calendar: cal))
        XCTAssertNil(ClockInRules.decide(now: d(0, 0, 0), activation: d(0, 0), isLocked: false, calendar: cal))
    }

    func testRule3_exactlyNine_isAllowed() {
        XCTAssertEqual(ClockInRules.decide(now: d(9, 0), activation: d(8, 0), isLocked: false, calendar: cal), d(9, 0))
    }

    func testRule4_locked_noRecord() {
        XCTAssertNil(ClockInRules.decide(now: d(9, 30), activation: d(9, 16), isLocked: true, calendar: cal))
        XCTAssertNil(ClockInRules.decide(now: d(14, 0), activation: d(3, 0), isLocked: true, calendar: cal))
    }

    // MARK: 규칙 5

    func testRule5_yesterdayRecordIsIgnoredAfterMidnight() {
        let yesterday = d(9, 16, day: 22)
        XCTAssertNil(ClockInRules.validRecord(yesterday, now: d(0, 0, 1), calendar: cal))
        XCTAssertNil(ClockInRules.validRecord(yesterday, now: d(23, 59, 59, day: 22).addingTimeInterval(1), calendar: cal))
        XCTAssertEqual(ClockInRules.validRecord(yesterday, now: d(23, 59, 59, day: 22), calendar: cal), yesterday)
        XCTAssertNil(ClockInRules.validRecord(nil, now: d(10, 0), calendar: cal))
    }

    func testRule5_midnightResetsToWaitingSnapshot() {
        let record = ClockInRules.validRecord(d(9, 16, day: 22), now: d(0, 0, 1), calendar: cal)
        XCTAssertEqual(SnapshotCalculator.make(clockIn: record, now: d(0, 0, 1)).phase, .waiting)
    }

    func testDayKey_usesCalendarTimeZone() {
        XCTAssertEqual(ClockInRules.dayKey(d(0, 0, 1), calendar: cal), "2026-11-23")
        XCTAssertEqual(ClockInRules.dayKey(d(23, 59, 59), calendar: cal), "2026-11-23")
        // 같은 순간이라도 UTC 달력이면 전날 (15:00Z = 24:00 KST 직전)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ClockInRules.dayKey(d(0, 30), calendar: utc), "2026-11-22")
    }

    // MARK: 규칙 1 (보관)

    func testPurge_removesOnlyRecordsOlderThan14Days() {
        let now = d(10, 0)
        let keys = ["clockIn.2026-11-23", "clockIn.2026-11-09", "clockIn.2026-11-08",
                    "clockIn.2026-10-01", "clockIn.garbage", "other.2026-01-01"]
        XCTAssertEqual(Set(ClockInRules.keysToPurge(keys, now: now, calendar: cal)),
                       ["clockIn.2026-11-08", "clockIn.2026-10-01"])
    }

    func testStorage_oneRecordPerDay_persistsAndPurges() {
        let suite = "kaltoe.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ClockInStorage(defaults: defaults, calendar: cal)

        XCTAssertTrue(storage.saveIfAbsent(d(9, 16)))
        XCTAssertFalse(storage.saveIfAbsent(d(10, 30)), "하루에 하나 — 두 번째는 무시")
        XCTAssertEqual(storage.load(for: d(18, 0)), d(9, 16))
        XCTAssertNil(storage.load(for: d(9, 0, day: 24)))
        XCTAssertEqual(defaults.object(forKey: "clockIn.2026-11-23") as? Double, d(9, 16).timeIntervalSince1970)

        XCTAssertTrue(storage.saveIfAbsent(d(9, 0, day: 1)))
        storage.purge(now: d(10, 0))
        XCTAssertNil(storage.load(for: d(9, 0, day: 1)))
        XCTAssertNotNil(storage.load(for: d(9, 0)))
    }
}
