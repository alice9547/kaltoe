using System.Diagnostics;
using System.Windows.Threading;
using Kaltoe.Core;
using Microsoft.Win32;

namespace Kaltoe.App;

/// 설정 창이 컨트롤러에 요청하는 것.
internal interface ISettingsHost
{
    AppSettings CurrentSettings { get; }
    DateTime Today { get; }
    DateTime? TodayClockIn { get; }
    bool LaunchAtLogin { get; set; }
    void ApplySettings(AppSettings settings);
}

/// 앱 전체 배선: 엔진·저장·위젯·트레이·타이머·시스템 이벤트. UI 스레드에서만 쓴다.
internal sealed class AppController : ISettingsHost, IDisposable
{
    private readonly Dispatcher _dispatcher = System.Windows.Application.Current.Dispatcher;
    private readonly LaunchOptions _options;
    private readonly DemoScenario? _demo;
    private readonly Stopwatch _wall = Stopwatch.StartNew();   // 데모 가상 시계 + 애니메이션 시계

    private AppFile _file = new();
    private DayState _days = new();
    private WorkdayEngine? _engine;
    private IWidgetView? _widget;
    private TrayController? _tray;
    private SettingsWindow? _settingsWindow;
    private DispatcherTimer? _clockTimer;
    private DispatcherTimer? _animTimer;
    private WorkdaySnapshot _snapshot = WorkdaySnapshot.Waiting(DateTime.Now);
    private bool _widgetVisible = true;
    private bool _disposed;
    private bool _systemEventsHooked;

    public AppController(LaunchOptions options)
    {
        _options = options;
        if (options.IsDemo)
        {
            var widget = new WidgetSettings
            {
                Style = options.Style ?? WidgetStyle.Terminal,
                FontSize = options.FontSize ?? WidgetSizing.DefaultFontSize,
                Character = options.Character ?? MascotCharacter.Maltese,
            };
            _demo = DemoScenario.Create(options.DemoName, DateTime.Today, widget, new PaySettings { Comprehensive = options.Comprehensive ?? new PaySettings().Comprehensive });
        }
    }

    private bool IsDemo => _demo is not null;

    private static DateTime Now() => DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified);

    public AppSettings CurrentSettings => _engine?.Settings ?? _demo?.Settings ?? _file.Settings;
    public DateTime Today => DateTime.Today;
    public DateTime? TodayClockIn => _engine?.ClockInRecord(Now());

    public bool LaunchAtLogin
    {
        get => LoginItem.IsEnabled();
        set => SetLaunchAtLogin(value);
    }

    // ── 시작·종료 ──

    public void Start()
    {
        if (IsDemo)
        {
            _file = new AppFile { Settings = _demo!.Settings };
        }
        else
        {
            _file = AppFile.Parse(FileIo.ReadOrNull(AppPaths.Settings));
            _days = DayState.Parse(FileIo.ReadOrNull(AppPaths.ClockIn));
            FirstRunSetup();

            _engine = new WorkdayEngine(_file.Settings, _days);
            _engine.StateChanged += SaveDays;
            _engine.RecoveryRequested += OnRecoveryRequested;
            _engine.Start(Now(), isLocked: false);   // 시작 시에는 잠기지 않은 것으로 가정
        }

        _widgetVisible = _file.Widget.Visible;
        _tray = new TrayController(BuildTrayActions(), () => new TrayMenuState(
            _snapshot, CurrentSettings, _widgetVisible, LoginItem.IsEnabled(), IsDemo));

        _tray.SetCharacter(CurrentSettings.Widget.Character);
        CreateWidget(PlacementKind.Saved);
        HookSystemEvents();

        _animTimer = new DispatcherTimer(DispatcherPriority.Render, _dispatcher) { Interval = TimeSpan.FromMilliseconds(100) };
        _animTimer.Tick += (_, _) => _widget?.Animate(_wall.Elapsed.TotalSeconds);
        if (_widgetVisible) _animTimer.Start();

        _clockTimer = new DispatcherTimer(DispatcherPriority.Normal, _dispatcher);
        _clockTimer.Tick += (_, _) => OnClockTick();
        OnClockTick();
    }

    /// 첫 실행 때 한 번 로그인 시 자동 실행을 켠다(이후엔 메뉴/설정의 값을 따른다).
    private void FirstRunSetup()
    {
        if (_file.LaunchAtLoginInitialized)
        {
            LoginItem.RefreshPathIfEnabled();
            return;
        }
        // 등록에 실패하면(예: dotnet 으로 개발 실행 중) 표시하지 않고 다음 실행 때 다시 시도한다.
        if (!LoginItem.Set(true)) return;
        _file = _file with { LaunchAtLoginInitialized = true };
        SaveFile();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try
        {
            _clockTimer?.Stop();
            _animTimer?.Stop();
            UnhookSystemEvents();
            if (!IsDemo) { CaptureWidgetPosition(); SaveFile(); SaveDays(); }
            _settingsWindow?.Close();
            _widget?.CloseWidget();
            _tray?.Dispose();
        }
        catch (Exception ex) { Log.Write($"종료 처리 실패: {ex.Message}"); }
    }

    // ── 매초 ──

    private void OnClockTick()
    {
        if (_disposed) return;
        var now = Now();
        try
        {
            if (_engine is not null)
            {
                _engine.Tick(now);
                foreach (var n in _engine.TakeDueNotifications(now)) _tray?.ShowBalloon(n.Title, n.Body);
            }
            Render(now);
        }
        catch (Exception ex) { Log.Write($"틱 처리 실패: {ex}"); }

        // 다음 초 경계 직후에 깨어난다 — 매초 표시가 건너뛰거나 겹치지 않게.
        if (_clockTimer is not null)
            _clockTimer.Interval = TimeSpan.FromMilliseconds(Math.Clamp(1000 - now.Millisecond + 15, 20, 1015));
        _clockTimer?.Start();
    }

    private void Render(DateTime now)
    {
        _snapshot = _engine?.Snapshot(now) ?? _demo!.Snapshot(_wall.Elapsed);
        _tray?.SetTooltip(WidgetText.TrayLine(_snapshot));
        if (_widgetVisible) _widget?.Update(_snapshot, CurrentSettings);
    }

    // ── 위젯 ──

    private void CreateWidget(PlacementKind kind)
    {
        var s = CurrentSettings.Widget;
        (int X, int Y)? keep = kind == PlacementKind.KeepTopLeft ? _widget?.TopLeftPx : null;
        PlacementRequest request;
        if (kind == PlacementKind.KeepTopLeft && keep is { } k)
            request = new PlacementRequest(PlacementKind.KeepTopLeft, k.X, k.Y);
        else if (s.Style == WidgetStyle.Bubble)
            request = new PlacementRequest(PlacementKind.Saved, _file.Widget.BubbleRight, _file.Widget.BubbleBottom);
        else
            request = new PlacementRequest(PlacementKind.Saved, _file.Widget.X, _file.Widget.Y);

        if (_widget is not null)
        {
            _widget.Dropped -= OnWidgetDropped;
            _widget.HideRequested -= OnHideRequested;
            _widget.CloseWidget();
        }

        _widget = s.Style == WidgetStyle.Bubble
            ? new BubbleWidgetWindow(MascotArt.For(s.Character), s.FontSize, request)
            : new TerminalWidgetWindow(MascotArt.For(s.Character), s.FontSize, request);
        _widget.Dropped += OnWidgetDropped;
        _widget.HideRequested += OnHideRequested;
        _widget.Update(_snapshot, CurrentSettings);
        _widget.Animate(_wall.Elapsed.TotalSeconds);
        if (_widgetVisible) _widget.ShowWidget();
    }

    private void OnHideRequested() => SetWidgetVisible(false);

    private void OnWidgetDropped()
    {
        CaptureWidgetPosition();
        SaveFile();
    }

    /// 지금 위젯의 위치를 현재 모양의 저장 칸에 옮겨 적는다(모양마다 따로).
    private void CaptureWidgetPosition()
    {
        if (_widget?.PositionToSave is not { } pos) return;
        _file = _file with
        {
            Widget = CurrentSettings.Widget.Style == WidgetStyle.Bubble
                ? _file.Widget with { BubbleRight = pos.X, BubbleBottom = pos.Y }
                : _file.Widget with { X = pos.X, Y = pos.Y },
        };
    }

    private void SetWidgetVisible(bool visible)
    {
        _widgetVisible = visible;
        _file = _file with { Widget = _file.Widget with { Visible = visible } };
        if (visible)
        {
            _widget?.Update(_snapshot, CurrentSettings);
            _widget?.ShowWidget();
            _animTimer?.Start();
        }
        else
        {
            CaptureWidgetPosition();
            _widget?.HideWidget();
            _animTimer?.Stop();
        }
        SaveFile();
    }

    // ── 트레이 메뉴 동작 ──

    private TrayActions BuildTrayActions() => new()
    {
        ToggleWidget = () => SetWidgetVisible(!_widgetVisible),
        OpenSettings = OpenSettings,
        RedetectToday = () => { _engine?.RedetectToday(Now()); Render(Now()); },
        SetLaunchAtLogin = SetLaunchAtLogin,
        Quit = () => System.Windows.Application.Current.Shutdown(),
    };

    private void OpenSettings()
    {
        if (IsDemo) return;
        if (_settingsWindow is not null) { _settingsWindow.Activate(); return; }
        _settingsWindow = new SettingsWindow(this);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    private void SetLaunchAtLogin(bool enabled)
    {
        if (IsDemo) return;
        LoginItem.Set(enabled);
    }

    /// 설정 창에서 유효한 값이 들어왔다 — 저장하고 즉시 반영한다.
    public void ApplySettings(AppSettings next)
    {
        if (IsDemo || _engine is null) return;
        var previous = _engine.Settings;
        if (next == previous) return;

        _file = _file with { Settings = next };
        SaveFile();
        var now = Now();
        _engine.UpdateSettings(next, now);

        if (previous.Widget.Character != next.Widget.Character) _tray?.SetCharacter(next.Widget.Character);
        if (previous.Widget != next.Widget)
        {
            // 모양이 바뀌면 그 모양의 저장 위치로, 글자 크기만 바뀌면 왼쪽 위 모서리를 유지한 채 다시 만든다.
            if (previous.Widget.Style != next.Widget.Style) CaptureWidgetPositionFor(previous.Widget.Style);
            CreateWidget(previous.Widget.Style != next.Widget.Style ? PlacementKind.Saved : PlacementKind.KeepTopLeft);
            if (_widgetVisible) _animTimer?.Start();
        }
        Render(now);
    }

    /// 모양을 바꾸기 직전, 떠나는 모양의 위치를 저장 칸에 적는다.
    private void CaptureWidgetPositionFor(WidgetStyle style)
    {
        if (_widget?.PositionToSave is not { } pos) return;
        _file = _file with
        {
            Widget = style == WidgetStyle.Bubble
                ? _file.Widget with { BubbleRight = pos.X, BubbleBottom = pos.Y }
                : _file.Widget with { X = pos.X, Y = pos.Y },
        };
        SaveFile();
    }

    // ── 저장 ──

    private void SaveFile()
    {
        if (!IsDemo) FileIo.WriteAtomic(AppPaths.Settings, _file.ToJson());
    }

    private void SaveDays()
    {
        if (!IsDemo) FileIo.WriteAtomic(AppPaths.ClockIn, _days.ToJson());
    }

    // ── 사후 복구 ──

    private async void OnRecoveryRequested(RecoveryRequest request)
    {
        try
        {
            var result = await RecoveryQuery.RunAsync(request);   // 이 UI 스레드로 돌아온다
            if (_disposed || _engine is null) return;
            var now = Now();
            _engine.FinishRecovery(request.Token, result, now);
            Render(now);
        }
        catch (Exception ex) { Log.Write($"사후 복구 처리 실패: {ex}"); }
    }

    // ── 잠금·깨어남 감지 ──

    private void HookSystemEvents()
    {
        if (IsDemo || _systemEventsHooked) return;
        SystemEvents.SessionSwitch += OnSessionSwitch;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        _systemEventsHooked = true;
    }

    private void UnhookSystemEvents()
    {
        if (!_systemEventsHooked) return;
        SystemEvents.SessionSwitch -= OnSessionSwitch;
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        _systemEventsHooked = false;
    }

    // SystemEvents 는 다른 스레드에서 올 수 있다 — UI 스레드로 넘긴다.
    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed || _engine is null) return;
            var now = Now();
            switch (e.Reason)
            {
                case SessionSwitchReason.SessionLock: _engine.NoteLocked(now); break;
                case SessionSwitchReason.SessionUnlock: _engine.NoteUnlocked(now); break;
                case SessionSwitchReason.SessionLogon: _engine.NoteActivation(now); break;
                default: return;
            }
            Render(now);
        });
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume) return;
        _dispatcher.BeginInvoke(() =>
        {
            if (_disposed || _engine is null) return;
            var now = Now();
            _engine.NoteActivation(now);
            Render(now);
        });
    }
}
