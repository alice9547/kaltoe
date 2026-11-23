using Kaltoe.Core;

namespace Kaltoe.App;

/// 캐릭터 한 마리의 그림 데이터(격자 크기·팔레트·프레임). MascotData / MascotDataOrange 를 같은 모양으로 묶는다.
internal sealed record MascotArt(
    int Width, int Height,
    IReadOnlyDictionary<char, uint> Palette,
    IReadOnlyDictionary<string, string[]> Frames)
{
    public static readonly MascotArt Maltese = new(
        MascotData.Width, MascotData.Height, MascotData.Palette, MascotData.Frames);

    public static readonly MascotArt Orange = new(
        MascotDataOrange.Width, MascotDataOrange.Height, MascotDataOrange.Palette, MascotDataOrange.Frames);

    public static MascotArt For(MascotCharacter character)
        => character == MascotCharacter.Orange ? Orange : Maltese;
}
