// 유동 모드 출근 규칙(docs/spec.md 2절)의 순수 판단 함수.
namespace Kaltoe.Core;

public static class ClockInRules
{
    /// 규칙 2·3·4: 지금 출근으로 기록할 시각. 기록하면 안 되는 상황이면 null.
    /// - 지금 &lt; 오늘 earliestStart → null (규칙 3)
    /// - 화면 잠금 중 → null (규칙 4)
    /// - 그 외 → max(earliestStart, 활성화 시각) (규칙 2)
    public static DateTime? Decide(DateTime now, DateTime activation, bool isLocked, TimeOnly earliestStart)
    {
        var earliest = now.Date + earliestStart.ToTimeSpan();
        if (now < earliest || isLocked) return null;
        // 활성화 시각이 미래일 수는 없다(시계 보정 방어).
        var act = activation < now ? activation : now;
        return act > earliest ? act : earliest;
    }
}
