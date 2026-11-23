using System.Runtime.InteropServices;
using Kaltoe.Core;

namespace Kaltoe.App;

/// Win32 호출 모음.
internal static class Native
{
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;

    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    /// 포커스를 뺏지 않고 Alt+Tab 목록에 안 뜨게.
    public static void ApplyNoActivateToolWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        var style = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    }

    public static bool MoveTo(IntPtr hwnd, int x, int y)
        => hwnd != IntPtr.Zero && SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);

    public static PixelRect? GetRect(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var r)) return null;
        return new PixelRect(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
    }
}

/// 모니터 작업 영역(물리 픽셀).
internal static class Screens
{
    public static IReadOnlyList<PixelRect> WorkAreas()
    {
        var list = new List<PixelRect>();
        foreach (var s in System.Windows.Forms.Screen.AllScreens)
        {
            var a = s.WorkingArea;
            list.Add(new PixelRect(a.X, a.Y, a.Width, a.Height));
        }
        if (list.Count == 0) list.Add(new PixelRect(0, 0, 1920, 1040));
        return list;
    }

    public static PixelRect Primary()
    {
        var a = System.Windows.Forms.Screen.PrimaryScreen?.WorkingArea;
        return a is { } r ? new PixelRect(r.X, r.Y, r.Width, r.Height) : WorkAreas()[0];
    }
}
