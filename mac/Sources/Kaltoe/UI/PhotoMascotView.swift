// 실사 마스코트 (docs/spec.md 6-2절): 사진 한 장을 움직임(PhotoMascotMotion)과 덧그림으로 살려 낸다.
// 이미지 데이터는 PhotoMascotData(생성물, 원본 shared/photo-maltese.png)에 base64 로 내장돼 있다.
import AppKit
import SwiftUI

enum PhotoMascotImage {
    /// 표시용 이미지 (긴 변 192px). 디코딩에 실패하면 빈 이미지.
    static let image: NSImage = {
        guard let data = Data(base64Encoded: PhotoMascotData.pngBase64), let image = NSImage(data: data) else { return NSImage() }
        return image
    }()

    /// 폭 / 높이
    static var aspect: CGFloat {
        let s = image.size
        return s.width > 0 && s.height > 0 ? s.width / s.height : 1
    }

    /// 메뉴바 아이콘: 얼굴(머리 전체)만 담은 컬러 이미지(템플릿 아님). 크기는 pt.
    static func menuBarImage(pointSize: CGFloat) -> NSImage {
        guard let data = Data(base64Encoded: PhotoMascotData.faceBase64), let face = NSImage(data: data) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        face.size = NSSize(width: pointSize, height: pointSize)
        face.isTemplate = false
        return face
    }
}

struct PhotoMascotView: View {
    var mood: MascotMood
    var tick: Int
    var jumpStart: Int?
    var onTap: () -> Void
    /// true 면 옅은 그림자(검정 35%, 흐림 3, 아래 1)를 준다 — 말풍선 모양 (외곽선 대신).
    var shadow: Bool = false
    /// fontSize / 12
    var ratio: CGFloat = 1
    /// 그릴 사진 (내장 강아지 또는 사용자 지정 사진 — docs/spec.md 6-3절).
    var source: PhotoMascotSource = .builtin

    /// 레이아웃(화면에 차지하는) 정사각형 한 변 pt. 사진은 이 안에서 아래에 붙는다.
    static func displaySize(ratio: CGFloat) -> CGFloat { PhotoMascotMotion.baseSize * ratio }

    var body: some View {
        let side = Self.displaySize(ratio: ratio)
        // 이미지 사각형: 긴 변이 슬롯(정사각형)의 한 변. 가로로 긴 사진은 폭이, 세로로 긴 사진은 높이가 side.
        let aspect = source.aspect
        let w = aspect >= 1 ? side : side * aspect
        let h = aspect >= 1 ? side / aspect : side
        let t = PhotoMascotMotion.seconds(tick: tick)
        let m = PhotoMascotMotion.transform(mood: mood, tick: tick)
        let lift = CGFloat(PhotoMascotMotion.jumpLift(tick: tick, jumpStart: jumpStart)) * ratio

        ZStack(alignment: .topLeading) {
            // 사진 + 사진을 따라 움직이는 덧그림(눈물·화남 표시)
            ZStack(alignment: .topLeading) {
                Image(nsImage: source.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: w, height: h)
                    .shadow(color: shadow ? .black.opacity(0.35) : .clear, radius: 3 * ratio, x: 0, y: 1 * ratio)
                overlay(w: w, h: h) { ctx in
                    if mood == .angry { Self.drawAnger(ctx, w: w, h: h, t: t, source: source) }
                    if mood == .cry { Self.drawTears(ctx, w: w, h: h, t: t, source: source) }
                }
            }
            .frame(width: w, height: h)
            .scaleEffect(x: 1, y: CGFloat(m.scaleY), anchor: .bottom)
            .rotationEffect(.degrees(m.rotation), anchor: .bottom)
            .offset(x: CGFloat(m.offsetX) * ratio, y: CGFloat(m.offsetY) * ratio)
            .opacity(m.opacity)

            // 제자리에 있는 덧그림(z·밥그릇·반짝이·색종이)
            overlay(w: w, h: h) { ctx in
                switch mood {
                case .sleep: Self.drawZ(ctx, w: w, h: h, tick: tick, onLight: shadow)
                case .eat: Self.drawBowl(ctx, w: w, h: h)
                case .sparkle: Self.drawSparks(ctx, w: w, h: h, t: t)
                case .dance: Self.drawConfetti(ctx, w: w, h: h, t: t)
                case .idle, .angry, .cry: break
                }
            }
        }
        .frame(width: w, height: h)
        .frame(width: side, height: side, alignment: .bottom)
        .offset(y: -lift)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    /// 이미지 사각형 밖으로 나가도 그릴 수 있게 사방에 여유를 둔 캔버스 (레이아웃 크기는 그대로).
    private func overlay(w: CGFloat, h: CGFloat, _ draw: @escaping (inout GraphicsContext) -> Void) -> some View {
        let margin = 0.3 * w
        return Canvas { ctx, _ in
            var c = ctx
            c.translateBy(x: margin, y: margin)
            draw(&c)
        }
        .frame(width: w + 2 * margin, height: h + 2 * margin)
        .padding(-margin)
        .allowsHitTesting(false)
    }

    // MARK: 덧그림 그리기 (좌표 계산은 PhotoMascotMotion)

    private static func color(_ hex: UInt32, _ alpha: Double = 1) -> Color { Color(hex: hex, opacity: alpha) }

    /// onLight: 말풍선 모양(밝은 배경에도 놓임)이면 어두운 회색, 터미널이면 밝은 회색.
    private static func drawZ(_ c: GraphicsContext, w: CGFloat, h: CGFloat, tick: Int, onLight: Bool) {
        guard let z = PhotoMascotMotion.zFloat(tick: tick) else { return }
        let text = Text("z").font(.system(size: 0.22 * w, weight: .heavy, design: .rounded))
            .foregroundColor(color(onLight ? 0x6E6E73 : 0xC7C7CC, z.alpha))
        c.draw(text, at: CGPoint(x: z.x * w, y: z.y * h))
    }

    private static func drawBowl(_ c: GraphicsContext, w: CGFloat, h: CGFloat) {
        let b = PhotoMascotMotion.bowl
        let bw = b.width * w, bh = b.height * w
        let x0 = b.centerX * w - bw / 2, bottom = h + 0.03 * w      // 이미지 아래 변보다 살짝 아래(발 앞)
        let rimH = bh * 0.34
        // 사료(수북이)
        c.fill(Path(ellipseIn: CGRect(x: x0 + bw * 0.1, y: bottom - bh - rimH * 0.2, width: bw * 0.8, height: rimH * 1.1)),
               with: .color(color(0x8B5A2B)))
        // 그릇 몸통(아래가 좁은 사다리꼴)
        var body = Path()
        body.move(to: CGPoint(x: x0, y: bottom - bh + rimH / 2))
        body.addLine(to: CGPoint(x: x0 + bw, y: bottom - bh + rimH / 2))
        body.addLine(to: CGPoint(x: x0 + bw * 0.86, y: bottom))
        body.addLine(to: CGPoint(x: x0 + bw * 0.14, y: bottom))
        body.closeSubpath()
        c.fill(body, with: .color(color(0xE8734A)))
        // 윗 테두리
        c.fill(Path(ellipseIn: CGRect(x: x0 - bw * 0.02, y: bottom - bh, width: bw * 1.04, height: rimH)),
               with: .color(color(0xF7B48F)))
        c.fill(Path(ellipseIn: CGRect(x: x0 + bw * 0.08, y: bottom - bh + rimH * 0.18, width: bw * 0.84, height: rimH * 0.64)),
               with: .color(color(0x8B5A2B)))
    }

    private static func star(center: CGPoint, r: CGFloat) -> Path {
        var p = Path()
        let inner = r * 0.28
        for i in 0..<8 {
            let radius = i % 2 == 0 ? r : inner
            let a = Double(i) * .pi / 4 - .pi / 2
            let pt = CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private static func drawSparks(_ c: GraphicsContext, w: CGFloat, h: CGFloat, t: Double) {
        for s in PhotoMascotMotion.sparks(seconds: t) {
            c.fill(star(center: CGPoint(x: s.x * w, y: s.y * h), r: s.size * w),
                   with: .color(color(PhotoMascotMotion.sparkColor, s.alpha)))
        }
    }

    private static func drawConfetti(_ c: GraphicsContext, w: CGFloat, h: CGFloat, t: Double) {
        for p in PhotoMascotMotion.confetti(seconds: t) {
            var cc = c
            cc.translateBy(x: p.x * w, y: p.y * h)
            cc.rotate(by: .degrees(p.rotation))
            let s = p.size * w
            cc.fill(Path(CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2)), with: .color(color(p.color)))
        }
    }

    /// 화남 표시(💢): 중심을 둘러싼 네 개의 안쪽으로 휜 호.
    private static func drawAnger(_ c: GraphicsContext, w: CGFloat, h: CGFloat, t: Double, source: PhotoMascotSource) {
        let center = CGPoint(x: source.angerCenter.x * w, y: source.angerCenter.y * h)
        let size = CGFloat(PhotoMascotMotion.angerSize * PhotoMascotMotion.angerPulse(seconds: t)) * w
        let r = size / 2                      // 표시 반지름
        let d = r * 0.8, rho = r * 0.5        // 호의 중심 거리와 반지름 — 십자 모양 틈이 남는다
        var path = Path()
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            // 중심에서 (sx, sy) 방향 점을 중심으로 하는 4분원 — 표시 중심 쪽으로 볼록하다.
            let corner = CGPoint(x: center.x + CGFloat(sx) * d, y: center.y + CGFloat(sy) * d)
            let a0: Double = sx < 0 ? (sy < 0 ? 0 : 270) : (sy < 0 ? 90 : 180)   // 화면 좌표(아래가 +y)에서 중심을 향하는 90° 구간의 시작
            for step in 0...8 {
                let a = (a0 + Double(step) * 11.25) * .pi / 180
                let pt = CGPoint(x: corner.x + CGFloat(cos(a)) * rho, y: corner.y + CGFloat(sin(a)) * rho)
                if step == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
        c.stroke(path, with: .color(color(0xE5393B)), style: StrokeStyle(lineWidth: max(1.5, 0.045 * w), lineCap: .round))
    }

    private static func drawTears(_ c: GraphicsContext, w: CGFloat, h: CGFloat, t: Double, source: PhotoMascotSource) {
        for tear in PhotoMascotMotion.tears(seconds: t, leftEye: source.leftEye, rightEye: source.rightEye) {
            let dw = 0.05 * w, dh = 0.075 * w
            let rect = CGRect(x: tear.x * w - dw / 2, y: tear.y * h - dh / 2, width: dw, height: dh)
            c.fill(Path(ellipseIn: rect), with: .color(color(PhotoMascotMotion.tearColor, tear.alpha)))
        }
    }
}
