using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Kaltoe.Core;

namespace Kaltoe.App;

/// 처리가 끝난 사용자 지정 사진: 화면용 이미지(고정됨)와 저장할 PNG 바이트.
internal sealed record ProcessedPhoto(BitmapSource Image, byte[] Png);

/// 사용자 지정 사진 처리 (docs/spec.md 6-3절): 읽기(EXIF 방향) → 배경 지우기(원형 자르기) → 투명 여백 자르기 → 긴 변 512px 로 축소 → PNG.
/// 픽셀 계산은 Kaltoe.Core 의 PhotoPixels(byte[] BGRA 순수 함수)가 하고, 여기서는 WPF 로 읽고 쓰기만 한다.
/// 윈도우에는 자동 누끼 기능이 없으므로 이미 투명한 이미지가 아니면 가운데 기준 원형으로 자른다.
internal static class CustomPhotoProcessor
{
    /// 처리를 UI 를 막지 않게 별도 STA 스레드에서 돌린다(RenderTargetBitmap·DrawingVisual 은 STA 가 안전하다). 결과는 고정(Freeze)돼 있어 UI 스레드에서 쓸 수 있다.
    public static Task<ProcessedPhoto> ProcessAsync(string path)
    {
        var tcs = new TaskCompletionSource<ProcessedPhoto>();
        var thread = new Thread(() =>
        {
            try { tcs.SetResult(Process(path)); }
            catch (Exception ex) { tcs.SetException(ex); }
        }) { IsBackground = true, Name = "Kaltoe.CustomPhoto" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return tcs.Task;
    }

    private static T Fz<T>(T f) where T : Freezable
    {
        if (f.CanFreeze) f.Freeze();
        return f;
    }

    /// 파일을 처리한다. 읽을 수 없거나 처리에 실패하면 예외(호출한 쪽이 "사진을 불러오지 못했습니다" 를 보여 준다). 어느 스레드에서나 부를 수 있다.
    public static ProcessedPhoto Process(string path)
    {
        var src = Load(path);
        var conv = new FormatConvertedBitmap(src, PixelFormats.Bgra32, null, 0);
        int w = conv.PixelWidth, h = conv.PixelHeight;
        var px = new byte[w * h * 4];
        conv.CopyPixels(px, w * 4, 0);

        if (!PhotoPixels.HasTransparency(px, w, h))            // 이미 투명 부분이 있으면 그대로 쓴다
        {
            px = PhotoPixels.CircleCrop(px, w, h, out var side);
            w = h = side;
        }

        var bounds = PhotoPixels.OpaqueBounds(px, w, h) ?? throw new InvalidDataException("남은 픽셀이 없습니다");
        px = PhotoPixels.Crop(px, w, h, bounds);
        w = bounds.Width;
        h = bounds.Height;

        BitmapSource result = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, w * 4);
        var (nw, nh) = PhotoPixels.FitSize(w, h, PhotoPixels.LongSide);
        if (nw != w || nh != h) result = Resize(result, nw, nh);
        Fz(result);
        return new ProcessedPhoto(result, EncodePng(result));
    }

    /// (1) 읽기: PNG/JPEG/BMP/GIF(첫 프레임). EXIF 방향을 적용하고 긴 변이 작업 해상도(1600)를 넘으면 줄인다.
    private static BitmapSource Load(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count == 0) throw new InvalidDataException("프레임이 없습니다");
        BitmapSource frame = decoder.Frames[0];
        var (rotation, flip) = PhotoPixels.ExifTransform(ReadOrientation(decoder.Frames[0]));
        // 좌우 뒤집기 → 회전 순서. TransformedBitmap 은 배율·90° 회전만 지원해서 한 단계씩 적용한다.
        if (flip) frame = Transformed(frame, new ScaleTransform(-1, 1));
        if (rotation != 0) frame = Transformed(frame, new RotateTransform(rotation));
        var (w, h) = PhotoPixels.FitSize(frame.PixelWidth, frame.PixelHeight, PhotoPixels.WorkingLongSide);
        if (w != frame.PixelWidth || h != frame.PixelHeight) frame = Resize(frame, w, h);
        return frame;
    }

    private static BitmapSource Transformed(BitmapSource source, Transform transform)
    {
        var t = new TransformedBitmap();
        t.BeginInit();
        t.Source = source;
        t.Transform = transform;
        t.EndInit();
        return Fz(t);
    }

    private static int ReadOrientation(BitmapFrame frame)
    {
        try
        {
            if (frame.Metadata is BitmapMetadata m)
            {
                foreach (var query in new[] { "System.Photo.Orientation", "/app1/ifd/{ushort=274}" })
                    if (m.ContainsQuery(query) && m.GetQuery(query) is ushort o) return o;
            }
        }
        catch (Exception) { /* PNG/BMP/GIF 등은 방향 정보가 없다 */ }
        return 1;
    }

    /// 고품질 보간으로 크기를 바꾼다(Pbgra32).
    internal static BitmapSource Resize(BitmapSource source, int width, int height)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var dc = visual.RenderOpen()) dc.DrawImage(source, new Rect(0, 0, width, height));
        var target = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        return Fz(target);
    }

    internal static byte[] EncodePng(BitmapSource image)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }
}

/// 위젯이 그릴 사진 한 장과 덧그림 위치 (docs/spec.md 6-2절, 6-3절). Image 가 null 이면 내장 강아지 사진.
internal sealed record PhotoSource(
    BitmapSource? Image,
    double LeftEyeX, double LeftEyeY, double RightEyeX, double RightEyeY,
    double AngerX, double AngerY, bool IsCustom)
{
    public static readonly PhotoSource Builtin = new(null,
        PhotoMascot.LeftEyeX, PhotoMascot.LeftEyeY, PhotoMascot.RightEyeX, PhotoMascot.RightEyeY,
        PhotoMascot.AngerCenterX, PhotoMascot.AngerCenterY, false);

    /// 눈 위치를 모르는 사용자 지정 사진: 눈물은 폭의 35%·65%, 높이의 45%, 화남 표시는 오른쪽 위 모서리.
    public static PhotoSource Custom(BitmapSource image) => new(image,
        PhotoMascot.CustomLeftEyeX, PhotoMascot.CustomLeftEyeY, PhotoMascot.CustomRightEyeX, PhotoMascot.CustomRightEyeY,
        PhotoMascot.CustomAngerCenterX, PhotoMascot.CustomAngerCenterY, true);
}

/// 저장한 사용자 지정 사진(%APPDATA%\Kaltoe\custom-mascot.png)을 들고 있는다. UI 스레드에서 쓴다.
internal sealed class CustomPhotoStore
{
    public static CustomPhotoStore Current { get; } = new();

    public BitmapSource? Image { get; private set; }
    public bool HasPhoto => Image is not null;

    private CustomPhotoStore() { Image = TryRead(AppPaths.CustomPhoto); }

    /// 저장한 파일을 읽는다. 없거나 깨졌으면 null (그러면 내장 사진처럼 동작한다).
    internal static BitmapSource? TryRead(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var ms = new MemoryStream(File.ReadAllBytes(path));
            var frame = BitmapDecoder.Create(ms, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
            if (frame.PixelWidth <= 0 || frame.PixelHeight <= 0) return null;
            if (frame.CanFreeze) frame.Freeze();
            return frame;
        }
        catch (Exception ex)
        {
            Log.Write($"사용자 지정 사진 읽기 실패: {ex.Message}");
            return null;
        }
    }

    /// 저장하고 즉시 반영한다. 저장에 실패하면 false 이고 이전 사진을 유지한다.
    public bool Install(ProcessedPhoto photo)
    {
        if (!FileIo.WriteBytesAtomic(AppPaths.CustomPhoto, photo.Png)) return false;
        Image = TryRead(AppPaths.CustomPhoto) ?? photo.Image;
        return true;
    }

    /// 이번 실행에만 쓴다 — 파일을 쓰지 않는다(확인용 --custom-photo).
    public void UseTransient(BitmapSource image) => Image = image;

    /// 저장한 파일을 지우고 내장 사진으로 돌아간다.
    public void Remove()
    {
        try { if (File.Exists(AppPaths.CustomPhoto)) File.Delete(AppPaths.CustomPhoto); }
        catch (Exception ex) { Log.Write($"사용자 지정 사진 삭제 실패: {ex.Message}"); }
        Image = null;
    }

    /// 설정의 customPhoto 가 켜져 있고 사진이 있으면 사용자 지정, 아니면 내장 사진.
    public PhotoSource Resolve(bool customPhotoEnabled)
        => customPhotoEnabled && Image is { } img ? PhotoSource.Custom(img) : PhotoSource.Builtin;
}

/// 사용자 지정 사진으로 실행 중에 만드는 아이콘들 (전체 이미지를 정사각 안에 맞춰 축소).
internal static class PhotoIcons
{
    /// 정사각 size 안에 사진 전체를 맞춰 넣은 이미지(투명 여백).
    public static BitmapSource Square(BitmapSource image, int size)
    {
        var (x, y, w, h) = PhotoPixels.FitInSquare(image.PixelWidth, image.PixelHeight, size);
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var dc = visual.RenderOpen()) dc.DrawImage(image, new Rect(x, y, w, h));
        var target = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        if (target.CanFreeze) target.Freeze();
        return target;
    }

    /// 트레이 아이콘(16·20·24·32). 실패하면 null — 호출한 쪽이 파일 아이콘으로 대체한다.
    public static System.Drawing.Icon? Tray(BitmapSource image)
    {
        try
        {
            var ico = IcoBuilder.Build(new[] { 16, 20, 24, 32 }
                .Select(n => (n, CustomPhotoProcessor.EncodePng(Square(image, n)))).ToList());
            return new System.Drawing.Icon(new MemoryStream(ico));
        }
        catch (Exception ex)
        {
            Log.Write($"트레이 아이콘 만들기 실패: {ex.Message}");
            return null;
        }
    }

    /// 설정 창 아이콘.
    public static BitmapSource Window(BitmapSource image) => Square(image, 64);
}
