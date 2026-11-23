using System.Windows;
using Kaltoe.Core;

namespace Kaltoe.App;

public partial class KaltoeApp : Application
{
    private Mutex? _mutex;
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

        // 중복 실행 방지: 이미 실행 중이면 조용히 종료. 데모는 실제 앱과 따로 돈다.
        _mutex = new Mutex(true, options.IsDemo ? @"Local\Kaltoe.Demo" : @"Local\Kaltoe.SingleInstance", out var created);
        if (!created)
        {
            _mutex.Dispose();
            _mutex = null;
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
        }
        catch (Exception ex)
        {
            Log.Write($"시작 실패: {ex}");
            MessageBox.Show($"칼퇴를 시작하지 못했습니다.\n{ex.Message}", "칼퇴", MessageBoxButton.OK, MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
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
