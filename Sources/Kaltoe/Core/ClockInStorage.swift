// 날짜별 출근 기록 저장 (UserDefaults, 키 `clockIn.yyyy-MM-dd`).
import Foundation

struct ClockInStorage {
    static let keyPrefix = "clockIn."

    let defaults: UserDefaults
    let calendar: Calendar

    private func key(for date: Date) -> String {
        Self.keyPrefix + ClockInRules.dayKey(date, calendar: calendar)
    }

    /// `date` 가 속한 날의 출근 기록. 없으면 nil.
    func load(for date: Date) -> Date? {
        guard let t = defaults.object(forKey: key(for: date)) as? Double else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// 규칙 1: 하루 하나. 이미 있으면 덮어쓰지 않고 false.
    @discardableResult
    func saveIfAbsent(_ clockIn: Date) -> Bool {
        let k = key(for: clockIn)
        guard defaults.object(forKey: k) == nil else { return false }
        defaults.set(clockIn.timeIntervalSince1970, forKey: k)
        return true
    }

    /// 14일 지난 기록 삭제.
    func purge(now: Date) {
        let keys = Array(defaults.dictionaryRepresentation().keys)
        for k in ClockInRules.keysToPurge(keys, now: now, calendar: calendar) {
            defaults.removeObject(forKey: k)
        }
    }
}
