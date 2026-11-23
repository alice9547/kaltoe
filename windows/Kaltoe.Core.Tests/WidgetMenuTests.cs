using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

/// docs/spec.md 4절 "메뉴" + 7절 3번 — 트레이와 위젯 오른쪽 클릭이 같은 항목을 쓴다.
public class WidgetMenuTests
{
    private static IReadOnlyList<MenuEntry> Menu(AppSettings s, DateTime now, DateTime? clockIn, bool visible = true, bool login = false, bool demo = false)
        => WidgetMenu.Build(SnapshotCalculator.Make(s, now, clockIn), s, visible, login, demo);

    private static string[] Texts(IReadOnlyList<MenuEntry> m) => m.Select(e => e.IsSeparator ? "-" : e.Text).ToArray();

    [Fact]
    public void Flexible_Waiting_NoClockOutNoPay()
    {
        var m = Menu(Flex(), At(8, 41), null);
        Assert.Equal(new[] { "출근 기록 없음", "-", "위젯 숨기기", "설정…", "오늘 출근 다시 감지", "로그인 시 자동 실행", "-", "칼퇴 종료" }, Texts(m));
    }

    [Fact]
    public void Fixed_Working_HasClockOut_NoRedetect()
    {
        var m = Menu(Fixed(), At(10, 0), null);
        Assert.Equal(new[] { "출근 08:30", "퇴근 17:30", "-", "위젯 숨기기", "설정…", "로그인 시 자동 실행", "-", "칼퇴 종료" }, Texts(m));
    }

    [Fact]
    public void Lunch_AddsLunchLine_AfterClockOut()
    {
        var m = Menu(WithLunch(Fixed()), At(10, 0), null);
        Assert.Equal(new[] { "출근 08:30", "퇴근 17:30", "점심 11:30–13:00" }, Texts(m).Take(3));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Done_WithOvertime_AllowanceLine_FollowsComprehensive(bool comprehensive)
    {
        var s = Flex() with { Pay = new PaySettings { Comprehensive = comprehensive } };
        var now = At(18, 28);
        var snap = SnapshotCalculator.Make(s, now, At(9, 16));
        var expected = WidgetText.AllowanceMenuTitle(snap, s.Pay);
        Assert.NotNull(expected);
        var texts = Texts(WidgetMenu.Build(snap, s, true, false, false));
        Assert.Equal(new[] { "출근 09:16", "퇴근 18:16", expected! }, texts.Take(3));
        Assert.Equal(comprehensive, expected!.Contains("(포괄)"));
    }

    [Fact]
    public void Done_WithoutOvertime_NoAllowanceLine()
    {
        var texts = Texts(Menu(Flex(), At(18, 16, 30), At(9, 16)));
        Assert.DoesNotContain(texts, t => t.StartsWith("연장수당"));
    }

    [Fact]
    public void WidgetHidden_ShowsShowLabel()
    {
        var m = Menu(Flex(), At(10, 0), At(9, 16), visible: false);
        Assert.Contains(m, e => e.Action == MenuAction.ToggleWidget && e.Text == "위젯 보이기");
    }

    [Fact]
    public void LaunchAtLogin_CheckedFollowsState()
    {
        Assert.True(Menu(Flex(), At(10, 0), At(9, 16), login: true).Single(e => e.Action == MenuAction.ToggleLaunchAtLogin).Checked);
        Assert.False(Menu(Flex(), At(10, 0), At(9, 16), login: false).Single(e => e.Action == MenuAction.ToggleLaunchAtLogin).Checked);
    }

    [Fact]
    public void Demo_DisablesSettingsRedetectLogin_ButNotToggleOrQuit()
    {
        var m = Menu(Flex(), At(10, 0), At(9, 16), demo: true);
        Assert.False(m.Single(e => e.Action == MenuAction.OpenSettings).Enabled);
        Assert.False(m.Single(e => e.Action == MenuAction.RedetectToday).Enabled);
        Assert.False(m.Single(e => e.Action == MenuAction.ToggleLaunchAtLogin).Enabled);
        Assert.True(m.Single(e => e.Action == MenuAction.ToggleWidget).Enabled);
        Assert.True(m.Single(e => e.Action == MenuAction.Quit).Enabled);
    }

    [Fact]
    public void InfoLines_AreDisabledAndActionless()
    {
        var m = Menu(Flex(), At(10, 0), At(9, 16));
        foreach (var e in m.TakeWhile(e => !e.IsSeparator))
        {
            Assert.Equal(MenuAction.None, e.Action);
            Assert.False(e.Enabled);
        }
    }

    [Fact]
    public void Notices_MatchSpec()
    {
        Assert.Equal("위젯을 숨겼습니다 — 칼퇴를 다시 실행하면 다시 보입니다", LostWidgetNotices.HiddenBody);
        Assert.Equal("칼퇴가 실행 중입니다 — 위젯을 오른쪽 클릭하면 설정을 열 수 있어요", LostWidgetNotices.FirstRunBody);
    }
}

public class LaunchSettingsFlagTests
{
    [Fact]
    public void Settings_Alone_Real() => Assert.True(LaunchOptions.Parse(new[] { "--settings" }) is { OpenSettings: true, Error: null, IsDemo: false });

    [Fact]
    public void Settings_WithDemo() => Assert.True(LaunchOptions.Parse(new[] { "--demo", "working", "--settings" }) is { OpenSettings: true, Error: null, IsDemo: true });

    [Fact]
    public void NoFlag_Default() => Assert.False(LaunchOptions.Parse(new[] { "--demo", "working" }).OpenSettings);
}

public class ClampNearestTests
{
    private static readonly PixelRect Left = new(0, 0, 1920, 1040);
    private static readonly PixelRect Right = new(1920, 0, 1920, 1040);

    [Fact]
    public void FullyOffScreen_PicksNearestArea_NotFirst()
    {
        var widget = new PixelRect(4500, 200, 320, 150);   // 오른쪽 모니터 바깥(오른쪽)
        var (x, y) = WidgetPlacement.ClampInto(widget, new[] { Left, Right }, Left);
        Assert.Equal((Right.Right - 320, 200), (x, y));
    }

    [Fact]
    public void BottomRightOffScreen_SingleScreen_PushedInside()
    {
        var widget = new PixelRect(1910, 1035, 320, 150);   // 거의 다 나감 → IsOnScreen 거짓
        Assert.False(WidgetPlacement.IsOnScreen(widget, new[] { Left }));
        var (x, y) = WidgetPlacement.ClampInto(widget, new[] { Left }, Left);
        Assert.Equal((1920 - 320, 1040 - 150), (x, y));
    }
}
