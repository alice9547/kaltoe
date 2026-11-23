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
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clock: AnimationClock
    var onClose: () -> Void

    /// 기본(100%) 창 크기.
    static let baseSize = CGSize(width: 320, height: 150)
    /// 기본 마스코트 표시 크기.
    static let baseMascot: CGFloat = 56

    /// 글자 크기(px) → 위젯 전체 비율 (`fontSize / 12`).
    static func ratio(fontSize: Int) -> CGFloat { CGFloat(fontSize) / CGFloat(WorkSettings.baseFontSize) }

    /// `widget.fontSize` 를 적용한 창 크기 (점 단위로 반올림).
    static func size(fontSize: Int) -> CGSize {
        let k = ratio(fontSize: fontSize)
        return CGSize(width: (baseSize.width * k).rounded(), height: (baseSize.height * k).rounded())
    }

    /// 위젯 전체(글자·줄 간격·여백·상단 바·신호등·마스코트)에 곱하는 비율.
    private var k: CGFloat { Self.ratio(fontSize: settings.settings.fontSize) }
    private var mono: Font { .system(size: 12 * k, design: .monospaced) }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            content
        }
        .frame(width: Self.size(fontSize: settings.settings.fontSize).width,
               height: Self.size(fontSize: settings.settings.fontSize).height)
        .background(Color(hex: 0x1B1B1F, opacity: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12 * k, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12 * k, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: max(1, k)))
    }

    private var titleBar: some View {
        ZStack {
            Color(hex: 0x2A2A30)
            Text("kaltoe — zsh")
                .font(.system(size: 11 * k))
                .foregroundColor(Color(hex: 0x8E8E93))
            HStack(spacing: 7 * k) {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 11 * k, height: 11 * k)
                    .contentShape(Circle().inset(by: -3 * k))
                    .onTapGesture(perform: onClose)
                Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 11 * k, height: 11 * k)
                Circle().fill(Color(hex: 0x28C840)).frame(width: 11 * k, height: 11 * k)
                Spacer()
            }
            .padding(.leading, 10 * k)
        }
        .frame(height: 26 * k)
    }

    private var content: some View {
        let snap = store.snapshot
        let lines = WidgetText.lines(for: snap, settings: settings.settings)
        let cursorOn = (clock.tick / 3) % 2 == 0
        return ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 2 * k) {
                ForEach(lines.indices, id: \.self) { i in
                    render(lines[i], cursor: i == lines.count - 1 ? cursorOn : nil)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12 * k)
            .padding(.top, 9 * k)

            MascotView(mood: MascotMood.resolve(snap, settings: settings.settings), tick: clock.tick, jumpStart: clock.jumpStart,
                       onTap: { clock.jump() })
                .scaledMascot(baseSize: Self.baseMascot, ratio: k)
                .padding(.trailing, 8 * k)
                .padding(.bottom, 6 * k)
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
