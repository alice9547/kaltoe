import AppKit
import Combine

/// 메뉴바 항목과 메뉴.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: WorkdayStore
    private let widget: WidgetController
    private let actions: AppActions
    private let statusItem: NSStatusItem
    private var cancellable: AnyCancellable?
    private var lastTitle: String?

    init(store: WorkdayStore, widget: WidgetController, actions: AppActions) {
        self.store = store
        self.widget = widget
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = MascotArt.templateImage(size: 16)
            button.imagePosition = .imageLeft
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        applyTitle(store.snapshot)
        cancellable = store.$snapshot.sink { [weak self] snap in self?.applyTitle(snap) }
    }

    deinit { NSStatusBar.system.removeStatusItem(statusItem) }

    // 문자열이 같으면 다시 쓰지 않는다.
    private func applyTitle(_ snap: WorkdaySnapshot) {
        let title = WidgetText.menuBarTitle(for: snap)
        guard title != lastTitle else { return }
        lastTitle = title
        statusItem.button?.attributedTitle = NSAttributedString(
            string: " " + title,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
    }

    // MARK: 메뉴 (열릴 때마다 최신 상태로 다시 만든다)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = store.snapshot

        menu.addItem(info(WidgetText.clockInMenuTitle(for: snap)))
        if let out = WidgetText.clockOutMenuTitle(for: snap) { menu.addItem(info(out)) }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: widget.isVisible ? "위젯 숨기기" : "위젯 보이기",
                                action: #selector(toggleWidget), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let login = NSMenuItem(title: "로그인 시 자동 실행",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = actions.isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "칼퇴 종료", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleWidget() {
        if widget.isVisible { widget.hide() } else { widget.show() }
    }

    @objc private func toggleLaunchAtLogin() {
        actions.setLaunchAtLogin(!actions.isLaunchAtLoginEnabled())
    }

    @objc private func quitApp() { actions.quit() }
}
