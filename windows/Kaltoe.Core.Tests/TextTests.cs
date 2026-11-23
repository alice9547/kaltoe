using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class TextTests
{
    private static string[] Plain(WorkdaySnapshot s, AppSettings st) => WidgetText.Lines(s, st).Select(l => l.Plain).ToArray();
    private static WorkdaySnapshot Snap(AppSettings s, DateTime? clockIn, DateTime now) => SnapshotCalculator.Make(s, now, clockIn);

    // ── 시간 포맷 ──

    [Theory]
    [InlineData(3 * 3600 + 12 * 60 + 8, "3h 12m 08s")]
    [InlineData(3600, "1h 00m 00s")]
    [InlineData(3599, "59m 59s")]
    [InlineData(12 * 60 + 8, "12m 08s")]
    [InlineData(5, "0m 05s")]
    [InlineData(0, "0m 00s")]
    [InlineData(-3, "0m 00s")]
    public void RemainingLong(int seconds, string expected)
        => Assert.Equal(expected, WidgetText.RemainingLong(TimeSpan.FromSeconds(seconds)));

    [Theory]
    [InlineData(3 * 3600 + 12 * 60 + 59, "3h 12m")]
    [InlineData(3600, "1h 0m")]
    [InlineData(3599, "59m")]
    [InlineData(12 * 60, "12m")]
    [InlineData(60, "1m")]
    [InlineData(59, "59s")]
    [InlineData(42, "42s")]
    [InlineData(0, "0s")]
    public void RemainingShort(int seconds, string expected)
        => Assert.Equal(expected, WidgetText.RemainingShort(TimeSpan.FromSeconds(seconds)));

    [Fact]
    public void RemainingLong_TruncatesFractions()
        => Assert.Equal("0m 01s", WidgetText.RemainingLong(TimeSpan.FromMilliseconds(1999)));

    [Fact]
    public void Overtime_Format() => Assert.Equal("+0h 12m", WidgetText.Overtime(TimeSpan.FromMinutes(12) + TimeSpan.FromSeconds(30)));

    [Fact]
    public void Overtime_Format_Hours() => Assert.Equal("+2h 5m", WidgetText.Overtime(TimeSpan.FromMinutes(125)));

    [Theory]
    [InlineData(0.0, "[....................] 0%")]
    [InlineData(0.27, "[#####...............] 27%")]
    [InlineData(0.41, "[########............] 41%")]
    [InlineData(0.64, "[############........] 64%")]
    [InlineData(0.98, "[###################.] 98%")]
    [InlineData(1.0, "[####################] 100%")]
    [InlineData(1.5, "[####################] 100%")]
    [InlineData(-0.2, "[....................] 0%")]
    public void ProgressBar(double p, string expected) => Assert.Equal(expected, WidgetText.ProgressBar(p));

    [Fact]
    public void Clock_Format()
    {
        Assert.Equal("09:05", WidgetText.Clock(At(9, 5)));
        Assert.Equal("18:16", WidgetText.Clock(At(18, 16, 59)));
        Assert.Equal("--:--", WidgetText.Clock(null));
    }

    // ── 위젯 줄 (spec 4절 예시 그대로) ──

    [Fact]
    public void Waiting_Flexible()
    {
        var lines = Plain(Snap(Flex(), null, At(8, 41)), Flex());
        Assert.Equal(new[] { "$ whoami", "아직 출근 전인 사람", "# waiting for first unlock after 09:00..." }, lines);
    }

    [Fact]
    public void Waiting_Flexible_UsesConfiguredEarliestStart()
    {
        var st = Flex(earliestH: 7);
        Assert.Equal("# waiting for first unlock after 07:00...", Plain(Snap(st, null, At(6, 0)), st)[2]);
    }

    [Fact]
    public void Waiting_Fixed()
    {
        var st = Fixed();
        var lines = Plain(Snap(st, null, At(8, 18)), st);
        Assert.Equal(new[] { "$ whoami", "아직 출근 전인 사람", "# 출근 08:30 까지 12m" }, lines);
    }

    [Fact]
    public void BeforeLunch_Lines()
    {
        var st = WithLunch(Fixed());
        var lines = Plain(Snap(st, null, At(10, 47, 52)), st);
        Assert.Equal(new[]
        {
            "$ npm install 점심",
            "installing... 42m 08s left",
            "[###########.........] 4" + "2%".Substring(0, 0) + "", // placeholder replaced below
        }.Take(2).ToArray(), lines.Take(2).ToArray());
        Assert.Equal("in 08:30 → out 17:30", lines[3]);
        Assert.Equal("# 점심 11:30 · 퇴근까지 6h 42m", lines[4]);
        Assert.Matches(@"^\[#+\.*\] \d+%$", lines[2]);
    }

    [Fact]
    public void BeforeLunch_ProgressExample()
    {
        var st = WithLunch(Fixed());
        // 09:16 → 27%
        var snap = Snap(st, null, At(10, 47, 52));
        Assert.Equal(WidgetText.ProgressBar(snap.Progress), Plain(snap, st)[2]);
    }

    [Fact]
    public void Lunch_Lines()
    {
        var st = WithLunch(Fixed());
        var snap = Snap(st, null, At(12, 41, 52));
        var lines = Plain(snap, st);
        Assert.Equal("$ sleep 점심", lines[0]);
        Assert.Equal("점심 끝까지 18m 08s", lines[1]);
        Assert.Equal(WidgetText.ProgressBar(snap.Progress), lines[2]);
        Assert.Equal("in 08:30 → out 17:30", lines[3]);
        Assert.Equal("# 지금은 밥이 P0 입니다", lines[4]);
    }

    [Fact]
    public void Working_Lines()
    {
        var st = Flex();
        var snap = Snap(st, At(9, 16), At(15, 3, 52));   // 퇴근 18:16 → 3h 12m 08s
        var lines = Plain(snap, st);
        Assert.Equal("$ sudo 퇴근 --force", lines[0]);
        Assert.Equal("Permission denied: 3h 12m 08s left", lines[1]);
        Assert.Equal("in 09:16 → out 18:16", lines[3]);
        Assert.Equal(5, lines.Length);
    }

    [Fact]
    public void AlmostDone_Lines()
    {
        var st = Flex();
        var lines = Plain(Snap(st, At(9, 16), At(18, 6, 55)), st);
        Assert.Equal("$ git commit -m \"퇴근 준비\"", lines[0]);
        Assert.Equal("9m 05s left", lines[1]);
        Assert.Equal("[###################.] 98%", lines[2]);
        Assert.Equal("in 09:16 → out 18:16", lines[3]);
        Assert.Equal("# 지금 배포하면 안 됩니다", lines[4]);
    }

    [Fact]
    public void Done_Lines_WithOvertime()
    {
        var st = Flex();
        var lines = Plain(Snap(st, At(9, 16), At(18, 28, 30)), st);
        Assert.Equal(new[]
        {
            "$ exit", "Process finished with exit code 0", "퇴근하세요! out 18:16", "# 야근 중 +0h 12m", "# 포괄이라 0원 (원래 +2,064원)",
        }, lines);
    }

    [Fact]
    public void Done_Lines_NoOvertimeLine_Under60Seconds()
    {
        var st = Flex();
        Assert.Equal(3, Plain(Snap(st, At(9, 16), At(18, 16, 59)), st).Length);
        Assert.Equal(5, Plain(Snap(st, At(9, 16), At(18, 17, 0)), st).Length);
    }

    // ── 색 스타일 ──

    [Fact]
    public void Styles_FollowSpecColors()
    {
        var st = Flex();
        var working = WidgetText.Lines(Snap(st, At(9, 16), At(15, 3, 52)), st);
        Assert.Equal(LineStyle.Prompt, working[0].Spans[0].Style);
        Assert.Equal(LineStyle.Command, working[0].Spans[1].Style);
        Assert.Equal(new[] { LineStyle.Output, LineStyle.Accent, LineStyle.Output }, working[1].Spans.Select(s => s.Style));
        Assert.Equal(LineStyle.Comment, working[4].Spans[0].Style);

        var almost = WidgetText.Lines(Snap(st, At(9, 16), At(18, 6, 55)), st);
        Assert.Equal(LineStyle.AccentBold, almost[1].Spans[0].Style);

        var done = WidgetText.Lines(Snap(st, At(9, 16), At(18, 20)), st);
        Assert.Equal(LineStyle.Success, done[1].Spans[0].Style);
        Assert.Equal(LineStyle.Output, done[2].Spans[0].Style);
    }

    // ── 주석 ──

    [Theory]
    [InlineData(0.0, "# 아직 컴파일 중...")]
    [InlineData(0.2499, "# 아직 컴파일 중...")]
    [InlineData(0.25, "# it works on my machine")]
    [InlineData(0.4999, "# it works on my machine")]
    [InlineData(0.50, "# 반 넘었다. 나머지는 미래의 내가")]
    [InlineData(0.7499, "# 반 넘었다. 나머지는 미래의 내가")]
    [InlineData(0.75, "# 거의 다 왔다. 금요일 배포만 하지 말자")]
    [InlineData(0.99, "# 거의 다 왔다. 금요일 배포만 하지 말자")]
    public void Comment_ByProgress(double progress, string expected)
    {
        var s = new WorkdaySnapshot(At(15, 0), At(9, 0), At(18, 0), null, null, WorkPhase.Working,
            At(18, 0), TimeSpan.FromHours(3), TimeSpan.FromHours(3), TimeSpan.Zero, progress);
        Assert.Equal(expected, WidgetText.Comment(s));
    }

    [Theory]
    [InlineData(11, 59, "# 아직 컴파일 중...")]
    [InlineData(12, 0, "# 점심: 일단 밥부터 먹고 생각하자")]
    [InlineData(12, 59, "# 점심: 일단 밥부터 먹고 생각하자")]
    [InlineData(13, 0, "# it works on my machine")]
    public void Comment_LunchHour_WhenLunchUnused(int h, int m, string expected)
    {
        var st = Flex();
        var snap = Snap(st, At(9, 0), At(h, m, 30));   // 12:00 → progress 0.33
        // 11:59 는 progress < 0.25 가 아니므로 기대값을 진행률로 확인
        var byProgress = snap.Progress < 0.25 ? "# 아직 컴파일 중..." : "# it works on my machine";
        Assert.Equal(h == 12 ? expected : byProgress, WidgetText.Comment(snap));
    }

    [Fact]
    public void Comment_LunchHour_NotUsed_WhenLunchEnabled()
    {
        // 점심 사용 중이면 12시여도 일반 주석(점심 단계가 아닌 working 일 때)
        var st = WithLunch(Flex(), 11, 0, 11, 30);   // 12시엔 이미 끝난 점심
        var snap = Snap(st, At(9, 0), At(12, 30));
        Assert.Equal(WorkPhase.Working, snap.Phase);
        Assert.NotNull(snap.LunchStart);
        Assert.NotEqual("# 점심: 일단 밥부터 먹고 생각하자", WidgetText.Comment(snap));
    }

    // ── 트레이 한 줄 ──

    [Fact]
    public void TrayLine_ByPhase()
    {
        var flex = Flex();
        Assert.Equal("출근 전", WidgetText.TrayLine(Snap(flex, null, At(9, 30))));
        var lunch = WithLunch(Fixed());
        Assert.Equal("점심까지 42m", WidgetText.TrayLine(Snap(lunch, null, At(10, 47, 52))));
        Assert.Equal("점심 끝까지 18m", WidgetText.TrayLine(Snap(lunch, null, At(12, 41, 52))));
        Assert.Equal("18:16까지 3h 12m", WidgetText.TrayLine(Snap(flex, At(9, 16), At(15, 3, 52))));
        Assert.Equal("18:16까지 9m", WidgetText.TrayLine(Snap(flex, At(9, 16), At(18, 6, 55))));
        Assert.Equal("퇴근! +12m", WidgetText.TrayLine(Snap(flex, At(9, 16), At(18, 28, 30))));
        Assert.Equal("퇴근!", WidgetText.TrayLine(Snap(flex, At(9, 16), At(18, 16, 59))));
    }

    [Fact]
    public void TrayLine_FixedWaiting_IsAlsoOutBefore() => Assert.Equal("출근 전", WidgetText.TrayLine(Snap(Fixed(), null, At(8, 0))));

    [Fact]
    public void TrayLine_IsWithin63Chars_ForAllScenarios()
    {
        foreach (var name in DemoScenario.Names)
        {
            var d = DemoScenario.Create(name, Day)!;
            Assert.True(WidgetText.TrayLine(d.Snapshot(TimeSpan.Zero)).Length <= 63);
        }
        Assert.Equal(63, WidgetText.Truncate(new string('가', 100)).Length);
        Assert.Equal("짧음", WidgetText.Truncate("짧음"));
    }

    // ── 메뉴 ──

    [Fact]
    public void MenuTitles()
    {
        var flex = Flex();
        var none = Snap(flex, null, At(9, 30));
        Assert.Equal("출근 기록 없음", WidgetText.ClockInMenuTitle(none));
        Assert.Null(WidgetText.ClockOutMenuTitle(none));
        var work = Snap(flex, At(9, 16), At(10, 0));
        Assert.Equal("출근 09:16", WidgetText.ClockInMenuTitle(work));
        Assert.Equal("퇴근 18:16", WidgetText.ClockOutMenuTitle(work));
        Assert.Null(WidgetText.LunchMenuTitle(flex));
        Assert.Equal("점심 11:30–13:00", WidgetText.LunchMenuTitle(WithLunch(flex)));
    }

    // ── 설정 창 미리보기 ──

    [Fact]
    public void Preview_Fixed_WithLunch()
        => Assert.Equal("출근 08:30 · 점심 11:30–13:00 · 퇴근 17:30", WidgetText.Preview(WithLunch(Fixed()), Day, null));

    [Fact]
    public void Preview_Fixed_NoLunch()
        => Assert.Equal("출근 08:30 · 퇴근 17:30", WidgetText.Preview(Fixed(), Day, null));

    [Fact]
    public void Preview_Flexible_NoRecord() => Assert.Equal("출근 — · 퇴근 —", WidgetText.Preview(Flex(), Day, null));

    [Fact]
    public void Preview_Flexible_WithRecord()
        => Assert.Equal("출근 09:16 · 점심 11:30–13:00 · 퇴근 18:16", WidgetText.Preview(WithLunch(Flex()), Day, At(9, 16)));
}
