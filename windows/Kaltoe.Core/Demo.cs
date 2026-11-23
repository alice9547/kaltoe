// 데모 모드(--demo <이름>) — 가짜 데이터를 흘려 화면을 바로 확인할 수 있게 한다. 설정·기록 파일은 건드리지 않는다.
namespace Kaltoe.Core;

public sealed record DemoScenario(string Name, AppSettings Settings, DateTime? ClockIn, DateTime StartNow)
{
    public static readonly IReadOnlyList<string> Names = new[] { "waiting", "beforelunch", "lunch", "working", "almost", "done" };

    /// 가상 시각 = StartNow + 실제 경과 시간.
    public WorkdaySnapshot Snapshot(TimeSpan elapsed) => SnapshotCalculator.Make(Settings, StartNow + elapsed, ClockIn);

    public static DemoScenario? Create(string? name, DateTime today, WidgetSettings? widget = null)
    {
        var d = today.Date;
        DateTime At(int h, int m, int s = 0) => d.AddHours(h).AddMinutes(m).AddSeconds(s);
        var baseSettings = AppSettings.Default with { Widget = widget ?? new WidgetSettings() };
        var flex = baseSettings;
        var fixedLunch = baseSettings with
        {
            Mode = WorkMode.Fixed,
            Lunch = new LunchSettings { Enabled = true },
        };
        return name?.ToLowerInvariant() switch
        {
            "waiting" => new("waiting", flex, null, At(8, 41)),
            "beforelunch" => new("beforelunch", fixedLunch, null, At(10, 47, 52)),
            "lunch" => new("lunch", fixedLunch, null, At(12, 41, 52)),
            "working" => new("working", flex, At(9, 16), At(14, 3, 52)),
            "almost" => new("almost", flex, At(9, 16), At(18, 6, 55)),
            "done" => new("done", flex, At(9, 16), At(18, 28)),
            _ => null,
        };
    }
}

/// 실행 인자 해석: `--demo <이름>` `--style terminal|bubble` `--font-size <px>`.
public sealed record LaunchOptions(string? DemoName, WidgetStyle? Style, int? FontSize, string? Error)
{
    public bool IsDemo => DemoName is not null;

    public static LaunchOptions Parse(IReadOnlyList<string> args)
    {
        string? demo = null; WidgetStyle? style = null; int? font = null;
        for (var i = 0; i < args.Count; i++)
        {
            var a = args[i];
            string? Next() => i + 1 < args.Count ? args[++i] : null;
            switch (a.ToLowerInvariant())
            {
                case "--demo":
                    demo = Next()?.ToLowerInvariant();
                    if (demo is null || !DemoScenario.Names.Contains(demo))
                        return new(null, null, null, $"--demo 에는 {string.Join("|", DemoScenario.Names)} 중 하나를 지정하세요");
                    break;
                case "--style":
                    var st = Next()?.ToLowerInvariant();
                    if (st == "terminal") style = WidgetStyle.Terminal;
                    else if (st == "bubble") style = WidgetStyle.Bubble;
                    else return new(null, null, null, "--style 에는 terminal|bubble 중 하나를 지정하세요");
                    break;
                case "--font-size":
                    if (!WidgetSizing.TryParseFontSize(Next(), out var px, out var err)) return new(null, null, null, err);
                    font = px;
                    break;
                default:
                    return new(null, null, null, $"알 수 없는 실행 인자: {a}");
            }
        }
        // --style / --font-size 는 데모 모드에서만 의미가 있다.
        if (demo is null && (style is not null || font is not null))
            return new(null, null, null, "--style, --font-size 는 --demo 와 함께만 쓸 수 있습니다");
        return new(demo, style, font, null);
    }
}
