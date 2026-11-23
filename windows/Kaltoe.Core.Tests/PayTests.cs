using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class PayTests
{
    // 기본 = 시간당 10320원(비어 있음). 포괄 켬/끔 두 가지.
    private static readonly PaySettings Normal = new() { Comprehensive = false };
    private static readonly PaySettings Comprehensive = new() { Comprehensive = true };

    // 퇴근 18:16 (출근 09:16)
    private static WorkdaySnapshot Done(int overtimeSeconds)
        => SnapshotCalculator.Make(Flex(), At(18, 16).AddSeconds(overtimeSeconds), At(9, 16));

    private static AppSettings With(PaySettings pay) => Flex() with { Pay = pay };

    // ── 기본값 ──

    [Fact]
    public void Defaults_ComprehensiveOn_RateEmpty_PerHour()
    {
        var p = AppSettings.Default.Pay;
        Assert.True(p.Comprehensive);
        Assert.Null(p.RateAmount);
        Assert.Equal(PayUnit.Hour, p.RateUnit);
    }

    // ── 금액 계산 ──

    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 172)]       // 10320 / 60
    [InlineData(12, 2064)]
    [InlineData(60, 10320)]
    [InlineData(61, 10492)]    // 61 × 10320 / 60 = 10492
    [InlineData(-5, 0)]
    public void Allowance_EmptyRate_UsesMinimumHourly(int minutes, long won)
        => Assert.Equal(won, PayCalc.Allowance(minutes, Normal));

    [Fact]
    public void Allowance_NoPremiumRate_IsPlainRate()
        => Assert.Equal(10320, PayCalc.Allowance(60, Normal));   // 1.5배 가산 없음

    [Theory]
    [InlineData(300, 12, 3600)]     // 분당 300원 × 12분
    [InlineData(300, 1, 300)]
    [InlineData(1, 12, 12)]
    public void Allowance_PerMinute(int rate, int minutes, long won)
        => Assert.Equal(won, PayCalc.Allowance(minutes, new PaySettings { RateAmount = rate, RateUnit = PayUnit.Minute }));

    [Theory]
    [InlineData(20000, 12, 4000)]   // 시간당 20000원 × 12분
    [InlineData(20000, 60, 20000)]
    [InlineData(10001, 1, 166)]     // 166.68 → 내림
    [InlineData(1, 59, 0)]          // 59/60 → 0
    public void Allowance_PerHour(int rate, int minutes, long won)
        => Assert.Equal(won, PayCalc.Allowance(minutes, new PaySettings { RateAmount = rate, RateUnit = PayUnit.Hour }));

    [Fact]
    public void Allowance_EmptyRate_IgnoresUnit()
        => Assert.Equal(2064, PayCalc.Allowance(12, new PaySettings { RateAmount = null, RateUnit = PayUnit.Minute }));

    [Fact]
    public void Allowance_NoOverflow_AtMaxima()
    {
        Assert.Equal(1440L * 10_000_000, PayCalc.Allowance(1440, new PaySettings { RateAmount = 10_000_000, RateUnit = PayUnit.Minute }));
        Assert.Equal(1440L * 10_000_000 / 60, PayCalc.Allowance(1440, new PaySettings { RateAmount = 10_000_000, RateUnit = PayUnit.Hour }));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(59, 0)]
    [InlineData(60, 1)]
    [InlineData(119, 1)]
    [InlineData(12 * 60 + 59, 12)]
    [InlineData(-10, 0)]
    public void OvertimeMinutes_Floors(int seconds, int minutes)
        => Assert.Equal(minutes, PayCalc.OvertimeMinutes(TimeSpan.FromSeconds(seconds)));

    // ── 표기 ──

    [Theory]
    [InlineData(0, "0원")]
    [InlineData(172, "172원")]
    [InlineData(2064, "2,064원")]
    [InlineData(12384, "12,384원")]
    [InlineData(1000000, "1,000,000원")]
    public void FormatWon_UsesThousandsSeparator(long won, string expected) => Assert.Equal(expected, PayCalc.FormatWon(won));

    // ── 단가 검증 경계 ──

    [Theory]
    [InlineData(null, true)]        // 비워 둘 수 있다
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(10320, true)]
    [InlineData(10000000, true)]
    [InlineData(10000001, false)]
    [InlineData(-1, false)]
    public void Rate_Range_InSettingsValidator(int? rate, bool ok)
        => Assert.Equal(ok, SettingsValidator.Validate(With(new PaySettings { RateAmount = rate })) is null);

    [Theory]
    [InlineData("300", true, 300)]
    [InlineData(" 1 ", true, 1)]
    [InlineData("10000000", true, 10000000)]
    [InlineData("", true, null)]
    [InlineData("   ", true, null)]
    [InlineData(null, true, null)]
    [InlineData("0", false, null)]
    [InlineData("10000001", false, null)]
    [InlineData("abc", false, null)]
    [InlineData("10,320", false, null)]
    [InlineData("1.5", false, null)]
    [InlineData("-3", false, null)]
    [InlineData("99999999999", false, null)]
    public void Rate_ParseInput(string? text, bool ok, int? expected)
    {
        Assert.Equal(ok, PayCalc.TryParseRate(text, out var amount, out var error));
        if (ok) { Assert.Equal(expected, amount); Assert.Null(error); }
        else { Assert.Null(amount); Assert.False(string.IsNullOrEmpty(error)); }
    }

    [Fact]
    public void Json_RoundTrip_AndKeys()
    {
        var pay = new PaySettings { Comprehensive = false, RateAmount = 300, RateUnit = PayUnit.Minute };
        var json = new AppFile { Settings = With(pay) }.ToJson();
        Assert.Contains("\"comprehensive\": false", json);
        Assert.Contains("\"rateAmount\": 300", json);
        Assert.Contains("\"rateUnit\": \"minute\"", json);
        Assert.Equal(pay, AppFile.Parse(json).Settings.Pay);
    }

    [Fact]
    public void Json_EmptyRate_RoundTrips()
    {
        var json = new AppFile().ToJson();
        Assert.Contains("\"comprehensive\": true", json);
        Assert.Contains("\"rateAmount\": null", json);
        Assert.Contains("\"rateUnit\": \"hour\"", json);
        Assert.Equal(new PaySettings(), AppFile.Parse(json).Settings.Pay);
    }

    [Fact]
    public void OldSettingsFile_WithoutPay_GetsDefaults()
        => Assert.Equal(new PaySettings(), AppFile.Parse("{\"settings\":{\"mode\":\"fixed\"}}").Settings.Pay);

    [Fact]
    public void OldFileWithHourlyWage_IsIgnored()
        => Assert.Equal(new PaySettings(), AppFile.Parse("{\"settings\":{\"pay\":{\"hourlyWage\":12000}}}").Settings.Pay);

    [Fact]
    public void RateOutOfRangeInFile_ResetsSettings()
        => Assert.Null(AppFile.Parse("{\"settings\":{\"pay\":{\"rateAmount\":0}}}").Settings.Pay.RateAmount);

    // ── 터미널 마지막 줄 ──

    [Fact]
    public void Terminal_NotComprehensive_12min()
    {
        var lines = WidgetText.Lines(Done(12 * 60 + 5), With(Normal));
        Assert.Equal(5, lines.Count);
        Assert.Equal("# 야근 중 +0h 12m", lines[3].Plain);
        Assert.Equal("# 연장수당 +2,064원", lines[^1].Plain);
        Assert.Equal(new[] { LineStyle.Comment, LineStyle.Accent }, lines[^1].Spans.Select(x => x.Style));
        Assert.Equal("+2,064원", lines[^1].Spans[1].Text);
    }

    [Fact]
    public void Terminal_Comprehensive_12min()
    {
        var lines = WidgetText.Lines(Done(12 * 60 + 5), With(Comprehensive));
        Assert.Equal(5, lines.Count);
        Assert.Equal("# 야근 중 +0h 12m", lines[3].Plain);
        Assert.Equal("# 포괄이라 0원 (원래 +2,064원)", lines[^1].Plain);
        Assert.Equal(new[] { LineStyle.Comment, LineStyle.Accent, LineStyle.Comment }, lines[^1].Spans.Select(x => x.Style));
        Assert.Equal("0원", lines[^1].Spans[1].Text);
    }

    [Theory]
    [InlineData(1, "+0h 1m", "+172원")]
    [InlineData(60, "+1h 0m", "+10,320원")]
    public void Terminal_OtherAmounts(int minutes, string overtime, string amount)
    {
        var lines = WidgetText.Lines(Done(minutes * 60), With(Normal));
        Assert.Equal($"# 야근 중 {overtime}", lines[3].Plain);
        Assert.Equal($"# 연장수당 {amount}", lines[4].Plain);
    }

    [Fact]
    public void Terminal_PerMinuteRate()
    {
        var pay = new PaySettings { Comprehensive = false, RateAmount = 300, RateUnit = PayUnit.Minute };
        Assert.Equal("# 연장수당 +3,600원", WidgetText.Lines(Done(12 * 60), With(pay))[^1].Plain);
    }

    [Fact]
    public void Terminal_PerHourRate()
    {
        var pay = new PaySettings { Comprehensive = false, RateAmount = 20000, RateUnit = PayUnit.Hour };
        Assert.Equal("# 연장수당 +4,000원", WidgetText.Lines(Done(12 * 60), With(pay))[^1].Plain);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Terminal_NoOvertime_NoPayText(bool comprehensive)
    {
        var s = With(new PaySettings { Comprehensive = comprehensive });
        foreach (var sec in new[] { 0, 30, 59 })
        {
            var lines = WidgetText.Lines(Done(sec), s);
            Assert.Equal(3, lines.Count);
            Assert.DoesNotContain(lines, l => l.Plain.Contains("원") || l.Plain.Contains("야근"));
        }
    }

    // ── 말풍선 ──

    [Fact]
    public void Bubble_NotComprehensive() => Assert.Equal("야근 12분 · +2,064원", BubbleText.Line(Done(12 * 60 + 30), Normal));

    [Fact]
    public void Bubble_Comprehensive() => Assert.Equal("야근 12분 · 0원 (포괄)", BubbleText.Line(Done(12 * 60 + 30), Comprehensive));

    [Theory]
    [InlineData(1, "야근 1분 · +172원")]
    [InlineData(60, "야근 60분 · +10,320원")]
    public void Bubble_Amounts(int minutes, string expected) => Assert.Equal(expected, BubbleText.Line(Done(minutes * 60), Normal));

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Bubble_NoOvertime_NoPayText(bool comprehensive)
    {
        var pay = new PaySettings { Comprehensive = comprehensive };
        Assert.Equal("퇴근하세요!", BubbleText.Line(Done(0), pay));
        Assert.Equal("퇴근하세요!", BubbleText.Line(Done(59), pay));
        Assert.Equal("야근 1분 · " + (comprehensive ? "0원 (포괄)" : "+172원"), BubbleText.Line(Done(60), pay));
    }

    [Fact]
    public void Bubble_NullPay_UsesDefaults_WhichIsComprehensive()
        => Assert.Equal("야근 12분 · 0원 (포괄)", BubbleText.Line(Done(12 * 60)));

    // ── 메뉴 ──

    [Fact]
    public void Menu_NotComprehensive() => Assert.Equal("연장수당 +2,064원", WidgetText.AllowanceMenuTitle(Done(12 * 60), Normal));

    [Fact]
    public void Menu_Comprehensive() => Assert.Equal("연장수당 0원 (포괄)", WidgetText.AllowanceMenuTitle(Done(12 * 60), Comprehensive));

    [Fact]
    public void Menu_NoOvertime_OrNotDone_Null()
    {
        Assert.Null(WidgetText.AllowanceMenuTitle(Done(0), Normal));
        Assert.Null(WidgetText.AllowanceMenuTitle(Done(59), Comprehensive));
        var working = SnapshotCalculator.Make(Flex(), At(12, 0), At(9, 16));
        Assert.Null(WidgetText.AllowanceMenuTitle(working, Normal));
        Assert.Null(WidgetText.AllowanceMenuTitle(WorkdaySnapshot.Waiting(At(8, 0)), Normal));
    }

    [Fact]
    public void TrayLine_Unchanged_ByPay()
    {
        Assert.Equal("퇴근! +12m", WidgetText.TrayLine(Done(12 * 60 + 5)));
        Assert.Equal("퇴근!", WidgetText.TrayLine(Done(30)));
    }

    // ── 마스코트 기분 ──

    [Fact]
    public void Mood_Overtime_NotComprehensive_IsAngry()
        => Assert.Equal(MascotMood.Angry, MascotPlayback.MoodOf(Done(60), Normal));

    [Fact]
    public void Mood_Overtime_Comprehensive_IsCry()
        => Assert.Equal(MascotMood.Cry, MascotPlayback.MoodOf(Done(12 * 60), Comprehensive));

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Mood_Done_NoOvertime_StillDance(bool comprehensive)
    {
        var pay = new PaySettings { Comprehensive = comprehensive };
        Assert.Equal(MascotMood.Dance, MascotPlayback.MoodOf(Done(0), pay));
        Assert.Equal(MascotMood.Dance, MascotPlayback.MoodOf(Done(59), pay));
    }

    [Fact]
    public void Mood_OvertimeMinuteBoundary_IsAt60Seconds()
    {
        Assert.Equal(MascotMood.Dance, MascotPlayback.MoodOf(Done(59), Normal));
        Assert.Equal(MascotMood.Angry, MascotPlayback.MoodOf(Done(60), Normal));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Mood_OtherPhases_UnaffectedByPay(bool comprehensive)
    {
        var pay = new PaySettings { Comprehensive = comprehensive };
        Assert.Equal(MascotMood.Sleep, MascotPlayback.MoodOf(WorkdaySnapshot.Waiting(At(8, 0)), pay));
        Assert.Equal(MascotMood.Idle, MascotPlayback.MoodOf(SnapshotCalculator.Make(Flex(), At(12, 0), At(9, 16)), pay));
        Assert.Equal(MascotMood.Sparkle, MascotPlayback.MoodOf(SnapshotCalculator.Make(Flex(), At(18, 10), At(9, 16)), pay));
    }

    // ── 데모 ──

    [Fact]
    public void Demo_Done_Is12MinOvertime_BothPaySettings()
    {
        var off = DemoScenario.Create("done", Day, null, new PaySettings { Comprehensive = false })!;
        var on = DemoScenario.Create("done", Day, null, new PaySettings { Comprehensive = true })!;
        Assert.Equal(12, PayCalc.OvertimeMinutes(off.Snapshot(TimeSpan.Zero).Overtime));
        Assert.Equal("야근 12분 · +2,064원", BubbleText.Line(off.Snapshot(TimeSpan.Zero), off.Settings.Pay));
        Assert.Equal("야근 12분 · 0원 (포괄)", BubbleText.Line(on.Snapshot(TimeSpan.Zero), on.Settings.Pay));
        Assert.Equal(MascotMood.Angry, MascotPlayback.MoodOf(off.Snapshot(TimeSpan.Zero), off.Settings.Pay));
        Assert.Equal(MascotMood.Cry, MascotPlayback.MoodOf(on.Snapshot(TimeSpan.Zero), on.Settings.Pay));
    }

    [Fact]
    public void LaunchOptions_Comprehensive_OnOff()
    {
        Assert.True(LaunchOptions.Parse(new[] { "--demo", "done", "--comprehensive", "on" }).Comprehensive);
        Assert.False(LaunchOptions.Parse(new[] { "--demo", "done", "--comprehensive", "off" }).Comprehensive);
        Assert.Null(LaunchOptions.Parse(new[] { "--demo", "done" }).Comprehensive);
        Assert.NotNull(LaunchOptions.Parse(new[] { "--demo", "done", "--comprehensive" }).Error);
        Assert.NotNull(LaunchOptions.Parse(new[] { "--demo", "done", "--comprehensive", "maybe" }).Error);
        Assert.NotNull(LaunchOptions.Parse(new[] { "--comprehensive", "on" }).Error);
    }
}

public class TerminalOvertimeLayoutTests
{
    private static WorkdaySnapshot Done(int sec) => SnapshotCalculator.Make(T.Flex(), T.At(18, 16).AddSeconds(sec), T.At(9, 16));

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Done_WithOvertime_IsFiveLines_SameAsWorking(bool comprehensive)
    {
        var s = T.Flex() with { Pay = new PaySettings { Comprehensive = comprehensive } };
        Assert.Equal(5, WidgetText.Lines(Done(12 * 60), s).Count);
        var working = SnapshotCalculator.Make(s, T.At(15, 0), T.At(9, 16));
        Assert.Equal(5, WidgetText.Lines(working, s).Count);   // 창 높이는 그대로
    }

    [Fact]
    public void Done_AllLines_FitWidth_ByCharCount()
    {
        // 가장 긴 줄이 working 단계의 가장 긴 줄(# 거의 다 왔다...) 이하여야 한다(글자 수·한글 폭 가중 기준).
        static double W(string t) => t.Sum(c => c > 0x2E80 ? 12.0 : 7.0);
        var longestExisting = W("# 거의 다 왔다. 금요일 배포만 하지 말자");
        foreach (var comprehensive in new[] { false, true })
        {
            var s = T.Flex() with { Pay = new PaySettings { Comprehensive = comprehensive } };
            foreach (var line in WidgetText.Lines(Done(12 * 60), s))
                Assert.True(W(line.Plain) <= longestExisting, $"{line.Plain} = {W(line.Plain)}");
        }
    }

    [Fact]
    public void AmountColors_Accent()
    {
        var off = WidgetText.Lines(Done(12 * 60), T.Flex() with { Pay = new PaySettings { Comprehensive = false } })[^1];
        Assert.Equal(new[] { LineStyle.Comment, LineStyle.Accent }, off.Spans.Select(x => x.Style));
        var on = WidgetText.Lines(Done(12 * 60), T.Flex() with { Pay = new PaySettings { Comprehensive = true } })[^1];
        Assert.Equal(new[] { LineStyle.Comment, LineStyle.Accent, LineStyle.Comment }, on.Spans.Select(x => x.Style));
        Assert.Equal("0원", on.Spans[1].Text);
    }
}
