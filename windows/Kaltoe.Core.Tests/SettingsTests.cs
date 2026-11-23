using Kaltoe.Core;

namespace Kaltoe.Core.Tests;

public class SettingsTests
{
    [Fact]
    public void Defaults_MatchSpec()
    {
        var s = AppSettings.Default;
        Assert.Equal(WorkMode.Flexible, s.Mode);
        Assert.Equal(new TimeOnly(9, 0), s.Flexible.EarliestStart);
        Assert.Equal(540, s.Flexible.WorkMinutes);
        Assert.Equal(new TimeOnly(8, 30), s.Fixed.Start);
        Assert.Equal(new TimeOnly(17, 30), s.Fixed.End);
        Assert.False(s.Lunch.Enabled);
        Assert.Equal(new TimeOnly(11, 30), s.Lunch.Start);
        Assert.Equal(new TimeOnly(13, 0), s.Lunch.End);
        Assert.True(s.Notify.Lunch);
        Assert.True(s.Notify.BeforeEnd);
        Assert.True(s.Notify.End);
        Assert.Equal(12, s.Widget.FontSize);
        Assert.Null(SettingsValidator.Validate(s));
    }

    [Theory]
    [InlineData(60, true)]
    [InlineData(959, true)]
    [InlineData(960, true)]
    [InlineData(59, false)]
    [InlineData(961, false)]
    [InlineData(0, false)]
    [InlineData(-5, false)]
    public void WorkMinutes_Range(int minutes, bool ok)
    {
        var s = T.Flex(minutes: minutes);
        Assert.Equal(ok, SettingsValidator.Validate(s) is null);
    }

    [Fact]
    public void Fixed_EndMustBeAfterStart()
    {
        Assert.Null(SettingsValidator.Validate(T.Fixed(8, 30, 8, 31)));
        Assert.NotNull(SettingsValidator.Validate(T.Fixed(8, 30, 8, 30)));
        Assert.NotNull(SettingsValidator.Validate(T.Fixed(18, 0, 9, 0)));
    }

    [Fact]
    public void Lunch_EndMustBeAfterStart_OnlyWhenEnabled()
    {
        Assert.NotNull(SettingsValidator.Validate(T.WithLunch(T.Flex(), 13, 0, 11, 30)));
        Assert.NotNull(SettingsValidator.Validate(T.WithLunch(T.Flex(), 12, 0, 12, 0)));
        var disabled = T.Flex() with { Lunch = new LunchSettings { Enabled = false, Start = T.Tm(13, 0), End = T.Tm(11, 0) } };
        Assert.Null(SettingsValidator.Validate(disabled));
    }

    [Fact]
    public void InactiveModeValues_AreNotValidated()
    {
        // 유동 모드일 때 고정 시각이 이상해도(화면에 안 보임) 오류로 보지 않는다.
        var s = T.Flex() with { Fixed = new FixedSettings { Start = T.Tm(18, 0), End = T.Tm(9, 0) } };
        Assert.Null(SettingsValidator.Validate(s));
        // 고정 모드일 때 유동 근무 시간이 이상해도 마찬가지.
        var f = T.Fixed() with { Flexible = new FlexibleSettings { WorkMinutes = 5 } };
        Assert.Null(SettingsValidator.Validate(f));
    }

    [Theory]
    [InlineData(8, true)]
    [InlineData(12, true)]
    [InlineData(20, true)]
    [InlineData(32, true)]
    [InlineData(7, false)]
    [InlineData(33, false)]
    [InlineData(0, false)]
    [InlineData(-12, false)]
    public void FontSize_Range(int px, bool ok)
    {
        var s = AppSettings.Default with { Widget = new WidgetSettings { FontSize = px } };
        Assert.Equal(ok, SettingsValidator.Validate(s) is null);
    }

    [Theory]
    [InlineData("12", true, 12)]
    [InlineData(" 8 ", true, 8)]
    [InlineData("32", true, 32)]
    [InlineData("7", false, 0)]
    [InlineData("33", false, 0)]
    [InlineData("", false, 0)]
    [InlineData("abc", false, 0)]
    [InlineData("12.5", false, 0)]
    [InlineData("-1", false, 0)]
    [InlineData(null, false, 0)]
    public void FontSize_ParseInput(string? text, bool ok, int expected)
    {
        Assert.Equal(ok, WidgetSizing.TryParseFontSize(text, out var px, out var error));
        if (ok) { Assert.Equal(expected, px); Assert.Null(error); }
        else Assert.False(string.IsNullOrEmpty(error));
    }

    [Theory]
    [InlineData("09:00", true, 9, 0)]
    [InlineData("9:05", true, 9, 5)]
    [InlineData("00:00", true, 0, 0)]
    [InlineData("23:59", true, 23, 59)]
    [InlineData(" 18:16 ", true, 18, 16)]
    [InlineData("24:00", false, 0, 0)]
    [InlineData("09:60", false, 0, 0)]
    [InlineData("9", false, 0, 0)]
    [InlineData("", false, 0, 0)]
    [InlineData("ab:cd", false, 0, 0)]
    [InlineData(null, false, 0, 0)]
    public void TimeText_Parse(string? text, bool ok, int h, int m)
    {
        Assert.Equal(ok, TimeText.TryParse(text, out var t));
        if (ok) Assert.Equal(new TimeOnly(h, m), t);
    }

    [Fact]
    public void TimeText_Format_IsTwoDigit() => Assert.Equal("09:05", TimeText.Format(new TimeOnly(9, 5)));
}

public class SizingTests
{
    [Fact]
    public void Factor_IsFontSizeOver12()
    {
        Assert.Equal(1.0, WidgetSizing.Factor(12));
        Assert.Equal(2.0, WidgetSizing.Factor(24));
        Assert.Equal(8 / 12.0, WidgetSizing.Factor(8), 9);
    }

    [Theory]
    [InlineData(12, 320, 150)]
    [InlineData(24, 640, 300)]
    [InlineData(8, 213, 100)]
    [InlineData(32, 853, 400)]
    public void WindowSize_ScalesBaseSize(int fontSize, int w, int h)
        => Assert.Equal((w, h), WidgetSizing.WindowSize(fontSize));

    [Theory]
    // 격자 16: 기본 3칸(=48px)
    [InlineData(16, 16, 12, 3)]
    [InlineData(16, 16, 8, 2)]    // 32px → 2
    [InlineData(16, 16, 20, 5)]   // 80px → 5
    [InlineData(16, 16, 32, 8)]   // 128px → 8
    // 격자 24: 기본 2칸(=48px)
    [InlineData(24, 24, 12, 2)]
    [InlineData(24, 24, 8, 1)]    // 32/24=1.33 → 1
    [InlineData(24, 24, 20, 3)]   // 80/24=3.33 → 3
    [InlineData(24, 24, 32, 5)]   // 128/24=5.33 → 5
    public void MascotCell_IsIntegerNearestToBaseTimesFactor(int gw, int gh, int fontSize, int cell)
        => Assert.Equal(cell, WidgetSizing.MascotCell(gw, gh, fontSize));

    [Fact]
    public void MascotCell_UsesLongerSide_AndNeverBelowOne()
    {
        Assert.Equal(2, WidgetSizing.MascotCell(16, 24, 12));
        Assert.Equal(1, WidgetSizing.MascotCell(100, 100, 8));
        Assert.Equal(1, WidgetSizing.MascotCell(0, 0, 8) >= 1 ? 1 : 0);
    }
}
