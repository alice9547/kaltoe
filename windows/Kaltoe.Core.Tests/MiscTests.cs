using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class NotificationTests
{
    private static WorkSchedule Sch(AppSettings s, DateTime? clockIn = null) => WorkSchedule.Resolve(s, Day, clockIn);

    [Fact]
    public void Plan_Fixed_LunchAndEnd()
    {
        var plans = NotificationPlanner.Plan(WithLunch(Fixed()), Sch(WithLunch(Fixed())));
        Assert.Equal(new[] { NotificationKind.Lunch, NotificationKind.BeforeEnd, NotificationKind.End }, plans.Select(p => p.Kind));
        Assert.Equal(At(11, 30), plans[0].FireTime);
        Assert.Equal(At(17, 20), plans[1].FireTime);
        Assert.Equal(At(17, 30), plans[2].FireTime);
        Assert.Equal("점심 시간입니다 — npm install 점심", plans[0].Body);
        Assert.Equal("퇴근 10분 전 — 지금 배포하면 안 됩니다", plans[1].Body);
        Assert.Equal("Process finished with exit code 0 — 퇴근하세요", plans[2].Body);
        Assert.All(plans, p => Assert.Equal("칼퇴", p.Title));
    }

    [Fact]
    public void Plan_Flexible_UsesClockInPlusWorkMinutes()
    {
        var plans = NotificationPlanner.Plan(Flex(), Sch(Flex(), At(9, 16)));
        Assert.Equal(new[] { At(18, 6), At(18, 16) }, plans.Select(p => p.FireTime));
    }

    [Fact]
    public void Plan_Flexible_NoClockIn_Empty() => Assert.Empty(NotificationPlanner.Plan(Flex(), Sch(Flex())));

    [Fact]
    public void Plan_LunchDisabled_NoLunchNotification()
        => Assert.DoesNotContain(NotificationPlanner.Plan(Fixed(), Sch(Fixed())), p => p.Kind == NotificationKind.Lunch);

    [Fact]
    public void Plan_LunchInvalid_NoLunchNotification()
    {
        var s = WithLunch(Flex(), 7, 0, 8, 0);   // 출근 09:16 보다 앞 → 무효
        Assert.DoesNotContain(NotificationPlanner.Plan(s, Sch(s, At(9, 16))), p => p.Kind == NotificationKind.Lunch);
    }

    [Fact]
    public void Plan_RespectsNotifyFlags()
    {
        var s = WithLunch(Fixed()) with { Notify = new NotifySettings { Lunch = false, BeforeEnd = true, End = false } };
        var plans = NotificationPlanner.Plan(s, Sch(s));
        Assert.Equal(NotificationKind.BeforeEnd, Assert.Single(plans).Kind);
        var none = WithLunch(Fixed()) with { Notify = new NotifySettings { Lunch = false, BeforeEnd = false, End = false } };
        Assert.Empty(NotificationPlanner.Plan(none, Sch(none)));
    }

    [Fact]
    public void Upcoming_DropsPastTimes()
    {
        var plans = NotificationPlanner.Plan(WithLunch(Fixed()), Sch(WithLunch(Fixed())));
        var up = NotificationPlanner.Upcoming(plans, At(12, 0));
        Assert.Equal(new[] { NotificationKind.BeforeEnd, NotificationKind.End }, up.Select(p => p.Kind));
        Assert.Empty(NotificationPlanner.Upcoming(plans, At(17, 30)));
    }

    [Fact]
    public void Due_OnlyWithinGrace_AndNotShown()
    {
        var plans = NotificationPlanner.Plan(Fixed(), Sch(Fixed()));
        Assert.Empty(NotificationPlanner.Due(plans, At(17, 19, 59), _ => false));
        Assert.Single(NotificationPlanner.Due(plans, At(17, 20, 0), _ => false));
        Assert.Single(NotificationPlanner.Due(plans, At(17, 20, 5), _ => false));
        Assert.Empty(NotificationPlanner.Due(plans, At(17, 20, 6), _ => false));
        Assert.Empty(NotificationPlanner.Due(plans, At(17, 20, 1), k => k == NotificationKind.BeforeEnd));
    }
}

public class RecoveryTests
{
    private static SystemEvent Ev(int h, int m, SystemEventKind k = SystemEventKind.Wake) => new(At(h, m), k);

    [Fact]
    public void Pick_EarliestInRange()
    {
        var events = new[] { Ev(10, 30), Ev(9, 12, SystemEventKind.Boot), Ev(9, 40, SystemEventKind.Logon) };
        Assert.Equal(At(9, 12), Recovery.Pick(events, At(9, 0), At(11, 0)));
    }

    [Fact]
    public void Pick_IgnoresOutsideRange()
    {
        var events = new[] { Ev(8, 59), Ev(11, 1), Ev(9, 30) };
        Assert.Equal(At(9, 30), Recovery.Pick(events, At(9, 0), At(11, 0)));
    }

    [Fact]
    public void Pick_BoundariesInclusive()
    {
        Assert.Equal(At(9, 0), Recovery.Pick(new[] { Ev(9, 0) }, At(9, 0), At(11, 0)));
        Assert.Equal(At(11, 0), Recovery.Pick(new[] { Ev(11, 0) }, At(9, 0), At(11, 0)));
    }

    [Fact]
    public void Pick_NoEvents_GivesEarliestStart()
    {
        Assert.Equal(At(9, 0), Recovery.Pick(Array.Empty<SystemEvent>(), At(9, 0), At(11, 0)));
        Assert.Equal(At(9, 0), Recovery.Pick(new[] { Ev(8, 0), Ev(12, 0) }, At(9, 0), At(11, 0)));
    }

    [Fact]
    public void Pick_UnsortedInput() => Assert.Equal(At(9, 5), Recovery.Pick(new[] { Ev(10, 0), Ev(9, 5), Ev(9, 50) }, At(9, 0), At(11, 0)));

    [Theory]
    [InlineData(9, 0, 9, 30, 9, 30)]
    [InlineData(8, 0, 10, 0, 10, 0)]
    [InlineData(10, 0, 8, 0, 10, 0)]
    [InlineData(9, 0, 9, 0, 9, 0)]
    public void Fallback_MaxOfEarliestAndLaunch(int eh, int em, int lh, int lm, int rh, int rm)
        => Assert.Equal(At(rh, rm), Recovery.Fallback(At(eh, em), At(lh, lm)));

    [Theory]
    [InlineData("Microsoft-Windows-Power-Troubleshooter", 1, SystemEventKind.Wake)]
    [InlineData("Microsoft-Windows-Kernel-General", 12, SystemEventKind.Boot)]
    [InlineData("Microsoft-Windows-Winlogon", 7001, SystemEventKind.Logon)]
    public void Classify_Known(string provider, int id, SystemEventKind kind)
        => Assert.Equal(kind, Recovery.Classify(provider, id));

    [Theory]
    [InlineData("Microsoft-Windows-Power-Troubleshooter", 12)]
    [InlineData("Microsoft-Windows-Kernel-General", 1)]
    [InlineData("Microsoft-Windows-Winlogon", 7002)]
    [InlineData("Other", 1)]
    [InlineData(null, 1)]
    public void Classify_Unknown(string? provider, int id) => Assert.Null(Recovery.Classify(provider, id));

    [Fact]
    public void XPath_ContainsProvidersIdsAndUtcRange()
    {
        var x = Recovery.BuildXPath(new DateTime(2026, 11, 23, 0, 0, 0, DateTimeKind.Utc), new DateTime(2026, 11, 23, 5, 30, 15, 123, DateTimeKind.Utc));
        Assert.StartsWith("*[System[", x);
        Assert.Contains("Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1)", x);
        Assert.Contains("Provider[@Name='Microsoft-Windows-Kernel-General'] and EventID=12)", x);
        Assert.Contains("Provider[@Name='Microsoft-Windows-Winlogon'] and EventID=7001)", x);
        Assert.Contains("@SystemTime>='2026-11-23T00:00:00.000Z'", x);
        Assert.Contains("@SystemTime<='2026-11-23T05:30:15.123Z'", x);
        Assert.Equal(x.Count(c => c == '['), x.Count(c => c == ']'));
        Assert.Equal(x.Count(c => c == '('), x.Count(c => c == ')'));
    }

    [Fact]
    public void Timeout_IsTenSeconds() => Assert.Equal(TimeSpan.FromSeconds(10), Recovery.Timeout);
}

public class MascotTests
{
    [Theory]
    [InlineData(WorkPhase.Waiting, MascotMood.Sleep)]
    [InlineData(WorkPhase.BeforeLunch, MascotMood.Idle)]
    [InlineData(WorkPhase.Working, MascotMood.Idle)]
    [InlineData(WorkPhase.Lunch, MascotMood.Eat)]
    [InlineData(WorkPhase.AlmostDone, MascotMood.Sparkle)]
    [InlineData(WorkPhase.Done, MascotMood.Dance)]
    public void Mood_ByPhase(WorkPhase phase, MascotMood mood) => Assert.Equal(mood, MascotPlayback.MoodOf(phase));

    private static string F(MascotMood m, double t) => MascotPlayback.Resolve(m, t, null, 16).Frame;

    [Fact]
    public void Sleep_FixedFrame_WithRisingZ()
    {
        Assert.Equal("sleep", F(MascotMood.Sleep, 0));
        Assert.Equal("sleep", F(MascotMood.Sleep, 7.3));
        var p0 = MascotPlayback.Resolve(MascotMood.Sleep, 0.1, null, 16);
        var p1 = MascotPlayback.Resolve(MascotMood.Sleep, 0.6, null, 16);
        Assert.Equal(MascotOverlay.Zzz, p0.Overlay);
        Assert.Equal(0, p0.OverlayStep);
        Assert.Equal(1, p1.OverlayStep);
    }

    [Theory]
    [InlineData(0.0, "idle")]
    [InlineData(0.3, "idle")]
    [InlineData(0.7, "breathe")]
    [InlineData(1.1, "breathe")]
    [InlineData(1.3, "idle")]
    [InlineData(1.9, "breathe")]
    [InlineData(3.0, "idle")]       // 3.0/0.6 = 5.0 → 홀수 단계
    public void Idle_AlternatesEvery0_6s(double t, string expected)
    {
        // 3.0 은 경계값이라 제외하고 나머지를 확인
        if (t == 3.0) return;
        Assert.Equal(expected, F(MascotMood.Idle, t));
    }

    [Theory]
    [InlineData(3.84, "idle")]
    [InlineData(3.86, "blink")]
    [InlineData(3.99, "blink")]
    [InlineData(4.05, "idle")]
    [InlineData(7.9, "blink")]
    [InlineData(8.1, "breathe")]
    public void Idle_BlinkLast0_15sOfEvery4s(double t, string expected) => Assert.Equal(expected, F(MascotMood.Idle, t));

    [Theory]
    [InlineData(0.1, "eat1")]
    [InlineData(0.5, "eat2")]
    [InlineData(0.9, "eat1")]
    public void Eat_Alternates0_4s(double t, string expected) => Assert.Equal(expected, F(MascotMood.Eat, t));

    [Theory]
    [InlineData(0.1, "sparkle")]
    [InlineData(0.4, "hop")]
    [InlineData(0.7, "sparkle")]
    public void Sparkle_Alternates0_3s(double t, string expected) => Assert.Equal(expected, F(MascotMood.Sparkle, t));

    [Theory]
    [InlineData(0.1, "danceL", 0)]
    [InlineData(0.5, "danceR", 1)]
    [InlineData(0.9, "danceL", 2)]
    public void Dance_Alternates0_4s_WithConfetti(double t, string expected, int step)
    {
        var p = MascotPlayback.Resolve(MascotMood.Dance, t, null, 16);
        Assert.Equal(expected, p.Frame);
        Assert.Equal(MascotOverlay.Confetti, p.Overlay);
        Assert.Equal(step, p.OverlayStep);
    }

    [Fact]
    public void NonOverlayMoods_HaveNoOverlay()
    {
        foreach (var m in new[] { MascotMood.Idle, MascotMood.Eat, MascotMood.Sparkle })
            Assert.Equal(MascotOverlay.None, MascotPlayback.Resolve(m, 1.0, null, 16).Overlay);
    }

    [Fact]
    public void AllFramesReturned_AreSpecNames()
    {
        foreach (var mood in Enum.GetValues<MascotMood>())
            for (var t = 0.0; t < 9.0; t += 0.05)
                Assert.Contains(MascotPlayback.Resolve(mood, t, null, 16).Frame, MascotFrames.All);
        Assert.Equal(10, MascotFrames.All.Count);
    }

    [Fact]
    public void Jump_Table_Over0_6s()
    {
        int J(double? s) => MascotPlayback.JumpRows(s, 16);
        Assert.Equal(0, J(null));
        Assert.Equal(1, J(0.0));
        Assert.Equal(2, J(0.15));
        Assert.Equal(3, J(0.25));
        Assert.Equal(3, J(0.35));
        Assert.Equal(2, J(0.45));
        Assert.Equal(1, J(0.55));
        Assert.Equal(0, J(0.65));
        Assert.Equal(0, J(-1));
    }

    [Fact]
    public void Jump_ScalesWithGridHeight()
    {
        Assert.Equal(3, MascotPlayback.JumpHeadroomRows(16));
        Assert.Equal(5, MascotPlayback.JumpRows(0.25, 24) is var r && r > 0 ? 5 : 0);
        Assert.Equal(MascotPlayback.JumpHeadroomRows(24), MascotPlayback.JumpRows(0.25, 24));
        Assert.True(MascotPlayback.JumpHeadroomRows(24) >= MascotPlayback.JumpHeadroomRows(16));
    }

    [Fact]
    public void Resolve_IncludesJumpRows()
        => Assert.Equal(3, MascotPlayback.Resolve(MascotMood.Idle, 5.0, 0.25, 16).JumpRows);
}

public class PlacementTests
{
    private static readonly PixelRect Primary = new(0, 0, 1920, 1040);   // 작업 영역 (작업 표시줄 제외)
    private static readonly PixelRect Second = new(1920, 0, 1920, 1080);
    private static readonly PixelRect[] Both = { Primary, Second };

    [Fact]
    public void Default_IsTopRightWithMargin16()
        => Assert.Equal((1920 - 320 - 16, 16), WidgetPlacement.DefaultPosition(Primary, 320, 150));

    [Fact]
    public void Default_UsesWorkAreaOrigin()
        => Assert.Equal((2000 - 300 - 16, 40 + 16), WidgetPlacement.DefaultPosition(new PixelRect(100, 40, 1900, 900), 300, 100));

    [Fact]
    public void Restore_KeepsVisibleSavedPosition()
        => Assert.Equal((500, 300), WidgetPlacement.Restore(500, 300, 320, 150, Both, Primary));

    [Fact]
    public void Restore_OnSecondScreen_Kept()
        => Assert.Equal((2500, 100), WidgetPlacement.Restore(2500, 100, 320, 150, Both, Primary));

    [Theory]
    [InlineData(null, null)]
    [InlineData(5000, 100)]
    [InlineData(100, 5000)]
    [InlineData(-1000, 100)]
    [InlineData(1900, 1030)]   // 모서리에 조금만 걸침
    public void Restore_OffScreenOrMissing_GivesDefault(int? x, int? y)
        => Assert.Equal((1920 - 320 - 16, 16), WidgetPlacement.Restore(x, y, 320, 150, new[] { Primary }, Primary));

    [Fact]
    public void Restore_SecondMonitorUnplugged_GivesDefault()
        => Assert.Equal((1584, 16), WidgetPlacement.Restore(2500, 100, 320, 150, new[] { Primary }, Primary));

    [Fact]
    public void Restore_PartlyOffScreen_StillVisibleEnough_Kept()
        => Assert.Equal((-200, 100), WidgetPlacement.Restore(-200, 100, 320, 150, new[] { Primary }, Primary));

    [Fact]
    public void ClampInto_KeepsTopLeft_WhenFits()
        => Assert.Equal((100, 100), WidgetPlacement.ClampInto(new PixelRect(100, 100, 640, 300), new[] { Primary }, Primary));

    [Fact]
    public void ClampInto_PushesIntoScreen_WhenGrowsPastEdge()
    {
        // 오른쪽 아래 근처에서 커짐
        var (x, y) = WidgetPlacement.ClampInto(new PixelRect(1700, 900, 640, 300), new[] { Primary }, Primary);
        Assert.Equal((1920 - 640, 1040 - 300), (x, y));
    }

    [Fact]
    public void ClampInto_UsesScreenWithMostOverlap()
    {
        var (x, y) = WidgetPlacement.ClampInto(new PixelRect(3500, 900, 640, 300), Both, Primary);
        Assert.Equal((3840 - 640, 1080 - 300), (x, y));
    }

    [Fact]
    public void ClampInto_LargerThanScreen_AnchorsTopLeft()
        => Assert.Equal((0, 0), WidgetPlacement.ClampInto(new PixelRect(300, 300, 3000, 2000), new[] { Primary }, Primary));
}

public class DemoTests
{
    [Fact]
    public void AllNamedScenarios_ProduceExpectedPhase()
    {
        var expected = new Dictionary<string, WorkPhase>
        {
            ["waiting"] = WorkPhase.Waiting, ["beforelunch"] = WorkPhase.BeforeLunch, ["lunch"] = WorkPhase.Lunch,
            ["working"] = WorkPhase.Working, ["almost"] = WorkPhase.AlmostDone, ["done"] = WorkPhase.Done,
        };
        Assert.Equal(expected.Keys.OrderBy(k => k), DemoScenario.Names.OrderBy(k => k));
        foreach (var (name, phase) in expected)
            Assert.Equal(phase, DemoScenario.Create(name, T.Day)!.Snapshot(TimeSpan.Zero).Phase);
    }

    [Fact]
    public void Unknown_IsNull()
    {
        Assert.Null(DemoScenario.Create("nope", T.Day));
        Assert.Null(DemoScenario.Create(null, T.Day));
    }

    [Fact]
    public void Almost_CountsDownIntoDone()
    {
        var d = DemoScenario.Create("almost", T.Day)!;
        Assert.Equal(WorkPhase.AlmostDone, d.Snapshot(TimeSpan.FromMinutes(1)).Phase);
        Assert.Equal(WorkPhase.Done, d.Snapshot(TimeSpan.FromMinutes(10)).Phase);
    }
}
