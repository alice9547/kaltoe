import AppKit
import SwiftUI
import Combine

/// 포커스를 뺏지 않는 터미널 모양 플로팅 패널.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 첫 클릭부터 바로 반응하게 한다 (비활성 앱 위에서도 빨간 점·마스코트 클릭 가능).
private final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    /// 오른쪽 클릭 메뉴를 만들어 주는 함수 (메뉴바 메뉴와 같은 것).
    var menuProvider: (() -> NSMenu?)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    // control+클릭도 오른쪽 클릭으로 본다.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event) } else { super.mouseDown(with: event) }
    }

    private func showMenu(_ event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// 항상 최상단에 뜨는 플로팅 위젯 창.
final class WidgetController {
    private enum Key {
        static func origin(_ style: WidgetStyle) -> String {
            // 모양마다 자기 위치를 따로 저장한다. 터미널은 기존 키를 그대로 쓴다.
            style == .terminal ? "widget.origin" : "widget.origin.bubble"
        }
        static let visible = "widget.visible"
    }

    private let store: WorkdayStore
    private let panel: WidgetPanel
    private let clock = AnimationClock()
    private let defaults = UserDefaults.standard
    private let settings: SettingsStore
    private var moveObserver: NSObjectProtocol?
    private var layoutCancellable: AnyCancellable?
    private var currentFontSize: Int
    private var currentStyle: WidgetStyle
    private var mouseUpMonitor: Any?
    private var hosting: WidgetHostingView<WidgetRootView>!

    /// 위젯 오른쪽 클릭 때 띄울 메뉴. 메뉴바 메뉴와 같은 NSMenu 를 만들어 준다.
    var contextMenuProvider: (() -> NSMenu?)? {
        didSet { hosting.menuProvider = contextMenuProvider }
    }

    init(store: WorkdayStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
        currentFontSize = settings.settings.fontSize
        currentStyle = settings.settings.widgetStyle
        let size = Self.windowSize(style: currentStyle, fontSize: currentFontSize)
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = currentStyle == .terminal      // 말풍선은 그림자 없음
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // 뷰의 닫기 클로저는 아래에서 self 를 쓰므로 초기화 후 연결한다.
        let view = WidgetRootView(store: store, settings: settings, clock: clock, onClose: { [weak self] in self?.hide() })
        let hosting = WidgetHostingView(rootView: view)
        self.hosting = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        panel.setFrameOrigin(Self.clamped(NSRect(origin: restoredOrigin(style: currentStyle, size: size), size: size)).origin)
        layoutCancellable = settings.$settings
            .map { Layout(style: $0.widgetStyle, fontSize: $0.fontSize) }
            .removeDuplicates()
            .sink { [weak self] in self?.applyLayout($0) }
        // 드래그를 놓으면 화면 밖으로 나간 위젯을 안으로 밀어 넣는다.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if let self, event.window === self.panel { self.rescueIfOffscreen() }
            return event
        }
        // 드래그 중·후의 위치를 저장한다.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.defaults.set(NSStringFromPoint(self.panel.frame.origin), forKey: Key.origin(self.currentStyle))
        }
    }

    private struct Layout: Equatable {
        var style: WidgetStyle
        var fontSize: Int
    }

    static func windowSize(style: WidgetStyle, fontSize: Int) -> CGSize {
        switch style {
        case .terminal: return WidgetView.size(fontSize: fontSize)
        case .bubble: return BubbleWidgetView.size(fontSize: fontSize)
        }
    }

    /// 모양이나 글자 크기가 바뀌면 즉시 창을 바꾼다.
    /// - 글자 크기만: 왼쪽 위 모서리를 유지하고, 화면 밖으로 나가면 안으로 밀어 넣는다.
    /// - 모양: 그 모양에 저장된 위치로 옮긴다 (없으면 기본 위치).
    private func applyLayout(_ layout: Layout) {
        guard layout.style != currentStyle || layout.fontSize != currentFontSize else { return }
        let size = Self.windowSize(style: layout.style, fontSize: layout.fontSize)
        let old = panel.frame
        var frame: NSRect
        if layout.style != currentStyle {
            currentStyle = layout.style          // didMove 가 새 모양의 키로 저장하도록 먼저 바꾼다
            panel.hasShadow = layout.style == .terminal
            frame = NSRect(origin: restoredOrigin(style: layout.style, size: size), size: size)
        } else {
            frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        }
        currentFontSize = layout.fontSize
        frame = Self.clamped(frame)
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        panel.invalidateShadow()
    }

    /// 창이 걸쳐 있는 화면(없으면 주 화면)의 보이는 영역 안으로 밀어 넣는다.
    static func clamped(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { a, b in
            let ia = a.visibleFrame.intersection(frame), ib = b.visibleFrame.intersection(frame)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return frame }
        var f = frame
        f.origin.x = min(max(f.origin.x, area.minX), max(area.minX, area.maxX - f.width))
        f.origin.y = min(max(f.origin.y, area.minY), max(area.minY, area.maxY - f.height))
        return f
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
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

    /// 재실행 때: 보이게 하고 주 화면 오른쪽 위(현재 모양 크기 기준)로 옮긴다. 옮긴 위치는 didMove 가 저장한다.
    func revealAtDefaultPosition() {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let size = panel.frame.size
        panel.setFrameOrigin(WidgetPlacement.topRightOrigin(size: size, area: area))
        defaults.set(NSStringFromPoint(panel.frame.origin), forKey: Key.origin(currentStyle))
        show()
    }

    private func rescueIfOffscreen() {
        let areas = NSScreen.screens.map(\.visibleFrame)
        let fixed = WidgetPlacement.corrected(panel.frame, areas: areas)
        if fixed != panel.frame { panel.setFrame(fixed, display: true) }
    }

    // MARK: 위치

    private func restoredOrigin(style: WidgetStyle, size: CGSize) -> NSPoint {
        if let s = defaults.string(forKey: Key.origin(style)) {
            let p = NSPointFromString(s)
            let frame = NSRect(origin: p, size: size)
            // 어느 화면에든 가로·세로 48pt 이상 걸쳐 있어야 유효.
            if WidgetPlacement.isReachable(frame, areas: NSScreen.screens.map(\.visibleFrame)) { return p }
        }
        return defaultOrigin(style: style, size: size)
    }

    /// 터미널: 주 화면 오른쪽 위, 메뉴바 아래 16pt. 말풍선: 오른쪽 아래 구석 16pt.
    private func defaultOrigin(style: WidgetStyle, size: CGSize) -> NSPoint {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        switch style {
        case .terminal: return NSPoint(x: area.maxX - size.width - 16, y: area.maxY - size.height - 16)
        case .bubble: return NSPoint(x: area.maxX - size.width - 16, y: area.minY + 16)
        }
    }
}
