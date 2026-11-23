using System.Windows;
using Kaltoe.Core;

namespace Kaltoe.App;

public partial class KaltoeApp : Application
{
    private Mutex? _mutex;
    private EventWaitHandle? _showEvent;          // 두 번째 실행이 Set 하면 위젯을 꺼낸다
    private RegisteredWaitHandle? _showWait;
    private AppController? _controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var options = LaunchOptions.Parse(e.Args);
        if (options.Error is not null)
        {
            MessageBox.Show(options.Error, "칼퇴", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown(1);
            return;
        }

        // 중복 실행 방지: 이미 실행 중이면 기존 프로세스에게 "위젯을 보여 달라"고 알리고 조용히 종료. 데모는 실제 앱과 따로 돈다.
        var showEventName = options.IsDemo ? @"Local\Kaltoe.Demo.Show" : @"Local\Kaltoe.Show";
        _mutex = new Mutex(true, options.IsDemo ? @"Local\Kaltoe.Demo" : @"Local\Kaltoe.SingleInstance", out var created);
        if (!created)
        {
            _mutex.Dispose();
            _mutex = null;
            SignalRunningInstance(showEventName);
            Shutdown(0);
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            Log.Write($"처리되지 않은 예외: {args.Exception}");
            args.Handled = true;   // 트레이 앱은 한 번의 오류로 죽지 않는다
        };

        try
        {
            _controller = new AppController(options);
            _controller.Start();
            ListenForRelaunch(showEventName);
        }
        catch (Exception ex)
        {
            Log.Write($"시작 실패: {ex}");
            MessageBox.Show($"칼퇴를 시작하지 못했습니다.\n{ex.Message}", "칼퇴", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    /// 이름 있는 이벤트를 만들거나 열어 Set 한다. 첫 프로세스가 아직 이벤트를 안 만들었어도, 만들 때 이미 신호 상태로 이어받는다.
    private static void SignalRunningInstance(string name)
    {
        try
        {
            using var ev = new EventWaitHandle(false, EventResetMode.AutoReset, name);
            ev.Set();
        }
        catch (Exception ex) { Log.Write($"실행 중인 칼퇴에 알리지 못함: {ex.Message}"); }
    }

    /// 이벤트를 스레드 풀에서 기다리다가, 신호가 오면 UI 스레드(Dispatcher)로 넘겨 위젯을 꺼낸다.
    private void ListenForRelaunch(string name)
    {
        try
        {
            _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, name);
            _showWait = ThreadPool.RegisterWaitForSingleObject(_showEvent, (_, timedOut) =>
            {
                if (timedOut) return;
                try { Dispatcher.BeginInvoke(() => _controller?.RevealWidget()); }   // 창 조작은 반드시 UI 스레드에서
                catch (Exception ex) { Log.Write($"재실행 신호 처리 실패: {ex.Message}"); }
            }, null, Timeout.Infinite, executeOnlyOnce: false);
        }
        catch (Exception ex) { Log.Write($"재실행 신호 대기 실패: {ex.Message}"); }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _showWait?.Unregister(null);   // 대기 해제 후 핸들 닫기
        _showWait = null;
        _showEvent?.Dispose();
        _showEvent = null;
        _controller?.Dispose();   // 트레이 아이콘·이벤트 구독 해제
        _controller = null;
        if (_mutex is not null)
        {
            try { _mutex.ReleaseMutex(); } catch (ApplicationException) { /* 소유하지 않음 */ }
            _mutex.Dispose();
            _mutex = null;
        }
        base.OnExit(e);
    }
}
