using System.Windows;
using System.Windows.Media;
using Kaltoe.Core;

namespace Kaltoe.App;

/// MascotData 의 프레임을 사각형으로 찍어 그리는 컨트롤. 안티에일리어싱 없음.
/// 격자 둘레에 1칸 여유(외곽선용)와 점프용 위쪽 여유를 둔 캔버스에 그린다.
internal sealed class MascotControl : FrameworkElement
{
    private const string FallbackFrame = MascotFrames.Idle;

    private static readonly Dictionary<uint, SolidColorBrush> BrushCache = new();

    private readonly int _gw = Math.Max(1, MascotData.Width);
    private readonly int _gh = Math.Max(1, MascotData.Height);
    private readonly int _headroom;
    private readonly double _unit;          // 한 칸의 레이아웃 크기(DIP)
    private readonly bool _outline;         // 말풍선 모양: 실루엣 바깥 외곽선
    private readonly Dictionary<string, IReadOnlyList<(int X, int Y)>> _outlineCache = new();
    private MascotPose _pose = new(MascotFrames.Idle, MascotOverlay.None, 0, 0);

    /// <param name="cellPx">한 칸의 최종 화면 픽셀 크기(정수).</param>
    /// <param name="layoutScale">이 컨트롤을 감싼 LayoutTransform 의 배율(없으면 1). 최종 크기가 cellPx 가 되도록 보정한다.</param>
    /// <param name="outline">말풍선 모양이면 true(외곽선을 그린다).</param>
    public MascotControl(int cellPx, double layoutScale, bool outline)
    {
        _unit = Math.Max(1, cellPx) / (layoutScale <= 0 ? 1 : layoutScale);
        _outline = outline;
        _headroom = MascotPlayback.JumpHeadroomRows(_gh);
        SnapsToDevicePixels = true;
        UseLayoutRounding = true;
        RenderOptions.SetEdgeMode(this, EdgeMode.Aliased);
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.NearestNeighbor);
    }

    private int CanvasCols => _gw + 2;
    private int CanvasRows => _headroom + 1 + _gh + 1;

    public void SetPose(MascotPose pose)
    {
        if (pose == _pose) return;
        _pose = pose;
        InvalidateVisual();
    }

    protected override Size MeasureOverride(Size availableSize) => new(CanvasCols * _unit, CanvasRows * _unit);

    private static SolidColorBrush BrushOf(uint rgb)
    {
        if (!BrushCache.TryGetValue(rgb, out var b))
        {
            b = new SolidColorBrush(Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb));
            b.Freeze();
            BrushCache[rgb] = b;
        }
        return b;
    }

    private static (string Name, string[] Rows) FrameRows(string name)
    {
        if (MascotData.Frames.TryGetValue(name, out var rows)) return (name, rows);
        // 자리표시 데이터에는 idle 만 있을 수 있다 — 없는 프레임은 idle 로 대신 그린다.
        if (MascotData.Frames.TryGetValue(FallbackFrame, out rows)) return (FallbackFrame, rows);
        foreach (var kv in MascotData.Frames) return (kv.Key, kv.Value);
        return (FallbackFrame, Array.Empty<string>());
    }

    private static bool IsOpaque(string[] rows, int x, int y)
        => y >= 0 && y < rows.Length && x >= 0 && x < rows[y].Length
           && rows[y][x] != '.' && MascotData.Palette.ContainsKey(rows[y][x]);

    protected override void OnRender(DrawingContext dc)
    {
        // 빈 곳도 클릭·드래그가 잡히도록 투명 사각형을 깐다.
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, CanvasCols * _unit, CanvasRows * _unit));

        var (frameName, rows) = FrameRows(_pose.Frame);
        const int ox = 1;
        var oy = _headroom + 1 - Math.Clamp(_pose.JumpRows, 0, _headroom);

        void Cell(int cx, int cy, uint rgb)
        {
            if (cx < 0 || cy < 0 || cx >= CanvasCols || cy >= CanvasRows) return;
            dc.DrawRectangle(BrushOf(rgb), null, new Rect(cx * _unit, cy * _unit, _unit, _unit));
        }

        // 1) 뒤에 깔리는 색종이
        if (_pose.Overlay == MascotOverlay.Confetti) DrawConfetti(Cell, oy);

        // 2) 외곽선(말풍선 모양)
        if (_outline)
        {
            if (!_outlineCache.TryGetValue(frameName, out var cells))
            {
                cells = MascotOutline.Cells(_gw, _gh, (x, y) => IsOpaque(rows, x, y));
                _outlineCache[frameName] = cells;
            }
            foreach (var (x, y) in cells) Cell(ox + x, oy + y, MascotOutline.Color);
        }

        // 3) 본체
        for (var y = 0; y < rows.Length && y < _gh; y++)
        {
            var row = rows[y];
            for (var x = 0; x < row.Length && x < _gw; x++)
            {
                var ch = row[x];
                if (ch == '.' || !MascotData.Palette.TryGetValue(ch, out var rgb)) continue;
                Cell(ox + x, oy + y, rgb);
            }
        }

        // 4) 위에 뜨는 z
        if (_pose.Overlay == MascotOverlay.Zzz) DrawZ(Cell);
    }

    private static readonly string[] ZShape = { "zzz", ".z.", "zzz" };
    private const uint ZColorOnDark = 0xC7C7CC;
    private const uint ZColorOnLight = 0x6E6E73;

    private void DrawZ(Action<int, int, uint> cell)
    {
        var k = Math.Max(1, (int)Math.Round(_gh / 16.0, MidpointRounding.AwayFromZero));
        var baseTop = _headroom + 1;                       // 본체 맨 윗줄
        // 머리 위로 떠오른다: 낮은 곳 → 높은 곳 → 사라짐
        int[] tops = { baseTop + 2 * k, baseTop + k, baseTop, int.MinValue };
        var top = tops[_pose.OverlayStep % tops.Length];
        if (top == int.MinValue) return;
        var left = 1 + _gw - 3 * k;
        var color = _outline ? ZColorOnLight : ZColorOnDark;
        for (var r = 0; r < ZShape.Length; r++)
        for (var c = 0; c < ZShape[r].Length; c++)
        {
            if (ZShape[r][c] != 'z') continue;
            for (var dy = 0; dy < k; dy++)
            for (var dx = 0; dx < k; dx++)
                cell(left + c * k + dx, top + r * k + dy, color);
        }
    }

    // 색종이: (가로 비율, 세로 시작 비율, 색)
    private static readonly (double Fx, double Fy, uint Color)[] Confetti =
    {
        (0.00, 0.05, 0xFF5F57), (0.98, 0.25, 0xFEBC2E), (0.12, 0.00, 0x28C840),
        (0.85, 0.10, 0x5AC8FA), (0.50, 0.00, 0xFF5F57), (0.68, 0.05, 0xFEBC2E),
        (0.30, 0.15, 0x5AC8FA), (0.93, 0.00, 0x28C840),
    };

    private void DrawConfetti(Action<int, int, uint> cell, int spriteTop)
    {
        var fall = Math.Max(2, _gh / 2);
        foreach (var (fx, fy, color) in Confetti)
        {
            var x = (int)Math.Round(fx * (CanvasCols - 1));
            var y = spriteTop + ((int)Math.Round(fy * _gh) + _pose.OverlayStep) % fall;
            cell(x, y, color);
        }
    }
}
