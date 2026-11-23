using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class EngineTests
{
    private sealed class Harness
    {
        public readonly DayState State = new();
        public readonly List<RecoveryRequest> Requests = new();
        public int Saves;
        public WorkdayEngine Engine;

        public Harness(AppSettings? settings = null)
        {
            Engine = new WorkdayEngine(settings ?? Flex(), State);
            Engine.RecoveryRequested += Requests.Add;
            Engine.StateChanged += () => Saves++;
        }

        public DateTime? Record(DateTime day) => State.GetClockIn(DayKey.Of(day));
    }

    // ── 규칙 2: 9:16 에 해제 → 09:16 ──

    [Fact]
    public void Rule2_UnlockAt0916_RecordsThen()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 0));
        h.Engine.NoteLocked(At(8, 5));
        h.Engine.Tick(At(9, 15));
        Assert.Null(h.Record(Day));
        h.Engine.NoteUnlocked(At(9, 16));
        Assert.Equal(At(9, 16), h.Record(Day));
        Assert.Equal(WorkPhase.Working, h.Engine.Snapshot(At(9, 16, 1)).Phase);
        Assert.Equal(At(18, 16), h.Engine.Snapshot(At(9, 16, 1)).ClockOut);
    }

    [Fact]
    public void Rule2_UsingSince0840_RecordsAt0900()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 40));
        for (var t = At(8, 40, 1); t <= At(9, 0, 5); t = t.AddSeconds(1)) h.Engine.Tick(t);
        Assert.Equal(At(9, 0), h.Record(Day));
    }

    [Fact]
    public void Rule3_BeforeEarliest_NoRecord()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 59));
        h.Engine.Tick(At(8, 59, 30));
        h.Engine.NoteActivation(At(8, 59, 40));
        Assert.Null(h.Record(Day));
        Assert.Equal(WorkPhase.Waiting, h.Engine.Snapshot(At(8, 59, 40)).Phase);
    }

    [Fact]
    public void Rule4_WhileLocked_NoRecord_EvenAfterEarliest()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 0));
        h.Engine.NoteLocked(At(8, 30));
        for (var t = At(8, 55); t <= At(9, 30); t = t.AddMinutes(1)) h.Engine.Tick(t);
        Assert.Null(h.Record(Day));
        h.Engine.NoteActivation(At(9, 31));   // 잠긴 채로의 깨어남 알림
        Assert.Null(h.Record(Day));
        h.Engine.NoteUnlocked(At(9, 40));
        Assert.Equal(At(9, 40), h.Record(Day));
    }

    [Fact]
    public void Rule1_OneRecordPerDay_NeverChanges()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 59));
        h.Engine.Tick(At(9, 0));
        Assert.Equal(At(9, 0), h.Record(Day));
        h.Engine.NoteLocked(At(12, 0));
        h.Engine.NoteUnlocked(At(13, 0));
        Assert.Equal(At(9, 0), h.Record(Day));
    }

    [Fact]
    public void Rule5_Midnight_NewDay_YesterdayRecordIgnored()
    {
        var h = new Harness();
        h.State.TrySetClockIn("2026-11-22", new DateTime(2026, 11, 22, 9, 0, 0));
        h.Engine.Start(At(9, 5));
        Assert.Single(h.Requests);   // 오늘 기록 없음 → 복구
        h.Engine.FinishRecovery(h.Requests[0].Token, At(9, 1), At(9, 5));
        Assert.Equal(At(9, 1), h.Record(Day));

        var tomorrow = Day.AddDays(1);
        h.Engine.Tick(tomorrow.AddHours(1));   // 01:00 — 새 날, earliest 전
        Assert.Null(h.Record(tomorrow));
        Assert.Equal(WorkPhase.Waiting, h.Engine.Snapshot(tomorrow.AddHours(1)).Phase);
        h.Engine.NoteUnlocked(tomorrow.AddHours(9).AddMinutes(20));
        Assert.Equal(tomorrow.AddHours(9).AddMinutes(20), h.Record(tomorrow));
        Assert.Equal(At(9, 1), h.Record(Day));   // 어제 기록은 그대로
    }

    [Fact]
    public void Rule5_PendingRecovery_DiscardedOnNewDay()
    {
        var h = new Harness();
        h.Engine.Start(At(23, 0));
        var token = h.Requests[0].Token;
        var tomorrow = Day.AddDays(1);
        h.Engine.Tick(tomorrow.AddMinutes(1));
        h.Engine.FinishRecovery(token, At(9, 0), tomorrow.AddMinutes(1));   // 지난 날 것 — 버림
        Assert.Null(h.Record(tomorrow));
        Assert.Null(h.Record(Day));
    }

    [Fact]
    public void TimerGap_TwoSeconds_RefreshesActivation()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 0));
        h.Engine.Tick(At(8, 0, 1));
        // 절전: 08:00:01 → 09:30:00 (타이머가 건너뜀). 활성화 시각 = 09:30
        h.Engine.Tick(At(9, 30));
        Assert.Equal(At(9, 30), h.Record(Day));
    }

    [Fact]
    public void TimerGap_BelowTwoSeconds_DoesNotRefresh()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 40));
        h.Engine.Tick(At(8, 40, 1));
        for (var t = At(8, 40, 2); t < At(9, 0); t = t.AddSeconds(1)) h.Engine.Tick(t);
        h.Engine.Tick(At(9, 0));
        Assert.Equal(At(9, 0), h.Record(Day));
    }

    // ── 규칙 6: 사후 복구 ──

    [Fact]
    public void Rule6_StartAfterEarliest_RequestsRecovery_AndHoldsRule2()
    {
        var h = new Harness();
        h.Engine.Start(At(10, 30));
        var req = Assert.Single(h.Requests);
        Assert.Equal(At(9, 0), req.EarliestStart);
        Assert.Equal(At(10, 30), req.Now);
        Assert.True(h.Engine.RecoveryPending);
        h.Engine.Tick(At(10, 30, 1));
        h.Engine.NoteUnlocked(At(10, 30, 2));
        Assert.Null(h.Record(Day));   // 보류
        Assert.Equal(WorkPhase.Waiting, h.Engine.Snapshot(At(10, 30, 2)).Phase);
        h.Engine.FinishRecovery(req.Token, At(9, 12), At(10, 30, 3));
        Assert.Equal(At(9, 12), h.Record(Day));
        Assert.False(h.Engine.RecoveryPending);
    }

    [Fact]
    public void Rule6_Failure_FallsBackToMaxOfEarliestAndLaunch()
    {
        var h = new Harness();
        h.Engine.Start(At(10, 30));
        h.Engine.FinishRecovery(h.Requests[0].Token, null, At(10, 30, 5));
        Assert.Equal(At(10, 30), h.Record(Day));
    }

    [Fact]
    public void Rule6_NotRequested_BeforeEarliest()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 30));
        Assert.Empty(h.Requests);
        Assert.False(h.Engine.RecoveryPending);
    }

    [Fact]
    public void Rule6_NotRequested_WhenRecordExists()
    {
        var h = new Harness();
        h.State.TrySetClockIn(DayKey.Of(Day), At(9, 3));
        h.Engine.Start(At(10, 30));
        Assert.Empty(h.Requests);
        Assert.Equal(At(9, 3), h.Engine.Snapshot(At(10, 30)).ClockIn);
    }

    [Fact]
    public void Rule6_StaleToken_Ignored()
    {
        var h = new Harness();
        h.Engine.Start(At(10, 0));
        h.Engine.FinishRecovery(999, At(9, 0), At(10, 0));
        Assert.Null(h.Record(Day));
        Assert.True(h.Engine.RecoveryPending);
    }

    [Fact]
    public void Rule6_LiveRecordWinsOverLateRecovery()
    {
        // 복구 중에는 규칙 2 가 보류되므로 실시간 기록이 먼저 생길 수 없다. 그래도 복구 결과는 기존 기록을 덮지 않는다.
        var h = new Harness();
        h.Engine.Start(At(10, 0));
        var token = h.Requests[0].Token;
        h.State.TrySetClockIn(DayKey.Of(Day), At(9, 40));
        h.Engine.FinishRecovery(token, At(9, 5), At(10, 0, 5));
        Assert.Equal(At(9, 40), h.Record(Day));
    }

    // ── 규칙 8: 다시 감지 ──

    [Fact]
    public void Rule8_Redetect_ClearsRecord_AndRecovers()
    {
        var h = new Harness();
        h.State.TrySetClockIn(DayKey.Of(Day), At(9, 40));
        h.Engine.Start(At(11, 0));
        Assert.Empty(h.Requests);
        h.Engine.RedetectToday(At(11, 0, 5));
        Assert.Null(h.Record(Day));
        var req = Assert.Single(h.Requests);
        h.Engine.FinishRecovery(req.Token, At(9, 7), At(11, 0, 6));
        Assert.Equal(At(9, 7), h.Record(Day));
    }

    [Fact]
    public void Rule8_Redetect_SupersedesPendingRecovery()
    {
        var h = new Harness();
        h.Engine.Start(At(11, 0));
        var first = h.Requests[0].Token;
        h.Engine.RedetectToday(At(11, 0, 5));
        Assert.Equal(2, h.Requests.Count);
        h.Engine.FinishRecovery(first, At(9, 1), At(11, 0, 6));
        Assert.Null(h.Record(Day));
        h.Engine.FinishRecovery(h.Requests[1].Token, At(9, 2), At(11, 0, 7));
        Assert.Equal(At(9, 2), h.Record(Day));
    }

    [Fact]
    public void Rule8_Redetect_IgnoredInFixedMode()
    {
        var h = new Harness(Fixed());
        h.Engine.Start(At(10, 0));
        h.Engine.RedetectToday(At(10, 1));
        Assert.Empty(h.Requests);
    }

    // ── 고정 모드 ──

    [Fact]
    public void Fixed_NoDetection_NoStorage_NoRecovery()
    {
        var h = new Harness(Fixed());
        h.Engine.Start(At(10, 0));
        h.Engine.NoteUnlocked(At(10, 1));
        h.Engine.Tick(At(10, 2));
        Assert.Empty(h.Requests);
        Assert.Empty(h.State.ClockIns);
        var s = h.Engine.Snapshot(At(10, 2));
        Assert.Equal(At(8, 30), s.ClockIn);
        Assert.Equal(At(17, 30), s.ClockOut);
    }

    [Fact]
    public void ModeSwitch_FixedToFlexible_RunsRecovery()
    {
        var h = new Harness(Fixed());
        h.Engine.Start(At(10, 0));
        h.Engine.UpdateSettings(Flex(), At(10, 5));
        Assert.Single(h.Requests);
        Assert.Equal(WorkPhase.Waiting, h.Engine.Snapshot(At(10, 5)).Phase);
    }

    [Fact]
    public void SettingsChange_AppliesToSnapshotImmediately()
    {
        var h = new Harness();
        h.State.TrySetClockIn(DayKey.Of(Day), At(9, 0));
        h.Engine.Start(At(9, 30));
        Assert.Equal(At(18, 0), h.Engine.Snapshot(At(9, 30)).ClockOut);
        h.Engine.UpdateSettings(Flex(minutes: 480), At(9, 31));
        Assert.Equal(At(17, 0), h.Engine.Snapshot(At(9, 31)).ClockOut);
    }

    [Fact]
    public void StateChanged_FiresOnRecord()
    {
        var h = new Harness();
        h.Engine.Start(At(9, 0), isLocked: false);
        h.Engine.FinishRecovery(h.Requests[0].Token, At(9, 0), At(9, 0));
        Assert.True(h.Saves > 0);
    }

    // ── 알림 ──

    [Fact]
    public void Notifications_FireOnce_AcrossRestart()
    {
        var settings = Fixed();
        var h = new Harness(settings);
        h.Engine.Start(At(17, 19, 50));
        Assert.Empty(h.Engine.TakeDueNotifications(At(17, 19, 59)));
        var due = h.Engine.TakeDueNotifications(At(17, 20, 0));
        Assert.Equal(NotificationKind.BeforeEnd, Assert.Single(due).Kind);
        Assert.Empty(h.Engine.TakeDueNotifications(At(17, 20, 1)));

        // 앱 재시작 (같은 DayState 를 파일에서 다시 읽음)
        var reloaded = DayState.Parse(h.State.ToJson());
        var e2 = new WorkdayEngine(settings, reloaded);
        e2.Start(At(17, 20, 2));
        Assert.Empty(e2.TakeDueNotifications(At(17, 20, 3)));
        var end = Assert.Single(e2.TakeDueNotifications(At(17, 30, 0)));
        Assert.Equal(NotificationKind.End, end.Kind);
    }

    [Fact]
    public void Notifications_PastTimes_AreNotShown()
    {
        var h = new Harness(Fixed());
        h.Engine.Start(At(17, 45));
        Assert.Empty(h.Engine.TakeDueNotifications(At(17, 45, 1)));
        Assert.Empty(h.State.Notified);
    }

    [Fact]
    public void Notifications_Flexible_NeedRecord()
    {
        var h = new Harness();
        h.Engine.Start(At(8, 0));
        Assert.Empty(h.Engine.TakeDueNotifications(At(18, 0)));
    }
}
