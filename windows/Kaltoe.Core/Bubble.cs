// 말풍선 모양 — docs/spec.md 5-2절. 문구(분 단위 올림), 계단 모양 윤곽, 마스코트 외곽선 칸 계산. 모두 순수 함수.
namespace Kaltoe.Core;

public static class BubbleText
{
    /// 분 단위 올림. 0 이하 → 0, 0초 초과 → 1분, 60초 → 1분, 61초 → 2분.
    public static int CeilMinutes(TimeSpan span)
    {
        if (span <= TimeSpan.Zero) return 0;
        return (int)((span.Ticks + TimeSpan.TicksPerMinute - 1) / TimeSpan.TicksPerMinute);
    }

    /// 분 단위 내림(야근).
    public static int FloorMinutes(TimeSpan span) => span <= TimeSpan.Zero ? 0 : (int)(span.Ticks / TimeSpan.TicksPerMinute);

    /// 야근 1분 이상이면 `야근 12분 · +3,096원` / 포괄이면 `야근 12분 · 0원 (포괄)`, 아니면 `퇴근하세요!`.
    private static string DoneLine(WorkdaySnapshot s, PaySettings pay)
    {
        var minutes = FloorMinutes(s.Overtime);
        if (minutes < 1) return "퇴근하세요!";
        return pay.Comprehensive
            ? $"야근 {minutes}분 · {PayCalc.FormatWon(0)} (포괄)"
            : $"야근 {minutes}분 · +{PayCalc.FormatWon(PayCalc.Allowance(minutes, pay))}";
    }

    public static string Line(WorkdaySnapshot s, PaySettings? pay = null) => s.Phase switch
    {
        WorkPhase.Waiting => s.Target is null ? "출근 전…" : $"출근 {CeilMinutes(s.Remaining)}분 전",
        WorkPhase.BeforeLunch => $"점심 {CeilMinutes(s.Remaining)}분 전",
        WorkPhase.Lunch => $"점심 끝 {CeilMinutes(s.Remaining)}분 전",
        WorkPhase.AlmostDone => $"퇴근 {CeilMinutes(s.Remaining)}분 전!",
        WorkPhase.Done => DoneLine(s, pay ?? new PaySettings()),
        _ => $"퇴근 {CeilMinutes(s.Remaining)}분 전",   // Working
    };
}

/// 말풍선 윤곽: 둥근 사각을 step 픽셀 계단으로 만든 닫힌 다각형(시계 방향). 꼬리는 아래쪽 오른쪽에 붙은 계단 삼각형.
public static class BubbleShape
{
    public const int CornerSteps = 3;
    public const int TailSteps = 3;

    /// <param name="width">몸통 폭</param>
    /// <param name="height">몸통 높이(꼬리 제외)</param>
    /// <param name="step">계단 한 칸(px). 기본 글자 크기에서 2.</param>
    /// <returns>꼬리를 포함한 윤곽 점. 좌표 범위는 x 0..width, y 0..height + 꼬리 높이.</returns>
    public static IReadOnlyList<(int X, int Y)> Outline(int width, int height, int step)
    {
        var c = CornerSteps * step;

        // 왼쪽 위 모서리 계단(왼쪽 변 → 위쪽 변): (0,c) (s,c) (s,c-s) ... (c,0). 나머지 모서리는 이것을 뒤집어 만든다.
        var tl = new List<(int X, int Y)>();
        for (var i = 0; i < CornerSteps; i++)
        {
            tl.Add((i * step, c - i * step));
            tl.Add(((i + 1) * step, c - i * step));
        }
        tl.Add((c, 0));

        var pts = new List<(int X, int Y)>();
        pts.AddRange(tl);                                                                    // 왼쪽 위
        pts.AddRange(Enumerable.Reverse(tl).Select(p => (width - p.X, p.Y)));                // 오른쪽 위
        pts.AddRange(tl.Select(p => (width - p.X, height - p.Y)));                           // 오른쪽 아래

        // 꼬리: 아래 변을 오른쪽→왼쪽으로 가다가 오른쪽 가장자리에서 아래로 내려갔다 계단으로 올라온다.
        var tailRight = width - c - step;
        var tailLeft = tailRight - TailSteps * step;
        pts.Add((tailRight, height));
        for (var i = TailSteps; i >= 1; i--)
        {
            pts.Add((tailLeft + i * step, height + i * step));
            pts.Add((tailLeft + (i - 1) * step, height + i * step));
        }
        pts.Add((tailLeft, height));

        pts.AddRange(Enumerable.Reverse(tl).Select(p => (p.X, height - p.Y)));              // 왼쪽 아래

        // 연속 중복점 제거
        var result = new List<(int X, int Y)>();
        foreach (var p in pts)
            if (result.Count == 0 || result[^1] != p) result.Add(p);
        if (result.Count > 1 && result[0] == result[^1]) result.RemoveAt(result.Count - 1);
        return result;
    }

    public static int TailHeight(int step) => TailSteps * step;

    /// 몸통이 모서리·꼬리를 담을 수 있는 최소 크기.
    public static (int Width, int Height) MinBody(int step)
        => (2 * CornerSteps * step + (TailSteps + 1) * step, 2 * CornerSteps * step);
}

public static class MascotOutline
{
    public static readonly uint Color = 0x3A3A44;

    /// 불투명 칸의 상하좌우 이웃 중 투명한 칸(격자 바깥 1칸 여유 포함: x -1..width, y -1..height).
    /// isOpaque 는 격자 범위 밖에서 호출되지 않는다(범위 밖은 투명으로 본다).
    public static IReadOnlyList<(int X, int Y)> Cells(int width, int height, Func<int, int, bool> isOpaque)
    {
        bool Opaque(int x, int y) => x >= 0 && x < width && y >= 0 && y < height && isOpaque(x, y);
        var result = new List<(int X, int Y)>();
        for (var y = -1; y <= height; y++)
        for (var x = -1; x <= width; x++)
        {
            if (Opaque(x, y)) continue;
            if (Opaque(x - 1, y) || Opaque(x + 1, y) || Opaque(x, y - 1) || Opaque(x, y + 1))
                result.Add((x, y));
        }
        return result;
    }
}
