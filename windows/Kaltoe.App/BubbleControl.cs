using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 말풍선: 흰 채움 + 2px 테두리 + 픽셀 계단 모서리 + 오른쪽 아래 꼬리, 한 줄 글자.
/// 모든 치수(계단 한 칸·여백·테두리)는 글자 크기 비율에 맞춰 키운다.
internal sealed class BubbleControl : FrameworkElement
{
    private static readonly Brush Fill = Freeze(new SolidColorBrush(Color.FromRgb(0xFF, 0xFF, 0xFF)));
    private static readonly Brush Stroke = Freeze(new SolidColorBrush(Color.FromRgb(0x2B, 0x2B, 0x33)));
    private static readonly Brush TextBrush = Freeze(new SolidColorBrush(Color.FromRgb(0x1B, 0x1B, 0x1F)));
    private static readonly Typeface Face = new(new FontFamily("Segoe UI, Malgun Gothic"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);

    private readonly double _textSize;   // fontSize + 1 (px)
    private readonly int _step;          // 계단 한 칸 = 테두리 두께(px). 기본 글자 크기에서 2.
    private readonly int _padX, _padY;
    private string _text = "";
    private FormattedText? _formatted;

    public BubbleControl(int fontSize)
    {
        _textSize = fontSize + 1;
        var factor = WidgetSizing.Factor(fontSize);
        _step = Math.Max(1, (int)Math.Round(2 * factor));
        _padX = Math.Max(1, (int)Math.Round(12 * factor));
        _padY = Math.Max(1, (int)Math.Round(8 * factor));
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
        RenderOptions.SetEdgeMode(this, EdgeMode.Aliased);
    }

    private static Brush Freeze(SolidColorBrush b) { b.Freeze(); return b; }

    public string Text
    {
        get => _text;
        set
        {
            if (_text == value) return;
            _text = value;
            _formatted = null;
            InvalidateMeasure();
            InvalidateVisual();
        }
    }

    private FormattedText Format()
        => _formatted ??= new FormattedText(_text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
            Face, _textSize, TextBrush, VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private (int W, int H) Body()
    {
        var ft = Format();
        var min = BubbleShape.MinBody(_step);
        var w = (int)Math.Ceiling(ft.WidthIncludingTrailingWhitespace) + 2 * (_padX + _step);
        var h = (int)Math.Ceiling(ft.Height) + 2 * (_padY + _step);
        return (Math.Max(w, min.Width), Math.Max(h, min.Height));
    }

    protected override Size MeasureOverride(Size availableSize)
    {
        var (w, h) = Body();
        return new Size(w, h + BubbleShape.TailHeight(_step));
    }

    protected override void OnRender(DrawingContext dc)
    {
        var (w, h) = Body();
        // 테두리 선은 윤곽선 가운데에 그려지므로 반 두께만큼 안쪽으로 들여 바깥 가장자리가 정확히 크기에 맞게.
        var inset = _step / 2.0;
        var pts = BubbleShape.Outline(w - _step, h - _step, _step);

        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            ctx.BeginFigure(new Point(pts[0].X + inset, pts[0].Y + inset), isFilled: true, isClosed: true);
            for (var i = 1; i < pts.Count; i++)
                ctx.LineTo(new Point(pts[i].X + inset, pts[i].Y + inset), isStroked: true, isSmoothJoin: false);
        }
        geometry.Freeze();

        var pen = new Pen(Stroke, _step) { LineJoin = PenLineJoin.Miter, MiterLimit = 4 };
        pen.Freeze();
        dc.DrawGeometry(Fill, pen, geometry);
        dc.DrawText(Format(), new Point(_step + _padX, _step + _padY));
    }
}
