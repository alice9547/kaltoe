// 실사 캐릭터의 움직임·덧그림 계산 (docs/spec.md 6-2절 표). 그리지 않는 순수 함수만 둔다.
// 윈도우(Kaltoe.Core/PhotoMascot.cs)가 같은 숫자를 쓴다 — 고칠 때 양쪽을 함께 고칠 것.
//
// 시각은 애니메이션 시계의 틱(0.1초 단위) × 0.1 초다. 파형의 "T초" 는 한 번 오가는 데 걸리는 시간(주기)이다.
// 거리 단위 "px" 는 기본 크기(마스코트 폭 60) 기준 — 그릴 때 `ratio`(= fontSize / 12)를 곱한다.
// 덧그림 좌표는 이미지 사각형 기준 비율(0~1, 왼쪽 위 원점, x 는 폭 기준, y 는 높이 기준)이고,
// 크기 값은 폭 기준 비율이다. 사각형 밖(< 0, > 1)으로 나가도 된다.
import Foundation
import CoreGraphics

/// 이미지에 곱하는 변환. 세로 확대·회전은 이미지 아래 가운데를 기준으로 한다(발이 바닥에 붙어 있게).
struct PhotoTransform: Equatable {
    var scaleY: Double = 1
    /// 기본 크기 px. 오른쪽이 +
    var offsetX: Double = 0
    /// 기본 크기 px. 아래쪽이 +
    var offsetY: Double = 0
    /// 도. 시계 방향이 +
    var rotation: Double = 0
    var opacity: Double = 1
}

struct PhotoZ: Equatable { var x: Double; var y: Double; var alpha: Double }
struct PhotoSpark: Equatable { var x: Double; var y: Double; var size: Double; var alpha: Double }
struct PhotoConfetti: Equatable { var x: Double; var y: Double; var size: Double; var rotation: Double; var color: UInt32 }
struct PhotoTear: Equatable { var x: Double; var y: Double; var alpha: Double }

enum PhotoMascotMotion {
    /// 기본 표시 폭(pt). 터미널·말풍선 모두 같다 (spec 6-2절).
    static let baseSize: CGFloat = 60
    /// 틱 → 초.
    static func seconds(tick: Int) -> Double { Double(tick) / 10 }

    /// 0 → 1 → 0 으로 부드럽게 오가는 파형. t = 0 에서 0, 주기의 절반에서 1.
    static func wave(_ t: Double, period: Double) -> Double {
        0.5 - 0.5 * cos(2 * Double.pi * t / period)
    }

    /// 기분별 움직임.
    static func transform(mood: MascotMood, seconds t: Double) -> PhotoTransform {
        var out = PhotoTransform()
        switch mood {
        case .sleep:                                  // 아주 느린 숨, 불투명도 85%
            out.scaleY = 1 + 0.03 * wave(t, period: 2.0)
            out.opacity = 0.85
        case .idle:                                   // 숨
            out.scaleY = 1 + 0.02 * wave(t, period: 1.2)
        case .eat:                                    // 고개 끄덕임: 아래로 2px ↔ 0
            out.offsetY = 2 * wave(t, period: 0.4)
        case .sparkle:                                // 통통 뜀: 위로 4px ↔ 0
            out.offsetY = -4 * wave(t, period: 0.3)
        case .dance:                                  // 좌우 기울임 −8° ↔ +8°
            out.rotation = -8 + 16 * wave(t, period: 0.4)
        case .angry:                                  // 좌우 떨림 ±1.5px, 0.08초마다 바뀜
            out.offsetX = Int((t / 0.08 + 1e-9).rounded(.down)) % 2 == 0 ? -1.5 : 1.5
        case .cry:                                    // 살짝 처짐
            out.offsetY = 1
        }
        return out
    }

    static func transform(mood: MascotMood, tick: Int) -> PhotoTransform {
        transform(mood: mood, seconds: seconds(tick: tick))
    }

    /// 클릭 점프의 높이(기본 크기 px). 픽셀 캐릭터와 같은 6틱 곡선(MascotPlayer.jumpTable)에 칸당 3px.
    static let jumpPixelsPerStep: Double = 3
    static func jumpLift(tick: Int, jumpStart: Int?) -> Double {
        Double(MascotPlayer.jumpOffset(tick: tick, jumpStart: jumpStart)) * jumpPixelsPerStep
    }

    // MARK: 덧그림

    /// sleep 의 떠오르는 z. 0.5초마다 한 칸씩 올라가며 옅어지고, 4번째 칸(1.5~2초)은 쉰다.
    static func zFloat(tick: Int) -> PhotoZ? {
        let step = (tick / 5) % 4
        guard step < 3 else { return nil }
        return PhotoZ(x: 0.93, y: [0.10, 0.0, -0.10][step], alpha: [1.0, 0.8, 0.55][step])
    }

    /// 밥그릇: 발치 가운데. 이미지 아래 변에 맞닿는다. (중심 x, 폭, 높이 — 폭 기준 비율)
    static let bowl = (centerX: 0.5, width: 0.54, height: 0.15)

    /// sparkle 의 양옆 노란 반짝이 — 0.3초마다 두 쌍이 번갈아 커졌다 작아진다.
    static let sparkColor: UInt32 = 0xFFD93B
    static func sparks(seconds t: Double) -> [PhotoSpark] {
        let phase = Int((t / 0.3 + 1e-9).rounded(.down)) % 2
        func s(_ x: Double, _ y: Double, group: Int) -> PhotoSpark {
            let on = phase == group
            return PhotoSpark(x: x, y: y, size: on ? 0.17 : 0.10, alpha: on ? 1 : 0.55)
        }
        // 오른쪽은 사진 안쪽에 둔다 — 말풍선 모양의 창이 마스코트 오른쪽 끝에서 바로 끝나 밖으로 나가면 잘린다.
        return [s(-0.03, 0.30, group: 0), s(0.07, 0.62, group: 1),
                s(0.86, 0.18, group: 1), s(0.82, 0.52, group: 0)]
    }

    /// dance 의 색종이 — 몸 주변 고정 자리에서 0.8초 주기로 오르내리며 돈다.
    static let confettiColors: [UInt32] = [0xFF5F57, 0xFEBC2E, 0x28C840, 0x5AC8FA, 0xFF8AD0, 0xF28C5A]
    static let confettiSlots: [(x: Double, y: Double)] = [
        (-0.04, 0.10), (0.10, -0.05), (0.32, -0.07), (0.60, -0.06), (0.84, 0.00),
        (0.98, 0.18), (-0.05, 0.45), (0.98, 0.50), (0.02, 0.80), (0.97, 0.78),
    ]
    static func confetti(seconds t: Double) -> [PhotoConfetti] {
        confettiSlots.enumerated().map { i, slot in
            let bob = 0.04 * wave(t + Double(i) * 0.08, period: 0.8)
            return PhotoConfetti(x: slot.x, y: slot.y + bob, size: 0.06,
                                 rotation: (t * 220 + Double(i) * 47).truncatingRemainder(dividingBy: 360),
                                 color: confettiColors[i % confettiColors.count])
        }
    }

    /// angry 의 화남 표시 (머리 오른쪽 위). 중심 좌표·크기(폭 기준), 맥박처럼 커졌다 작아진다.
    static let angerCenter = (x: 0.80, y: 0.11)
    /// 사용자 지정 사진(눈 위치를 모름, docs/spec.md 6-3절): 눈물은 폭의 35%·65%, 높이의 45% 에서 떨어지고 화남 표시는 오른쪽 위 모서리.
    static let customLeftEye = CGPoint(x: 0.35, y: 0.45)
    static let customRightEye = CGPoint(x: 0.65, y: 0.45)
    static let customAngerCenter = (x: 0.85, y: 0.15)
    static let angerSize = 0.30
    static func angerPulse(seconds t: Double) -> Double { 1 + 0.15 * wave(t, period: 0.3) }

    /// cry 의 눈물방울: 눈 아래에서 0.4초 주기로 떨어지며 옅어진다. 오른쪽 눈은 4분의 1 주기 늦다.
    static let tearColor: UInt32 = 0x7CC8F5
    static func tears(seconds t: Double, leftEye: CGPoint, rightEye: CGPoint) -> [PhotoTear] {
        [(leftEye, 0.0), (rightEye, 0.25)].map { eye, offset in
            var p = (t / 0.4 + offset).truncatingRemainder(dividingBy: 1)
            if p < 0 { p += 1 }
            return PhotoTear(x: Double(eye.x), y: Double(eye.y) + 0.05 + 0.12 * p, alpha: 1 - 0.7 * p)
        }
    }
}
