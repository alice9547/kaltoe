using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Shapes;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 터미널 모양 위젯(docs/spec.md 4절). 기본 320×150 을 LayoutTransform 으로 글자 크기 비율만큼 키우고 줄인다.
internal sealed class TerminalWidgetWindow : FloatingWindow, IWidgetView
{
    private const double BaseWidth = WidgetSizing.BaseWidth;
    private const double BaseHeight = WidgetSizing.BaseHeight;

    private static readonly FontFamily Mono = new("Cascadia Mono, Consolas, D2Coding, Malgun Gothic");
    private static readonly FontFamily Sans = new("Segoe UI, Malgun Gothic");

    private static readonly Dictionary<uint, SolidColorBrush> Brushes_ = new();
    private static SolidColorBrush B(uint rgb, byte alpha = 255)
    {
        var key = ((uint)alpha << 24) ^ rgb ^ ((uint)alpha << 8);
        if (!Brushes_.TryGetValue(key, out var b))
        {
            b = new SolidColorBrush(Color.FromArgb(alpha, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
            b.Freeze();
            Brushes_[key] = b;
        }
        return b;
    }

    private readonly MascotArt _art;
    private readonly int _fontSize;
    private readonly double _factor;
    private readonly PlacementRequest _placement;
    private readonly TextBlock _lines;
    private readonly MascotControl _mascot;
    private Run? _cursor;
    private string _signature = "";
    private MascotMood _mood = MascotMood.Sleep;
    private double _jumpStart = double.NaN;
    private double _seconds;
    private bool _cursorOn = true;

    public event Action? HideRequested;

    public TerminalWidgetWindow(MascotArt art, int fontSize, PlacementRequest placement)
    {
        _art = art;
        _fontSize = fontSize;
        _factor = WidgetSizing.Factor(fontSize);
        _placement = placement;
        var (w, h) = WidgetSizing.WindowSize(fontSize);
        Width = w;
        Height = h;

        var cell = WidgetSizing.MascotCell(art.Width, art.Height, fontSize, WidgetStyle.Terminal);
        _mascot = new MascotControl(art, cell, _factor, outline: false)
        {
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 8, 6),
        };

        _lines = new TextBlock
        {
            FontFamily = Mono,
            FontSize = 12,
            LineHeight = 16,
            LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(12, 9, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
        };

        var content = new Grid();
        content.Children.Add(_lines);
        content.Children.Add(_mascot);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(26) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var bar = BuildTitleBar();
        Grid.SetRow(bar, 0);
        Grid.SetRow(content, 1);
        root.Children.Add(bar);
        root.Children.Add(content);

        var card = new Border
        {
            Width = BaseWidth,
            Height = BaseHeight,
            CornerRadius = new CornerRadius(12),
            Background = B(0x1B1B1F, 0xF0),   // 불투명도 0.94
            BorderBrush = B(0xFFFFFF, 0x14),
            BorderThickness = new Thickness(1),
            Child = root,
            LayoutTransform = new ScaleTransform(_factor, _factor),
            SnapsToDevicePixels = true,
        };
        Content = card;
    }

    private UIElement BuildTitleBar()
    {
        var title = new TextBlock
        {
            Text = "kaltoe — zsh",
            FontFamily = Sans,
            FontSize = 11,
            Foreground = B(0x8E8E93),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
        };

        Border Dot(uint rgb, bool clickable)
        {
            var dot = new Border
            {
                Padding = new Thickness(3.5, 7.5, 3.5, 7.5),
                Background = Brushes.Transparent,   // 점 주변도 클릭이 잡히게
                Child = new Ellipse { Width = 11, Height = 11, Fill = B(rgb) },
            };
            if (clickable)
            {
                dot.Cursor = Cursors.Hand;
                dot.MouseLeftButtonDown += (_, e) =>
                {
                    e.Handled = true;   // 드래그로 번지지 않게
                    HideRequested?.Invoke();
                };
            }
            return dot;
        }

        var dots = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(6.5, 0, 0, 0),
        };
        dots.Children.Add(Dot(0xFF5F57, true));
        dots.Children.Add(Dot(0xFEBC2E, false));
        dots.Children.Add(Dot(0x28C840, false));

        var grid = new Grid();
        grid.Children.Add(title);
        grid.Children.Add(dots);
        return new Border { Background = B(0x2A2A30), CornerRadius = new CornerRadius(11, 11, 0, 0), Child = grid };
    }

    // ── 배치 ──

    protected override void PlaceInitially()
    {
        var dpi = Dpi;
        var (w, h) = WidgetSizing.WindowSize(_fontSize);
        var size = (W: ToPx(w, dpi.DpiScaleX), H: ToPx(h, dpi.DpiScaleY));
        var areas = Screens.WorkAreas();
        var primary = Screens.Primary();

        (int X, int Y) pos;
        if (_placement is { Kind: PlacementKind.KeepTopLeft, X: { } kx, Y: { } ky })
            pos = WidgetPlacement.ClampInto(new PixelRect(kx, ky, size.W, size.H), areas, primary);
        else
            pos = WidgetPlacement.Restore(_placement.X, _placement.Y, size.W, size.H, areas, primary);
        Native.MoveTo(Handle, pos.X, pos.Y);
    }

    public (int X, int Y)? PositionToSave => TopLeftPx;

    // ── 내용 ──

    public void Update(WorkdaySnapshot snapshot, AppSettings settings)
    {
        _mood = MascotPlayback.MoodOf(snapshot, settings.Pay);
        var lines = WidgetText.Lines(snapshot, settings);
        var signature = string.Join("\n", lines.Select(l => string.Join("|", l.Spans.Select(s => $"{(int)s.Style}:{s.Text}"))));
        if (signature == _signature) return;
        _signature = signature;

        _lines.Inlines.Clear();
        for (var i = 0; i < lines.Count; i++)
        {
            if (i > 0) _lines.Inlines.Add(new LineBreak());
            foreach (var span in lines[i].Spans)
            {
                var run = new Run(span.Text) { Foreground = ColorOf(span.Style) };
                if (span.Style == LineStyle.AccentBold) run.FontWeight = FontWeights.Bold;
                _lines.Inlines.Add(run);
            }
        }
        // 마지막 줄 끝의 깜빡이는 블록 커서
        _cursor = new Run("█") { Foreground = _cursorOn ? B(0xF2F2F7) : Brushes.Transparent };
        _lines.Inlines.Add(_cursor);
    }

    private static Brush ColorOf(LineStyle style) => style switch
    {
        LineStyle.Prompt or LineStyle.Success => B(0x28C840),
        LineStyle.Command => B(0xF2F2F7),
        LineStyle.Output => B(0xC7C7CC),
        LineStyle.Accent or LineStyle.AccentBold => B(0xF28C5A),
        _ => B(0x6E6E73),   // Comment
    };

    public void Animate(double seconds)
    {
        _seconds = seconds;
        var on = (int)Math.Floor(seconds / 0.5) % 2 == 0;
        if (on != _cursorOn)
        {
            _cursorOn = on;
            if (_cursor is not null) _cursor.Foreground = on ? B(0xF2F2F7) : Brushes.Transparent;
        }
        double? since = double.IsNaN(_jumpStart) ? null : seconds - _jumpStart;
        _mascot.SetPose(MascotPlayback.Resolve(_mood, seconds, since, _art.Height));
    }

    protected override bool IsMascotHit(DependencyObject? source) => IsInside(source, _mascot);

    protected override void OnMascotClicked() => _jumpStart = _seconds;
}
