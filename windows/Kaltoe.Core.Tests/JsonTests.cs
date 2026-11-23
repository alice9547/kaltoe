using Kaltoe.Core;

namespace Kaltoe.Core.Tests;

public class JsonTests
{
    [Fact]
    public void AppFile_RoundTrips()
    {
        var file = new AppFile
        {
            Settings = T.WithLunch(T.Fixed(9, 0, 18, 0)) with { Widget = new WidgetSettings { FontSize = 20 } },
            Widget = new WidgetState { X = 100, Y = 50, Visible = false },
            LaunchAtLoginInitialized = true,
        };
        var back = AppFile.Parse(file.ToJson());
        Assert.Equal(file, back);
    }

    [Fact]
    public void AppFile_WritesSpecKeysAndHhmm()
    {
        var json = new AppFile().ToJson();
        Assert.Contains("\"mode\": \"flexible\"", json);
        Assert.Contains("\"earliestStart\": \"09:00\"", json);
        Assert.Contains("\"workMinutes\": 540", json);
        Assert.Contains("\"fontSize\": 12", json);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("{ 깨진 json")]
    [InlineData("[1,2,3]")]
    [InlineData("null")]
    [InlineData("{\"settings\":{\"flexible\":{\"earliestStart\":\"25:99\"}}}")]
    public void AppFile_BrokenFile_GivesDefaults(string? json)
        => Assert.Equal(new AppFile(), AppFile.Parse(json));

    [Fact]
    public void AppFile_MissingKeys_GetDefaults()
    {
        var f = AppFile.Parse("{\"settings\":{\"mode\":\"fixed\"}}");
        Assert.Equal(WorkMode.Fixed, f.Settings.Mode);
        Assert.Equal(new TimeOnly(8, 30), f.Settings.Fixed.Start);
        Assert.Equal(12, f.Settings.Widget.FontSize);
        Assert.True(f.Widget.Visible);
    }

    [Fact]
    public void AppFile_InvalidSettings_ResetToDefaults_KeepWidgetState()
    {
        var f = AppFile.Parse("{\"settings\":{\"flexible\":{\"workMinutes\":5}},\"widget\":{\"x\":10,\"y\":20,\"visible\":false}}");
        Assert.Equal(AppSettings.Default, f.Settings);
        Assert.Equal(new WidgetState { X = 10, Y = 20, Visible = false }, f.Widget);
    }

    [Fact]
    public void AppFile_FontSizeOutOfRange_ResetsSettings()
    {
        var f = AppFile.Parse("{\"settings\":{\"widget\":{\"fontSize\":99}}}");
        Assert.Equal(12, f.Settings.Widget.FontSize);
    }

    [Fact]
    public void DayState_RoundTrips()
    {
        var s = new DayState();
        Assert.True(s.TrySetClockIn("2026-11-23", DateTime.SpecifyKind(T.At(9, 16, 7), DateTimeKind.Local)));
        s.MarkNotified("2026-11-23", NotificationKind.End);
        var back = DayState.Parse(s.ToJson());
        Assert.Equal(T.At(9, 16, 7), back.GetClockIn("2026-11-23"));
        Assert.Equal(DateTimeKind.Unspecified, back.GetClockIn("2026-11-23")!.Value.Kind);
        Assert.True(back.IsNotified("2026-11-23", NotificationKind.End));
        Assert.False(back.IsNotified("2026-11-23", NotificationKind.Lunch));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("not json")]
    [InlineData("{\"clockIns\":{\"2026-11-23\":\"garbage\"}}")]
    public void DayState_Broken_GivesEmpty(string? json)
        => Assert.Empty(DayState.Parse(json).ClockIns);

    [Fact]
    public void DayState_OneRecordPerDay()
    {
        var s = new DayState();
        Assert.True(s.TrySetClockIn("2026-11-23", T.At(9, 0)));
        Assert.False(s.TrySetClockIn("2026-11-23", T.At(10, 0)));
        Assert.Equal(T.At(9, 0), s.GetClockIn("2026-11-23"));
    }

    [Fact]
    public void DayState_Purge_KeepsFourteenDaysAndDropsOlder()
    {
        var now = T.At(10, 0);   // 2026-11-23
        var s = new DayState();
        foreach (var key in new[] { "2026-11-23", "2026-11-09", "2026-11-08", "2026-10-01", "bad-key" })
        {
            s.ClockIns[key] = T.At(9, 0);
            s.Notified[key] = new List<string> { "End" };
        }
        Assert.True(s.Purge(now));
        Assert.Equal(new[] { "2026-11-09", "2026-11-23" }, s.ClockIns.Keys.OrderBy(k => k).ToArray());
        Assert.Equal(new[] { "2026-11-09", "2026-11-23" }, s.Notified.Keys.OrderBy(k => k).ToArray());
        Assert.False(s.Purge(now));
    }
}
