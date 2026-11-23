// 출근 시각 규칙 — 시스템 호출 없는 순수 함수 모음.
// 시각·달력·잠금 여부를 인자로 받으므로 테스트에서 그대로 검증한다.
import Foundation

enum ClockInRules {
    /// 날짜 키 "yyyy-MM-dd" (달력 기준 로컬 날짜).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `date` 가 속한 날의 09:00:00 ("오늘 9시").
    static func earliestClockIn(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: WorkRules.earliestClockInHour, minute: 0, second: 0,
                      of: date, matchingPolicy: .nextTime) ?? calendar.startOfDay(for: date)
    }

    /// 규칙 2·3·4: 지금 출근으로 기록할 시각. 기록하면 안 되는 상황이면 nil.
    /// - 현재 시각 < 오늘 9시 → nil (규칙 3)
    /// - 화면 잠금 중 → nil (규칙 4)
    /// - 그 외 → max(오늘 9시, 활성화 시각) (규칙 2)
    static func decide(now: Date, activation: Date, isLocked: Bool, calendar: Calendar) -> Date? {
        let nine = earliestClockIn(on: now, calendar: calendar)
        guard now >= nine, !isLocked else { return nil }
        // 활성화 시각이 미래일 수는 없다(시계 보정 등 방어).
        return max(nine, min(activation, now))
    }

    /// 규칙 5: 저장된 기록이 "오늘" 것일 때만 유효. 전날 기록은 무시한다.
    static func validRecord(_ record: Date?, now: Date, calendar: Calendar) -> Date? {
        guard let record, calendar.isDate(record, inSameDayAs: now) else { return nil }
        return record
    }

    /// 규칙 1: 보관 기간(기본 14일)이 지난 `clockIn.yyyy-MM-dd` 키를 골라낸다.
    static func keysToPurge(_ keys: [String], now: Date, calendar: Calendar,
                            retentionDays: Int = 14) -> [String] {
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return [] }
        let cutoff = dayKey(cutoffDate, calendar: calendar)
        return keys.filter { key in
            guard key.hasPrefix(ClockInStorage.keyPrefix) else { return false }
            let day = String(key.dropFirst(ClockInStorage.keyPrefix.count))
            guard isDayKey(day) else { return false }
            return day < cutoff   // "yyyy-MM-dd" 는 문자열 비교가 곧 날짜 비교
        }
    }

    private static func isDayKey(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 10, u[4] == UInt8(ascii: "-"), u[7] == UInt8(ascii: "-") else { return false }
        return u.enumerated().allSatisfy { i, ch in i == 4 || i == 7 || (ch >= 48 && ch <= 57) }
    }
}

enum SnapshotCalculator {
    /// 매초 스냅샷. 기록이 없으면 waiting.
    static func make(clockIn: Date?, now: Date) -> WorkdaySnapshot {
        guard let clockIn else { return .waiting(now: now) }
        let total = WorkRules.workDuration
        let clockOut = clockIn.addingTimeInterval(total)
        let left = clockOut.timeIntervalSince(now)
        let phase: WorkPhase
        if now >= clockOut {
            phase = .done
        } else if left <= WorkRules.almostDoneThreshold {
            phase = .almostDone
        } else {
            phase = .working
        }
        return WorkdaySnapshot(
            now: now, clockIn: clockIn, clockOut: clockOut,
            remaining: max(0, left),
            overtime: max(0, -left),
            progress: min(1, max(0, now.timeIntervalSince(clockIn) / total)),
            phase: phase)
    }
}
