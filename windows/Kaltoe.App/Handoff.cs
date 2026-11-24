using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace Kaltoe.App;

/// 새 버전으로 갈아타기 (docs/spec.md 8절).
/// 새 버전을 실행하면 ① 켜져 있는 옛 버전을 끄고 대신 뜨고 ② 옛 버전 exe 파일(과 비게 된 폴더)을 지운다.
internal static class Handoff
{
    /// 다음 버전이 이 버전을 끌 때 Set 하는 이벤트. 이 버전부터 듣는다 (그 전 버전은 강제 종료).
    public const string QuitEventName = @"Local\Kaltoe.Quit";
    private const string ExeName = "Kaltoe.exe";
    private const string ProductName = "칼퇴";

    private static string InstallFile => Path.Combine(AppPaths.Dir, "install.json");

    public static Version Mine
    {
        get
        {
            var v = typeof(Handoff).Assembly.GetName().Version ?? new Version(0, 0, 0);
            return new Version(v.Major, v.Minor, Math.Max(v.Build, 0));
        }
    }

    /// 칼퇴 exe 의 버전 (파일 정보의 제품 이름이 '칼퇴' 일 때만). 칼퇴가 아니거나 못 읽으면 null.
    public static Version? ReadVersion(string? path)
    {
        try
        {
            if (string.IsNullOrEmpty(path) || !File.Exists(path)) return null;
            var info = FileVersionInfo.GetVersionInfo(path);
            if (info.ProductName != ProductName) return null;
            return new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart);
        }
        catch (Exception ex) { Log.Write($"버전 읽기 실패 {path}: {ex.Message}"); return null; }
    }

    /// 실행 중인 다른 칼퇴가 전부 나보다 옛 버전이면 모두 끄고 true. 같거나 새 버전(또는 버전 모름)이 하나라도 있으면 아무것도 안 하고 false.
    /// 끈 프로세스의 exe 경로는 stoppedPaths 에 담는다 (나중에 지울 후보).
    public static bool StopOlderInstances(List<string> stoppedPaths)
    {
        var me = Environment.ProcessId;
        var others = Process.GetProcessesByName("Kaltoe").Where(p => p.Id != me).ToList();
        try
        {
            if (others.Count == 0) return false;
            var paths = new List<(Process Proc, string Path)>();
            foreach (var p in others)
            {
                string? path = null;
                try { path = p.MainModule?.FileName; } catch { /* 권한 없음 → 버전 모름 */ }
                var v = ReadVersion(path);
                if (v is null || v >= Mine) return false;
                paths.Add((p, path!));
            }

            // 이 버전 이후의 칼퇴는 종료 신호를 듣고 스스로 끈다(트레이 아이콘도 정리됨).
            try { if (EventWaitHandle.TryOpenExisting(QuitEventName, out var quit)) using (quit) quit.Set(); }
            catch (Exception ex) { Log.Write($"종료 신호 실패: {ex.Message}"); }

            foreach (var (p, path) in paths)
            {
                try
                {
                    if (!p.WaitForExit(3000)) { p.Kill(); p.WaitForExit(3000); }
                    Log.Write($"옛 버전 종료: {path}");
                    stoppedPaths.Add(path);
                }
                catch (Exception ex) { Log.Write($"옛 버전 종료 실패 {path}: {ex.Message}"); }
            }
            return true;
        }
        finally
        {
            foreach (var p in others) p.Dispose();
        }
    }

    /// 지난번에 실행된 exe 경로 (이 버전부터 기록).
    public static string? LastExePath()
    {
        try
        {
            var text = FileIo.ReadOrNull(InstallFile);
            if (text is null) return null;
            using var doc = JsonDocument.Parse(text);
            return doc.RootElement.TryGetProperty("exePath", out var v) ? v.GetString() : null;
        }
        catch (Exception ex) { Log.Write($"install.json 읽기 실패: {ex.Message}"); return null; }
    }

    /// 후보 경로 중 '지금 exe 가 아니고, 이름이 Kaltoe.exe 이고, 칼퇴 옛 버전' 인 파일만 지운다.
    /// 지운 뒤 폴더가 비었고 폴더 이름이 Kaltoe 로 시작하면 폴더도 지운다. 끝나면 지금 경로를 기록한다.
    /// 강제 종료한 프로세스가 파일을 잠깐 잡고 있을 수 있어 몇 번 다시 시도한다 — 그래서 백그라운드에서 돈다.
    public static void CleanUpOldCopies(IEnumerable<string?> candidates)
    {
        var current = Environment.ProcessPath;
        if (string.IsNullOrEmpty(current)) return;
        var list = candidates.Where(c => !string.IsNullOrWhiteSpace(c)).Select(c => c!).ToList();
        Task.Run(() =>
        {
            foreach (var raw in list.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    var path = Path.GetFullPath(raw);
                    if (string.Equals(path, current, StringComparison.OrdinalIgnoreCase)) continue;
                    if (!string.Equals(Path.GetFileName(path), ExeName, StringComparison.OrdinalIgnoreCase)) continue;
                    var v = ReadVersion(path);
                    if (v is null || v >= Mine) continue;
                    if (!DeleteWithRetry(path)) continue;
                    Log.Write($"옛 버전 파일 삭제: {path} ({v})");

                    var dir = Path.GetDirectoryName(path);
                    if (dir is not null && Path.GetFileName(dir).StartsWith("Kaltoe", StringComparison.OrdinalIgnoreCase)
                        && !Directory.EnumerateFileSystemEntries(dir).Any())
                    {
                        Directory.Delete(dir);
                        Log.Write($"빈 폴더 삭제: {dir}");
                    }
                }
                catch (Exception ex) { Log.Write($"옛 버전 정리 실패 {raw}: {ex.Message}"); }
            }
            FileIo.WriteAtomic(InstallFile, JsonSerializer.Serialize(new { exePath = current, version = Mine.ToString() }));
        });
    }

    private static bool DeleteWithRetry(string path)
    {
        for (var i = 0; i < 10; i++)
        {
            try { File.Delete(path); return true; }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                if (i == 9) { Log.Write($"삭제 실패 {path}: {ex.Message}"); return false; }
                Thread.Sleep(500);
            }
        }
        return false;
    }
}
