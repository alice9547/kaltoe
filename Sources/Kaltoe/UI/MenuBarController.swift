import AppKit
import Combine

/// 메뉴바 항목과 메뉴.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let store: WorkdayStore
    private let settings: SettingsStore
    private let widget: WidgetController
    private let actions: AppActions
    private let statusItem: NSStatusItem
    private var cancellable: AnyCancellable?
    private var lastTitle: String?

    init(store: WorkdayStore, settings: SettingsStore, widget: WidgetController, actions: AppActions) {
        self.store = store
        self.settings = settings
        self.widget = widget
        self.actions = actions
        // 새 항목은 메뉴바 맨 왼쪽에 생겨서, 항목이 많은 노치 맥에서는 노치 뒤로 숨는다.
        // 처음 한 번만 오른쪽 영역(오른쪽 끝에서 약 400pt)을 기본 위치로 준다. 이후엔 ⌘드래그한 위치가 유지된다.
        let positionKey = "NSStatusItem Preferred Position kaltoe"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(400.0, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "kaltoe"
        super.init()

        if let button = statusItem.button {
            button.image = MascotImage.menuBarTemplate(pointSize: 16)
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
        if let pay = WidgetText.overtimePayMenuTitle(for: snap, settings: settings.settings) { menu.addItem(info(pay)) }
        if let lunch = WidgetText.lunchMenuTitle(for: settings.settings) { menu.addItem(info(lunch)) }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: widget.isVisible ? "위젯 숨기기" : "위젯 보이기",
                                action: #selector(toggleWidget), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let prefs = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        if settings.settings.mode == .flexible {
            let redetect = NSMenuItem(title: "오늘 출근 다시 감지", action: #selector(redetectToday), keyEquivalent: "")
            redetect.target = self
            menu.addItem(redetect)
        }

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

    @objc private func openSettings() { actions.openSettings() }

    @objc private func redetectToday() { actions.redetectToday() }

    @objc private func toggleLaunchAtLogin() {
        actions.setLaunchAtLogin(!actions.isLaunchAtLoginEnabled())
    }

    @objc private func quitApp() { actions.quit() }
}
