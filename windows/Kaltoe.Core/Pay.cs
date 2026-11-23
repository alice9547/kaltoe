// 연장수당 계산 — docs/spec.md 5-3절. 순수 함수. 참고용 표시(가산율·야간·휴일 가산은 계산하지 않는다).
using System.Globalization;

namespace Kaltoe.Core;

public static class PayCalc
{
    /// 단가를 비워 뒀을 때의 기준: 2026년 최저시급.
    public const int DefaultHourlyRate = 10320;
    public const int MinRate = 1;
    public const int MaxRate = 10_000_000;

    public static bool IsValidRate(int rate) => rate >= MinRate && rate <= MaxRate;

    /// 단가 입력 문자열 → 값. 비어 있으면 성공하고 amount 는 null(= 최저시급).
    /// 숫자가 아니거나 범위 밖이면 false(error 에 이유).
    public static bool TryParseRate(string? text, out int? amount, out string? error)
    {
        amount = null;
        error = null;
        if (string.IsNullOrWhiteSpace(text)) return true;
        if (!int.TryParse(text.Trim(), NumberStyles.None, CultureInfo.InvariantCulture, out var value))
        {
            error = $"연장수당 단가: {MinRate}~{MaxRate:N0} 사이의 숫자를 입력하세요(비워 두면 최저시급)";
            return false;
        }
        if (!IsValidRate(value))
        {
            error = $"연장수당 단가는 {MinRate}~{MaxRate:N0}원 사이여야 합니다";
            return false;
        }
        amount = value;
        return true;
    }

    /// 야근 분 = floor(overtime / 60초).
    public static int OvertimeMinutes(TimeSpan overtime)
        => overtime <= TimeSpan.Zero ? 0 : (int)(overtime.Ticks / TimeSpan.TicksPerMinute);

    /// 연장수당(원). 단위가 시간당이면 floor(야근 분 × 단가 / 60), 분당이면 야근 분 × 단가.
    /// 단가가 비어 있으면 시간당 10320원. 가산율은 곱하지 않는다.
    public static long Allowance(int overtimeMinutes, PaySettings pay)
    {
        if (overtimeMinutes <= 0) return 0;
        var (rate, unit) = pay.RateAmount is { } r ? (r, pay.RateUnit) : (DefaultHourlyRate, PayUnit.Hour);
        return unit == PayUnit.Minute
            ? (long)overtimeMinutes * rate
            : (long)overtimeMinutes * rate / 60;
    }

    /// 세 자리 쉼표 + `원`. 예: `3,096원`.
    public static string FormatWon(long won) => won.ToString("N0", CultureInfo.InvariantCulture) + "원";
}
