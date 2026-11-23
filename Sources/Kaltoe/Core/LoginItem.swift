// 스텁 — 워크스트림 A 가 구현한다.
import Foundation

/// 로그인 시 자동 실행 등록.
enum LoginItem {
    static var isEnabled: Bool { false }
    static func setEnabled(_ enabled: Bool) {}
}
