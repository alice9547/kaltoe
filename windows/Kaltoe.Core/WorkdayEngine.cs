// 출근 감지 상태 기계. 시각·잠금 여부를 인자로 받고 기록은 DayState 에만 쓴다(파일 입출력·시스템 호출 없음).
// 판단은 ClockInRules / SnapshotCalculator / Recovery 의 순수 함수에 있고, 이 클래스는 이벤트를 받아 상태를 들고 그것들을 부르는 얇은 배선이다.
// 호출은 한 스레드(UI 스레드)에서만 한다.
namespace Kaltoe.Core;

public sealed record RecoveryRequest(int Token, DateTime EarliestStart, DateTime Now);

public sealed class WorkdayEngine
{
    private readonly DayState _state;
    private AppSettings _settings;

    private string _dayKey = "";
    private DateTime _activation;
    private DateTime _launchedAt;
    private DateTime _lastTick;
    private bool _locked;

    private int _nextToken;
    private int? _pendingToken;
    private DateTime _pendingEarliest;

    /// 사후 복구 조회를 시작해 달라는 요청. 조회가 끝나면 FinishRecovery 를 부른다.
    public event Action<RecoveryRequest>? RecoveryRequested;
    /// DayState 가 바뀌어 저장해야 함.
    public event Action? StateChanged;

    public WorkdayEngine(AppSettings settings, DayState state)
    {
        _settings = settings;
        _state = state;
    }

    public AppSettings Settings => _settings;
    public bool RecoveryPending => _pendingToken is not null;

    /// 오늘 출근 기록(유동 모드의 기록. 없으면 null).
    public DateTime? ClockInRecord(DateTime now) => _state.GetClockIn(DayKey.Of(now));

    // ── 시작 ──────────────────────────────────────────

    public void Start(DateTime now, bool isLocked = false)
    {
        _launchedAt = _activation = _lastTick = now;
        _locked = isLocked;
        _dayKey = DayKey.Of(now);
        if (_state.Purge(now)) StateChanged?.Invoke();
        if (NeedsRecovery(now)) StartRecovery(now);
    }

    // ── 이벤트 ────────────────────────────────────────

    /// 1초 타이머. 2초 이상 건너뛰었으면(절전 후) 그 순간부터 쓰기 시작한 것으로 본다.
    public void Tick(DateTime now)
    {
        if (now - _lastTick >= TimeSpan.FromSeconds(2)) _activation = now;
        _lastTick = now;
        SyncDay(now);
        Evaluate(now);
    }

    /// 컴퓨터를 쓰기 시작함 (잠금 해제·절전 해제·로그온).
    public void NoteActivation(DateTime now)
    {
        _activation = now;
        SyncDay(now);
        Evaluate(now);
    }

    public void NoteLocked(DateTime now)
    {
        _locked = true;
        SyncDay(now);
    }

    public void NoteUnlocked(DateTime now)
    {
        _locked = false;
        NoteActivation(now);
    }

    public void UpdateSettings(AppSettings settings, DateTime now)
    {
        var previous = _settings;
        _settings = settings;
        SyncDay(now);
        // 고정 → 유동으로 바뀌었고 오늘 기록이 없으면 사후 복구로 출근을 찾는다.
        if (previous.Mode != WorkMode.Flexible && NeedsRecovery(now)) StartRecovery(now);
        else Evaluate(now);
    }

    /// 규칙 8: 오늘 기록을 지우고 규칙 6부터 다시.
    public void RedetectToday(DateTime now)
    {
        if (_settings.Mode != WorkMode.Flexible) return;
        SyncDay(now);
        _pendingToken = null;
        if (_state.RemoveClockIn(DayKey.Of(now))) StateChanged?.Invoke();
        if (NeedsRecovery(now)) StartRecovery(now);
    }

    /// 조회 결과. result 가 null 이면 실패·타임아웃.
    public void FinishRecovery(int token, DateTime? result, DateTime now)
    {
        if (_pendingToken != token) return;   // 날이 바뀌었거나 새 요청이 대체함
        _pendingToken = null;
        if (_settings.Mode != WorkMode.Flexible) return;
        var t = result ?? Recovery.Fallback(_pendingEarliest, _launchedAt);
        Record(t, now);
    }

    // ── 출력 ──────────────────────────────────────────

    public WorkdaySnapshot Snapshot(DateTime now)
        => SnapshotCalculator.Make(_settings, now, ClockInRecord(now));

    /// 지금 띄울 알림을 돌려주고 "띄웠음"으로 표시한다(같은 날 같은 알림은 한 번만).
    public IReadOnlyList<PlannedNotification> TakeDueNotifications(DateTime now)
    {
        var day = DayKey.Of(now);
        var plans = NotificationPlanner.Plan(_settings, WorkSchedule.Resolve(_settings, now, ClockInRecord(now)));
        var due = NotificationPlanner.Due(plans, now, k => _state.IsNotified(day, k));
        if (due.Count == 0) return due;
        foreach (var p in due) _state.MarkNotified(day, p.Kind);
        StateChanged?.Invoke();
        return due;
    }

    // ── 내부 ──────────────────────────────────────────

    private bool NeedsRecovery(DateTime now)
        => _settings.Mode == WorkMode.Flexible
           && _state.GetClockIn(DayKey.Of(now)) is null
           && now >= EarliestToday(now);

    private DateTime EarliestToday(DateTime now) => now.Date + _settings.Flexible.EarliestStart.ToTimeSpan();

    private void StartRecovery(DateTime now)
    {
        var token = ++_nextToken;
        _pendingToken = token;
        _pendingEarliest = EarliestToday(now);
        RecoveryRequested?.Invoke(new RecoveryRequest(token, _pendingEarliest, now));
    }

    /// 규칙 5: 날짜가 바뀌면 새 날. 진행 중이던 복구는 지난 날 것이라 버린다.
    private void SyncDay(DateTime now)
    {
        var key = DayKey.Of(now);
        if (key == _dayKey) return;
        _dayKey = key;
        _pendingToken = null;
        if (_state.Purge(now)) StateChanged?.Invoke();
    }

    /// 규칙 2·3·4. 복구가 진행 중이면 보류(규칙 6).
    private void Evaluate(DateTime now)
    {
        if (_settings.Mode != WorkMode.Flexible || _pendingToken is not null) return;
        if (_state.GetClockIn(DayKey.Of(now)) is not null) return;
        if (ClockInRules.Decide(now, _activation, _locked, _settings.Flexible.EarliestStart) is { } t)
            Record(t, now);
    }

    /// 규칙 1: 하루 하나, 정해지면 바뀌지 않는다.
    private void Record(DateTime t, DateTime now)
    {
        if (_state.TrySetClockIn(DayKey.Of(now), t)) StateChanged?.Invoke();
    }
}
