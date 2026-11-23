using Kaltoe.Core;

namespace Kaltoe.Core.Tests;

/// 사용자 지정 사진(docs/spec.md 6-3절)의 픽셀 계산 — byte[] BGRA 순수 함수.
public class CustomPhotoMathTests
{
    /// (x, y) → (b, g, r, a) 로 w x h BGRA 버퍼를 만든다.
    private static byte[] Make(int w, int h, Func<int, int, (int B, int G, int R, int A)> px)
    {
        var buf = new byte[w * h * 4];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var (b, g, r, a) = px(x, y);
                var i = (y * w + x) * 4;
                buf[i] = (byte)b; buf[i + 1] = (byte)g; buf[i + 2] = (byte)r; buf[i + 3] = (byte)a;
            }
        return buf;
    }

    private static byte[] Opaque(int w, int h) => Make(w, h, (_, _) => (60, 120, 200, 255));
    private static byte AlphaAt(byte[] buf, int w, int x, int y) => buf[(y * w + x) * 4 + 3];

    // ── 알파 판정 (1%) ──

    [Fact]
    public void Transparency_ThresholdIsOnePercentOfPixels()
    {
        byte[] With(int n) => Make(100, 100, (x, y) => y * 100 + x < n ? (255, 255, 255, 0) : (10, 20, 30, 255));
        Assert.Equal(0, PhotoPixels.TransparentFraction(Opaque(10, 10), 10, 10));
        Assert.False(PhotoPixels.HasTransparency(Opaque(10, 10), 10, 10));
        Assert.True(PhotoPixels.HasTransparency(With(100), 100, 100));     // 정확히 1%
        Assert.False(PhotoPixels.HasTransparency(With(99), 100, 100));
        Assert.Equal(0.25, PhotoPixels.TransparentFraction(With(2500), 100, 100), 9);
    }

    [Fact]
    public void Transparency_SemiTransparentCountsAsTransparent()
        => Assert.True(PhotoPixels.HasTransparency(Make(10, 10, (_, _) => (0, 0, 0, 254)), 10, 10));

    [Fact]
    public void Buffers_WithWrongLengthOrSize_Throw()
    {
        Assert.Throws<ArgumentException>(() => PhotoPixels.TransparentFraction(new byte[10], 2, 2));
        Assert.Throws<ArgumentOutOfRangeException>(() => PhotoPixels.TransparentFraction(Array.Empty<byte>(), 0, 0));
    }

    // ── 경계 상자·자르기 ──

    [Fact]
    public void OpaqueBounds_FindsTheSmallestRectangle()
    {
        var b = Make(20, 10, (x, y) => x is >= 4 and <= 9 && y is >= 2 and <= 5 ? (1, 2, 3, 255) : (0, 0, 0, 0));
        Assert.Equal(new ImageRect(4, 2, 6, 4), PhotoPixels.OpaqueBounds(b, 20, 10));
        Assert.Null(PhotoPixels.OpaqueBounds(Make(5, 5, (_, _) => (0, 0, 0, 0)), 5, 5));
        Assert.Null(PhotoPixels.OpaqueBounds(Make(5, 5, (_, _) => (9, 9, 9, 8)), 5, 5));   // 문턱 이하의 옅은 알파는 무시
        Assert.NotNull(PhotoPixels.OpaqueBounds(Make(5, 5, (_, _) => (9, 9, 9, 9)), 5, 5));
    }

    [Fact]
    public void Crop_CopiesTheRegion()
    {
        var b = Make(10, 10, (x, y) => (x, y, 0, 255));
        var c = PhotoPixels.Crop(b, 10, 10, new ImageRect(3, 4, 2, 3));
        Assert.Equal(2 * 3 * 4, c.Length);
        Assert.Equal(new byte[] { 3, 4, 0, 255 }, c[..4]);
        Assert.Equal(new byte[] { 4, 6, 0, 255 }, c[^4..]);
        Assert.Throws<ArgumentOutOfRangeException>(() => PhotoPixels.Crop(b, 10, 10, new ImageRect(9, 9, 2, 2)));
    }

    [Theory]
    [InlineData(200, 100, 50, 0, 100)]
    [InlineData(100, 200, 0, 50, 100)]
    [InlineData(101, 100, 0, 0, 100)]
    [InlineData(64, 64, 0, 0, 64)]
    public void CenterSquare_UsesTheShorterSide(int w, int h, int x, int y, int side)
        => Assert.Equal(new ImageRect(x, y, side, side), PhotoPixels.CenterSquare(w, h));

    // ── 원형 마스크 ──

    [Fact]
    public void CircleCoverage_FeathersOnePixelInsideTheEdge()
    {
        Assert.Equal(1, PhotoPixels.CircleCoverage(0, 50));
        Assert.Equal(1, PhotoPixels.CircleCoverage(48.5, 50));
        Assert.Equal(1, PhotoPixels.CircleCoverage(49.5, 50), 12);
        Assert.Equal(0.5, PhotoPixels.CircleCoverage(50, 50), 12);
        Assert.Equal(0, PhotoPixels.CircleCoverage(50.5, 50), 12);
        Assert.Equal(0, PhotoPixels.CircleCoverage(80, 50));
    }

    [Fact]
    public void CircleCrop_CentersASquareAndClearsOutsideTheCircle()
    {
        var c = PhotoPixels.CircleCrop(Opaque(200, 100), 200, 100, out var size);
        Assert.Equal(100, size);
        Assert.Equal(100 * 100 * 4, c.Length);
        Assert.Equal(255, AlphaAt(c, 100, 50, 50));
        foreach (var (x, y) in new[] { (0, 0), (99, 0), (0, 99), (99, 99) }) Assert.Equal(0, AlphaAt(c, 100, x, y));
        Assert.Equal(255, AlphaAt(c, 100, 50, 2));
        Assert.InRange((int)AlphaAt(c, 100, 50, 0), 1, 254);                           // 가장자리 줄은 부드럽게
        Assert.Equal(new ImageRect(0, 0, 100, 100), PhotoPixels.OpaqueBounds(c, 100, 100));
    }

    [Fact]
    public void CircleCrop_KeepsColorAndOnlyChangesAlpha_FromTheCenter()
    {
        // 왼쪽 절반 파랑(B=255), 오른쪽 절반 빨강(R=255) 인 200x100: 가운데 100x100 은 반반
        var src = Make(200, 100, (x, _) => x < 100 ? (255, 0, 0, 255) : (0, 0, 255, 255));
        var c = PhotoPixels.CircleCrop(src, 200, 100, out _);
        Assert.Equal(255, c[(50 * 100 + 30) * 4]);        // 왼쪽 = 파랑
        Assert.Equal(255, c[(50 * 100 + 70) * 4 + 2]);    // 오른쪽 = 빨강
        // 가장자리의 부분 투명 픽셀도 색(B,G,R)은 원본 그대로
        var edge = (0 * 100 + 50) * 4;
        Assert.Equal(src[(0 * 200 + 50 + 50) * 4 + 2], c[edge + 2]);
    }

    // ── 축소 크기 ──

    [Theory]
    [InlineData(1024, 768, 512, 512, 384)]
    [InlineData(600, 1200, 512, 256, 512)]
    [InlineData(300, 200, 512, 300, 200)]      // 작은 사진은 키우지 않는다
    [InlineData(512, 512, 512, 512, 512)]
    [InlineData(5000, 3, 512, 512, 1)]         // 최소 1px
    public void FitSize_ShrinksLongSideNeverEnlarges(int w, int h, int longSide, int ew, int eh)
        => Assert.Equal((ew, eh), PhotoPixels.FitSize(w, h, longSide));

    [Fact]
    public void Constants_MatchTheSpec()
    {
        Assert.Equal(512, PhotoPixels.LongSide);
        Assert.Equal(0.01, PhotoPixels.TransparentFractionThreshold);
    }

    // ── EXIF 방향 ──

    [Theory]
    [InlineData(1, 0, false)]
    [InlineData(2, 0, true)]
    [InlineData(3, 180, false)]
    [InlineData(4, 180, true)]
    [InlineData(5, 270, true)]
    [InlineData(6, 90, false)]
    [InlineData(7, 90, true)]
    [InlineData(8, 270, false)]
    [InlineData(0, 0, false)]
    [InlineData(9, 0, false)]
    public void ExifTransform_MapsOrientationToFlipThenClockwiseRotation(int orientation, int rotation, bool flip)
        => Assert.Equal((rotation, flip), PhotoPixels.ExifTransform(orientation));

    [Fact]
    public void FitInSquare_CentersAndKeepsAspect()
    {
        Assert.Equal((0.0, 25.0, 100.0, 50.0), PhotoPixels.FitInSquare(200, 100, 100));
        Assert.Equal((25.0, 0.0, 50.0, 100.0), PhotoPixels.FitInSquare(100, 200, 100));
        Assert.Equal((0.0, 0.0, 32.0, 32.0), PhotoPixels.FitInSquare(512, 512, 32));
        var (x, y, w, h) = PhotoPixels.FitInSquare(512, 494, 18);
        Assert.Equal(18, w, 9);
        Assert.Equal(h, 18 - 2 * y, 9);
        Assert.Equal(0, x, 9);
    }

    [Fact]
    public void RotatedSize_SwapsForQuarterTurns()
    {
        Assert.Equal((20, 40), PhotoPixels.RotatedSize(40, 20, 90));
        Assert.Equal((20, 40), PhotoPixels.RotatedSize(40, 20, 270));
        Assert.Equal((40, 20), PhotoPixels.RotatedSize(40, 20, 180));
        Assert.Equal((40, 20), PhotoPixels.RotatedSize(40, 20, 0));
    }

    // ── ICO 만들기 ──

    [Fact]
    public void IcoBuilder_WritesHeaderEntriesAndPayloads()
    {
        var a = new byte[] { 1, 2, 3 };
        var b = new byte[] { 9, 8, 7, 6, 5 };
        var ico = IcoBuilder.Build(new[] { (16, a), (256, b) });
        Assert.Equal(6 + 2 * 16 + 3 + 5, ico.Length);
        Assert.Equal(new byte[] { 0, 0, 1, 0, 2, 0 }, ico[..6]);
        Assert.Equal(16, ico[6]); Assert.Equal(16, ico[7]);
        Assert.Equal(32, BitConverter.ToUInt16(ico, 12));                 // bpp
        Assert.Equal(3u, BitConverter.ToUInt32(ico, 14));                 // 크기
        Assert.Equal(38u, BitConverter.ToUInt32(ico, 18));                // 오프셋 = 6 + 2*16
        Assert.Equal(0, ico[22]); Assert.Equal(0, ico[23]);               // 256 은 0 으로 적는다
        Assert.Equal(5u, BitConverter.ToUInt32(ico, 30));
        Assert.Equal(41u, BitConverter.ToUInt32(ico, 34));
        Assert.Equal(a, ico[38..41]);
        Assert.Equal(b, ico[41..]);
        Assert.Throws<ArgumentException>(() => IcoBuilder.Build(Array.Empty<(int, byte[])>()));
        Assert.Throws<ArgumentOutOfRangeException>(() => IcoBuilder.Build(new[] { (300, a) }));
    }
}

public class CustomPhotoSettingsTests
{
    [Fact]
    public void CustomPhoto_DefaultsToFalse_AndOldFilesWithoutItStillLoad()
    {
        Assert.False(AppSettings.Default.Widget.CustomPhoto);
        Assert.False(AppFile.Parse("{\"settings\":{\"widget\":{\"character\":\"photo\",\"fontSize\":14}}}").Settings.Widget.CustomPhoto);
    }

    [Fact]
    public void CustomPhoto_RoundTripsInJson_AsCamelCaseBool()
    {
        var s = AppSettings.Default with { Widget = new WidgetSettings { Character = MascotCharacter.Photo, CustomPhoto = true } };
        var json = new AppFile { Settings = s }.ToJson();
        Assert.Contains("\"customPhoto\": true", json);
        var back = AppFile.Parse(json).Settings.Widget;
        Assert.True(back.CustomPhoto);
        Assert.Equal(MascotCharacter.Photo, back.Character);
        Assert.Null(SettingsValidator.Validate(s));
    }

    [Fact]
    public void LaunchOptions_CustomPhoto_IsDemoOnlyAndNeedsAPath()
    {
        var o = LaunchOptions.Parse(new[] { "--demo", "working", "--character", "photo", "--custom-photo", @"C:\a b\dog.jpeg" });
        Assert.Null(o.Error);
        Assert.Equal(@"C:\a b\dog.jpeg", o.CustomPhotoPath);
        Assert.Equal(MascotCharacter.Photo, o.Character);
        Assert.Null(LaunchOptions.Parse(new[] { "--demo", "working" }).CustomPhotoPath);
        Assert.NotNull(LaunchOptions.Parse(new[] { "--demo", "working", "--custom-photo" }).Error);
        Assert.NotNull(LaunchOptions.Parse(new[] { "--custom-photo", "x.png" }).Error);
    }

    [Fact]
    public void CustomEyes_AreThirtyFiveAndSixtyFivePercentAtFortyFivePercent()
    {
        Assert.Equal((0.35, 0.45, 0.65, 0.45),
            (PhotoMascot.CustomLeftEyeX, PhotoMascot.CustomLeftEyeY, PhotoMascot.CustomRightEyeX, PhotoMascot.CustomRightEyeY));
        Assert.True(PhotoMascot.CustomAngerCenterX > 0.8 && PhotoMascot.CustomAngerCenterY < 0.2);   // 오른쪽 위 모서리
        var t = PhotoMascot.Tears(0, PhotoMascot.CustomLeftEyeX, PhotoMascot.CustomLeftEyeY, PhotoMascot.CustomRightEyeX, PhotoMascot.CustomRightEyeY);
        Assert.Equal(0.35, t[0].X);
        Assert.Equal(0.65, t[1].X);
        Assert.True(t[0].Y > 0.45);
        // 기본 눈 좌표 오버로드는 내장 사진의 값
        Assert.Equal(PhotoMascot.Tears(0.2), PhotoMascot.Tears(0.2, PhotoMascot.LeftEyeX, PhotoMascot.LeftEyeY, PhotoMascot.RightEyeX, PhotoMascot.RightEyeY));
    }
}
