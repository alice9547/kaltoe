using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 실사 마스코트(docs/spec.md 6-2절): 사진 한 장(Assets/photo-maltese.png)을 움직임과 덧그림으로 살려 낸다.
/// 변환·덧그림 좌표는 Kaltoe.Core 의 PhotoMascot(순수 함수, 맥과 같은 숫자)가 계산하고 여기서는 그리기만 한다.
/// 컨트롤 안의 좌표는 "기본 크기 1px = _unit DIP" 로 환산한다.
internal sealed class PhotoMascotControl : FrameworkElement, IMascotView
{
    private const int ShadowPadPx = 12;      // 그림자 이미지에 더하는 사방 여유(이미지 픽셀) — 흐림이 번질 자리
    private const int ShadowBlurRadiusPx = 5; // 박스 블러 반지름(이미지 픽셀). 표시 폭 60 기준 "흐림 3" 에 해당(60/192 × 5 × 2 패스 ≈ 3)

    private static BitmapSource? _builtin;
    private static bool _builtinTried;

    private static readonly Dictionary<(uint Rgb, byte Alpha), SolidColorBrush> BrushCache = new();
    private static readonly Typeface ZFace = new(new FontFamily("Segoe UI, Malgun Gothic"), FontStyles.Normal, FontWeights.Black, FontStretches.Normal);

    private readonly PhotoSource _source;
    private BitmapSource? _shadow;           // 이 컨트롤의 사진용 그림자(한 번만 만든다)
    private readonly double _unit;
    private readonly bool _shadowOn;
    private readonly double _side;       // 정사각형 슬롯 한 변(= 60 × 비율). 사진은 이 안에서 아래에 붙는다.
    private readonly double _headroom;   // 슬롯 위쪽 여유: 점프 높이 + z 가 머리 위로 올라갈 자리

    private MascotMood _mood = MascotMood.Sleep;
    private double _seconds;
    private double? _sinceJump;

    /// <param name="unit">기본 크기 1px 가 이 컨트롤의 로컬 좌표에서 몇 DIP 인가(터미널 1, 말풍선은 글자 크기 비율).</param>
    /// <param name="shadow">말풍선 모양이면 true — 외곽선 대신 옅은 그림자(검정 35%, 흐림 3, 아래 1).</param>
    /// <param name="source">그릴 사진(내장 또는 사용자 지정)과 덧그림 위치.</param>
    public PhotoMascotControl(double unit, bool shadow, PhotoSource source)
    {
        _source = source;
        _unit = Math.Max(0.1, unit);
        _shadowOn = shadow;
        _side = WidgetSizing.PhotoBaseExtent * _unit;
        _headroom = Math.Ceiling(PhotoMascot.JumpHeadroom * _unit + 0.12 * _side);
        // 사진은 부드럽게(고품질 보간) 그린다. 픽셀 캐릭터와 달리 안티에일리어싱·칸 맞춤을 끈다.
        SnapsToDevicePixels = false;
        UseLayoutRounding = false;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        RenderOptions.SetEdgeMode(this, EdgeMode.Unspecified);
    }

    public FrameworkElement Element => this;

    public void Animate(MascotMood mood, double seconds, double? secondsSinceJump)
    {
        _mood = mood;
        _seconds = seconds;
        _sinceJump = secondsSinceJump;
        InvalidateVisual();
    }

    protected override Size MeasureOverride(Size availableSize) => new(_side, _headroom + _side);

    // ── 이미지 ──

    private BitmapSource? Image() => _source.Image ?? BuiltinImage();

    /// 내장 강아지 사진(리소스). 없으면 null — 사진 없이 덧그림만 그린다.
    internal static BitmapSource? BuiltinImage()
    {
        if (_builtinTried) return _builtin;
        _builtinTried = true;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri($"pack://application:,,,/Assets/{MascotAssets.PhotoImageFile}", UriKind.Absolute);
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            bmp.Freeze();
            _builtin = bmp;
        }
        catch (Exception ex)
        {
            Log.Write($"실사 이미지 로드 실패: {ex.Message}");   // 리소스가 없으면 사진 없이 덧그림만 그린다
        }
        return _builtin;
    }

    /// 사진의 알파를 흐리게 한 옅은 검정 그림자 이미지(사방 ShadowPadPx 여유). 한 번만 만든다.
    private BitmapSource? Shadow(BitmapSource img)
    {
        if (_shadow is not null) return _shadow;
        try
        {
            var src = new FormatConvertedBitmap(img, PixelFormats.Bgra32, null, 0);
            int w = src.PixelWidth, h = src.PixelHeight;
            var stride = w * 4;
            var pixels = new byte[h * stride];
            src.CopyPixels(pixels, stride, 0);

            int sw = w + 2 * ShadowPadPx, sh = h + 2 * ShadowPadPx;
            var a = new float[sw * sh];
            for (var y = 0; y < h; y++)
                for (var x = 0; x < w; x++)
                    a[(y + ShadowPadPx) * sw + x + ShadowPadPx] = pixels[y * stride + x * 4 + 3] / 255f;
            for (var pass = 0; pass < 2; pass++) a = BoxBlur(a, sw, sh, ShadowBlurRadiusPx);

            var outPx = new byte[sw * sh * 4];
            for (var i = 0; i < a.Length; i++)
                outPx[i * 4 + 3] = (byte)Math.Clamp((int)Math.Round(a[i] * 0.35f * 255f), 0, 255);   // 검정(0,0,0), 불투명도 35%
            var bmp = BitmapSource.Create(sw, sh, 96, 96, PixelFormats.Bgra32, null, outPx, sw * 4);
            bmp.Freeze();
            _shadow = bmp;
        }
        catch (Exception ex)
        {
            Log.Write($"그림자 생성 실패: {ex.Message}");
        }
        return _shadow;
    }

    private static float[] BoxBlur(float[] src, int w, int h, int r)
    {
        var tmp = new float[src.Length];
        var dst = new float[src.Length];
        var n = 2 * r + 1;
        for (var y = 0; y < h; y++)
        {
            float sum = 0;
            for (var dx = -r; dx <= r; dx++) sum += src[y * w + Math.Clamp(dx, 0, w - 1)];
            for (var x = 0; x < w; x++)
            {
                tmp[y * w + x] = sum / n;
                sum += src[y * w + Math.Min(x + r + 1, w - 1)] - src[y * w + Math.Max(x - r, 0)];
            }
        }
        for (var x = 0; x < w; x++)
        {
            float sum = 0;
            for (var dy = -r; dy <= r; dy++) sum += tmp[Math.Clamp(dy, 0, h - 1) * w + x];
            for (var y = 0; y < h; y++)
            {
                dst[y * w + x] = sum / n;
                sum += tmp[Math.Min(y + r + 1, h - 1) * w + x] - tmp[Math.Max(y - r, 0) * w + x];
            }
        }
        return dst;
    }

    // ── 그리기 ──

    private static SolidColorBrush BrushOf(uint rgb, double alpha = 1)
    {
        var a = (byte)Math.Clamp((int)Math.Round(alpha * 255), 0, 255);
        if (!BrushCache.TryGetValue((rgb, a), out var b))
        {
            b = new SolidColorBrush(Color.FromArgb(a, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
            b.Freeze();
            BrushCache[(rgb, a)] = b;
        }
        return b;
    }

    protected override void OnRender(DrawingContext dc)
    {
        var img = Image();
        var u = _unit;
        var side = _side;
        var aspect = img is null || img.PixelHeight == 0 ? 1.0 : (double)img.PixelWidth / img.PixelHeight;
        // 이미지 사각형: 긴 변이 슬롯(정사각형)의 한 변. 가로로 긴 사진은 폭이, 세로로 긴 사진은 높이가 side.
        var w = aspect >= 1 ? side : side * aspect;
        var h = aspect >= 1 ? side / aspect : side;
        var x0 = (side - w) / 2;             // 슬롯 안에서 가운데
        var bottom = _headroom + side;       // 슬롯 바닥 = 이미지 아랫변
        var top = bottom - h;                // 이미지 윗변

        // 사진 영역만 클릭·드래그를 받는다(점프 판정).
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(x0, top, w, h));

        var lift = PhotoMascot.JumpLift(_sinceJump) * u;
        // 이후 좌표는 이미지 사각형의 왼쪽(x = 0)을 기준으로 한다. 점프는 덧그림까지 통째로.
        dc.PushTransform(new TranslateTransform(x0, -lift));

        // 1) 사진 + 사진을 따라 움직이는 덧그림(눈물·화남 표시)
        var m = PhotoMascot.Transform(_mood, _seconds);
        dc.PushTransform(new TranslateTransform(m.OffsetX * u, m.OffsetY * u));
        dc.PushTransform(new RotateTransform(m.Rotation, w / 2, bottom));
        dc.PushTransform(new ScaleTransform(1, m.ScaleY, w / 2, bottom));
        dc.PushOpacity(m.Opacity);
        if (img is not null)
        {
            if (_shadowOn && Shadow(img) is { } shadow)
            {
                var k = w / img.PixelWidth;   // 이미지 픽셀 → DIP
                dc.DrawImage(shadow, new Rect(-ShadowPadPx * k, top - ShadowPadPx * k + 1 * u,
                    shadow.PixelWidth * k, shadow.PixelHeight * k));
            }
            dc.DrawImage(img, new Rect(0, top, w, h));
        }
        if (_mood == MascotMood.Angry) DrawAnger(dc, w, h, top);   // 중심은 _source.Anger*
        if (_mood == MascotMood.Cry) DrawTears(dc, w, h, top);
        dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop();   // 불투명도, 배율, 회전, 이동

        // 2) 제자리에 있는 덧그림(z·밥그릇·반짝이·색종이)
        switch (_mood)
        {
            case MascotMood.Sleep: DrawZ(dc, w, h, top); break;
            case MascotMood.Eat: DrawBowl(dc, w, h, top); break;
            case MascotMood.Sparkle: DrawSparks(dc, w, h, top); break;
            case MascotMood.Dance: DrawConfetti(dc, w, h, top); break;
        }
        dc.Pop();   // 점프
    }

    private void DrawZ(DrawingContext dc, double w, double h, double top)
    {
        if (PhotoMascot.ZFloat(_seconds) is not { } z) return;
        // 말풍선(밝은 배경)에서는 어두운 회색, 터미널(어두운 배경)에서는 밝은 회색
        var color = _shadowOn ? 0x6E6E73u : 0xC7C7CCu;
        var ft = new FormattedText("z", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, ZFace, 0.22 * w,
            BrushOf(color, z.Alpha), VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(ft, new Point(z.X * w - ft.Width / 2, top + z.Y * h - ft.Height / 2));
    }

    private static void DrawBowl(DrawingContext dc, double w, double h, double top)
    {
        var bw = PhotoMascot.BowlWidth * w;
        var bh = PhotoMascot.BowlHeight * w;
        var x0 = PhotoMascot.BowlCenterX * w - bw / 2;
        var bottom = top + h + 0.03 * w;      // 이미지 아래 변보다 살짝 아래(발 앞)
        var rimH = bh * 0.34;
        var food = BrushOf(0x8B5A2B);
        // 사료(수북이)
        dc.DrawEllipse(food, null, new Point(x0 + bw / 2, bottom - bh - rimH * 0.2 + rimH * 0.55), bw * 0.4, rimH * 0.55);
        // 그릇 몸통(아래가 좁은 사다리꼴)
        var body = new StreamGeometry();
        using (var c = body.Open())
        {
            c.BeginFigure(new Point(x0, bottom - bh + rimH / 2), true, true);
            c.LineTo(new Point(x0 + bw, bottom - bh + rimH / 2), true, false);
            c.LineTo(new Point(x0 + bw * 0.86, bottom), true, false);
            c.LineTo(new Point(x0 + bw * 0.14, bottom), true, false);
        }
        body.Freeze();
        dc.DrawGeometry(BrushOf(0xE8734A), null, body);
        // 윗 테두리
        dc.DrawEllipse(BrushOf(0xF7B48F), null, new Point(x0 + bw / 2, bottom - bh + rimH / 2), bw * 0.52, rimH / 2);
        dc.DrawEllipse(food, null, new Point(x0 + bw / 2, bottom - bh + rimH * 0.18 + rimH * 0.32), bw * 0.42, rimH * 0.32);
    }

    private static Geometry Star(Point center, double r)
    {
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            var inner = r * 0.28;
            for (var i = 0; i < 8; i++)
            {
                var radius = i % 2 == 0 ? r : inner;
                var a = i * Math.PI / 4 - Math.PI / 2;
                var p = new Point(center.X + Math.Cos(a) * radius, center.Y + Math.Sin(a) * radius);
                if (i == 0) c.BeginFigure(p, true, true); else c.LineTo(p, true, false);
            }
        }
        g.Freeze();
        return g;
    }

    private void DrawSparks(DrawingContext dc, double w, double h, double top)
    {
        foreach (var s in PhotoMascot.Sparks(_seconds))
            dc.DrawGeometry(BrushOf(PhotoMascot.SparkColor, s.Alpha), null, Star(new Point(s.X * w, top + s.Y * h), s.Size * w));
    }

    private void DrawConfetti(DrawingContext dc, double w, double h, double top)
    {
        foreach (var p in PhotoMascot.Confetti(_seconds))
        {
            var cx = p.X * w;
            var cy = top + p.Y * h;
            var s = p.Size * w;
            dc.PushTransform(new RotateTransform(p.Rotation, cx, cy));
            dc.DrawRectangle(BrushOf(p.Color), null, new Rect(cx - s / 2, cy - s / 4, s, s / 2));
            dc.Pop();
        }
    }

    /// 화남 표시(💢): 중심을 둘러싼 네 개의 안쪽으로 휜 호 (맥과 같은 기하).
    private void DrawAnger(DrawingContext dc, double w, double h, double top)
    {
        var cx = _source.AngerX * w;
        var cy = top + _source.AngerY * h;
        var r = PhotoMascot.AngerSize * PhotoMascot.AngerPulse(_seconds) * w / 2;
        var d = r * 0.8;
        var rho = r * 0.5;
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            foreach (var (sx, sy) in new[] { (-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0) })
            {
                var corner = new Point(cx + sx * d, cy + sy * d);
                // 화면 좌표(아래가 +y)에서 중심을 향하는 90° 구간의 시작 각도
                var a0 = sx < 0 ? (sy < 0 ? 0.0 : 270.0) : (sy < 0 ? 90.0 : 180.0);
                for (var step = 0; step <= 8; step++)
                {
                    var a = (a0 + step * 11.25) * Math.PI / 180;
                    var p = new Point(corner.X + Math.Cos(a) * rho, corner.Y + Math.Sin(a) * rho);
                    if (step == 0) c.BeginFigure(p, false, false); else c.LineTo(p, true, true);
                }
            }
        }
        g.Freeze();
        var pen = new Pen(BrushOf(PhotoMascot.AngerColor), Math.Max(1.5, 0.045 * w))
        { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        dc.DrawGeometry(null, pen, g);
    }

    private void DrawTears(DrawingContext dc, double w, double h, double top)
    {
        foreach (var t in PhotoMascot.Tears(_seconds, _source.LeftEyeX, _source.LeftEyeY, _source.RightEyeX, _source.RightEyeY))
        {
            var dw = 0.05 * w;
            var dh = 0.075 * w;
            dc.DrawEllipse(BrushOf(PhotoMascot.TearColor, t.Alpha), null, new Point(t.X * w, top + t.Y * h), dw / 2, dh / 2);
        }
    }
}
