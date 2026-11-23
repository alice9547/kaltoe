using System.Windows;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 위젯이 마스코트를 다루는 방식 — 픽셀 캐릭터(MascotControl)와 실사 캐릭터(PhotoMascotControl)가 같은 모양으로 구현한다.
internal interface IMascotView
{
    /// 창에 올릴 요소(정렬·여백·클릭 판정에 쓴다).
    FrameworkElement Element { get; }

    /// 0.1초마다. seconds = 재생 시작 후 지난 시간, secondsSinceJump = 마지막 클릭 후 지난 시간(없으면 null).
    void Animate(MascotMood mood, double seconds, double? secondsSinceJump);
}

internal static class MascotViews
{
    /// 캐릭터에 맞는 마스코트 요소를 만든다.
    /// <param name="layoutScale">이 요소를 감싼 LayoutTransform 의 배율(터미널은 글자 크기 비율, 말풍선은 1).</param>
    /// <param name="photo">실사(Photo) 캐릭터가 그릴 사진(내장 또는 사용자 지정). 생략하면 내장 사진.</param>
    public static IMascotView Create(MascotCharacter character, int fontSize, WidgetStyle style, double layoutScale, PhotoSource? photo = null)
    {
        if (character == MascotCharacter.Photo)
        {
            // 사진은 정수 칸 배율이 필요 없다: 기본 폭 60 × 비율. 감싼 변환이 이미 키우는 만큼은 덜어 낸다.
            var unit = WidgetSizing.Factor(fontSize) / (layoutScale <= 0 ? 1 : layoutScale);
            return new PhotoMascotControl(unit, shadow: style == WidgetStyle.Bubble, photo ?? PhotoSource.Builtin);
        }
        var art = MascotArt.For(character);
        var cell = WidgetSizing.MascotCell(art.Width, art.Height, fontSize, style);
        return new MascotControl(art, cell, layoutScale, outline: style == WidgetStyle.Bubble);
    }
}
