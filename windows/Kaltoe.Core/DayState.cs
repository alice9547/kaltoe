// clockin.json — 날짜별 출근 기록과 이미 띄운 알림. 순수 데이터 + 직렬화.
using System.Globalization;
using System.Text.Json;

namespace Kaltoe.Core;

public static class DayKey
{
    /// "yyyy-MM-dd"
    public static string Of(DateTime t) => t.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    public static bool IsValid(string key)
        => DateTime.TryParseExact(key, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);
}

public sealed class DayState
{
    public const int RetentionDays = 14;

    public Dictionary<string, DateTime> ClockIns { get; set; } = new();
    public Dictionary<string, List<string>> Notified { get; set; } = new();

    public DateTime? GetClockIn(string day) => ClockIns.TryGetValue(day, out var t) ? t : null;

    /// 하루 하나: 이미 있으면 false. 시각의 Kind 는 제거(저장 형식 고정).
    public bool TrySetClockIn(string day, DateTime t)
    {
        if (ClockIns.ContainsKey(day)) return false;
        ClockIns[day] = DateTime.SpecifyKind(t, DateTimeKind.Unspecified);
        return true;
    }

    public bool RemoveClockIn(string day) => ClockIns.Remove(day);

    public bool IsNotified(string day, NotificationKind kind)
        => Notified.TryGetValue(day, out var l) && l.Contains(kind.ToString());

    public void MarkNotified(string day, NotificationKind kind)
    {
        if (!Notified.TryGetValue(day, out var l)) Notified[day] = l = new List<string>();
        if (!l.Contains(kind.ToString())) l.Add(kind.ToString());
    }

    /// 보관 기간이 지난(그리고 형식이 잘못된) 날짜 키를 지운다. 바뀐 게 있으면 true.
    /// 오늘 기준 14일 전 날짜까지는 남기고 그보다 오래된 것을 지운다.
    public bool Purge(DateTime now, int retentionDays = RetentionDays)
    {
        var cutoff = DayKey.Of(now.Date.AddDays(-retentionDays));
        var changed = false;
        foreach (var key in ClockIns.Keys.Where(k => ShouldPurge(k, cutoff)).ToList())
        { ClockIns.Remove(key); changed = true; }
        foreach (var key in Notified.Keys.Where(k => ShouldPurge(k, cutoff)).ToList())
        { Notified.Remove(key); changed = true; }
        return changed;
    }

    private static bool ShouldPurge(string key, string cutoff)
        => !DayKey.IsValid(key) || string.CompareOrdinal(key, cutoff) < 0;

    public static DayState Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new DayState();
        try
        {
            var s = JsonSerializer.Deserialize<DayState>(json, KaltoeJson.Options);
            if (s is null) return new DayState();
            s.ClockIns ??= new();
            s.Notified ??= new();
            foreach (var k in s.ClockIns.Keys.ToList())
                s.ClockIns[k] = DateTime.SpecifyKind(s.ClockIns[k], DateTimeKind.Unspecified);
            return s;
        }
        catch (Exception)
        {
            return new DayState();
        }
    }

    public string ToJson() => JsonSerializer.Serialize(this, KaltoeJson.Options);
}
