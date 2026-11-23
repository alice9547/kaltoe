using System.Windows;
using System.Windows.Controls;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 말풍선 모양 위젯(docs/spec.md 5-2절): 투명 창에 마스코트 + 한 줄 말풍선.
/// 문구 길이에 따라 창 폭이 바뀌어도 마스코트(오른쪽 아래)가 제자리에 있도록 창의 오른쪽 아래 모서리를 기준(anchor)으로 배치한다.
internal sealed class BubbleWidgetWindow : FloatingWindow, IWidgetView
{
    private readonly int _fontSize;
    private readonly PlacementRequest _placement;
    private readonly BubbleControl _bubble;
    private readonly IMascotView _mascot;
    private MascotMood _mood = MascotMood.Sleep;
    private double _jumpStart = double.NaN;
    private double _seconds;
    private (int Right, int Bottom)? _anchor;

    // 말풍선 위젯에는 신호등 점이 없다 — 숨기기는 메뉴로만.
    public event Action? HideRequested { add { } remove { } }

    public BubbleWidgetWindow(MascotCharacter character, int fontSize, PlacementRequest placement, PhotoSource? photo = null)
    {
        _fontSize = fontSize;
        _placement = placement;
        SizeToContent = SizeToContent.WidthAndHeight;

        var factor = WidgetSizing.Factor(fontSize);

        _bubble = new BubbleControl(fontSize)
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            // 꼬리가 마스코트 머리 쪽(오른쪽 아래)을 향하도록, 말풍선 오른쪽 끝을 마스코트보다 안쪽에 둔다.
            Margin = new Thickness(0, 0, Math.Round(24 * factor), 0),
        };
        _mascot = MascotViews.Create(character, fontSize, WidgetStyle.Bubble, 1.0, photo);
        _mascot.Element.HorizontalAlignment = HorizontalAlignment.Right;
        _mascot.Element.VerticalAlignment = VerticalAlignment.Top;
        // 사진은 창 가장자리까지 그려지므로 덧그림이 잘리지 않게 오른쪽·아래에 작은 여유를 둔다(맥 말풍선과 같은 2px × 비율).
        if (character == MascotCharacter.Photo)
            _mascot.Element.Margin = new Thickness(0, 0, Math.Round(2 * factor), Math.Round(2 * factor));

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(_bubble, 0);
        Grid.SetRow(_mascot.Element, 1);
        grid.Children.Add(_bubble);
        grid.Children.Add(_mascot.Element);
        Content = grid;

        // 첫 레이아웃이 HWND 생성보다 먼저 끝날 수도 있어, 세 시점 모두에서 (멱등하게) 배치한다.
        SizeChanged += (_, _) => Reposition();
        Loaded += (_, _) => Reposition();
        ContentRendered += (_, _) => Reposition();
    }

    // ── 배치 ──

    protected override void PlaceInitially()
    {
        // 크기는 아직 모른다(레이아웃 전) — 첫 SizeChanged 에서 anchor 를 정하고 옮긴다.
    }

    private (int W, int H)? SizePx()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return null;
        var dpi = Dpi;
        return (ToPx(ActualWidth, dpi.DpiScaleX), ToPx(ActualHeight, dpi.DpiScaleY));
    }

    private void Reposition()
    {
        if (Handle == IntPtr.Zero || SizePx() is not { } size) return;
        var areas = Screens.WorkAreas();
        var primary = Screens.Primary();

        if (_anchor is null)
        {
            if (_placement is { Kind: PlacementKind.KeepTopLeft, X: { } kx, Y: { } ky })
            {
                var tl = WidgetPlacement.ClampInto(new PixelRect(kx, ky, size.W, size.H), areas, primary);
                _anchor = (tl.X + size.W, tl.Y + size.H);
            }
            else if (_placement is { X: { } r, Y: { } b }
                     && WidgetPlacement.IsOnScreen(new PixelRect(r - size.W, b - size.H, size.W, size.H), areas))
            {
                _anchor = (r, b);
            }
            else
            {
                var tl = WidgetPlacement.DefaultPosition(primary, size.W, size.H);
                _anchor = (tl.X + size.W, tl.Y + size.H);
            }
        }

        var (right, bottom) = _anchor.Value;
        var x = right - size.W;
        var y = bottom - size.H;
        if (PositionNow() is not { } cur || cur.X != x || cur.Y != y) Native.MoveTo(Handle, x, y);
    }

    private (int X, int Y)? PositionNow() => TopLeftPx;

    protected override void OnDragEnded()
    {
        if (RectPx is { } r) _anchor = (r.Right, r.Bottom);
    }

    public (int X, int Y)? PositionToSave => _anchor is { } a ? (a.Right, a.Bottom) : null;

    // ── 내용 ──

    public void Update(WorkdaySnapshot snapshot, AppSettings settings)
    {
        _mood = MascotPlayback.MoodOf(snapshot, settings.Pay);
        _bubble.Text = BubbleText.Line(snapshot, settings.Pay);
    }

    public void Animate(double seconds)
    {
        _seconds = seconds;
        double? since = double.IsNaN(_jumpStart) ? null : seconds - _jumpStart;
        _mascot.Animate(_mood, seconds, since);
    }

    protected override bool IsMascotHit(DependencyObject? source) => IsInside(source, _mascot.Element);

    protected override void OnMascotClicked() => _jumpStart = _seconds;
}
