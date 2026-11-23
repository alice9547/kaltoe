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

/// 트레이 메뉴와 위젯 오른쪽 클릭 메뉴가 공유하는 WinForms 메뉴 채우기. 항목 목록은 Core 의 WidgetMenu.Build 가 정한다.
internal static class MenuPresenter
{
    public static void Fill(ContextMenuStrip menu, Func<TrayMenuState> state, TrayActions actions)
    {
        var st = state();
        var old = menu.Items.Cast<ToolStripItem>().ToList();
        menu.Items.Clear();
        foreach (var item in old) item.Dispose();

        foreach (var e in WidgetMenu.Build(st.Snapshot, st.Settings, st.WidgetVisible, st.LaunchAtLogin, st.IsDemo))
        {
            if (e.IsSeparator) { menu.Items.Add(new ToolStripSeparator()); continue; }
            var checkedNow = e.Checked;
            ToolStripMenuItem item = e.Action switch
            {
                MenuAction.ToggleWidget => new(e.Text, null, (_, _) => actions.ToggleWidget()),
                MenuAction.OpenSettings => new(e.Text, null, (_, _) => actions.OpenSettings()),
                MenuAction.RedetectToday => new(e.Text, null, (_, _) => actions.RedetectToday()),
                MenuAction.ToggleLaunchAtLogin => new(e.Text, null, (_, _) => actions.SetLaunchAtLogin(!checkedNow)),
                MenuAction.Quit => new(e.Text, null, (_, _) => actions.Quit()),
                _ => new(e.Text),
            };
            item.Enabled = e.Enabled;
            item.Checked = e.Checked;
            menu.Items.Add(item);
        }
    }
}

/// 위젯 오른쪽 클릭 메뉴(docs/spec.md 7절 3번). 위젯 창은 WS_EX_NOACTIVATE 라 WPF ContextMenu 는 포커스 문제로 안 닫힐 수 있어 WinForms 메뉴를 쓴다.
internal sealed class WidgetContextMenu : IDisposable
{
    private readonly ContextMenuStrip _menu = new();
    private readonly TrayActions _actions;
    private readonly Func<TrayMenuState> _state;

    public WidgetContextMenu(TrayActions actions, Func<TrayMenuState> state)
    {
        _actions = actions;
        _state = state;
    }

    /// 화면 좌표(물리 픽셀)에 메뉴를 띄운다. UI 스레드에서만 호출한다.
    public void Show(int screenX, int screenY)
    {
        try
        {
            MenuPresenter.Fill(_menu, _state, _actions);
            Native.BringToForeground(_menu.Handle);   // 이게 없으면 바깥을 클릭해도 메뉴가 안 닫힌다
            _menu.Show(new System.Drawing.Point(screenX, screenY));
        }
        catch (Exception ex) { Log.Write($"위젯 메뉴 표시 실패: {ex.Message}"); }
    }

    public void Dispose() => _menu.Dispose();
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

    private System.Drawing.Icon LoadIcon() => LoadIcon(MascotCharacter.Maltese);

    /// 캐릭터별 트레이 아이콘(tray.ico / tray-orange.ico). 없으면 tray.ico, 그것도 없으면 기본 아이콘.
    private System.Drawing.Icon LoadIcon(MascotCharacter character)
    {
        foreach (var file in new[] { MascotAssets.TrayIconFile(character), MascotAssets.FallbackTrayIconFile })
        {
            try
            {
                var info = System.Windows.Application.GetResourceStream(new Uri($"pack://application:,,,/Assets/{file}", UriKind.Absolute));
                if (info?.Stream is not { } stream) continue;
                using (stream)
                {
                    var icon = new System.Drawing.Icon(stream);
                    _ownedIcon = icon;   // 이전 아이콘은 호출한 쪽(SetCharacter)이 교체한 뒤에 해제한다
                    return icon;
                }
            }
            catch (Exception ex)
            {
                Log.Write($"트레이 아이콘 로드 실패({file}): {ex.Message}");
            }
        }
        return System.Drawing.SystemIcons.Application;
    }

    /// 설정에서 캐릭터를 바꾸면 트레이 아이콘도 즉시 바꾼다.
    public void SetCharacter(MascotCharacter character)
    {
        if (_disposed) return;
        var previous = _ownedIcon;
        var icon = LoadIcon(character);
        _icon.Icon = icon;
        if (previous is not null && !ReferenceEquals(previous, _ownedIcon)) previous.Dispose();
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

    private void RebuildMenu() => MenuPresenter.Fill(_menu, _state, _actions);

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
