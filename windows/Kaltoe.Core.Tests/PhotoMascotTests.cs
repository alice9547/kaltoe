using Kaltoe.Core;

namespace Kaltoe.Core.Tests;

/// 실사 캐릭터(docs/spec.md 6-2절) 움직임·덧그림 계산. 맥의 PhotoMascotTests(Swift)와 같은 숫자를 확인한다.
public class PhotoMascotTests
{
    private const double Eps = 1e-9;
    private static PhotoTransform Tf(MascotMood m, double t) => PhotoMascot.Transform(m, t);
    private static void Near(double expected, double actual) => Assert.InRange(actual, expected - Eps, expected + Eps);

    // ── 움직임 (표의 범위와 주기) ──

    [Fact]
    public void Sleep_BreathesSlowlyAtEightyFivePercentOpacity()
    {
        Near(1.00, Tf(MascotMood.Sleep, 0).ScaleY);
        Near(1.03, Tf(MascotMood.Sleep, 1.0).ScaleY);   // 2초 주기의 절반에서 최대
        Near(1.00, Tf(MascotMood.Sleep, 2.0).ScaleY);
        Near(0.85, Tf(MascotMood.Sleep, 0.37).Opacity);
        Near(0, Tf(MascotMood.Sleep, 0.37).OffsetY);
    }

    [Fact]
    public void Idle_Breathes()
    {
        Near(1.00, Tf(MascotMood.Idle, 0).ScaleY);
        Near(1.02, Tf(MascotMood.Idle, 0.6).ScaleY);    // 1.2초 주기의 절반에서 최대
        Near(1.00, Tf(MascotMood.Idle, 1.2).ScaleY);
        Assert.Equal(1.0, Tf(MascotMood.Idle, 0.2).Opacity);
    }

    [Fact]
    public void Eat_NodsDownTwoPixels()
    {
        Near(0, Tf(MascotMood.Eat, 0).OffsetY);
        Near(2, Tf(MascotMood.Eat, 0.2).OffsetY);       // 0.4초 주기의 절반에서 아래로 2px
        Near(0, Tf(MascotMood.Eat, 0.4).OffsetY);
    }

    [Fact]
    public void Sparkle_HopsUpFourPixels()
    {
        Near(0, Tf(MascotMood.Sparkle, 0).OffsetY);
        Near(-4, Tf(MascotMood.Sparkle, 0.15).OffsetY);  // 0.3초 주기의 절반에서 위로 4px
        Near(0, Tf(MascotMood.Sparkle, 0.3).OffsetY);
    }

    [Fact]
    public void Dance_TiltsMinusEightToPlusEight()
    {
        Near(-8, Tf(MascotMood.Dance, 0).Rotation);
        Near(8, Tf(MascotMood.Dance, 0.2).Rotation);
        Near(-8, Tf(MascotMood.Dance, 0.4).Rotation);
        for (var i = 0; i <= 40; i++)
            Assert.InRange(Tf(MascotMood.Dance, i * 0.01).Rotation, -8.000001, 8.000001);
    }

    [Fact]
    public void Angry_ShakesPlusMinusOnePointFiveEveryEightyMilliseconds()
    {
        Near(-1.5, Tf(MascotMood.Angry, 0.00).OffsetX);
        Near(-1.5, Tf(MascotMood.Angry, 0.07).OffsetX);
        Near(1.5, Tf(MascotMood.Angry, 0.08).OffsetX);
        Near(1.5, Tf(MascotMood.Angry, 0.159).OffsetX);
        Near(-1.5, Tf(MascotMood.Angry, 0.16).OffsetX);
        Near(0, Tf(MascotMood.Angry, 0.5).OffsetY);
    }

    [Theory]
    [InlineData(0.0)]
    [InlineData(0.13)]
    [InlineData(0.4)]
    [InlineData(3.3)]
    public void Cry_DroopsOnePixel(double t)
    {
        Near(1, Tf(MascotMood.Cry, t).OffsetY);
        Near(1, Tf(MascotMood.Cry, t).ScaleY);
    }

    [Fact]
    public void NegativeTime_IsTreatedAsZero()
        => Assert.Equal(Tf(MascotMood.Eat, 0), Tf(MascotMood.Eat, -3));

    // ── 클릭 점프 ──

    [Fact]
    public void Jump_FollowsPixelCurveThreePixelsPerStep()
    {
        Assert.Equal(0, PhotoMascot.JumpLift(null));
        Assert.Equal(0, PhotoMascot.JumpLift(-0.1));
        var lifts = new[] { 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7 }.Select(s => PhotoMascot.JumpLift(s + 0.001)).ToArray();
        Assert.Equal(new[] { 3.0, 6.0, 9.0, 9.0, 6.0, 3.0, 0.0, 0.0 }, lifts);
        Assert.Equal(9, PhotoMascot.JumpHeadroom);
    }

    // ── 덧그림 ──

    [Fact]
    public void Z_RisesAndFadesThenRests()
    {
        var z0 = PhotoMascot.ZFloat(0.0)!.Value;
        var z1 = PhotoMascot.ZFloat(0.5)!.Value;
        var z2 = PhotoMascot.ZFloat(1.0)!.Value;
        Assert.Equal(new[] { 1.0, 0.8, 0.55 }, new[] { z0.Alpha, z1.Alpha, z2.Alpha });
        Assert.True(z0.Y > z1.Y && z1.Y > z2.Y);          // 위로 올라간다(y 감소)
        Assert.Null(PhotoMascot.ZFloat(1.5));             // 4번째 칸은 쉰다
        Assert.Equal(1.0, PhotoMascot.ZFloat(2.0)!.Value.Alpha);   // 2초 주기
    }

    [Fact]
    public void Tears_FallFromEachEyeEveryFourTenthsOfASecond()
    {
        var a = PhotoMascot.Tears(0);
        Assert.Equal(2, a.Count);
        Near(PhotoMascot.LeftEyeX, a[0].X);
        Near(PhotoMascot.RightEyeX, a[1].X);
        Assert.True(a[0].Y > PhotoMascot.LeftEyeY);       // 눈 아래에서 시작
        var b = PhotoMascot.Tears(0.2);
        Assert.True(b[0].Y > a[0].Y);                     // 시간이 지나면 떨어진다
        Assert.True(b[0].Alpha < a[0].Alpha);             // 옅어진다
        var c = PhotoMascot.Tears(0.4);
        Near(a[0].Y, c[0].Y);                             // 0.4초 주기
        Near(a[0].Alpha, c[0].Alpha);
    }

    [Fact]
    public void Sparks_TwoPairsAlternateEveryThreeTenths()
    {
        var a = PhotoMascot.Sparks(0);
        var b = PhotoMascot.Sparks(0.3);
        Assert.Equal(4, a.Count);
        Assert.Equal(a.Select(s => s.X), b.Select(s => s.X));                       // 자리는 그대로
        Assert.NotEqual(a.Select(s => s.Size), b.Select(s => s.Size));              // 커지는 쌍이 번갈아 바뀐다
        Assert.Equal(a.Select(s => s.Size), PhotoMascot.Sparks(0.6).Select(s => s.Size));
        Assert.Contains(a, s => s.X < 0.2);
        Assert.Contains(a, s => s.X > 0.8);                                         // 양옆
    }

    [Fact]
    public void Sparks_StayInsideThePhotoOnTheRight_SoABubbleWindowDoesNotClipThem()
        => Assert.All(PhotoMascot.Sparks(0).Concat(PhotoMascot.Sparks(0.3)),
            s => Assert.True(s.X + s.Size <= 1.04, $"x={s.X} size={s.Size}"));

    [Fact]
    public void Confetti_AroundTheBodyWithKnownColors()
    {
        var pieces = PhotoMascot.Confetti(0.4);
        Assert.Equal(PhotoMascot.ConfettiSlots.Count, pieces.Count);
        Assert.All(pieces, p => Assert.Contains(p.Color, PhotoMascot.ConfettiColors));
        Assert.True(pieces.Select(p => p.Color).Distinct().Count() > 3);
        Assert.All(pieces, p => Assert.InRange(p.Rotation, 0, 360));
    }

    [Fact]
    public void Anger_PulsesAroundTheBaseSize_AtTheHeadsUpperRight()
    {
        Near(1.0, PhotoMascot.AngerPulse(0));
        Near(1.15, PhotoMascot.AngerPulse(0.15));
        Assert.True(PhotoMascot.AngerCenterX > 0.7);
        Assert.True(PhotoMascot.AngerCenterY < 0.3);
    }

    [Fact]
    public void Eyes_AreRatiosInsideTheImage_LeftOfRight()
    {
        foreach (var v in new[] { PhotoMascot.LeftEyeX, PhotoMascot.LeftEyeY, PhotoMascot.RightEyeX, PhotoMascot.RightEyeY })
            Assert.InRange(v, 0.0, 1.0);
        Assert.True(PhotoMascot.LeftEyeX < PhotoMascot.RightEyeX);
        Assert.True(Math.Abs(PhotoMascot.LeftEyeY - PhotoMascot.RightEyeY) < 0.05);
    }

    // ── 맥과 같은 숫자 (맥 PhotoMascotMotion.swift 와 상수가 같은지) ──

    [Fact]
    public void Constants_MatchTheMacImplementation()
    {
        Assert.Equal((0.376, 0.395, 0.640, 0.386), (PhotoMascot.LeftEyeX, PhotoMascot.LeftEyeY, PhotoMascot.RightEyeX, PhotoMascot.RightEyeY));
        Assert.Equal((0.5, 0.54, 0.15), (PhotoMascot.BowlCenterX, PhotoMascot.BowlWidth, PhotoMascot.BowlHeight));
        Assert.Equal((0.80, 0.11, 0.30), (PhotoMascot.AngerCenterX, PhotoMascot.AngerCenterY, PhotoMascot.AngerSize));
        Assert.Equal(new uint[] { 0xFF5F57, 0xFEBC2E, 0x28C840, 0x5AC8FA, 0xFF8AD0, 0xF28C5A }, PhotoMascot.ConfettiColors);
        Assert.Equal(new[] { 0.93, 0.93, 0.93 }, new[] { 0.0, 0.5, 1.0 }.Select(t => PhotoMascot.ZFloat(t)!.Value.X));
        Assert.Equal(new[] { 0.10, 0.0, -0.10 }, new[] { 0.0, 0.5, 1.0 }.Select(t => PhotoMascot.ZFloat(t)!.Value.Y));
    }
}

public class PhotoSizingTests
{
    [Theory]
    [InlineData(12, 60.0)]
    [InlineData(8, 40.0)]
    [InlineData(24, 120.0)]
    [InlineData(32, 60.0 * 32 / 12)]
    public void PhotoExtent_IsSixtyTimesFactor_NoIntegerSnapping(int fontSize, double expected)
        => Assert.Equal(expected, WidgetSizing.PhotoExtent(fontSize), 9);

    [Fact]
    public void PhotoBase_IsSixtyForBothStyles_UnlikePixelTerminal()
    {
        Assert.Equal(60, WidgetSizing.PhotoBaseExtent);
        Assert.Equal(WidgetSizing.BubbleMascotBaseExtent, WidgetSizing.PhotoBaseExtent);
        Assert.NotEqual(WidgetSizing.MascotBaseExtent, WidgetSizing.PhotoBaseExtent);
    }

    [Fact]
    public void PhotoImageFile_IsTheAssetName() => Assert.Equal("photo-maltese.png", MascotAssets.PhotoImageFile);
}
