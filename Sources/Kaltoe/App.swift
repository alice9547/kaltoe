// 앱 진입점 — 머리(conductor) 소유. 손은 수정하지 않는다.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkdayStore()
    private var engine: WorkdayEngine?
    private var widget: WidgetController?
    private var menuBar: MenuBarController?
    private var demoTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO(conductor): [A↔B] 자동 실행 토글을 LoginItem 에 연결 (지금은 빈 동작)
        var actions = AppActions()
        actions.quit = { NSApp.terminate(nil) }

        let widget = WidgetController(store: store)
        self.widget = widget
        menuBar = MenuBarController(store: store, widget: widget, actions: actions)
        widget.show()

        if let demo = DemoMode.fromArguments() {
            startDemo(demo)
        } else {
            // TODO(conductor): [A↔B] 실제 엔진이 store 를 갱신 — 통합 때 동작 확인
            let engine = WorkdayEngine(store: store)
            self.engine = engine
            engine.start()
        }
    }

    /// UI 확인용 가짜 데이터. `--demo working|almost|done|waiting`
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
    case waiting, working, almost, done

    static func fromArguments() -> DemoMode? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo") else { return nil }
        return args.indices.contains(i + 1) ? DemoMode(rawValue: args[i + 1]) ?? .working : .working
    }

    func snapshot(launchedAt: Date, now: Date) -> WorkdaySnapshot {
        let total = WorkRules.workDuration
        // 실행 시점에 남아 있던 시간(초)
        let remainingAtLaunch: TimeInterval
        switch self {
        case .waiting: return .waiting(now: now)
        case .working: remainingAtLaunch = 3 * 3600 + 12 * 60 + 8
        case .almost: remainingAtLaunch = 9 * 60 + 5
        case .done: remainingAtLaunch = -12 * 60
        }
        let clockOut = launchedAt.addingTimeInterval(remainingAtLaunch)
        let clockIn = clockOut.addingTimeInterval(-total)
        let left = clockOut.timeIntervalSince(now)
        let phase: WorkPhase = left <= 0 ? .done
            : (left <= WorkRules.almostDoneThreshold ? .almostDone : .working)
        return WorkdaySnapshot(
            now: now, clockIn: clockIn, clockOut: clockOut,
            remaining: max(0, left), overtime: max(0, -left),
            progress: min(1, max(0, now.timeIntervalSince(clockIn) / total)),
            phase: phase)
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
