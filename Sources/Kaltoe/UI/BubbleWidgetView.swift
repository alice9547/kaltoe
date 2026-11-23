// 말풍선 모양 위젯 (docs/spec.md 5-2절): 투명 창에 마스코트와 한 줄 말풍선.
import SwiftUI

/// 계단 모서리(2px 단위)를 가진 말풍선 + 오른쪽 아래를 향한 꼬리. 모든 변이 축에 평행해서 또렷하다.
/// 사각형 `rect` 아래로 꼬리가 `tail` 만큼 더 나온다.
struct BubbleShape: Shape {
    var step: CGFloat          // 계단 한 칸 (2px × 비율)
    var tailHeight: CGFloat

    func path(in r: CGRect) -> Path {
        let s = step
        let w = r.width, h = r.height - tailHeight
        var p = Path()
        // 위쪽 변 → 오른쪽 위 모서리
        p.move(to: CGPoint(x: 2 * s, y: 0))
        for pt in [(w - 2 * s, 0), (w - 2 * s, s), (w - s, s), (w - s, 2 * s), (w, 2 * s),
                   // 오른쪽 변 → 오른쪽 아래 모서리
                   (w, h - 2 * s), (w - s, h - 2 * s), (w - s, h - s), (w - 2 * s, h - s), (w - 2 * s, h),
                   // 꼬리: 오른쪽은 수직, 왼쪽은 계단 (오른쪽 아래 방향)
                   (w - 3 * s, h), (w - 3 * s, h + tailHeight), (w - 4 * s, h + tailHeight),
                   (w - 4 * s, h + 2 * s), (w - 5 * s, h + 2 * s), (w - 5 * s, h + s), (w - 6 * s, h + s),
                   (w - 6 * s, h),
                   // 아래쪽 변 → 왼쪽 아래 모서리
                   (2 * s, h), (2 * s, h - s), (s, h - s), (s, h - 2 * s), (0, h - 2 * s),
                   // 왼쪽 변 → 왼쪽 위 모서리
                   (0, 2 * s), (s, 2 * s), (s, s), (2 * s, s)] {
            p.addLine(to: CGPoint(x: pt.0 + r.minX, y: pt.1 + r.minY))
        }
        p.closeSubpath()
        return p
    }
}

struct BubbleWidgetView: View {
    @ObservedObject var store: WorkdayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clock: AnimationClock

    static let baseSize = CGSize(width: 190, height: 120)
    static let baseMascot: CGFloat = 60

    /// 창 크기 (비율 적용, 점 단위로 반올림). 내용에 맞춘 대략값이고, 말풍선은 오른쪽 기준으로 왼쪽으로 늘어난다.
    static func size(fontSize: Int) -> CGSize {
        let k = WidgetView.ratio(fontSize: fontSize)
        return CGSize(width: (baseSize.width * k).rounded(), height: (baseSize.height * k).rounded())
    }

    private var k: CGFloat { WidgetView.ratio(fontSize: settings.settings.fontSize) }

    var body: some View {
        let snap = store.snapshot
        let mascot = ScaledMascot.displaySize(baseSize: Self.baseMascot, ratio: k)
        let step = 2 * k
        let tail = 3 * step
        let window = Self.size(fontSize: settings.settings.fontSize)
        return ZStack(alignment: .bottomTrailing) {
            ScaledMascot(mood: MascotMood(phase: snap.phase), tick: clock.tick, jumpStart: clock.jumpStart,
                         outline: true, baseSize: Self.baseMascot, ratio: k, onTap: { clock.jump() })
                .padding(.trailing, 2 * k)
                .padding(.bottom, 2 * k)

            Text(WidgetText.bubbleText(for: snap))
                .font(.system(size: CGFloat(settings.settings.fontSize + 1), weight: .medium))
                .foregroundColor(Color(hex: 0x1B1B1F))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12 * k)
                .padding(.vertical, 8 * k)
                .padding(.bottom, tail)                       // 꼬리 자리
                .background(
                    BubbleShape(step: step, tailHeight: tail)
                        .fill(Color.white)
                        .overlay(BubbleShape(step: step, tailHeight: tail)
                            .stroke(Color(hex: 0x2B2B33), style: StrokeStyle(lineWidth: 2 * k, lineJoin: .miter))))
                // 꼬리 끝이 마스코트 머리 위 가운데쯤을 향하게
                .padding(.trailing, max(0, mascot / 2 - 3 * step + 2 * k))
                .padding(.bottom, mascot * 0.88)
        }
        .frame(width: window.width, height: window.height, alignment: .bottomTrailing)
    }
}

/// 설정의 모양에 따라 터미널/말풍선 중 하나를 그린다.
struct WidgetRootView: View {
    @ObservedObject var store: WorkdayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clock: AnimationClock
    var onClose: () -> Void

    var body: some View {
        switch settings.settings.widgetStyle {
        case .terminal:
            WidgetView(store: store, settings: settings, clock: clock, onClose: onClose)
        case .bubble:
            BubbleWidgetView(store: store, settings: settings, clock: clock)
        }
    }
}
