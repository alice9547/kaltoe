// 로그인 시 자동 실행 등록 (SMAppService.mainApp).
// TODO(conductor): [A↔B] App.swift 의 AppActions 에 연결 —
//   actions.isLaunchAtLoginEnabled = { LoginItem.isEnabled }, actions.setLaunchAtLogin = { LoginItem.setEnabled($0) }
import Foundation
import ServiceManagement

enum LoginItem {
    /// 번들 식별자가 없으면(swift run) 항상 false.
    static var isEnabled: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 번들 식별자가 없으면 아무것도 하지 않는다. 오류는 삼키고 로그만 남긴다.
    static func setEnabled(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
        } catch {
            NSLog("Kaltoe: 로그인 시 자동 실행 \(enabled ? "등록" : "해제") 실패: \(error)")
        }
    }
}
