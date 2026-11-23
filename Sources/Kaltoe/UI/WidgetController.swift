import AppKit
import SwiftUI

/// 포커스를 뺏지 않는 터미널 모양 플로팅 패널.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 첫 클릭부터 바로 반응하게 한다 (비활성 앱 위에서도 빨간 점·마스코트 클릭 가능).
private final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 항상 최상단에 뜨는 플로팅 위젯 창.
final class WidgetController {
    private enum Key {
        static let origin = "widget.origin"
        static let visible = "widget.visible"
    }

    private let store: WorkdayStore
    private let panel: WidgetPanel
    private let clock = AnimationClock()
    private let defaults = UserDefaults.standard
    private var moveObserver: NSObjectProtocol?

    init(store: WorkdayStore) {
        self.store = store
        let size = WidgetView.size
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // 뷰의 닫기 클로저는 아래에서 self 를 쓰므로 초기화 후 연결한다.
        let view = WidgetView(store: store, clock: clock, onClose: { [weak self] in self?.hide() })
        let hosting = WidgetHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        panel.setFrameOrigin(restoredOrigin(size: size))
        // 드래그 중·후의 위치를 저장한다.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.defaults.set(NSStringFromPoint(self.panel.frame.origin), forKey: Key.origin)
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
        clock.start()
        defaults.set(true, forKey: Key.visible)
    }

    func hide() {
        panel.orderOut(nil)
        clock.stop()
        defaults.set(false, forKey: Key.visible)
    }

    // MARK: 위치

    private func restoredOrigin(size: CGSize) -> NSPoint {
        if let s = defaults.string(forKey: Key.origin) {
            let p = NSPointFromString(s)
            let frame = NSRect(origin: p, size: size)
            // 어느 화면에든 제목 줄 일부(60×26)가 걸쳐 있어야 유효.
            let valid = NSScreen.screens.contains { screen in
                let i = screen.visibleFrame.intersection(frame)
                return !i.isNull && i.width >= 60 && i.height >= 26
            }
            if valid { return p }
        }
        return defaultOrigin(size: size)
    }

    /// 주 화면 오른쪽 위, 메뉴바 아래 16pt.
    private func defaultOrigin(size: CGSize) -> NSPoint {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        return NSPoint(x: area.maxX - size.width - 16, y: area.maxY - size.height - 16)
    }
}
