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

    /// `working` 단계 주석 (spec 4절, 위에서부터 먼저 맞는 것).
    static func comment(for s: WorkdaySnapshot, lunchEnabled: Bool) -> String {
        if !lunchEnabled, Calendar.current.component(.hour, from: s.now) == 12 {
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

    static func lines(for s: WorkdaySnapshot, settings: WorkSettings = .default) -> [TerminalLine] {
        func line(_ spans: TextSpan...) -> TerminalLine { TerminalLine(spans: spans) }
        func cmd(_ text: String) -> TerminalLine {
            line(TextSpan(text: "$ ", style: .prompt), TextSpan(text: text, style: .command))
        }
        func out(_ text: String, _ style: LineStyle = .output) -> TerminalLine {
            line(TextSpan(text: text, style: style))
        }
        let inOut = "in \(clock(s.clockIn)) → out \(clock(s.clockOut))"

        switch s.phase {
        case .beforeLunch:
            return [
                cmd("npm install 점심"),
                line(TextSpan(text: "installing... ", style: .output),
                     TextSpan(text: remainingLong(s.remaining), style: .accent),
                     TextSpan(text: " left", style: .output)),
                out(progressBar(s.progress)),
                out(inOut),
                out("# 점심 \(clock(s.lunchStart)) · 퇴근까지 \(remainingShort(s.remainingToClockOut))", .comment),
            ]
        case .lunch:
            return [
                cmd("sleep 점심"),
                line(TextSpan(text: "점심 끝까지 ", style: .output),
                     TextSpan(text: remainingLong(s.remaining), style: .accent)),
                out(progressBar(s.progress)),
                out(inOut),
                out("# 지금은 밥이 P0 입니다", .comment),
            ]
        case .working:
            return [
                cmd("sudo 퇴근 --force"),
                line(TextSpan(text: "Permission denied: ", style: .output),
                     TextSpan(text: remainingLong(s.remaining), style: .accent),
                     TextSpan(text: " left", style: .output)),
                out(progressBar(s.progress)),
                out(inOut),
                out(comment(for: s, lunchEnabled: settings.lunchEnabled), .comment),
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
            if let pay = OvertimePay.display(for: s, settings: settings) {
                // 야근 줄은 그대로 두고 그 아래에 수당 줄을 따로 둔다 (총 5줄, spec 5-3절).
                result.append(out("# 야근 중 \(overtime(s.overtime))", .comment))
                if pay.comprehensive {
                    result.append(line(TextSpan(text: "# 포괄이라 ", style: .comment),
                                       TextSpan(text: OvertimePay.won(0), style: .accent),
                                       TextSpan(text: " (원래 +\(OvertimePay.won(pay.amount)))", style: .comment)))
                } else {
                    result.append(line(TextSpan(text: "# 연장수당 ", style: .comment),
                                       TextSpan(text: "+\(OvertimePay.won(pay.amount))", style: .accent)))
                }
            }
            return result
        case .waiting:
            // 고정 모드는 목표(출근 시각)가 있다. 유동 모드는 earliestStart 이후 첫 잠금 해제를 기다린다.
            let last: TerminalLine
            if let target = s.target {
                last = out("# 출근 \(clock(target)) 까지 \(remainingShort(s.remaining))", .comment)
            } else {
                last = out("# waiting for first unlock after \(settings.earliestStart.string)...", .comment)
            }
            return [cmd("whoami"), out("아직 출근 전인 사람"), last]
        }
    }

    // MARK: 메뉴바

    static func menuBarTitle(for s: WorkdaySnapshot) -> String {
        switch s.phase {
        case .waiting:
            return "출근 전"
        case .beforeLunch:
            return "점심까지 \(remainingShort(s.remaining))"
        case .lunch:
            return "점심 끝까지 \(remainingShort(s.remaining))"
        case .working, .almostDone:
            return "\(clock(s.clockOut))까지 \(remainingShort(s.remaining))"
        case .done:
            return s.overtime >= 60 ? "퇴근! +\(Int(s.overtime) / 60)m" : "퇴근!"
        }
    }

    // MARK: 말풍선 (docs/spec.md 5-2절)

    /// 분 단위 올림 (0초 초과 → 최소 1분, 60초 → 1분, 61초 → 2분).
    static func ceilMinutes(_ seconds: TimeInterval) -> Int {
        max(1, Int((max(0, seconds) / 60).rounded(.up)))
    }

    /// 말풍선 한 줄 문구.
    static func bubbleText(for s: WorkdaySnapshot, settings: WorkSettings = .default) -> String {
        let minutes = ceilMinutes(s.remaining)
        switch s.phase {
        case .waiting:
            return s.target == nil ? "출근 전…" : "출근 \(minutes)분 전"   // 유동 / 고정
        case .beforeLunch: return "점심 \(minutes)분 전"
        case .lunch: return "점심 끝 \(minutes)분 전"
        case .working: return "퇴근 \(minutes)분 전"
        case .almostDone: return "퇴근 \(minutes)분 전!"
        case .done:
            // 야근 1분 이상이면 연장수당 문구로 바뀐다 (5-3절).
            guard let pay = OvertimePay.display(for: s, settings: settings) else { return "퇴근하세요!" }
            return pay.comprehensive
                ? "야근 \(pay.minutes)분 · \(OvertimePay.won(0)) (포괄)"
                : "야근 \(pay.minutes)분 · +\(OvertimePay.won(pay.amount))"
        }
    }

    // MARK: 메뉴 항목 문구

    static func clockInMenuTitle(for s: WorkdaySnapshot) -> String {
        s.clockIn == nil ? "출근 기록 없음" : "출근 \(clock(s.clockIn))"
    }

    /// 출근이 없으면 nil (항목을 표시하지 않는다).
    static func clockOutMenuTitle(for s: WorkdaySnapshot) -> String? {
        s.clockIn == nil || s.clockOut == nil ? nil : "퇴근 \(clock(s.clockOut))"
    }

    /// done 이고 야근 1분 이상일 때만 (퇴근 줄 아래 비활성 항목).
    static func overtimePayMenuTitle(for s: WorkdaySnapshot, settings: WorkSettings) -> String? {
        guard let pay = OvertimePay.display(for: s, settings: settings) else { return nil }
        return pay.comprehensive ? "연장수당 \(OvertimePay.won(0)) (포괄)" : "연장수당 +\(OvertimePay.won(pay.amount))"
    }

    /// `lunch.enabled` 일 때만 (설정 기준 — 유효 여부와 무관).
    static func lunchMenuTitle(for settings: WorkSettings) -> String? {
        settings.lunchEnabled ? "점심 \(settings.lunchStart.string)–\(settings.lunchEnd.string)" : nil
    }

    /// 설정 화면 미리보기 한 줄. `출근 08:30 · 점심 11:30–13:00 · 퇴근 17:30`
    /// 유동 모드에서 오늘 기록이 없으면 `출근 —` (퇴근도 `—`).
    static func previewLine(settings s: WorkSettings, detectedClockIn: Date?, now: Date,
                            calendar: Calendar = .current) -> String {
        let t = DaySchedule.times(settings: s, detectedClockIn: detectedClockIn, now: now, calendar: calendar)
        var parts = ["출근 \(t.clockIn.map { clock($0) } ?? "—")"]
        if s.lunchEnabled { parts.append("점심 \(s.lunchStart.string)–\(s.lunchEnd.string)") }
        parts.append("퇴근 \(t.clockOut.map { clock($0) } ?? "—")")
        return parts.joined(separator: " · ")
    }
}
