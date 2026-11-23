// 사후 복구(docs/spec.md 2절 6번) — 시스템 로그 이벤트 중 출근 시각 고르기. 조회 자체는 앱 쪽.
namespace Kaltoe.Core;

public enum SystemEventKind
{
    /// 절전 해제 (Microsoft-Windows-Power-Troubleshooter, ID 1)
    Wake,
    /// 부팅 (Microsoft-Windows-Kernel-General, ID 12)
    Boot,
    /// 로그온 (Microsoft-Windows-Winlogon, ID 7001)
    Logon,
}

public sealed record SystemEvent(DateTime Time, SystemEventKind Kind);

public static class Recovery
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    public const string PowerProvider = "Microsoft-Windows-Power-Troubleshooter";
    public const string KernelProvider = "Microsoft-Windows-Kernel-General";
    public const string WinlogonProvider = "Microsoft-Windows-Winlogon";

    /// 제공자·이벤트 ID 가 우리가 찾는 종류인지.
    public static SystemEventKind? Classify(string? provider, int eventId) => (provider, eventId) switch
    {
        (PowerProvider, 1) => SystemEventKind.Wake,
        (KernelProvider, 12) => SystemEventKind.Boot,
        (WinlogonProvider, 7001) => SystemEventKind.Logon,
        _ => null,
    };

    /// earliestStart~now (양끝 포함) 사이 가장 이른 이벤트 시각. 없으면 earliestStart.
    public static DateTime Pick(IEnumerable<SystemEvent> events, DateTime earliestStart, DateTime now)
    {
        DateTime? best = null;
        foreach (var e in events)
        {
            if (e.Time < earliestStart || e.Time > now) continue;
            if (best is null || e.Time < best) best = e.Time;
        }
        return best ?? earliestStart;
    }

    /// 조회 실패·타임아웃 때의 대체값: max(earliestStart, 앱 실행 시각).
    public static DateTime Fallback(DateTime earliestStart, DateTime launchedAt)
        => launchedAt > earliestStart ? launchedAt : earliestStart;

    /// 이벤트 로그 XPath 쿼리. 시각은 UTC 로 받는다.
    public static string BuildXPath(DateTime fromUtc, DateTime toUtc)
    {
        static string Ts(DateTime t) => t.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture);
        return "*[System[(" +
               $"(Provider[@Name='{PowerProvider}'] and EventID=1) or " +
               $"(Provider[@Name='{KernelProvider}'] and EventID=12) or " +
               $"(Provider[@Name='{WinlogonProvider}'] and EventID=7001)" +
               $") and TimeCreated[@SystemTime>='{Ts(fromUtc)}' and @SystemTime<='{Ts(toUtc)}']]]";
    }
}
