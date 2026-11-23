using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Kaltoe.Core;

namespace Kaltoe.App;

internal enum PlacementKind
{
    /// 저장된 위치(없거나 화면 밖이면 기본 위치).
    Saved,
    /// 글자 크기를 바꾸는 중: 창의 왼쪽 위 모서리를 유지하고, 커져서 화면 밖으로 나가면 안으로 밀어 넣는다.
    KeepTopLeft,
}

/// X, Y 는 모양마다 의미가 다르다: 터미널은 왼쪽 위, 말풍선은 오른쪽 아래(Saved 일 때).
internal sealed record PlacementRequest(PlacementKind Kind, int? X, int? Y);

/// 컨트롤러가 위젯을 다루는 방식 — 터미널·말풍선 창이 같은 모양으로 구현한다.
internal interface IWidgetView
{
    void Update(WorkdaySnapshot snapshot, AppSettings settings);
    /// 마스코트·커서 애니메이션(0.1초마다). seconds = 재생 시작 후 지난 시간.
    void Animate(double seconds);
    void ShowWidget();
    void HideWidget();
    bool IsShown { get; }
    /// 저장할 위치. 창이 한 번도 안 만들어졌으면 null.
    (int X, int Y)? PositionToSave { get; }
    (int X, int Y)? TopLeftPx { get; }
    /// 사용자가 드래그를 끝냄(위치 저장 시점).
    event Action? Dropped;
    /// 터미널의 빨간 점 클릭.
    event Action? HideRequested;
    void CloseWidget();
}

/// 테두리 없는 투명 최상단 창의 공통 동작: 포커스 안 뺏기, 아무 데나 잡고 드래그, 마스코트는 클릭하면 점프(끌면 이동).
internal abstract class FloatingWindow : Window
{
    private Point? _pendingClick;
    private bool _closing;

    public event Action? Dropped;

    protected FloatingWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        WindowStartupLocation = WindowStartupLocation.Manual;
        // 첫 프레임이 엉뚱한 곳에 깜빡이지 않도록 화면 밖에서 시작해 SourceInitialized 에서 제자리로 옮긴다.
        Left = -10000;
        Top = -10000;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        Title = "칼퇴";
    }

    protected IntPtr Handle => new WindowInteropHelper(this).Handle;

    protected PixelRect? RectPx => Native.GetRect(Handle);

    public bool IsShown => IsVisible;

    public (int X, int Y)? TopLeftPx => RectPx is { } r ? (r.X, r.Y) : null;

    /// HWND 가 만들어진 직후(아직 안 보임). 확장 스타일과 위치를 여기서 적용한다 — 보이기 전이라 깜빡임이 없다.
    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        Native.ApplyNoActivateToolWindow(Handle);
        PlaceInitially();
    }

    protected abstract void PlaceInitially();

    protected abstract bool IsMascotHit(DependencyObject? source);

    protected abstract void OnMascotClicked();

    protected void RaiseDropped() => Dropped?.Invoke();

    protected static int ToPx(double dip, double scale) => (int)Math.Round(dip * scale);

    protected DpiScale Dpi => VisualTreeHelper.GetDpi(this);

    public void ShowWidget()
    {
        if (_closing) return;
        if (!IsVisible) Show();
    }

    public void HideWidget()
    {
        if (IsVisible) Hide();
    }

    public void CloseWidget()
    {
        _closing = true;
        try { Close(); } catch (InvalidOperationException) { /* 이미 닫힘 */ }
    }

    // ── 드래그 / 마스코트 클릭 ──

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.Handled || e.ButtonState != MouseButtonState.Pressed) return;
        if (IsMascotHit(e.OriginalSource as DependencyObject))
        {
            // 클릭이면 점프, 끌면 이동 — 움직임으로 구분한다.
            _pendingClick = e.GetPosition(this);
            CaptureMouse();
        }
        else
        {
            StartDrag();
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_pendingClick is not { } start) return;
        if (e.LeftButton != MouseButtonState.Pressed) { _pendingClick = null; ReleaseMouseCapture(); return; }
        var now = e.GetPosition(this);
        if (Math.Abs(now.X - start.X) >= SystemParameters.MinimumHorizontalDragDistance
            || Math.Abs(now.Y - start.Y) >= SystemParameters.MinimumVerticalDragDistance)
        {
            _pendingClick = null;
            ReleaseMouseCapture();
            StartDrag();
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (_pendingClick is null) return;
        _pendingClick = null;
        ReleaseMouseCapture();
        OnMascotClicked();
    }

    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        _pendingClick = null;
    }

    private void StartDrag()
    {
        try
        {
            DragMove();   // 마우스를 놓을 때까지 돌아오지 않는다
        }
        catch (InvalidOperationException)
        {
            return;   // 왼쪽 버튼이 이미 떼어진 경우
        }
        OnDragEnded();
        RaiseDropped();
    }

    protected virtual void OnDragEnded() { }

    protected static bool IsInside(DependencyObject? source, DependencyObject? container)
    {
        for (var d = source; d is not null; d = d is Visual or System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d))
            if (ReferenceEquals(d, container)) return true;
        return false;
    }
}
