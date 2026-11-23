// 위젯·트레이 문구 — docs/spec.md 4절. 스냅샷을 받아 문자열을 돌려주는 순수 함수.
using System.Globalization;

namespace Kaltoe.Core;

public enum LineStyle { Prompt, Command, Output, Accent, AccentBold, Success, Comment }

public sealed record TextSpan(string Text, LineStyle Style);

public sealed record TerminalLine(IReadOnlyList<TextSpan> Spans)
{
    public string Plain => string.Concat(Spans.Select(s => s.Text));
}

public static class WidgetText
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    // ── 포맷 ──

    /// HH:mm 24시간제. null 이면 "--:--".
    public static string Clock(DateTime? t) => t is { } v ? v.ToString("HH:mm", Inv) : "--:--";

    private static int WholeSeconds(TimeSpan t) => t < TimeSpan.Zero ? 0 : (int)t.TotalSeconds;

    /// `3h 12m 08s` / `12m 08s`
    public static string RemainingLong(TimeSpan span)
    {
        var t = WholeSeconds(span);
        int h = t / 3600, m = t % 3600 / 60, s = t % 60;
        return h > 0 ? string.Create(Inv, $"{h}h {m:00}m {s:00}s") : string.Create(Inv, $"{m}m {s:00}s");
    }

    /// `3h 12m` / `12m` / `42s`
    public static string RemainingShort(TimeSpan span)
    {
        var t = WholeSeconds(span);
        int h = t / 3600, m = t % 3600 / 60;
        if (h > 0) return string.Create(Inv, $"{h}h {m}m");
        if (m > 0) return string.Create(Inv, $"{m}m");
        return string.Create(Inv, $"{t}s");
    }

    /// `+0h 12m`
    public static string Overtime(TimeSpan span)
    {
        var t = WholeSeconds(span);
        return string.Create(Inv, $"+{t / 3600}h {t % 3600 / 60}m");
    }

    /// 20칸 진행률 바. 예: `[#####...............] 27%`
    public static string ProgressBar(double progress, int cells = 20)
    {
        var p = Math.Clamp(progress, 0.0, 1.0);
        const double eps = 1e-9;
        var filled = Math.Min(cells, (int)Math.Floor(p * cells + eps));
        var percent = (int)Math.Floor(p * 100 + eps);
        return string.Create(Inv, $"[{new string('#', filled)}{new string('.', cells - filled)}] {percent}%");
    }

    // ── 주석 ──

    public static string Comment(WorkdaySnapshot s)
    {
        // 점심 미사용(유효한 점심 없음)이고 지금 12:00~12:59
        if (s.LunchStart is null && s.Now.Hour == 12) return "# 점심: 일단 밥부터 먹고 생각하자";
        if (s.Progress < 0.25) return "# 아직 컴파일 중...";
        if (s.Progress < 0.50) return "# it works on my machine";
        if (s.Progress < 0.75) return "# 반 넘었다. 나머지는 미래의 내가";
        return "# 거의 다 왔다. 금요일 배포만 하지 말자";
    }

    // ── 위젯 본문 ──

    public static IReadOnlyList<TerminalLine> Lines(WorkdaySnapshot s, AppSettings settings)
    {
        static TextSpan S(string text, LineStyle style) => new(text, style);
        static TerminalLine Line(params TextSpan[] spans) => new(spans);
        static TerminalLine Cmd(string text) => Line(S("$ ", LineStyle.Prompt), S(text, LineStyle.Command));
        static TerminalLine Out(string text, LineStyle style = LineStyle.Output) => Line(S(text, style));

        var inOut = $"in {Clock(s.ClockIn)} → out {Clock(s.ClockOut)}";

        switch (s.Phase)
        {
            case WorkPhase.Waiting:
                var last = s.Target is { } target
                    ? $"# 출근 {Clock(target)} 까지 {RemainingShort(s.Remaining)}"
                    : $"# waiting for first unlock after {TimeText.Format(settings.Flexible.EarliestStart)}...";
                return new[] { Cmd("whoami"), Out("아직 출근 전인 사람"), Out(last, LineStyle.Comment) };

            case WorkPhase.BeforeLunch:
                return new[]
                {
                    Cmd("npm install 점심"),
                    Line(S("installing... ", LineStyle.Output), S(RemainingLong(s.Remaining), LineStyle.Accent), S(" left", LineStyle.Output)),
                    Out(ProgressBar(s.Progress)),
                    Out(inOut),
                    Out($"# 점심 {Clock(s.LunchStart)} · 퇴근까지 {RemainingShort(s.RemainingToClockOut)}", LineStyle.Comment),
                };

            case WorkPhase.Lunch:
                return new[]
                {
                    Cmd("sleep 점심"),
                    Line(S("점심 끝까지 ", LineStyle.Output), S(RemainingLong(s.Remaining), LineStyle.Accent)),
                    Out(ProgressBar(s.Progress)),
                    Out(inOut),
                    Out("# 지금은 밥이 P0 입니다", LineStyle.Comment),
                };

            case WorkPhase.AlmostDone:
                return new[]
                {
                    Cmd("git commit -m \"퇴근 준비\""),
                    Out($"{RemainingLong(s.Remaining)} left", LineStyle.AccentBold),
                    Out(ProgressBar(s.Progress)),
                    Out(inOut),
                    Out("# 지금 배포하면 안 됩니다", LineStyle.Comment),
                };

            case WorkPhase.Done:
                var done = new List<TerminalLine>
                {
                    Cmd("exit"),
                    Out("Process finished with exit code 0", LineStyle.Success),
                    Out($"퇴근하세요! out {Clock(s.ClockOut)}"),
                };
                if (s.Overtime >= TimeSpan.FromSeconds(60)) done.Add(Out($"# 야근 중 {Overtime(s.Overtime)}", LineStyle.Comment));
                return done;

            default: // Working
                return new[]
                {
                    Cmd("sudo 퇴근 --force"),
                    Line(S("Permission denied: ", LineStyle.Output), S(RemainingLong(s.Remaining), LineStyle.Accent), S(" left", LineStyle.Output)),
                    Out(ProgressBar(s.Progress)),
                    Out(inOut),
                    Out(Comment(s), LineStyle.Comment),
                };
        }
    }

    // ── 트레이 ──

    /// 트레이 툴팁 한 줄(docs/spec.md 4절).
    public static string TrayLine(WorkdaySnapshot s) => s.Phase switch
    {
        WorkPhase.Waiting => "출근 전",
        WorkPhase.BeforeLunch => $"점심까지 {RemainingShort(s.Remaining)}",
        WorkPhase.Lunch => $"점심 끝까지 {RemainingShort(s.Remaining)}",
        WorkPhase.Done => s.Overtime >= TimeSpan.FromSeconds(60)
            ? string.Create(Inv, $"퇴근! +{(int)s.Overtime.TotalMinutes}m") : "퇴근!",
        _ => $"{Clock(s.ClockOut)}까지 {RemainingShort(s.Remaining)}",
    };

    /// NotifyIcon.Text 는 63자 제한.
    public static string Truncate(string text, int max = 63) => text.Length <= max ? text : text[..max];

    // ── 메뉴 ──

    public static string ClockInMenuTitle(WorkdaySnapshot s)
        => s.ClockIn is null ? "출근 기록 없음" : $"출근 {Clock(s.ClockIn)}";

    /// 출근이 없으면 null(항목 생략).
    public static string? ClockOutMenuTitle(WorkdaySnapshot s)
        => s.ClockOut is null ? null : $"퇴근 {Clock(s.ClockOut)}";

    /// 점심 사용 중일 때만. 설정 값 그대로.
    public static string? LunchMenuTitle(AppSettings s)
        => s.Lunch.Enabled ? $"점심 {TimeText.Format(s.Lunch.Start)}–{TimeText.Format(s.Lunch.End)}" : null;

    // ── 설정 창 미리보기 ──

    /// `출근 08:30 · 점심 11:30–13:00 · 퇴근 17:30`. 유동에서 오늘 기록이 없으면 출근·퇴근은 `—`.
    public static string Preview(AppSettings s, DateTime today, DateTime? flexibleClockIn)
    {
        var sch = WorkSchedule.Resolve(s, today, flexibleClockIn);
        string T(DateTime? t) => t is { } v ? Clock(v) : "—";
        var parts = new List<string> { $"출근 {T(sch.ClockIn)}" };
        if (s.Lunch.Enabled) parts.Add($"점심 {TimeText.Format(s.Lunch.Start)}–{TimeText.Format(s.Lunch.End)}");
        parts.Add($"퇴근 {T(sch.ClockOut)}");
        return string.Join(" · ", parts);
    }
}
