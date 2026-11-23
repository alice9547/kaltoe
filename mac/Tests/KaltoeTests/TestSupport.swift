import XCTest
@testable import Kaltoe

/// 모든 테스트는 Asia/Seoul 로 고정한 달력을 쓴다.
enum TestCalendar {
    static let seoul: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// 2026-11-23 기준 (월요일) 서울 시각.
    static func date(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 23, month: Int = 11, year: Int = 2026) -> Date {
        seoul.date(from: DateComponents(year: year, month: month, day: day, hour: h, minute: m, second: s))!
    }
}
