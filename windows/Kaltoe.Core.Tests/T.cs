using Kaltoe.Core;

namespace Kaltoe.Core.Tests;

internal static class T
{
    // 테스트의 "오늘": 2026-11-23 (월). 시각은 로컬 벽시계 값이라 시간대와 무관하다.
    public static readonly DateTime Day = new(2026, 11, 23);
    public static DateTime At(int h, int m, int s = 0) => Day.AddHours(h).AddMinutes(m).AddSeconds(s);
    public static TimeOnly Tm(int h, int m) => new(h, m);

    public static AppSettings Flex(int earliestH = 9, int minutes = 540) => AppSettings.Default with
    {
        Flexible = new FlexibleSettings { EarliestStart = Tm(earliestH, 0), WorkMinutes = minutes },
    };

    public static AppSettings Fixed(int sh = 8, int sm = 30, int eh = 17, int em = 30) => AppSettings.Default with
    {
        Mode = WorkMode.Fixed,
        Fixed = new FixedSettings { Start = Tm(sh, sm), End = Tm(eh, em) },
    };

    public static AppSettings WithLunch(AppSettings s, int sh = 11, int sm = 30, int eh = 13, int em = 0) => s with
    {
        Lunch = new LunchSettings { Enabled = true, Start = Tm(sh, sm), End = Tm(eh, em) },
    };
}
