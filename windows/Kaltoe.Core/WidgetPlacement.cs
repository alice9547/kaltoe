// 위젯 위치 계산 — 화면 밖 복원 방지, 기본 위치, 크기 변경 후 화면 안으로 밀어 넣기. 단위는 물리 픽셀.
namespace Kaltoe.Core;

public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
}

public static class WidgetPlacement
{
    public const int Margin = 16;
    public const int MinVisible = 48;

    /// 기본 위치: 주 모니터 작업 영역 오른쪽 위, 여백 16.
    public static (int X, int Y) DefaultPosition(PixelRect workArea, int width, int height, int margin = Margin)
        => (workArea.Right - width - margin, workArea.Y + margin);

    /// 위젯이 어느 화면에든 충분히(가로·세로 MinVisible 이상) 걸쳐 있는지.
    public static bool IsOnScreen(PixelRect widget, IReadOnlyList<PixelRect> screens, int minVisible = MinVisible)
    {
        var need = Math.Min(minVisible, Math.Min(widget.Width, widget.Height));
        foreach (var s in screens)
        {
            var w = Math.Min(widget.Right, s.Right) - Math.Max(widget.X, s.X);
            var h = Math.Min(widget.Bottom, s.Bottom) - Math.Max(widget.Y, s.Y);
            if (w >= need && h >= need) return true;
        }
        return false;
    }

    /// 저장된 위치를 복원. 없거나 화면 밖이면 기본 위치.
    public static (int X, int Y) Restore(int? x, int? y, int width, int height,
        IReadOnlyList<PixelRect> screens, PixelRect primaryWorkArea)
    {
        if (x is { } px && y is { } py && IsOnScreen(new PixelRect(px, py, width, height), screens))
            return (px, py);
        return DefaultPosition(primaryWorkArea, width, height);
    }

    /// 크기가 바뀐 뒤: 왼쪽 위 모서리는 유지하고, 가장 많이 걸친 작업 영역 안으로 밀어 넣는다.
    /// 작업 영역보다 크면 그 영역의 왼쪽 위에 맞춘다.
    public static (int X, int Y) ClampInto(PixelRect widget, IReadOnlyList<PixelRect> workAreas, PixelRect primaryWorkArea)
    {
        var area = primaryWorkArea;
        long best = -1;
        foreach (var s in workAreas)
        {
            var w = Math.Max(0, Math.Min(widget.Right, s.Right) - Math.Max(widget.X, s.X));
            var h = Math.Max(0, Math.Min(widget.Bottom, s.Bottom) - Math.Max(widget.Y, s.Y));
            long overlap = (long)w * h;
            if (overlap > best) { best = overlap; area = s; }
        }
        var x = Math.Min(widget.X, area.Right - widget.Width);
        var y = Math.Min(widget.Y, area.Bottom - widget.Height);
        return (Math.Max(x, area.X), Math.Max(y, area.Y));
    }
}
