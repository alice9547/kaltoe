// 시스템 호출 모음 (테스트 대상 아님 — 순수 로직은 ClockInRules 등에 있다).
import Foundation
import CoreGraphics

enum SystemInfo {
    /// 부팅 시각 (`sysctl kern.boottime`).
    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    /// 화면이 잠겨 있는가 (`CGSSessionScreenIsLocked`). 세션 정보가 없으면 false.
    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let b = dict["CGSSessionScreenIsLocked"] as? Bool { return b }
        if let n = dict["CGSSessionScreenIsLocked"] as? NSNumber { return n.boolValue }
        return false
    }
}
