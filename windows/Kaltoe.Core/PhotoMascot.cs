// 실사 캐릭터의 움직임·덧그림 계산 — docs/spec.md 6-2절 표. 그리지 않는 순수 함수만 둔다.
// 맥(mac/Sources/Kaltoe/UI/PhotoMascotMotion.swift)과 같은 숫자를 쓴다 — 고칠 때 양쪽을 함께 고칠 것.
//
// 파형의 "T초" 는 한 번 오가는 데 걸리는 시간(주기)이다. 거리 단위 "px" 는 기본 크기(마스코트 폭 60) 기준이라
// 그릴 때 위젯 비율(= 글자 크기 / 12)을 곱한다. 덧그림 좌표는 이미지 사각형 기준 비율(0~1, 왼쪽 위 원점,
// x 는 폭 기준·y 는 높이 기준)이고 크기 값은 폭 기준 비율이다. 사각형 밖(< 0, > 1)으로 나가도 된다.
namespace Kaltoe.Core;

/// 이미지에 곱하는 변환. 세로 확대·회전은 이미지 아래 가운데를 기준으로 한다(발이 바닥에 붙어 있게).
/// <param name="ScaleY">세로 배율</param>
/// <param name="OffsetX">기본 크기 px, 오른쪽이 +</param>
/// <param name="OffsetY">기본 크기 px, 아래쪽이 +</param>
/// <param name="Rotation">도, 시계 방향이 +</param>
/// <param name="Opacity">불투명도 0~1</param>
public readonly record struct PhotoTransform(double ScaleY = 1, double OffsetX = 0, double OffsetY = 0, double Rotation = 0, double Opacity = 1);

public readonly record struct PhotoZ(double X, double Y, double Alpha);
public readonly record struct PhotoSpark(double X, double Y, double Size, double Alpha);
public readonly record struct PhotoConfetti(double X, double Y, double Size, double Rotation, uint Color);
public readonly record struct PhotoTear(double X, double Y, double Alpha);

public static class PhotoMascot
{
    // 눈 중심(이미지 기준 비율). shared/gen-photo.py 의 LEFT_EYE / RIGHT_EYE 와 같다 — 눈물 덧그림 위치.
    public const double LeftEyeX = 0.376, LeftEyeY = 0.395;
    public const double RightEyeX = 0.640, RightEyeY = 0.386;

    // 사용자 지정 사진(docs/spec.md 6-3절): 눈 위치를 모르므로 눈물은 폭의 35%·65%, 높이의 45% 에서 떨어지고
    // 화남 표시는 이미지 오른쪽 위 모서리. 맥 PhotoMascotMotion.custom* 와 같다.
    public const double CustomLeftEyeX = 0.35, CustomLeftEyeY = 0.45;
    public const double CustomRightEyeX = 0.65, CustomRightEyeY = 0.45;
    public const double CustomAngerCenterX = 0.85, CustomAngerCenterY = 0.15;

    /// 0 → 1 → 0 으로 부드럽게 오가는 파형. t = 0 에서 0, 주기의 절반에서 1.
    public static double Wave(double t, double period) => 0.5 - 0.5 * Math.Cos(2 * Math.PI * t / period);

    private static int Step(double seconds, double period) => (int)Math.Floor(seconds / period + 1e-9);

    /// 기분별 움직임.
    public static PhotoTransform Transform(MascotMood mood, double seconds)
    {
        var t = Math.Max(0, seconds);
        return mood switch
        {
            // 아주 느린 숨, 불투명도 85%
            MascotMood.Sleep => new PhotoTransform(ScaleY: 1 + 0.03 * Wave(t, 2.0), Opacity: 0.85),
            // 숨
            MascotMood.Idle => new PhotoTransform(ScaleY: 1 + 0.02 * Wave(t, 1.2)),
            // 고개 끄덕임: 아래로 2px ↔ 0
            MascotMood.Eat => new PhotoTransform(OffsetY: 2 * Wave(t, 0.4)),
            // 통통 뜀: 위로 4px ↔ 0
            MascotMood.Sparkle => new PhotoTransform(OffsetY: -4 * Wave(t, 0.3)),
            // 좌우 기울임 −8° ↔ +8°
            MascotMood.Dance => new PhotoTransform(Rotation: -8 + 16 * Wave(t, 0.4)),
            // 좌우 떨림 ±1.5px, 0.08초마다 바뀜
            MascotMood.Angry => new PhotoTransform(OffsetX: Step(t, 0.08) % 2 == 0 ? -1.5 : 1.5),
            // 살짝 처짐
            MascotMood.Cry => new PhotoTransform(OffsetY: 1),
            _ => new PhotoTransform(),
        };
    }

    /// 클릭 점프의 높이(기본 크기 px). 픽셀 캐릭터와 같은 6단계 곡선(0.1초 간격)에 칸당 3px.
    public const double JumpPixelsPerStep = 3;
    public static double JumpLift(double? secondsSinceJump)
        => MascotPlayback.JumpRows(secondsSinceJump, 16) * JumpPixelsPerStep;   // 격자 16 → 배율 1 → 곡선 값 그대로

    /// 점프 때 위로 올라갈 수 있는 최대 높이(기본 크기 px) — 위쪽 여유 공간.
    public static double JumpHeadroom => MascotPlayback.JumpHeadroomRows(16) * JumpPixelsPerStep;

    // ── 덧그림 ──

    /// sleep 의 떠오르는 z. 0.5초마다 한 칸씩 올라가며 옅어지고, 4번째 칸(1.5~2초)은 쉰다.
    public static PhotoZ? ZFloat(double seconds)
    {
        var step = Step(Math.Max(0, seconds), MascotPlayback.ZStepSeconds) % 4;
        if (step >= 3) return null;
        return new PhotoZ(0.93, new[] { 0.10, 0.0, -0.10 }[step], new[] { 1.0, 0.8, 0.55 }[step]);
    }

    /// 밥그릇: 발치 가운데. (중심 x, 폭, 높이 — 폭 기준 비율)
    public const double BowlCenterX = 0.5, BowlWidth = 0.54, BowlHeight = 0.15;

    public const uint SparkColor = 0xFFD93B;
    /// sparkle 의 양옆 노란 반짝이 — 0.3초마다 두 쌍이 번갈아 커졌다 작아진다.
    public static IReadOnlyList<PhotoSpark> Sparks(double seconds)
    {
        var phase = Step(Math.Max(0, seconds), 0.3) % 2;
        PhotoSpark S(double x, double y, int group)
        {
            var on = phase == group;
            return new PhotoSpark(x, y, on ? 0.17 : 0.10, on ? 1 : 0.55);
        }
        return new[] { S(-0.03, 0.30, 0), S(0.07, 0.62, 1), S(0.86, 0.18, 1), S(0.82, 0.52, 0) };
    }

    public static readonly IReadOnlyList<uint> ConfettiColors = new uint[] { 0xFF5F57, 0xFEBC2E, 0x28C840, 0x5AC8FA, 0xFF8AD0, 0xF28C5A };
    public static readonly IReadOnlyList<(double X, double Y)> ConfettiSlots = new[]
    {
        (-0.04, 0.10), (0.10, -0.05), (0.32, -0.07), (0.60, -0.06), (0.84, 0.00),
        (0.98, 0.18), (-0.05, 0.45), (0.98, 0.50), (0.02, 0.80), (0.97, 0.78),
    };
    /// dance 의 색종이 — 몸 주변 고정 자리에서 0.8초 주기로 오르내리며 돈다.
    public static IReadOnlyList<PhotoConfetti> Confetti(double seconds)
    {
        var t = Math.Max(0, seconds);
        var list = new List<PhotoConfetti>(ConfettiSlots.Count);
        for (var i = 0; i < ConfettiSlots.Count; i++)
        {
            var (x, y) = ConfettiSlots[i];
            var bob = 0.04 * Wave(t + i * 0.08, 0.8);
            list.Add(new PhotoConfetti(x, y + bob, 0.06, (t * 220 + i * 47) % 360, ConfettiColors[i % ConfettiColors.Count]));
        }
        return list;
    }

    /// angry 의 화남 표시(머리 오른쪽 위): 중심 좌표·크기(폭 기준). 맥박처럼 커졌다 작아진다.
    public const double AngerCenterX = 0.80, AngerCenterY = 0.11, AngerSize = 0.30;
    public static double AngerPulse(double seconds) => 1 + 0.15 * Wave(Math.Max(0, seconds), 0.3);
    public const uint AngerColor = 0xE5393B;

    public const uint TearColor = 0x7CC8F5;
    /// cry 의 눈물방울: 눈 아래에서 0.4초 주기로 떨어지며 옅어진다. 오른쪽 눈은 4분의 1 주기 늦다.
    public static IReadOnlyList<PhotoTear> Tears(double seconds)
        => Tears(seconds, LeftEyeX, LeftEyeY, RightEyeX, RightEyeY);

    /// 눈 위치를 직접 지정한다(사용자 지정 사진은 CustomLeftEye* / CustomRightEye*).
    public static IReadOnlyList<PhotoTear> Tears(double seconds, double leftX, double leftY, double rightX, double rightY)
    {
        var t = Math.Max(0, seconds);
        PhotoTear One(double ex, double ey, double offset)
        {
            var p = (t / 0.4 + offset) % 1.0;
            return new PhotoTear(ex, ey + 0.05 + 0.12 * p, 1 - 0.7 * p);
        }
        return new[] { One(leftX, leftY, 0.0), One(rightX, rightY, 0.25) };
    }
}
