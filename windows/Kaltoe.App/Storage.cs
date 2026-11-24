using System.Diagnostics;
using System.IO;
using System.Text;
using Microsoft.Win32;

namespace Kaltoe.App;

internal static class AppPaths
{
    public static string Dir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Kaltoe");
    public static string Settings => Path.Combine(Dir, "settings.json");
    public static string ClockIn => Path.Combine(Dir, "clockin.json");
    /// 사용자 지정 사진 (docs/spec.md 6-3절): %APPDATA%\Kaltoe\custom-mascot.png
    public static string CustomPhoto => Path.Combine(Dir, "custom-mascot.png");
    public static string ErrorLog => Path.Combine(Dir, "error.log");
}

internal static class FileIo
{
    public static string? ReadOrNull(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path, Encoding.UTF8) : null; }
        catch (Exception ex) { Log.Write($"읽기 실패 {path}: {ex.Message}"); return null; }
    }

    /// 바이너리 파일을 임시 파일에 쓰고 바꿔치기한다. 성공하면 true (실패하면 이전 파일은 그대로).
    public static bool WriteBytesAtomic(string path, byte[] data)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var tmp = path + ".tmp";
            File.WriteAllBytes(tmp, data);
            File.Move(tmp, path, overwrite: true);
            return true;
        }
        catch (Exception ex) { Log.Write($"쓰기 실패 {path}: {ex.Message}"); return false; }
    }

    /// 임시 파일에 쓰고 바꿔치기 — 쓰다가 꺼져도 기존 파일이 깨지지 않는다.
    public static void WriteAtomic(string path, string text)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            File.Move(tmp, path, overwrite: true);
        }
        catch (Exception ex) { Log.Write($"쓰기 실패 {path}: {ex.Message}"); }
    }
}

internal static class Log
{
    public static void Write(string message)
    {
        Debug.WriteLine("Kaltoe: " + message);
        try
        {
            Directory.CreateDirectory(AppPaths.Dir);
            var path = AppPaths.ErrorLog;
            if (File.Exists(path) && new FileInfo(path).Length > 256 * 1024) File.Delete(path);
            File.AppendAllText(path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
        }
        catch { /* 로그 실패는 무시 */ }
    }
}

/// 로그인 시 자동 실행: HKCU\Software\Microsoft\Windows\CurrentVersion\Run 의 Kaltoe 값.
internal static class LoginItem
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Kaltoe";

    public static bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) is string s && s.Length > 0;
        }
        catch (Exception ex) { Log.Write($"자동 실행 조회 실패: {ex.Message}"); return false; }
    }

    public static bool Set(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (enabled)
            {
                var path = Environment.ProcessPath;
                // `dotnet Kaltoe.dll` 로 개발 실행 중이면 dotnet.exe 를 등록하지 않는다.
                if (string.IsNullOrEmpty(path) || Path.GetFileNameWithoutExtension(path).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
                    return false;
                key.SetValue(ValueName, $"\"{path}\"");
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
            return true;
        }
        catch (Exception ex) { Log.Write($"자동 실행 설정 실패: {ex.Message}"); return false; }
    }

    /// 자동 실행에 등록된 exe 경로 (따옴표 뺀 값). 없으면 null.
    public static string? RegisteredPath()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(ValueName) is string s && s.Length > 0 ? s.Trim().Trim('"') : null;
        }
        catch (Exception ex) { Log.Write($"자동 실행 경로 조회 실패: {ex.Message}"); return null; }
    }

    /// 켜져 있는데 경로가 지금 실행 파일과 다르면(exe 를 옮김) 현재 경로로 고쳐 쓴다.
    public static void RefreshPathIfEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            if (key?.GetValue(ValueName) is not string current || current.Length == 0) return;
            var path = Environment.ProcessPath;
            if (string.IsNullOrEmpty(path)) return;
            if (!string.Equals(current, $"\"{path}\"", StringComparison.OrdinalIgnoreCase)) Set(true);
        }
        catch (Exception ex) { Log.Write($"자동 실행 경로 갱신 실패: {ex.Message}"); }
    }
}
