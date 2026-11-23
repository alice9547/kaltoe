// 설정 모델 — docs/spec.md 1절. 불변 record + with 로 바꾼다.
// JSON 키는 camelCase, 시각은 "HH:mm" 문자열, 모드는 문자열.
namespace Kaltoe.Core;

public enum WorkMode { Flexible, Fixed }

public sealed record FlexibleSettings
{
    public TimeOnly EarliestStart { get; init; } = new(9, 0);
    public int WorkMinutes { get; init; } = 540;
}

public sealed record FixedSettings
{
    public TimeOnly Start { get; init; } = new(8, 30);
    public TimeOnly End { get; init; } = new(17, 30);
}

public sealed record LunchSettings
{
    public bool Enabled { get; init; } = false;
    public TimeOnly Start { get; init; } = new(11, 30);
    public TimeOnly End { get; init; } = new(13, 0);
}

public sealed record NotifySettings
{
    public bool Lunch { get; init; } = true;
    public bool BeforeEnd { get; init; } = true;
    public bool End { get; init; } = true;
}

public enum WidgetStyle { Terminal, Bubble }

public sealed record WidgetSettings
{
    /// 위젯 모양. 터미널 창 / 말풍선(docs/spec.md 5-2절).
    public WidgetStyle Style { get; init; } = WidgetStyle.Terminal;

    /// 위젯 글자 크기(px). 허용 8~32. 위젯 전체 비율 = FontSize / 12.
    public int FontSize { get; init; } = WidgetSizing.DefaultFontSize;
}

public sealed record AppSettings
{
    public WorkMode Mode { get; init; } = WorkMode.Flexible;
    public FlexibleSettings Flexible { get; init; } = new();
    public FixedSettings Fixed { get; init; } = new();
    public LunchSettings Lunch { get; init; } = new();
    public NotifySettings Notify { get; init; } = new();
    public WidgetSettings Widget { get; init; } = new();

    public static AppSettings Default => new();
}

public static class SettingsLimits
{
    public const int MinWorkMinutes = 60;
    public const int MaxWorkMinutes = 960;
}

/// 설정 검증. 오류가 없으면 null, 있으면 사용자에게 보여 줄 첫 이유.
/// 현재 모드와 무관한 값(예: 유동 모드일 때 고정 시각)은 화면에 보이지 않으므로 검사하지 않는다.
public static class SettingsValidator
{
    public static string? Validate(AppSettings s)
    {
        if (s.Mode == WorkMode.Flexible)
        {
            var m = s.Flexible.WorkMinutes;
            if (m < SettingsLimits.MinWorkMinutes || m > SettingsLimits.MaxWorkMinutes)
                return "근무 시간은 1시간(60분)에서 16시간(960분) 사이여야 합니다";
        }
        else if (s.Fixed.End <= s.Fixed.Start)
        {
            return "퇴근 시각은 출근 시각보다 뒤여야 합니다";
        }

        if (s.Lunch.Enabled && s.Lunch.End <= s.Lunch.Start)
            return "점심 끝 시각은 시작 시각보다 뒤여야 합니다";

        if (!WidgetSizing.IsValidFontSize(s.Widget.FontSize))
            return $"글자 크기는 {WidgetSizing.MinFontSize}~{WidgetSizing.MaxFontSize}px 사이의 정수여야 합니다";

        return null;
    }
}

/// "HH:mm" 입력·출력.
public static class TimeText
{
    public static string Format(TimeOnly t) => t.ToString("HH:mm", System.Globalization.CultureInfo.InvariantCulture);

    /// "09:00", "9:00" 허용. "24:00"·"9"·"09:60" 등은 거부.
    public static bool TryParse(string? text, out TimeOnly value)
    {
        value = default;
        var m = System.Text.RegularExpressions.Regex.Match(text?.Trim() ?? "", @"^([0-9]{1,2}):([0-9]{2})$");
        if (!m.Success) return false;
        int h = int.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
        int min = int.Parse(m.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture);
        if (h > 23 || min > 59) return false;
        value = new TimeOnly(h, min);
        return true;
    }
}

/// 위젯 글자 크기 → 전체 비율·창 크기·마스코트 배율 (docs/spec.md 5-1절).
public static class WidgetSizing
{
    public const int DefaultFontSize = 12;
    public const int MinFontSize = 8;
    public const int MaxFontSize = 32;

    /// 기본 모양(글자 12px)의 창 크기.
    public const int BaseWidth = 320;
    public const int BaseHeight = 150;

    /// 마스코트 기본 표시 크기(비율 1일 때 긴 변의 픽셀 수). 터미널 48, 말풍선 약 60.
    public const int MascotBaseExtent = 48;
    public const int BubbleMascotBaseExtent = 60;

    public static int MascotBaseExtentOf(WidgetStyle style)
        => style == WidgetStyle.Bubble ? BubbleMascotBaseExtent : MascotBaseExtent;

    public static bool IsValidFontSize(int px) => px >= MinFontSize && px <= MaxFontSize;

    /// 글자 크기 입력 문자열 → 값. 숫자가 아니거나 범위 밖이면 false(error 에 이유).
    public static bool TryParseFontSize(string? text, out int px, out string? error)
    {
        px = 0;
        if (!int.TryParse(text?.Trim(), System.Globalization.NumberStyles.None,
                System.Globalization.CultureInfo.InvariantCulture, out px))
        {
            error = $"글자 크기: {MinFontSize}~{MaxFontSize} 사이의 숫자를 입력하세요";
            return false;
        }
        if (!IsValidFontSize(px))
        {
            error = $"글자 크기는 {MinFontSize}~{MaxFontSize}px 사이여야 합니다";
            return false;
        }
        error = null;
        return true;
    }

    /// 위젯 전체 비율.
    public static double Factor(int fontSize) => fontSize / (double)DefaultFontSize;

    /// 창 크기(DIP, 정수로 반올림).
    public static (int Width, int Height) WindowSize(int fontSize)
        => ((int)Math.Round(BaseWidth * Factor(fontSize)), (int)Math.Round(BaseHeight * Factor(fontSize)));

    /// 마스코트 한 칸의 정수 픽셀 크기(최종 화면 기준).
    /// "기본 표시 크기 × 비율" 에 가장 가까운 정수 배율. 최소 1.
    public static int MascotCell(int gridWidth, int gridHeight, int fontSize, WidgetStyle style = WidgetStyle.Terminal)
    {
        var dim = Math.Max(1, Math.Max(gridWidth, gridHeight));
        var target = MascotBaseExtentOf(style) * Factor(fontSize) / dim;
        return Math.Max(1, (int)Math.Round(target, MidpointRounding.AwayFromZero));
    }
}
