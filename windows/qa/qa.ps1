# 윈도우 서버에서 앱을 실제로 띄워 마우스로 조작해 보는 자가 QA.
# 사용: pwsh windows/qa/qa.ps1 -Exe publish/Kaltoe.exe -Out qa-out
param([string]$Exe = "publish/Kaltoe.exe", [string]$Out = "qa-out")
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  public static List<string> List(uint pid) {
    var o = new List<string>();
    EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) {
      var t = new StringBuilder(200); GetWindowText(h, t, 200); var c = new StringBuilder(200); GetClassName(h, c, 200);
      RECT r; GetWindowRect(h, out r);
      o.Add(String.Format("{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7:X}", t, IsWindowVisible(h), r.L, r.T, r.R - r.L, r.B - r.T, c, GetWindowLong(h, -20)));
    } return true; }, IntPtr.Zero);
    return o;
  }
}
"@
$script:failed = @()
function Shot($name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $Out "$name.png")); $g.Dispose(); $bmp.Dispose()
}
function Windows($p) { [W]::List([uint32]$p.Id) }
function Widget($p) {
  # 보이는 창 중 제목이 '칼퇴' 이고 크기가 있는 것
  foreach ($w in (Windows $p)) { $f = $w.Split('|'); if ($f[0] -eq '칼퇴' -and $f[1] -eq 'True' -and [int]$f[4] -gt 50) { return @{ X=[int]$f[2]; Y=[int]$f[3]; W=[int]$f[4]; H=[int]$f[5] } } }
  return $null
}
function Dump($label, $p) { Write-Host "[$label] alive=$(-not $p.HasExited)"; foreach ($w in (Windows $p)) { Write-Host "    $w" } }
function Check($name, $cond, $detail) { if ($cond) { Write-Host "PASS  $name  $detail" } else { Write-Host "FAIL  $name  $detail"; $script:failed += $name } }
function Drag($x1, $y1, $x2, $y2) {
  [W]::SetCursorPos($x1, $y1) | Out-Null; Start-Sleep -Milliseconds 300
  [W]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200
  for ($i = 1; $i -le 20; $i++) {
    [W]::SetCursorPos([int]($x1 + ($x2 - $x1) * $i / 20), [int]($y1 + ($y2 - $y1) * $i / 20)) | Out-Null
    [W]::mouse_event(0x0001, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
  }
  Start-Sleep -Milliseconds 300; [W]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 800
}
function Click($x, $y) { [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200; [W]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [W]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 800 }
function Launch($a) { if ($a.Count -gt 0) { $p = Start-Process -FilePath $Exe -ArgumentList $a -PassThru } else { $p = Start-Process -FilePath $Exe -PassThru }; Start-Sleep -Seconds 10; return $p }
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host "screen $($screen.Width)x$($screen.Height)"

# 1. 실제 모드 실행 → 위젯 보임
$p = Launch @()
Dump 'launch' $p; Shot '1-launch'
$w0 = Widget $p
Check 'launch-widget-visible' ($null -ne $w0) "rect=$($w0.X),$($w0.Y) $($w0.W)x$($w0.H)"

# 2. 본문을 잡고 드래그 → 위젯이 따라 움직이고 계속 보임
if ($w0) {
  $sx = $w0.X + 60; $sy = $w0.Y + [int]($w0.H * 0.55)
  Drag $sx $sy ($sx - 350) ($sy + 250)
  Dump 'after-drag' $p; Shot '2-after-drag'
  $w1 = Widget $p
  Check 'drag-still-visible' ($null -ne $w1) "rect=$($w1.X),$($w1.Y)"
  if ($w1) { Check 'drag-moved' ([math]::Abs(($w1.X - $w0.X) + 350) -lt 40 -and [math]::Abs(($w1.Y - $w0.Y) - 250) -lt 40) "dx=$($w1.X - $w0.X) dy=$($w1.Y - $w0.Y)" }
  Start-Sleep -Seconds 3; Dump 'drag+3s' $p; Shot '3-drag-settled'
  $w1b = Widget $p
  Check 'drag-stays-visible-after-3s' ($null -ne $w1b) "rect=$($w1b.X),$($w1b.Y)"

  # 3. 제목 줄을 잡고 한 번 더 드래그
  if ($w1b) {
    Drag ($w1b.X + [int]($w1b.W / 2)) ($w1b.Y + 12) ($w1b.X + [int]($w1b.W / 2) + 120) ($w1b.Y + 12 - 100)
    Dump 'after-drag2' $p; Shot '4-after-drag2'
    $w2 = Widget $p
    Check 'drag2-still-visible' ($null -ne $w2) "rect=$($w2.X),$($w2.Y)"
  }
}

# 4. 실행 중에 한 번 더 실행 → 기존 위젯이 보이는 상태여야 함
$p2 = Start-Process -FilePath $Exe -PassThru; Start-Sleep -Seconds 6
Dump 'second-launch(first proc)' $p; Shot '5-second-launch'
Check 'second-launch-first-alive' (-not $p.HasExited) ""
Check 'second-launch-widget-visible' ($null -ne (Widget $p)) ""
if (-not $p2.HasExited) { Stop-Process -Id $p2.Id -Force }

# 5. 빨간 점 클릭 → 숨김, 다시 실행하면 다시 보임
$w = Widget $p
if ($w) {
  Click ($w.X + 18) ($w.Y + 13)
  Dump 'after-red-dot' $p; Shot '6-after-red-dot'
  Check 'red-dot-hides' ($null -eq (Widget $p)) ""
  $p3 = Start-Process -FilePath $Exe -PassThru; Start-Sleep -Seconds 6
  Dump 'relaunch-while-hidden' $p; Shot '7-relaunch-while-hidden'
  Check 'relaunch-shows-hidden-widget' ($null -ne (Widget $p)) ""
  if (-not $p3.HasExited) { Stop-Process -Id $p3.Id -Force }
}

# 6. 종료 후 재실행 → 저장된 위치에서 보임
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2
Write-Host "--- saved files"; Get-ChildItem "$env:APPDATA\Kaltoe" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "--- $($_.Name)"; Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 40 }
$p = Launch @()
Dump 'restart' $p; Shot '8-restart'
Check 'restart-widget-visible' ($null -ne (Widget $p)) ""
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2

# 7. 말풍선 모양 드래그
$p = Launch @('--demo','working','--style','bubble')
Dump 'bubble' $p; Shot '9-bubble'
$b0 = Widget $p
Check 'bubble-visible' ($null -ne $b0) "rect=$($b0.X),$($b0.Y) $($b0.W)x$($b0.H)"
if ($b0) {
  Drag ($b0.X + 40) ($b0.Y + 20) ($b0.X - 300) ($b0.Y + 300)
  Dump 'bubble-after-drag' $p; Shot '10-bubble-after-drag'
  Check 'bubble-drag-still-visible' ($null -ne (Widget $p)) ""
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

# 8. 설정 창
$p = Launch @('--demo','working','--settings')
Dump 'settings' $p; Shot '11-settings'
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

Write-Host "--- event log"
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-15) } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -in '.NET Runtime', 'Application Error' } | ForEach-Object { Write-Host $_.TimeCreated $_.ProviderName; Write-Host $_.Message }
Write-Host "=== FAILED: $($script:failed.Count) [$($script:failed -join ', ')]"
if ($script:failed.Count -gt 0) { exit 1 }
