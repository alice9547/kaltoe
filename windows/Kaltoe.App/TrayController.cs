using System.Windows.Forms;
using Kaltoe.Core;

namespace Kaltoe.App;

internal sealed record TrayMenuState(
    WorkdaySnapshot Snapshot, AppSettings Settings, bool WidgetVisible, bool LaunchAtLogin, bool IsDemo);

internal sealed class TrayActions
{
    public Action ToggleWidget = () => { };
    public Action OpenSettings = () => { };
    public Action RedetectToday = () => { };
    public Action<bool> SetLaunchAtLogin = _ => { };
    public Action Quit = () => { };
}

/// 트레이 아이콘: 툴팁(spec 4절 한 줄), 왼쪽 클릭 = 위젯 보이기/숨기기, 오른쪽 클릭 = 메뉴, 알림은 풍선.
internal sealed class TrayController : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly ContextMenuStrip _menu = new();
    private readonly TrayActions _actions;
    private readonly Func<TrayMenuState> _state;
    private System.Drawing.Icon? _ownedIcon;
    private string _tooltip = "";
    private bool _disposed;

    public TrayController(TrayActions actions, Func<TrayMenuState> state)
    {
        _actions = actions;
        _state = state;
        _menu.Opening += (_, _) => RebuildMenu();

        _icon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "칼퇴",
            ContextMenuStrip = _menu,
            Visible = true,
        };
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) _actions.ToggleWidget();
        };
    }

    private System.Drawing.Icon LoadIcon()
    {
        try
        {
            var info = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/tray.ico", UriKind.Absolute));
            if (info?.Stream is { } stream)
            {
                using (stream) _ownedIcon = new System.Drawing.Icon(stream);
                return _ownedIcon;
            }
        }
        catch (Exception ex)
        {
            Log.Write($"트레이 아이콘 로드 실패(기본 아이콘 사용): {ex.Message}");
        }
        return System.Drawing.SystemIcons.Application;
    }

    public void SetTooltip(string text)
    {
        var t = WidgetText.Truncate(text);   // 63자 제한
        if (_disposed || t == _tooltip) return;
        _tooltip = t;
        try { _icon.Text = t; }
        catch (Exception ex) { Log.Write($"툴팁 설정 실패: {ex.Message}"); }
    }

    public void ShowBalloon(string title, string body)
    {
        if (_disposed) return;
        try { _icon.ShowBalloonTip(5000, title, body, ToolTipIcon.None); }
        catch (Exception ex) { Log.Write($"알림 표시 실패: {ex.Message}"); }
    }

    private void RebuildMenu()
    {
        var st = _state();
        _menu.Items.Clear();

        void Info(string text) => _menu.Items.Add(new ToolStripMenuItem(text) { Enabled = false });

        Info(WidgetText.ClockInMenuTitle(st.Snapshot));
        if (WidgetText.ClockOutMenuTitle(st.Snapshot) is { } outTitle) Info(outTitle);
        if (WidgetText.LunchMenuTitle(st.Settings) is { } lunchTitle) Info(lunchTitle);
        _menu.Items.Add(new ToolStripSeparator());

        _menu.Items.Add(new ToolStripMenuItem(st.WidgetVisible ? "위젯 숨기기" : "위젯 보이기", null, (_, _) => _actions.ToggleWidget()));
        _menu.Items.Add(new ToolStripMenuItem("설정…", null, (_, _) => _actions.OpenSettings()) { Enabled = !st.IsDemo });
        if (st.Settings.Mode == WorkMode.Flexible)
            _menu.Items.Add(new ToolStripMenuItem("오늘 출근 다시 감지", null, (_, _) => _actions.RedetectToday()) { Enabled = !st.IsDemo });
        _menu.Items.Add(new ToolStripMenuItem("로그인 시 자동 실행", null, (_, _) => _actions.SetLaunchAtLogin(!st.LaunchAtLogin))
        {
            Checked = st.LaunchAtLogin,
            Enabled = !st.IsDemo,
        });
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(new ToolStripMenuItem("칼퇴 종료", null, (_, _) => _actions.Quit()));
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try
        {
            _icon.Visible = false;   // 종료 후 트레이에 유령 아이콘이 남지 않게
            _icon.Dispose();
            _menu.Dispose();
            _ownedIcon?.Dispose();
        }
        catch (Exception ex) { Log.Write($"트레이 해제 실패: {ex.Message}"); }
    }
}
