using Kaltoe.Core;
using static Kaltoe.Core.Tests.T;

namespace Kaltoe.Core.Tests;

public class BubbleTextTests
{
    private static WorkdaySnapshot Snap(AppSettings s, DateTime? clockIn, DateTime now) => SnapshotCalculator.Make(s, now, clockIn);
    private static string B(AppSettings s, DateTime? clockIn, DateTime now) => BubbleText.Line(Snap(s, clockIn, now), s.Pay);

    // ── 올림 경계 ──

    [Theory]
    [InlineData(0, 0)]
    [InlineData(-5, 0)]
    [InlineData(1, 1)]      // 0초 초과 → 1분
    [InlineData(30, 1)]
    [InlineData(59, 1)]
    [InlineData(60, 1)]     // 60초 → 1분
    [InlineData(61, 2)]     // 61초 → 2분
    [InlineData(120, 2)]
    [InlineData(121, 3)]
    [InlineData(176 * 60 + 1, 177)]   // 176분 01초 → 177분
    public void CeilMinutes(int seconds, int minutes)
        => Assert.Equal(minutes, BubbleText.CeilMinutes(TimeSpan.FromSeconds(seconds)));

    [Fact]
    public void CeilMinutes_SubSecond_IsOne() => Assert.Equal(1, BubbleText.CeilMinutes(TimeSpan.FromMilliseconds(1)));

    [Theory]
    [InlineData(59, 0)]
    [InlineData(60, 1)]
    [InlineData(12 * 60 + 59, 12)]
    public void FloorMinutes(int seconds, int minutes)
        => Assert.Equal(minutes, BubbleText.FloorMinutes(TimeSpan.FromSeconds(seconds)));

    // ── 표의 모든 행 ──

    [Fact]
    public void Waiting_Flexible() => Assert.Equal("출근 전…", B(Flex(), null, At(8, 41)));

    [Fact]
    public void Waiting_Fixed() => Assert.Equal("출근 12분 전", B(Fixed(), null, At(8, 18)));

    [Fact]
    public void Waiting_Fixed_RoundsUp()
    {
        Assert.Equal("출근 1분 전", B(Fixed(), null, At(8, 29, 1)));
        Assert.Equal("출근 1분 전", B(Fixed(), null, At(8, 29, 0)));
        Assert.Equal("출근 2분 전", B(Fixed(), null, At(8, 28, 59)));
    }

    [Fact]
    public void BeforeLunch() => Assert.Equal("점심 43분 전", B(WithLunch(Fixed()), null, At(10, 47, 52)));   // 42m08s → 43분

    [Fact]
    public void BeforeLunch_ExactMinutes() => Assert.Equal("점심 42분 전", B(WithLunch(Fixed()), null, At(10, 48, 0)));

    [Fact]
    public void Lunch() => Assert.Equal("점심 끝 19분 전", B(WithLunch(Fixed()), null, At(12, 41, 52)));    // 18m08s → 19분

    [Fact]
    public void Working() => Assert.Equal("퇴근 177분 전", B(Flex(), At(9, 16), At(15, 19, 59)));            // 176m01s → 177분

    [Fact]
    public void Working_Exact() => Assert.Equal("퇴근 176분 전", B(Flex(), At(9, 16), At(15, 20, 0)));

    [Fact]
    public void AlmostDone() => Assert.Equal("퇴근 9분 전!", B(Flex(), At(9, 16), At(18, 7, 0)));

    [Fact]
    public void AlmostDone_9m05s_RoundsUpTo10() => Assert.Equal("퇴근 10분 전!", B(Flex(), At(9, 16), At(18, 6, 55)));

    [Fact]
    public void AlmostDone_RoundsUp_ToTen_AtBoundary() => Assert.Equal("퇴근 10분 전!", B(Flex(), At(9, 16), At(18, 6, 0)));

    [Fact]
    public void AlmostDone_LastMinute() => Assert.Equal("퇴근 1분 전!", B(Flex(), At(9, 16), At(18, 15, 30)));

    [Fact]
    public void Done() => Assert.Equal("퇴근하세요!", B(Flex(), At(9, 16), At(18, 16, 30)));

    [Fact]
    public void Done_Overtime_FloorMinutes()
    {
        Assert.Equal("퇴근하세요!", B(Flex(), At(9, 16), At(18, 16, 59)));
        Assert.Equal("야근 1분 · 0원 (포괄)", B(Flex(), At(9, 16), At(18, 17, 0)));
        Assert.Equal("야근 12분 · 0원 (포괄)", B(Flex(), At(9, 16), At(18, 28, 59)));
    }
}

public class BubbleShapeTests
{
    [Theory]
    [InlineData(100, 30, 2)]
    [InlineData(136, 28, 2)]
    [InlineData(200, 50, 3)]
    [InlineData(80, 20, 1)]
    public void Outline_IsClosedAxisAlignedAndInBounds(int w, int h, int step)
    {
        var pts = BubbleShape.Outline(w, h, step);
        var tail = BubbleShape.TailHeight(step);
        for (var i = 0; i < pts.Count; i++)
        {
            var a = pts[i];
            var b = pts[(i + 1) % pts.Count];   // 마지막→처음도 변이다(닫힘)
            Assert.True(a.X == b.X ^ a.Y == b.Y, $"{a}→{b} 는 축에 나란한 한 변이어야 함");
            Assert.InRange(a.X, 0, w);
            Assert.InRange(a.Y, 0, h + tail);
        }
        Assert.Equal(0, pts.Min(p => p.X));
        Assert.Equal(w, pts.Max(p => p.X));
        Assert.Equal(0, pts.Min(p => p.Y));
        Assert.Equal(h + tail, pts.Max(p => p.Y));
    }

    [Fact]
    public void Outline_CornersAreStaircases_NoPointAtTheSharpCorner()
    {
        var pts = BubbleShape.Outline(100, 30, 2);
        Assert.DoesNotContain((0, 0), pts);
        Assert.DoesNotContain((100, 0), pts);
        Assert.DoesNotContain((100, 30), pts);
        Assert.DoesNotContain((0, 30), pts);
        Assert.Contains((0, 6), pts);
        Assert.Contains((6, 0), pts);
        Assert.Contains((94, 0), pts);
        Assert.Contains((100, 6), pts);
    }

    [Fact]
    public void Outline_TailIsAtBottomRight_PointingDownRight()
    {
        var pts = BubbleShape.Outline(100, 30, 2);
        var below = pts.Where(p => p.Y > 30).ToList();
        Assert.NotEmpty(below);
        Assert.True(below.Min(p => p.X) > 50);          // 오른쪽 절반
        Assert.True(below.Max(p => p.X) < 100 - 6);     // 모서리 계단 안쪽
        // 꼬리 끝(가장 아래)은 꼬리 가장 오른쪽에 있다.
        var maxX = below.Max(p => p.X);
        Assert.Contains((maxX, 36), pts);
    }

    [Fact]
    public void Outline_BodyOnlyAtMinSize_StillValid()
    {
        var (w, h) = BubbleShape.MinBody(2);
        var pts = BubbleShape.Outline(w, h, 2);
        Assert.True(pts.Count > 20);
    }

    [Fact]
    public void Outline_Symmetric_TopCorners()
    {
        var pts = BubbleShape.Outline(100, 30, 2).Where(p => p.Y <= 6).ToHashSet();
        foreach (var p in pts.ToList()) Assert.Contains((100 - p.X, p.Y), pts);
    }
}

public class MascotOutlineTests
{
    private static string[] Grid(params string[] rows) => rows;
    private static bool Op(string[] g, int x, int y) => g[y][x] != '.';

    [Fact]
    public void SinglePixel_GivesFourNeighbors()
    {
        var g = Grid("...", ".W.", "...");
        var cells = MascotOutline.Cells(3, 3, (x, y) => Op(g, x, y));
        Assert.Equal(new[] { (1, 0), (0, 1), (2, 1), (1, 2) }.OrderBy(c => c).ToArray(), cells.OrderBy(c => c).ToArray());
    }

    [Fact]
    public void DiagonalsAreNotOutlined()
    {
        var g = Grid("...", ".W.", "...");
        var cells = MascotOutline.Cells(3, 3, (x, y) => Op(g, x, y));
        Assert.DoesNotContain((0, 0), cells);
        Assert.DoesNotContain((2, 2), cells);
    }

    [Fact]
    public void OpaqueCells_AreNeverOutlineCells()
    {
        var g = Grid("WW", "WW");
        var cells = MascotOutline.Cells(2, 2, (x, y) => Op(g, x, y));
        Assert.All(cells, c => Assert.False(c.X >= 0 && c.X < 2 && c.Y >= 0 && c.Y < 2));
    }

    [Fact]
    public void EdgePixels_OutlineOutsideTheGrid_OneCellMargin()
    {
        var g = Grid("W");
        var cells = MascotOutline.Cells(1, 1, (x, y) => Op(g, x, y));
        Assert.Equal(new[] { (-1, 0), (0, -1), (0, 1), (1, 0) }.OrderBy(c => c).ToArray(), cells.OrderBy(c => c).ToArray());
    }

    [Fact]
    public void AllCells_WithinMarginRange()
    {
        var g = Grid("WWW", "W.W", "WWW");
        var cells = MascotOutline.Cells(3, 3, (x, y) => Op(g, x, y));
        Assert.All(cells, c => { Assert.InRange(c.X, -1, 3); Assert.InRange(c.Y, -1, 3); });
        Assert.Contains((1, 1), cells);   // 속이 빈 구멍도 이웃이 불투명이면 칠함
    }

    [Fact]
    public void Empty_GivesNothing() => Assert.Empty(MascotOutline.Cells(4, 4, (_, _) => false));

    [Fact]
    public void Ring_CountIsPerimeter()
    {
        var g = Grid("WW", "WW");
        Assert.Equal(8, MascotOutline.Cells(2, 2, (x, y) => Op(g, x, y)).Count);
    }
}

public class StyleSettingsTests
{
    [Fact]
    public void Style_DefaultTerminal_AndJsonNames()
    {
        Assert.Equal(WidgetStyle.Terminal, AppSettings.Default.Widget.Style);
        var json = new AppFile { Settings = AppSettings.Default with { Widget = new WidgetSettings { Style = WidgetStyle.Bubble } } }.ToJson();
        Assert.Contains("\"style\": \"bubble\"", json);
        Assert.Equal(WidgetStyle.Bubble, AppFile.Parse(json).Settings.Widget.Style);
        Assert.Contains("\"style\": \"terminal\"", new AppFile().ToJson());
    }

    [Fact]
    public void Position_IsStoredPerStyle()
    {
        var f = new AppFile { Widget = new WidgetState { X = 10, Y = 20, BubbleRight = 900, BubbleBottom = 700 } };
        var back = AppFile.Parse(f.ToJson());
        Assert.Equal(f.Widget, back.Widget);
    }

    [Fact]
    public void BubbleMascot_BaseIs60_TerminalIs48()
    {
        Assert.Equal(4, WidgetSizing.MascotCell(16, 16, 12, WidgetStyle.Bubble));    // 60/16=3.75 → 4
        Assert.Equal(3, WidgetSizing.MascotCell(16, 16, 12, WidgetStyle.Terminal));
        Assert.Equal(3, WidgetSizing.MascotCell(24, 24, 12, WidgetStyle.Bubble));    // 2.5 → 3
        Assert.Equal(6, WidgetSizing.MascotCell(16, 16, 20, WidgetStyle.Bubble));    // 100/16=6.25 → 6
    }

    [Fact]
    public void Demo_AcceptsStyleAndFontSize()
    {
        var d = DemoScenario.Create("working", Day, new WidgetSettings { Style = WidgetStyle.Bubble, FontSize = 20 })!;
        Assert.Equal(WidgetStyle.Bubble, d.Settings.Widget.Style);
        Assert.Equal(20, d.Settings.Widget.FontSize);
    }
}

public class LaunchOptionsTests
{
    [Fact]
    public void NoArgs_Normal()
    {
        var o = LaunchOptions.Parse(Array.Empty<string>());
        Assert.False(o.IsDemo);
        Assert.Null(o.Error);
    }

    [Fact]
    public void Demo_WithStyleAndFont()
    {
        var o = LaunchOptions.Parse(new[] { "--demo", "Working", "--style", "bubble", "--font-size", "20" });
        Assert.Equal("working", o.DemoName);
        Assert.Equal(WidgetStyle.Bubble, o.Style);
        Assert.Equal(20, o.FontSize);
        Assert.Null(o.Error);
    }

    [Theory]
    [InlineData("--demo")]
    [InlineData("--demo", "nope")]
    [InlineData("--demo", "done", "--style", "x")]
    [InlineData("--demo", "done", "--font-size", "7")]
    [InlineData("--demo", "done", "--font-size", "abc")]
    [InlineData("--style", "bubble")]
    [InlineData("--wat")]
    public void Invalid_GivesError(params string[] args) => Assert.NotNull(LaunchOptions.Parse(args).Error);
}
