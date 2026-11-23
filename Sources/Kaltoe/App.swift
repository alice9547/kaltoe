// 앱 진입점.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkdayStore()
    private let settings = SettingsStore()
    private var engine: WorkdayEngine?
    private var widget: WidgetController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var demoTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var actions = AppActions()
        actions.isLaunchAtLoginEnabled = { LoginItem.isEnabled }
        actions.setLaunchAtLogin = { LoginItem.setEnabled($0) }
        actions.quit = { NSApp.terminate(nil) }
        actions.openSettings = { [weak self] in self?.settingsWindow?.show() }
        actions.redetectToday = { [weak self] in self?.engine?.redetectToday() }

        // 설정 화면 미리보기가 쓰는 오늘의 유동 모드 출근 기록.
        let storage = ClockInStorage(defaults: .standard, calendar: .autoupdatingCurrent)
        settingsWindow = SettingsWindowController(
            store: store, settingsStore: settings, actions: actions,
            detectedClockIn: { storage.load(for: Date()) })

        let widget = WidgetController(store: store, settings: settings)
        self.widget = widget
        menuBar = MenuBarController(store: store, settings: settings, widget: widget, actions: actions)
        widget.show()

        if let demo = DemoMode.fromArguments() {
            startDemo(demo)
        } else {
            enableLaunchAtLoginOnFirstRun()
            let engine = WorkdayEngine(store: store, settings: settings)
            self.engine = engine
            engine.start()
        }

        // 확인용: `--font-size <8~32>` 는 저장 없이 이번 실행에만 글자 크기(px)를 바꾼다.
        if let i = CommandLine.arguments.firstIndex(of: "--font-size"),
           CommandLine.arguments.indices.contains(i + 1), let v = Int(CommandLine.arguments[i + 1]) {
            var s = settings.settings
            s.fontSize = v
            settings.update(s, persist: false)
        }

        // 확인용: `--comprehensive [on|off]` 는 저장 없이 이번 실행에만 포괄임금제를 켜거나(기본 on) 끈다.
        if let i = CommandLine.arguments.firstIndex(of: "--comprehensive") {
            var s = settings.settings
            let next = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "on"
            s.comprehensivePay = next != "off"
            settings.update(s, persist: false)
        }

        // 확인용: `--style terminal|bubble` 도 저장 없이 이번 실행에만 모양을 바꾼다.
        if let i = CommandLine.arguments.firstIndex(of: "--style"),
           CommandLine.arguments.indices.contains(i + 1),
           let style = WidgetStyle(rawValue: CommandLine.arguments[i + 1]) {
            var s = settings.settings
            s.widgetStyle = style
            settings.update(s, persist: false)
        }

        // 확인용: 설정 창을 바로 띄운다.
        if CommandLine.arguments.contains("--settings") { settingsWindow?.show() }
    }

    /// 앱이 꺼져 있으면 출근을 실시간으로 못 잡으므로, 처음 한 번은 자동 실행을 켠다.
    /// 이후에는 메뉴에서 끈 상태를 존중한다.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "loginItem.configured"
        guard Bundle.main.bundleIdentifier != nil,
              !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        LoginItem.setEnabled(true)
    }

    /// UI 확인용 가짜 데이터. `--demo waiting|beforelunch|lunch|working|almost|done`
    private func startDemo(_ mode: DemoMode) {
        let start = Date()
        let update = { [store] in
            store.snapshot = mode.snapshot(launchedAt: start, now: Date())
        }
        update()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in update() }
    }
}

enum DemoMode: String {
    case waiting, beforelunch, lunch, working, almost, done

    static func fromArguments() -> DemoMode? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo") else { return nil }
        return args.indices.contains(i + 1) ? DemoMode(rawValue: args[i + 1]) ?? .working : .working
    }

    /// 실행 시점을 기준으로 가짜 일정을 만들고, 단계는 실제와 같은 순수 함수로 정한다.
    func snapshot(launchedAt: Date, now: Date) -> WorkdaySnapshot {
        let workDay: TimeInterval = 9 * 3600
        let lunchLength: TimeInterval = 90 * 60
        func at(_ seconds: TimeInterval) -> Date { launchedAt.addingTimeInterval(seconds) }

        var clockOut: Date
        var lunch: (Date, Date)?
        switch self {
        case .waiting: return .waiting(now: now)
        case .working: clockOut = at(3 * 3600 + 12 * 60 + 8)
        case .almost: clockOut = at(9 * 60 + 5)
        case .done: clockOut = at(-12 * 60)
        case .beforelunch:
            // 점심 시작 42m 08s 전, 출근은 점심 3시간 전
            let lunchStart = at(42 * 60 + 8)
            lunch = (lunchStart, lunchStart.addingTimeInterval(lunchLength))
            clockOut = lunchStart.addingTimeInterval(-3 * 3600 + workDay)
        case .lunch:
            // 점심 끝 18m 08s 전
            let lunchEnd = at(18 * 60 + 8)
            lunch = (lunchEnd.addingTimeInterval(-lunchLength), lunchEnd)
            clockOut = lunchEnd.addingTimeInterval(-lunchLength - 3 * 3600 + workDay)
        }
        return SnapshotCalculator.make(now: now, clockIn: clockOut.addingTimeInterval(-workDay), clockOut: clockOut,
                                       lunchStart: lunch?.0, lunchEnd: lunch?.1)
    }
}

@main
enum KaltoeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
