// 위젯·메뉴바 문구 생성 — WorkdaySnapshot 을 받아 문자열을 돌려주는 순수 함수 모음.
import Foundation

enum LineStyle: Equatable {
    case prompt, command, output, accent, accentBold, success, comment
}

struct TextSpan: Equatable {
    var text: String
    var style: LineStyle
}

struct TerminalLine: Equatable {
    var spans: [TextSpan]
    var plain: String { spans.map(\.text).joined() }
}

enum WidgetText {
    // MARK: 포맷

    /// `HH:mm` 24시간제.
    static func clock(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `3h 12m 08s` / `12m 08s`.
    static func remainingLong(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        return String(format: "%dm %02ds", m, s)
    }

    /// `3h 12m` / `12m` / `42s` (메뉴바용).
    static func remainingShort(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let h = t / 3600, m = (t % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(t)s"
    }

    /// `+0h 12m`
    static func overtime(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return "+\(t / 3600)h \((t % 3600) / 60)m"
    }

    /// 20칸 진행률 바. 예: `[##########..........] 52%`
    static func progressBar(_ progress: Double, cells: Int = 20) -> String {
        let p = min(1, max(0, progress))
        let filled = min(cells, Int(p * Double(cells)))
        return "[" + String(repeating: "#", count: filled)
            + String(repeating: ".", count: cells - filled) + "] \(Int(p * 100))%"
    }

    // MARK: 주석

    static func comment(for s: WorkdaySnapshot) -> String {
        if Calendar.current.component(.hour, from: s.now) == 12 {
            return "# 점심: 일단 밥부터 먹고 생각하자"
        }
        switch s.progress {
        case ..<0.25: return "# 아직 컴파일 중..."
        case ..<0.50: return "# it works on my machine"
        case ..<0.75: return "# 반 넘었다. 나머지는 미래의 내가"
        default: return "# 거의 다 왔다. 금요일 배포만 하지 말자"
        }
    }

    // MARK: 위젯 본문

    static func lines(for s: WorkdaySnapshot) -> [TerminalLine] {
        func line(_ spans: TextSpan...) -> TerminalLine { TerminalLine(spans: spans) }
        func cmd(_ text: String) -> TerminalLine {
            line(TextSpan(text: "$ ", style: .prompt), TextSpan(text: text, style: .command))
        }
        func out(_ text: String, _ style: LineStyle = .output) -> TerminalLine {
            line(TextSpan(text: text, style: style))
        }
        let inOut = "in \(clock(s.clockIn)) → out \(clock(s.clockOut))"

        switch s.phase {
        case .working:
            return [
                cmd("sudo 퇴근 --force"),
                line(TextSpan(text: "Permission denied: ", style: .output),
                     TextSpan(text: remainingLong(s.remaining), style: .accent),
                     TextSpan(text: " left", style: .output)),
                out(progressBar(s.progress)),
                out(inOut),
                out(comment(for: s), .comment),
            ]
        case .almostDone:
            return [
                cmd("git commit -m \"퇴근 준비\""),
                out("\(remainingLong(s.remaining)) left", .accentBold),
                out(progressBar(s.progress)),
                out(inOut),
                out("# 지금 배포하면 안 됩니다", .comment),
            ]
        case .done:
            var result = [
                cmd("exit"),
                out("Process finished with exit code 0", .success),
                out("퇴근하세요! out \(clock(s.clockOut))"),
            ]
            if s.overtime >= 60 { result.append(out("# 야근 중 \(overtime(s.overtime))", .comment)) }
            return result
        case .waiting:
            return [
                cmd("whoami"),
                out("아직 출근 전인 사람"),
                out(String(format: "# waiting for first unlock after %02d:00...",
                           WorkRules.earliestClockInHour), .comment),
            ]
        }
    }

    // MARK: 메뉴바

    static func menuBarTitle(for s: WorkdaySnapshot) -> String {
        switch s.phase {
        case .working, .almostDone:
            return "\(clock(s.clockOut))까지 \(remainingShort(s.remaining))"
        case .done:
            return s.overtime >= 60 ? "퇴근! +\(Int(s.overtime) / 60)m" : "퇴근!"
        case .waiting:
            return "출근 전"
        }
    }

    static func clockInMenuTitle(for s: WorkdaySnapshot) -> String {
        s.phase == .waiting || s.clockIn == nil ? "출근 기록 없음" : "출근 \(clock(s.clockIn))"
    }

    /// waiting 이면 nil (항목을 표시하지 않는다).
    static func clockOutMenuTitle(for s: WorkdaySnapshot) -> String? {
        s.phase == .waiting || s.clockOut == nil ? nil : "퇴근 \(clock(s.clockOut))"
    }
}
