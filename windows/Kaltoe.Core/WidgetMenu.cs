// 트레이 메뉴 / 위젯 오른쪽 클릭 메뉴의 항목 목록 — docs/spec.md 4절 "메뉴", 7절 3번. 순수 함수.
namespace Kaltoe.Core;

public enum MenuAction { None, ToggleWidget, OpenSettings, RedetectToday, ToggleLaunchAtLogin, Quit }

/// 메뉴 한 줄. Separator 면 Text 는 비어 있다. Action 이 None 이고 구분선이 아니면 정보 줄(비활성).
public sealed record MenuEntry(string Text, MenuAction Action = MenuAction.None, bool Enabled = true, bool Checked = false, bool IsSeparator = false)
{
    public static MenuEntry Separator { get; } = new("", IsSeparator: true, Enabled: false);
}

public static class WidgetMenu
{
    /// 단계(출근·퇴근·연장수당 줄)·모드(유동일 때만 출근 다시 감지)·점심 사용 여부·포괄 여부(연장수당 문구)에 따른 항목.
    public static IReadOnlyList<MenuEntry> Build(WorkdaySnapshot snapshot, AppSettings settings, bool widgetVisible, bool launchAtLogin, bool isDemo)
    {
        var list = new List<MenuEntry>();
        void Info(string text) => list.Add(new MenuEntry(text, Enabled: false));

        Info(WidgetText.ClockInMenuTitle(snapshot));
        if (WidgetText.ClockOutMenuTitle(snapshot) is { } outTitle) Info(outTitle);
        if (WidgetText.AllowanceMenuTitle(snapshot, settings.Pay) is { } payTitle) Info(payTitle);
        if (WidgetText.LunchMenuTitle(settings) is { } lunchTitle) Info(lunchTitle);
        list.Add(MenuEntry.Separator);

        list.Add(new MenuEntry(widgetVisible ? "위젯 숨기기" : "위젯 보이기", MenuAction.ToggleWidget));
        list.Add(new MenuEntry("설정…", MenuAction.OpenSettings, Enabled: !isDemo));
        if (settings.Mode == WorkMode.Flexible)
            list.Add(new MenuEntry("오늘 출근 다시 감지", MenuAction.RedetectToday, Enabled: !isDemo));
        list.Add(new MenuEntry("로그인 시 자동 실행", MenuAction.ToggleLaunchAtLogin, Enabled: !isDemo, Checked: launchAtLogin));
        list.Add(MenuEntry.Separator);
        list.Add(new MenuEntry("칼퇴 종료", MenuAction.Quit));
        return list;
    }
}

/// 트레이 풍선 알림 문구 — docs/spec.md 7절 5·6번.
public static class LostWidgetNotices
{
    public const string Title = "칼퇴";
    public const string HiddenBody = "위젯을 숨겼습니다 — 칼퇴를 다시 실행하면 다시 보입니다";
    public const string FirstRunBody = "칼퇴가 실행 중입니다 — 위젯을 오른쪽 클릭하면 설정을 열 수 있어요";
}
