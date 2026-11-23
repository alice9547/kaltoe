using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class SnapshotTests
{
    private static WorkdaySnapshot Flexible(AppSettings s, DateTime? clockIn, DateTime now) => SnapshotCalculator.Make(s, now, clockIn);

    [Fact]
    public void Flexible_NoRecord_Waiting()
    {
        var s = Flexible(Flex(), null, At(9, 30));
        Assert.Equal(WorkPhase.Waiting, s.Phase);
        Assert.Null(s.Target);
        Assert.Null(s.ClockIn);
        Assert.Equal(TimeSpan.Zero, s.Remaining);
        Assert.Equal(0, s.Progress);
    }

    [Fact]
    public void Fixed_BeforeStart_WaitingWithTarget()
    {
        var s = Flexible(Fixed(), null, At(8, 18));
        Assert.Equal(WorkPhase.Waiting, s.Phase);
        Assert.Equal(At(8, 30), s.Target);
        Assert.Equal(TimeSpan.FromMinutes(12), s.Remaining);
        Assert.Equal(At(8, 30), s.ClockIn);
        Assert.Equal(At(17, 30), s.ClockOut);
        Assert.Equal(TimeSpan.FromHours(9) + TimeSpan.FromMinutes(12), s.RemainingToClockOut);
    }

    [Fact]
    public void Fixed_AtStart_IsWorking()
    {
        var s = Flexible(Fixed(), null, At(8, 30));
        Assert.Equal(WorkPhase.Working, s.Phase);
        Assert.Equal(At(17, 30), s.Target);
        Assert.Equal(0, s.Progress);
    }

    [Fact]
    public void Working_Fields()
    {
        var s = Flexible(Flex(), At(9, 16), At(14, 4));
        Assert.Equal(WorkPhase.Working, s.Phase);
        Assert.Equal(At(18, 16), s.ClockOut);
        Assert.Equal(At(18, 16), s.Target);
        Assert.Equal(TimeSpan.FromHours(4) + TimeSpan.FromMinutes(12), s.Remaining);
        Assert.Equal(s.Remaining, s.RemainingToClockOut);
        Assert.Equal(TimeSpan.Zero, s.Overtime);
        Assert.Equal((14 * 60 + 4 - (9 * 60 + 16)) / 540.0, s.Progress, 9);
        Assert.Null(s.LunchStart);
    }

    [Fact]
    public void AlmostDone_Boundary_TenMinutes()
    {
        var clockIn = At(9, 16);   // 퇴근 18:16
        Assert.Equal(WorkPhase.Working, Flexible(Flex(), clockIn, At(18, 5, 59)).Phase);
        var at10 = Flexible(Flex(), clockIn, At(18, 6));       // 정확히 10분 남음 → almostDone
        Assert.Equal(WorkPhase.AlmostDone, at10.Phase);
        Assert.Equal(At(18, 16), at10.Target);
        Assert.Equal(WorkPhase.AlmostDone, Flexible(Flex(), clockIn, At(18, 15, 59)).Phase);
    }

    [Fact]
    public void Done_Boundary_AndOvertime()
    {
        var clockIn = At(9, 16);
        var at = Flexible(Flex(), clockIn, At(18, 16));
        Assert.Equal(WorkPhase.Done, at.Phase);
        Assert.Null(at.Target);
        Assert.Equal(TimeSpan.Zero, at.Remaining);
        Assert.Equal(TimeSpan.Zero, at.RemainingToClockOut);
        Assert.Equal(1.0, at.Progress);
        var late = Flexible(Flex(), clockIn, At(18, 28, 30));
        Assert.Equal(TimeSpan.FromMinutes(12) + TimeSpan.FromSeconds(30), late.Overtime);
    }

    // ── 점심 (spec 3절 표) ──

    private static readonly AppSettings FixedLunch = WithLunch(Fixed());   // 08:30–17:30, 점심 11:30–13:00

    [Theory]
    [InlineData(8, 30, 0, WorkPhase.BeforeLunch)]
    [InlineData(11, 29, 59, WorkPhase.BeforeLunch)]
    [InlineData(11, 30, 0, WorkPhase.Lunch)]      // lunchStart ≤ 지금
    [InlineData(12, 59, 59, WorkPhase.Lunch)]
    [InlineData(13, 0, 0, WorkPhase.Working)]     // 지금 < lunchEnd 가 아님
    [InlineData(17, 19, 59, WorkPhase.Working)]
    [InlineData(17, 20, 0, WorkPhase.AlmostDone)]
    [InlineData(17, 29, 59, WorkPhase.AlmostDone)]
    [InlineData(17, 30, 0, WorkPhase.Done)]
    public void FixedWithLunch_PhaseTable(int h, int m, int sec, WorkPhase phase)
        => Assert.Equal(phase, Flexible(FixedLunch, null, At(h, m, sec)).Phase);

    [Fact]
    public void BeforeLunch_TargetsLunchStart()
    {
        var s = Flexible(FixedLunch, null, At(10, 47, 52));
        Assert.Equal(At(11, 30), s.Target);
        Assert.Equal(TimeSpan.FromMinutes(42) + TimeSpan.FromSeconds(8), s.Remaining);
        Assert.Equal(At(11, 30), s.LunchStart);
        Assert.Equal(At(13, 0), s.LunchEnd);
        Assert.Equal(At(17, 30) - At(10, 47, 52), s.RemainingToClockOut);
    }

    [Fact]
    public void Lunch_TargetsLunchEnd()
    {
        var s = Flexible(FixedLunch, null, At(12, 41, 52));
        Assert.Equal(WorkPhase.Lunch, s.Phase);
        Assert.Equal(At(13, 0), s.Target);
        Assert.Equal(TimeSpan.FromMinutes(18) + TimeSpan.FromSeconds(8), s.Remaining);
    }

    [Fact]
    public void BeforeLunch_WinsOverAlmostDone()
    {
        // 퇴근 12:00, 점심 11:55–13:00 — 10분 안쪽이어도 표 순서상 점심 단계가 먼저.
        var s = WithLunch(Fixed(8, 0, 12, 0), 11, 55, 13, 0);
        Assert.Equal(WorkPhase.BeforeLunch, Flexible(s, null, At(11, 50)).Phase);
        Assert.Equal(WorkPhase.Lunch, Flexible(s, null, At(11, 56)).Phase);
    }

    [Fact]
    public void Lunch_NotValid_WhenBeforeClockIn()
    {
        // 출근 13:00 이후면 lunchEnd(13:00) ≤ clockIn → 점심 무효
        var s = Flexible(WithLunch(Flex()), At(13, 0), At(14, 0));
        Assert.Equal(WorkPhase.Working, s.Phase);
        Assert.Null(s.LunchStart);
        Assert.Null(s.LunchEnd);
    }

    [Fact]
    public void Lunch_Valid_WhenClockInJustBeforeLunchEnd()
    {
        var s = Flexible(WithLunch(Flex()), At(12, 59), At(12, 59, 30));
        Assert.Equal(WorkPhase.Lunch, s.Phase);
    }

    [Fact]
    public void Lunch_NotValid_WhenAfterClockOut()
    {
        // 출근 03:00 → 퇴근 12:00, 점심 12:00 시작 → lunchStart < clockOut 이 아니므로 무효
        var s = Flexible(WithLunch(T.Flex(0, 540), 12, 0, 13, 0), At(3, 0), At(4, 0));
        Assert.Null(s.LunchStart);
        Assert.Equal(WorkPhase.Working, s.Phase);
    }

    [Fact]
    public void Lunch_Disabled_NeverLunchPhase()
    {
        var s = Flexible(Fixed(), null, At(12, 0));
        Assert.Equal(WorkPhase.Working, s.Phase);
        Assert.Null(s.LunchStart);
    }

    [Fact]
    public void Progress_IsClampedAndUsesClockInToOut()
    {
        var s = Flexible(Fixed(), null, At(13, 0));
        Assert.Equal((13 * 60 - (8 * 60 + 30)) / 540.0, s.Progress, 9);
    }

    [Fact]
    public void WorkMinutes_ControlsClockOut()
    {
        var s = Flexible(Flex(minutes: 480), At(9, 0), At(10, 0));
        Assert.Equal(At(17, 0), s.ClockOut);
    }
}
