import SwiftUI

/// 위젯이 보일 때만 도는 애니메이션 시계 (0.1초 단위).
final class AnimationClock: ObservableObject {
    @Published private(set) var tick = 0
    @Published private(set) var jumpStart: Int?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick &+= 1
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func jump() { jumpStart = tick }
}

struct WidgetView: View {
    @ObservedObject var store: WorkdayStore
    @ObservedObject var clock: AnimationClock
    var onClose: () -> Void

    static let size = CGSize(width: 320, height: 150)
    private let mono = Font.system(size: 12, design: .monospaced)

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(hex: 0x1B1B1F, opacity: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var titleBar: some View {
        ZStack {
            Color(hex: 0x2A2A30)
            Text("kaltoe — zsh")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: 0x8E8E93))
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 11, height: 11)
                    .contentShape(Circle().inset(by: -3))
                    .onTapGesture(perform: onClose)
                Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 11, height: 11)
                Circle().fill(Color(hex: 0x28C840)).frame(width: 11, height: 11)
                Spacer()
            }
            .padding(.leading, 10)
        }
        .frame(height: 26)
    }

    private var content: some View {
        let snap = store.snapshot
        let lines = WidgetText.lines(for: snap)
        let cursorOn = (clock.tick / 3) % 2 == 0
        return ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { i in
                    render(lines[i], cursor: i == lines.count - 1 ? cursorOn : nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 9)

            MascotView(phase: snap.phase, tick: clock.tick, jumpStart: clock.jumpStart,
                       onTap: { clock.jump() })
                .padding(.trailing, 8)
                .padding(.bottom, 6)
        }
    }

    private func render(_ line: TerminalLine, cursor: Bool?) -> some View {
        var text = Text("")
        for span in line.spans {
            var t = Text(span.text).foregroundColor(color(span.style))
            if span.style == .accentBold { t = t.bold() }
            text = text + t
        }
        if let on = cursor {
            text = text + Text("▋").foregroundColor(Color(hex: 0xF2F2F7, opacity: on ? 1 : 0))
        }
        return text.font(mono).lineLimit(1).fixedSize()
    }

    private func color(_ s: LineStyle) -> Color {
        switch s {
        case .prompt, .success: return Color(hex: 0x28C840)
        case .command: return Color(hex: 0xF2F2F7)
        case .output: return Color(hex: 0xC7C7CC)
        case .accent, .accentBold: return Color(hex: 0xF28C5A)
        case .comment: return Color(hex: 0x6E6E73)
        }
    }
}
