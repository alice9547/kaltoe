// 알림 계획 — docs/spec.md 4절 알림 표. 순수 함수.
namespace Kaltoe.Core;

public enum NotificationKind { Lunch, BeforeEnd, End }

public sealed record PlannedNotification(NotificationKind Kind, DateTime FireTime, string Title, string Body);

public static class NotificationPlanner
{
    public const string Title = "칼퇴";
    public const string LunchBody = "점심 시간입니다 — npm install 점심";
    public const string BeforeEndBody = "퇴근 10분 전 — 지금 배포하면 안 됩니다";
    public const string EndBody = "Process finished with exit code 0 — 퇴근하세요";

    /// 이 일정에서 (시각과 무관하게) 알릴 수 있는 알림 전부.
    public static IReadOnlyList<PlannedNotification> Plan(AppSettings s, WorkSchedule sch)
    {
        var list = new List<PlannedNotification>();
        if (sch.ClockOut is not { } clockOut) return list;
        if (s.Notify.Lunch && sch.LunchStart is { } ls)
            list.Add(new(NotificationKind.Lunch, ls, Title, LunchBody));
        if (s.Notify.BeforeEnd)
            list.Add(new(NotificationKind.BeforeEnd, clockOut - SnapshotCalculator.AlmostDoneThreshold, Title, BeforeEndBody));
        if (s.Notify.End)
            list.Add(new(NotificationKind.End, clockOut, Title, EndBody));
        return list;
    }

    /// 이미 지난 시각을 뺀, 앞으로 올 알림.
    public static IReadOnlyList<PlannedNotification> Upcoming(IEnumerable<PlannedNotification> plans, DateTime now)
        => plans.Where(p => p.FireTime > now).ToList();

    /// 지금 띄울 알림: 시각이 지났고(now ≥ 시각), 지난 지 grace 이내이고, 아직 안 띄운 것.
    /// grace 를 넘긴 것은 "이미 지난 시각"으로 보고 띄우지 않는다.
    public static IReadOnlyList<PlannedNotification> Due(
        IEnumerable<PlannedNotification> plans, DateTime now,
        Func<NotificationKind, bool> alreadyShown, TimeSpan? grace = null)
    {
        var g = grace ?? DefaultGrace;
        return plans.Where(p => p.FireTime <= now && now - p.FireTime <= g && !alreadyShown(p.Kind)).ToList();
    }

    public static readonly TimeSpan DefaultGrace = TimeSpan.FromSeconds(5);
}
