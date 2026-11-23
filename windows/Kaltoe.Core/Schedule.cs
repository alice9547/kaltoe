// 오늘의 출근·퇴근·점심 시각과 단계·스냅샷 계산 — docs/spec.md 2·3절. 시스템 호출 없는 순수 함수.
// 모든 시각은 "로컬 벽시계 시각"(DateTime, Kind 무시)으로 다룬다. 시간대 변환을 하지 않으므로 테스트에서 시간대를 고정할 필요가 없다.
namespace Kaltoe.Core;

public enum WorkPhase { Waiting, BeforeLunch, Lunch, Working, AlmostDone, Done }

/// 오늘의 일정. 점심은 "유효할 때만" 채워진다.
public sealed record WorkSchedule(DateTime? ClockIn, DateTime? ClockOut, DateTime? LunchStart, DateTime? LunchEnd)
{
    /// <param name="day">오늘(날짜 부분만 사용)</param>
    /// <param name="flexibleClockIn">유동 모드의 오늘 출근 기록(없으면 null). 고정 모드에서는 무시.</param>
    public static WorkSchedule Resolve(AppSettings s, DateTime day, DateTime? flexibleClockIn)
    {
        DateTime? clockIn, clockOut;
        if (s.Mode == WorkMode.Fixed)
        {
            clockIn = day.Date + s.Fixed.Start.ToTimeSpan();
            clockOut = day.Date + s.Fixed.End.ToTimeSpan();
        }
        else if (flexibleClockIn is { } ci)
        {
            clockIn = ci;
            clockOut = ci.AddMinutes(s.Flexible.WorkMinutes);
        }
        else
        {
            return new WorkSchedule(null, null, null, null);
        }

        DateTime? ls = null, le = null;
        if (s.Lunch.Enabled)
        {
            var start = day.Date + s.Lunch.Start.ToTimeSpan();
            var end = day.Date + s.Lunch.End.ToTimeSpan();
            // 점심이 유효: 출근 < 점심 끝, 점심 시작 < 퇴근
            if (clockIn < end && start < clockOut) { ls = start; le = end; }
        }
        return new WorkSchedule(clockIn, clockOut, ls, le);
    }
}

public sealed record WorkdaySnapshot(
    DateTime Now,
    DateTime? ClockIn,
    DateTime? ClockOut,
    DateTime? LunchStart,
    DateTime? LunchEnd,
    WorkPhase Phase,
    DateTime? Target,
    TimeSpan Remaining,
    TimeSpan RemainingToClockOut,
    TimeSpan Overtime,
    double Progress)
{
    public static WorkdaySnapshot Waiting(DateTime now)
        => new(now, null, null, null, null, WorkPhase.Waiting, null, TimeSpan.Zero, TimeSpan.Zero, TimeSpan.Zero, 0);
}

public static class SnapshotCalculator
{
    public static readonly TimeSpan AlmostDoneThreshold = TimeSpan.FromMinutes(10);

    public static WorkdaySnapshot Make(AppSettings settings, DateTime now, DateTime? flexibleClockIn)
        => Make(settings.Mode, WorkSchedule.Resolve(settings, now, flexibleClockIn), now);

    public static WorkdaySnapshot Make(WorkMode mode, WorkSchedule sch, DateTime now)
    {
        // 1) waiting: 유동은 기록 없음, 고정은 지금 < 출근
        if (sch.ClockIn is not { } clockIn || sch.ClockOut is not { } clockOut)
            return WorkdaySnapshot.Waiting(now);

        var toOut = Max0(clockOut - now);
        var overtime = Max0(now - clockOut);

        if (mode == WorkMode.Fixed && now < clockIn)
        {
            return new WorkdaySnapshot(now, clockIn, clockOut, sch.LunchStart, sch.LunchEnd,
                WorkPhase.Waiting, clockIn, clockIn - now, toOut, TimeSpan.Zero, 0);
        }

        WorkPhase phase;
        DateTime? target;
        if (now >= clockOut) { phase = WorkPhase.Done; target = null; }
        else if (sch.LunchStart is { } ls && sch.LunchEnd is { } le && now < ls)
        { phase = WorkPhase.BeforeLunch; target = ls; }
        else if (sch.LunchStart is { } ls2 && sch.LunchEnd is { } le2 && now >= ls2 && now < le2)
        { phase = WorkPhase.Lunch; target = le2; }
        else if (toOut <= AlmostDoneThreshold) { phase = WorkPhase.AlmostDone; target = clockOut; }
        else { phase = WorkPhase.Working; target = clockOut; }

        var total = (clockOut - clockIn).TotalSeconds;
        var progress = phase == WorkPhase.Done ? 1.0
            : total <= 0 ? 0.0
            : Math.Clamp((now - clockIn).TotalSeconds / total, 0.0, 1.0);

        return new WorkdaySnapshot(now, clockIn, clockOut, sch.LunchStart, sch.LunchEnd,
            phase, target, target is { } t ? Max0(t - now) : TimeSpan.Zero, toOut, overtime, progress);
    }

    private static TimeSpan Max0(TimeSpan t) => t < TimeSpan.Zero ? TimeSpan.Zero : t;
}
