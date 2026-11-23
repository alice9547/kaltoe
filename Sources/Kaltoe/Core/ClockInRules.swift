// 출근 시각 규칙 — 시스템 호출 없는 순수 함수 모음.
// 시각·달력·잠금 여부를 인자로 받으므로 테스트에서 그대로 검증한다.
import Foundation

enum ClockInRules {
    /// 날짜 키 "yyyy-MM-dd" (달력 기준 로컬 날짜).
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `date` 가 속한 날의 `earliestStart` ("오늘 출근 인정 시작 시각").
    static func earliestClockIn(on date: Date, earliestStart: TimeOfDay, calendar: Calendar) -> Date {
        earliestStart.date(on: date, calendar: calendar)
    }

    /// 규칙 2·3·4: 지금 출근으로 기록할 시각. 기록하면 안 되는 상황이면 nil.
    /// - 현재 시각 < 오늘 earliestStart → nil (규칙 3)
    /// - 화면 잠금 중 → nil (규칙 4)
    /// - 그 외 → max(오늘 earliestStart, 활성화 시각) (규칙 2)
    static func decide(now: Date, activation: Date, isLocked: Bool,
                       earliestStart: TimeOfDay, calendar: Calendar) -> Date? {
        let nine = earliestClockIn(on: now, earliestStart: earliestStart, calendar: calendar)
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

/// 하루 일정 계산 (순수 함수). 설정 + 출근 기록 → 출근·퇴근·점심 시각.
enum DaySchedule {
    struct Times: Equatable {
        var clockIn: Date?
        var clockOut: Date?
        /// 설정상 점심 시각(사용 중일 때만). 유효성은 `SnapshotCalculator.validLunch` 로 따로 본다.
        var lunch: (start: Date, end: Date)?

        static func == (a: Times, b: Times) -> Bool {
            a.clockIn == b.clockIn && a.clockOut == b.clockOut
                && a.lunch?.start == b.lunch?.start && a.lunch?.end == b.lunch?.end
        }
    }

    /// - 고정: 출근·퇴근 = 오늘 설정 시각 (기록과 무관).
    /// - 유동: 출근 = 기록(없으면 nil), 퇴근 = 출근 + workMinutes.
    static func times(settings s: WorkSettings, detectedClockIn: Date?, now: Date, calendar: Calendar) -> Times {
        var t = Times()
        switch s.mode {
        case .fixed:
            t.clockIn = s.fixedStart.date(on: now, calendar: calendar)
            t.clockOut = s.fixedEnd.date(on: now, calendar: calendar)
        case .flexible:
            t.clockIn = detectedClockIn
            t.clockOut = detectedClockIn.map { $0.addingTimeInterval(TimeInterval(s.workMinutes) * 60) }
        }
        if s.lunchEnabled {
            t.lunch = (s.lunchStart.date(on: now, calendar: calendar), s.lunchEnd.date(on: now, calendar: calendar))
        }
        return t
    }
}

enum SnapshotCalculator {
    /// spec 3절: 점심이 "유효" = 사용 중 && clockIn < lunchEnd && lunchStart < clockOut.
    static func validLunch(clockIn: Date, clockOut: Date,
                           lunch: (start: Date, end: Date)?) -> (start: Date, end: Date)? {
        guard let lunch, clockIn < lunch.end, lunch.start < clockOut else { return nil }
        return lunch
    }

    static func make(now: Date, times: DaySchedule.Times) -> WorkdaySnapshot {
        make(now: now, clockIn: times.clockIn, clockOut: times.clockOut,
             lunchStart: times.lunch?.start, lunchEnd: times.lunch?.end)
    }

    /// 매초 스냅샷 — 단계는 spec 3절 표를 위에서부터 먼저 맞는 순서로 결정한다.
    /// `lunchStart`/`lunchEnd` 는 설정상 점심 시각(사용 안 하면 nil). 유효하지 않으면 여기서 버린다.
    static func make(now: Date, clockIn: Date?, clockOut: Date?,
                     lunchStart: Date? = nil, lunchEnd: Date? = nil) -> WorkdaySnapshot {
        guard let clockIn, let clockOut else { return .waiting(now: now) }

        let lunch = validLunch(clockIn: clockIn, clockOut: clockOut,
                               lunch: lunchStart.flatMap { s in lunchEnd.map { (s, $0) } })
        let toClockOut = max(0, clockOut.timeIntervalSince(now))
        let overtime = max(0, now.timeIntervalSince(clockOut))
        let span = clockOut.timeIntervalSince(clockIn)
        let progress = span > 0 ? min(1, max(0, now.timeIntervalSince(clockIn) / span)) : 0

        let phase: WorkPhase
        var target: Date?
        if now < clockIn {
            phase = .waiting
            target = clockIn                       // 고정 모드의 출근 전
        } else if now >= clockOut {
            phase = .done
        } else if let lunch, now < lunch.start {
            phase = .beforeLunch; target = lunch.start
        } else if let lunch, now < lunch.end {
            phase = .lunch; target = lunch.end
        } else if toClockOut <= WorkRules.almostDoneThreshold {
            phase = .almostDone; target = clockOut
        } else {
            phase = .working; target = clockOut
        }

        return WorkdaySnapshot(
            now: now, clockIn: clockIn, clockOut: clockOut,
            lunchStart: lunch?.start, lunchEnd: lunch?.end,
            target: target,
            remaining: target.map { max(0, $0.timeIntervalSince(now)) } ?? 0,
            remainingToClockOut: toClockOut,
            overtime: overtime, progress: progress, phase: phase)
    }
}
