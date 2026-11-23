import AppKit
import SwiftUI

/// 설정 창. 한 번에 하나만 열리고, 닫아도 앱은 종료되지 않는다.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: WorkdayStore
    private let settingsStore: SettingsStore
    private let actions: AppActions
    private let detectedClockIn: () -> Date?
    private var window: NSWindow?

    init(store: WorkdayStore, settingsStore: SettingsStore, actions: AppActions,
         detectedClockIn: @escaping () -> Date?) {
        self.store = store
        self.settingsStore = settingsStore
        self.actions = actions
        self.detectedClockIn = detectedClockIn
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            // 열 때마다 저장된 값으로 다시 시작한다 (열려 있던 임시 입력이 남지 않게).
            let hosting = NSHostingView(rootView: SettingsView(
                store: store, settingsStore: settingsStore, actions: actions, detectedClockIn: detectedClockIn))
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)
            window.center()
        }
        // 앱이 accessory 라서 직접 앞으로 가져와야 한다.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // 활성화가 거절돼도(다른 앱이 앞일 때) 창은 맨 앞으로
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "칼퇴 설정"
        w.isReleasedWhenClosed = false
        w.delegate = self
        return w
    }
}
