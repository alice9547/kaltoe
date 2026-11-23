// 마스코트 재생 순서 — docs/spec.md 6절 표. 프레임 데이터는 앱의 MascotData 가 가지고 있고, 여기서는 "어느 프레임을 언제" 만 계산한다.
namespace Kaltoe.Core;

public enum MascotMood { Sleep, Idle, Eat, Sparkle, Dance }

public enum MascotOverlay { None, Zzz, Confetti }

public static class MascotFrames
{
    public const string Idle = "idle", Blink = "blink", Breathe = "breathe", Sleep = "sleep",
        Eat1 = "eat1", Eat2 = "eat2", Sparkle = "sparkle", Hop = "hop", DanceL = "danceL", DanceR = "danceR";

    public static readonly IReadOnlyList<string> All = new[]
        { Idle, Blink, Breathe, Sleep, Eat1, Eat2, Sparkle, Hop, DanceL, DanceR };
}

/// <param name="Frame">프레임 이름(spec 6절 10개 중 하나)</param>
/// <param name="Overlay">프레임 위에 얹는 장식</param>
/// <param name="OverlayStep">장식 애니메이션 단계(0부터 계속 증가)</param>
/// <param name="JumpRows">점프로 위로 올라간 칸 수(0 이상, 격자 높이에 비례)</param>
public sealed record MascotPose(string Frame, MascotOverlay Overlay, int OverlayStep, int JumpRows);

public static class MascotPlayback
{
    public static MascotMood MoodOf(WorkPhase phase) => phase switch
    {
        WorkPhase.Waiting => MascotMood.Sleep,
        WorkPhase.Lunch => MascotMood.Eat,
        WorkPhase.AlmostDone => MascotMood.Sparkle,
        WorkPhase.Done => MascotMood.Dance,
        _ => MascotMood.Idle,   // BeforeLunch, Working
    };

    public const double ZStepSeconds = 0.5;
    public const double ConfettiStepSeconds = 0.4;
    public const double JumpStepSeconds = 0.1;
    private static readonly int[] JumpTable = { 1, 2, 3, 3, 2, 1 };

    /// 격자 16 기준 점프 높이 3칸. 격자가 커지면 비례.
    public static int JumpScale(int gridHeight) => Math.Max(1, (int)Math.Round(gridHeight / 16.0, MidpointRounding.AwayFromZero));

    /// 점프 때 위로 올라갈 수 있는 최대 칸 수(위쪽 여유 공간).
    public static int JumpHeadroomRows(int gridHeight) => JumpTable.Max() * JumpScale(gridHeight);

    public static int JumpRows(double? secondsSinceJump, int gridHeight)
    {
        if (secondsSinceJump is not { } s || s < 0) return 0;
        var step = Step(s, JumpStepSeconds);
        return step < JumpTable.Length ? JumpTable[step] * JumpScale(gridHeight) : 0;
    }

    /// <param name="elapsedSeconds">재생 시작 후 지난 시간(초)</param>
    /// <param name="secondsSinceJump">마지막 클릭 후 지난 시간. 점프한 적 없으면 null</param>
    public static MascotPose Resolve(MascotMood mood, double elapsedSeconds, double? secondsSinceJump, int gridHeight)
    {
        var t = Math.Max(0, elapsedSeconds);
        var jump = JumpRows(secondsSinceJump, gridHeight);
        switch (mood)
        {
            case MascotMood.Sleep:
                return new(MascotFrames.Sleep, MascotOverlay.Zzz, Step(t, ZStepSeconds), jump);
            case MascotMood.Eat:
                return new(Alternate(t, 0.4, MascotFrames.Eat1, MascotFrames.Eat2), MascotOverlay.None, 0, jump);
            case MascotMood.Sparkle:
                return new(Alternate(t, 0.3, MascotFrames.Sparkle, MascotFrames.Hop), MascotOverlay.None, 0, jump);
            case MascotMood.Dance:
                return new(Alternate(t, 0.4, MascotFrames.DanceL, MascotFrames.DanceR),
                    MascotOverlay.Confetti, Step(t, ConfettiStepSeconds), jump);
            default:
                // idle↔breathe 0.6초 간격, 4초마다 blink 0.15초(주기의 끝 0.15초)
                var inCycle = t % 4.0;
                if (inCycle >= 4.0 - 0.15) return new(MascotFrames.Blink, MascotOverlay.None, 0, jump);
                return new(Alternate(t, 0.6, MascotFrames.Idle, MascotFrames.Breathe), MascotOverlay.None, 0, jump);
        }
    }

    private static int Step(double seconds, double period) => (int)Math.Floor(seconds / period + 1e-9);

    private static string Alternate(double seconds, double period, string a, string b)
        => Step(seconds, period) % 2 == 0 ? a : b;
}
