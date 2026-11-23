// 사용자 지정 사진 처리의 픽셀 계산 — docs/spec.md 6-3절. WPF 에 의존하지 않는 순수 함수만 둔다(앱은 BitmapSource 로 읽고 여기로 계산한다).
// 픽셀 버퍼는 byte[] BGRA(8비트, 알파 비프리멀티 = WPF 의 Bgra32), 행 순서는 위에서 아래, 줄 간격 = width * 4.
namespace Kaltoe.Core;

public readonly record struct ImageRect(int X, int Y, int Width, int Height);

public static class PhotoPixels
{
    /// 저장하는 사진의 긴 변 (spec 6-3절).
    public const int LongSide = 512;
    /// 읽을 때 줄여 두는 작업 해상도 상한(처리 속도·메모리).
    public const int WorkingLongSide = 1600;
    /// "이미 투명한 이미지" 기준: 알파 < 255 인 픽셀의 비율이 이 값 이상.
    public const double TransparentFractionThreshold = 0.01;

    private static void Check(byte[] bgra, int width, int height)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width), "크기는 1 이상이어야 합니다");
        if (bgra.Length != width * height * 4) throw new ArgumentException($"버퍼 길이 {bgra.Length} != {width}x{height}x4");
    }

    /// 알파가 255 보다 작은 픽셀의 비율(0~1).
    public static double TransparentFraction(byte[] bgra, int width, int height)
    {
        Check(bgra, width, height);
        long n = 0;
        for (var i = 3; i < bgra.Length; i += 4) if (bgra[i] < 255) n++;
        return n / (double)((long)width * height);
    }

    /// 이미 투명 부분이 있는 이미지인가: 알파 < 255 인 픽셀이 1% 이상.
    public static bool HasTransparency(byte[] bgra, int width, int height)
        => TransparentFraction(bgra, width, height) >= TransparentFractionThreshold;

    /// 알파가 threshold 보다 큰 픽셀을 모두 담는 최소 사각형. 하나도 없으면 null.
    public static ImageRect? OpaqueBounds(byte[] bgra, int width, int height, byte threshold = 8)
    {
        Check(bgra, width, height);
        int minX = width, minY = height, maxX = -1, maxY = -1;
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
                if (bgra[(y * width + x) * 4 + 3] > threshold)
                {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
        return maxX < 0 ? null : new ImageRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }

    /// 사각형 영역을 잘라 낸 새 버퍼.
    public static byte[] Crop(byte[] bgra, int width, int height, ImageRect r)
    {
        Check(bgra, width, height);
        if (r.X < 0 || r.Y < 0 || r.Width <= 0 || r.Height <= 0 || r.X + r.Width > width || r.Y + r.Height > height)
            throw new ArgumentOutOfRangeException(nameof(r));
        var o = new byte[r.Width * r.Height * 4];
        for (var row = 0; row < r.Height; row++)
            Buffer.BlockCopy(bgra, ((r.Y + row) * width + r.X) * 4, o, row * r.Width * 4, r.Width * 4);
        return o;
    }

    /// 가운데 기준 정사각형(한 변 = 짧은 변). 홀수 차이는 왼쪽·위로 내림한 위치.
    public static ImageRect CenterSquare(int width, int height)
    {
        var side = Math.Min(width, height);
        return new ImageRect((width - side) / 2, (height - side) / 2, side, side);
    }

    /// 중심에서 distance 떨어진 픽셀의 원 안쪽 비율(0~1). 반지름 안쪽 1px 에 걸쳐 부드럽게 줄어든다.
    public static double CircleCoverage(double distance, double radius)
        => Math.Min(1, Math.Max(0, radius - distance + 0.5));

    /// 가운데 정사각형으로 자른 뒤 원 밖을 투명하게 한다(가장자리 1px 부드럽게). 돌려주는 버퍼는 size x size.
    public static byte[] CircleCrop(byte[] bgra, int width, int height, out int size)
    {
        var sq = CenterSquare(width, height);
        size = sq.Width;
        var o = Crop(bgra, width, height, sq);
        var c = size / 2.0;
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
            {
                var dx = x + 0.5 - c;
                var dy = y + 0.5 - c;
                var f = CircleCoverage(Math.Sqrt(dx * dx + dy * dy), c);
                if (f >= 1) continue;
                var i = (y * size + x) * 4 + 3;
                o[i] = (byte)Math.Round(o[i] * f);    // 비프리멀티 → 알파만 줄인다
            }
        return o;
    }

    /// 긴 변이 longSide 를 넘으면 그 크기에 맞춘 (너비, 높이), 아니면 그대로(키우지 않는다). 최소 1.
    public static (int Width, int Height) FitSize(int width, int height, int longSide)
    {
        var l = Math.Max(width, height);
        if (l <= longSide) return (width, height);
        var k = longSide / (double)l;
        return (Math.Max(1, (int)Math.Round(width * k)), Math.Max(1, (int)Math.Round(height * k)));
    }

    /// EXIF 방향 값(1~8) → 보정 변환. 먼저 좌우 뒤집기(FlipHorizontal)를 하고, 그다음 시계 방향으로 Rotation(0/90/180/270)도 돌린다.
    /// 1 이외·범위 밖의 값은 "그대로".
    public static (int Rotation, bool FlipHorizontal) ExifTransform(int orientation) => orientation switch
    {
        2 => (0, true),
        3 => (180, false),
        4 => (180, true),
        5 => (270, true),
        6 => (90, false),
        7 => (90, true),
        8 => (270, false),
        _ => (0, false),
    };

    /// size x size 정사각형 안에 비율을 유지하며 가운데 맞춘 사각형(아이콘 만들기용). 키우지는 않고 정사각을 꽉 채우게 맞춘다.
    public static (double X, double Y, double Width, double Height) FitInSquare(int width, int height, double size)
    {
        var k = size / Math.Max(width, height);
        var w = width * k;
        var h = height * k;
        return ((size - w) / 2, (size - h) / 2, w, h);
    }

    /// 회전 후 크기(90/270 이면 가로세로가 바뀐다).
    public static (int Width, int Height) RotatedSize(int width, int height, int rotation)
        => rotation is 90 or 270 ? (height, width) : (width, height);
}

/// 여러 크기의 PNG 를 담은 ICO 파일(PNG 압축 항목)을 만든다 — 사용자 지정 사진으로 트레이 아이콘을 만들 때 쓴다.
public static class IcoBuilder
{
    /// images: (정사각 한 변 px, PNG 바이트). 한 변은 1~256.
    public static byte[] Build(IReadOnlyList<(int Size, byte[] Png)> images)
    {
        if (images.Count == 0) throw new ArgumentException("이미지가 없습니다", nameof(images));
        using var ms = new MemoryStream();
        using var w = new BinaryWriter(ms);
        w.Write((ushort)0);                    // reserved
        w.Write((ushort)1);                    // type = icon
        w.Write((ushort)images.Count);
        var offset = 6 + 16 * images.Count;
        foreach (var (size, png) in images)
        {
            if (size is < 1 or > 256) throw new ArgumentOutOfRangeException(nameof(images), $"아이콘 크기 {size}");
            w.Write((byte)(size == 256 ? 0 : size));   // width (0 = 256)
            w.Write((byte)(size == 256 ? 0 : size));   // height
            w.Write((byte)0);                          // 팔레트 색 수
            w.Write((byte)0);                          // reserved
            w.Write((ushort)1);                        // planes
            w.Write((ushort)32);                       // bpp
            w.Write((uint)png.Length);
            w.Write((uint)offset);
            offset += png.Length;
        }
        foreach (var (_, png) in images) w.Write(png);
        w.Flush();
        return ms.ToArray();
    }
}
