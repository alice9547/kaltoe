using System.Windows;
using System.Windows.Controls;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 설정 창(docs/spec.md 5절). 값이 유효하면 바꾸는 즉시 저장·반영, 유효하지 않으면 빨간 글씨로 이유를 보여 주고 저장하지 않는다.
public partial class SettingsWindow : Window
{
    private readonly ISettingsHost _host;
    private bool _loading;

    internal SettingsWindow(ISettingsHost host)
    {
        _host = host;
        InitializeComponent();
        Load(host.CurrentSettings);

        foreach (var tb in new[] { TbEarliest, TbHours, TbMinutes, TbFixedStart, TbFixedEnd, TbLunchStart, TbLunchEnd, TbFontSize })
            tb.TextChanged += (_, _) => OnChanged();
        foreach (var rb in new[] { RbFlexible, RbFixed, RbTerminal, RbBubble })
            rb.Checked += (_, _) => OnChanged();
        foreach (var cb in new[] { CbLunch, CbNotifyLunch, CbNotifyBeforeEnd, CbNotifyEnd })
        {
            cb.Checked += (_, _) => OnChanged();
            cb.Unchecked += (_, _) => OnChanged();
        }
        CbLaunch.Checked += (_, _) => OnLaunchChanged();
        CbLaunch.Unchecked += (_, _) => OnLaunchChanged();
        BtnFontUp.Click += (_, _) => StepFont(+1);
        BtnFontDown.Click += (_, _) => StepFont(-1);
    }

    private void Load(AppSettings s)
    {
        _loading = true;
        try
        {
            RbFlexible.IsChecked = s.Mode == WorkMode.Flexible;
            RbFixed.IsChecked = s.Mode == WorkMode.Fixed;
            TbEarliest.Text = TimeText.Format(s.Flexible.EarliestStart);
            TbHours.Text = (s.Flexible.WorkMinutes / 60).ToString();
            TbMinutes.Text = (s.Flexible.WorkMinutes % 60).ToString();
            TbFixedStart.Text = TimeText.Format(s.Fixed.Start);
            TbFixedEnd.Text = TimeText.Format(s.Fixed.End);
            CbLunch.IsChecked = s.Lunch.Enabled;
            TbLunchStart.Text = TimeText.Format(s.Lunch.Start);
            TbLunchEnd.Text = TimeText.Format(s.Lunch.End);
            CbNotifyLunch.IsChecked = s.Notify.Lunch;
            CbNotifyBeforeEnd.IsChecked = s.Notify.BeforeEnd;
            CbNotifyEnd.IsChecked = s.Notify.End;
            RbTerminal.IsChecked = s.Widget.Style == WidgetStyle.Terminal;
            RbBubble.IsChecked = s.Widget.Style == WidgetStyle.Bubble;
            TbFontSize.Text = s.Widget.FontSize.ToString();
            CbLaunch.IsChecked = _host.LaunchAtLogin;
            UpdateEnabled();
            TbPreview.Text = WidgetText.Preview(s, _host.Today, _host.TodayClockIn);
            TbError.Text = "";
        }
        finally { _loading = false; }
    }

    private void UpdateEnabled()
    {
        var flexible = RbFlexible.IsChecked == true;
        FlexiblePanel.IsEnabled = flexible;
        FixedPanel.IsEnabled = !flexible;
        LunchPanel.IsEnabled = CbLunch.IsChecked == true;
    }

    private void OnLaunchChanged()
    {
        if (_loading) return;
        _host.LaunchAtLogin = CbLaunch.IsChecked == true;
    }

    private void StepFont(int delta)
    {
        var current = WidgetSizing.TryParseFontSize(TbFontSize.Text, out var px, out _) ? px : _host.CurrentSettings.Widget.FontSize;
        var next = Math.Clamp(current + delta, WidgetSizing.MinFontSize, WidgetSizing.MaxFontSize);
        TbFontSize.Text = next.ToString();   // TextChanged → OnChanged
    }

    private void OnChanged()
    {
        if (_loading) return;
        UpdateEnabled();

        var (result, error) = Read();
        if (result is null)
        {
            TbError.Text = error ?? "";
            TbPreview.Text = "";
            return;
        }
        var invalid = SettingsValidator.Validate(result);
        if (invalid is not null)
        {
            TbError.Text = invalid;
            TbPreview.Text = "";
            return;
        }
        TbError.Text = "";
        TbPreview.Text = WidgetText.Preview(result, _host.Today, _host.TodayClockIn);
        _host.ApplySettings(result);
    }

    /// 입력칸 → 설정. 화면에 보이는(현재 모드에서 쓰는) 칸만 해석하고 나머지는 현재 값을 유지한다.
    private (AppSettings? Settings, string? Error) Read()
    {
        string? error = null;
        var current = _host.CurrentSettings;

        bool Time(TextBox box, string label, TimeOnly fallback, bool needed, out TimeOnly value)
        {
            value = fallback;
            if (!needed) return true;
            if (TimeText.TryParse(box.Text, out value)) return true;
            error = $"{label}: HH:mm 형식으로 입력하세요 (예: 09:00)";
            return false;
        }

        var flexible = RbFlexible.IsChecked == true;
        var lunchOn = CbLunch.IsChecked == true;

        if (!Time(TbEarliest, "출근 인정 시작", current.Flexible.EarliestStart, flexible, out var earliest)) return (null, error);
        var minutes = current.Flexible.WorkMinutes;
        if (flexible)
        {
            if (!int.TryParse(TbHours.Text.Trim(), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var h))
            { error = "근무 시간: 시간은 숫자로 입력하세요"; return (null, error); }
            if (!int.TryParse(TbMinutes.Text.Trim(), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var m) || m > 59)
            { error = "근무 시간: 분은 0~59 사이 숫자로 입력하세요"; return (null, error); }
            minutes = h * 60 + m;
        }
        if (!Time(TbFixedStart, "출근", current.Fixed.Start, !flexible, out var fixedStart)) return (null, error);
        if (!Time(TbFixedEnd, "퇴근", current.Fixed.End, !flexible, out var fixedEnd)) return (null, error);
        if (!Time(TbLunchStart, "점심 시작", current.Lunch.Start, lunchOn, out var lunchStart)) return (null, error);
        if (!Time(TbLunchEnd, "점심 끝", current.Lunch.End, lunchOn, out var lunchEnd)) return (null, error);
        if (!WidgetSizing.TryParseFontSize(TbFontSize.Text, out var fontSize, out error)) return (null, error);

        var settings = new AppSettings
        {
            Mode = flexible ? WorkMode.Flexible : WorkMode.Fixed,
            Flexible = new FlexibleSettings { EarliestStart = earliest, WorkMinutes = minutes },
            Fixed = new FixedSettings { Start = fixedStart, End = fixedEnd },
            Lunch = new LunchSettings { Enabled = lunchOn, Start = lunchStart, End = lunchEnd },
            Notify = new NotifySettings
            {
                Lunch = CbNotifyLunch.IsChecked == true,
                BeforeEnd = CbNotifyBeforeEnd.IsChecked == true,
                End = CbNotifyEnd.IsChecked == true,
            },
            Widget = new WidgetSettings
            {
                Style = RbBubble.IsChecked == true ? WidgetStyle.Bubble : WidgetStyle.Terminal,
                FontSize = fontSize,
            },
        };
        return (settings, null);
    }
}
