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
function SettingsWin($p) {
  # 보이는 창 중 제목이 '칼퇴 설정' 인 것 (위젯 창 제목 '칼퇴' 와 섞이지 않게 정확히 비교)
  foreach ($w in (Windows $p)) { $f = $w.Split('|'); if ($f[0] -eq '칼퇴 설정' -and $f[1] -eq 'True' -and [int]$f[4] -gt 50) { return @{ X=[int]$f[2]; Y=[int]$f[3]; W=[int]$f[4]; H=[int]$f[5] } } }
  return $null
}
function MenuWindow($p) {
  # 오른쪽 클릭 메뉴(WinForms ContextMenuStrip): 보이는 창 중 클래스가 WindowsForms10 으로 시작하고 크기가 있는 것.
  # (트레이 아이콘의 숨은 창은 보이지 않거나 크기가 없어 걸러진다)
  foreach ($w in (Windows $p)) { $f = $w.Split('|'); if ($f[6] -like 'WindowsForms10*' -and $f[1] -eq 'True' -and [int]$f[4] -gt 20 -and [int]$f[5] -gt 20) { return @{ X=[int]$f[2]; Y=[int]$f[3]; W=[int]$f[4]; H=[int]$f[5] } } }
  return $null
}
function WorkArea { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
# 기본 위치 = 주 모니터 작업 영역 오른쪽 위, 여백 16 (100% 배율 기준, 오차 8px)
function NearDefault($w) {
  $wa = WorkArea
  return ([math]::Abs($w.X - ($wa.Right - $w.W - 16)) -le 8 -and [math]::Abs($w.Y - ($wa.Y + 16)) -le 8)
}
function DefaultText($w) { $wa = WorkArea; return "rect=$($w.X),$($w.Y) expected~$($wa.Right - $w.W - 16),$($wa.Y + 16)" }
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
function RightClick($x, $y) { [W]::SetCursorPos($x, $y) | Out-Null; Start-Sleep -Milliseconds 200; [W]::mouse_event(0x0008,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [W]::mouse_event(0x0010,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 1000 }
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

# 4. 실행 중에 한 번 더 실행 → 새 프로세스는 곧 끝나고, 기존 위젯이 보이며 기본 위치(오른쪽 위)로 돌아와야 함
$p2 = Start-Process -FilePath $Exe -PassThru; Start-Sleep -Seconds 6
Dump 'second-launch(first proc)' $p; Shot '5-second-launch'
Check 'second-launch-first-alive' (-not $p.HasExited) ""
Check 'second-launch-exits-quietly' ($p2.HasExited) "exited=$($p2.HasExited)"
$w4 = Widget $p
Check 'second-launch-widget-visible' ($null -ne $w4) ""
if ($w4) { Check 'relaunch-resets-to-default-position' (NearDefault $w4) (DefaultText $w4) }
if (-not $p2.HasExited) { Stop-Process -Id $p2.Id -Force }

# 5. 위젯 오른쪽 클릭 → 메뉴(WinForms 팝업 창)가 뜨는지, Esc 로 닫히는지
$wm = Widget $p
if ($wm) {
  RightClick ($wm.X + 60) ($wm.Y + [int]($wm.H * 0.55))
  Dump 'context-menu' $p; Shot '6-context-menu'
  $m = MenuWindow $p
  Check 'right-click-opens-menu' ($null -ne $m) "menu=$($m.X),$($m.Y) $($m.W)x$($m.H)"
  [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); Start-Sleep -Milliseconds 800
  $still = MenuWindow $p
  Write-Host "INFO  esc-closes-menu=$($null -eq $still)"
  if ($null -ne $still) {
    # Esc 로 안 닫히면 바깥 클릭으로 닫히는지 확인한다(SetForegroundWindow 가 제대로 동작하는지)
    Click ([int]($screen.Width / 4)) ([int]($screen.Height / 2))
    Check 'menu-closes-on-outside-click' ($null -eq (MenuWindow $p)) "esc did not close it"
  }
  Shot '7-after-menu-close'
  Check 'widget-visible-after-menu' ($null -ne (Widget $p)) ""
}

# 6. 위젯을 화면 오른쪽 아래 바깥으로 거의 다 끌어낸 뒤 → 작업 영역 안으로 밀려 들어와야 함
$wd = Widget $p
if ($wd) {
  $wa = WorkArea
  # 왼쪽 가장자리 근처를 잡고 커서를 화면 끝까지 끌면 위젯이 거의 다 화면 밖으로 나간다
  Drag ($wd.X + 10) ($wd.Y + 60) ($screen.Right - 1) ($screen.Bottom - 1)
  Dump 'after-offscreen-drag' $p; Shot '8-offscreen-drag'
  $wo = Widget $p
  Check 'offscreen-drag-widget-visible' ($null -ne $wo) ""
  if ($wo) {
    $inside = ($wo.X -ge ($wa.X - 2)) -and ($wo.Y -ge ($wa.Y - 2)) -and (($wo.X + $wo.W) -le ($wa.Right + 2)) -and (($wo.Y + $wo.H) -le ($wa.Bottom + 2))
    Check 'offscreen-drag-clamped-into-workarea' $inside "rect=$($wo.X),$($wo.Y) $($wo.W)x$($wo.H) workarea=$($wa.X),$($wa.Y) $($wa.Width)x$($wa.Height)"
    Check 'offscreen-drag-pushed-to-corner' ([math]::Abs($wo.X - ($wa.Right - $wo.W)) -le 3 -and [math]::Abs($wo.Y - ($wa.Bottom - $wo.H)) -le 3) "rect=$($wo.X),$($wo.Y)"
  }
}

# 7. 빨간 점 클릭 → 숨김, 다시 실행하면 다시 보이고 기본 위치로
$w = Widget $p
if ($w) {
  Click ($w.X + 18) ($w.Y + 13)
  Dump 'after-red-dot' $p; Shot '9-after-red-dot'
  Check 'red-dot-hides' ($null -eq (Widget $p)) ""
  $p3 = Start-Process -FilePath $Exe -PassThru; Start-Sleep -Seconds 6
  Dump 'relaunch-while-hidden' $p; Shot '10-relaunch-while-hidden'
  $w3 = Widget $p
  Check 'relaunch-shows-hidden-widget' ($null -ne $w3) ""
  if ($w3) { Check 'relaunch-while-hidden-default-position' (NearDefault $w3) (DefaultText $w3) }
  if (-not $p3.HasExited) { Stop-Process -Id $p3.Id -Force }
}

# 8. 종료 후 재실행 → 위젯이 보인다
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2
Write-Host "--- saved files"; Get-ChildItem "$env:APPDATA\Kaltoe" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "--- $($_.Name)"; Get-Content $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 40 }
$p = Launch @()
Dump 'restart' $p; Shot '11-restart'
Check 'restart-widget-visible' ($null -ne (Widget $p)) ""
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2

# 9. 예전 버전이 남긴 "visible": false 가 파일에 있어도 시작하면 보여야 한다
$sf = "$env:APPDATA\Kaltoe\settings.json"
$prepared = $false
if (Test-Path $sf) {
  $t = Get-Content $sf -Raw
  $t2 = $t -replace '"visible"\s*:\s*true', '"visible": false'
  if ($t2 -ne $t) { Set-Content -Path $sf -Value $t2 -Encoding UTF8; $prepared = $true }
}
Check 'stale-hidden-flag-prepared' $prepared "settings.json 에 visible:false 를 써 넣음"
$p = Launch @()
Dump 'stale-hidden-flag' $p; Shot '12-stale-hidden-flag'
Check 'stale-hidden-flag-ignored' ($null -ne (Widget $p)) ""
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2

# 10. 말풍선 모양 드래그
$p = Launch @('--demo','working','--style','bubble')
Dump 'bubble' $p; Shot '13-bubble'
$b0 = Widget $p
Check 'bubble-visible' ($null -ne $b0) "rect=$($b0.X),$($b0.Y) $($b0.W)x$($b0.H)"
if ($b0) {
  Drag ($b0.X + 40) ($b0.Y + 20) ($b0.X - 300) ($b0.Y + 300)
  Dump 'bubble-after-drag' $p; Shot '14-bubble-after-drag'
  Check 'bubble-drag-still-visible' ($null -ne (Widget $p)) ""
}
# 10-1. 말풍선도 화면 오른쪽 아래 바깥으로 끌어내면 작업 영역 안으로
$b1 = Widget $p
if ($b1) {
  $wa = WorkArea
  Drag ($b1.X + 40) ($b1.Y + 20) ($screen.Right - 1) ($screen.Bottom - 1)
  Dump 'bubble-offscreen-drag' $p; Shot '15-bubble-offscreen-drag'
  $b2 = Widget $p
  Check 'bubble-offscreen-widget-visible' ($null -ne $b2) ""
  if ($b2) {
    $inside = ($b2.X -ge ($wa.X - 2)) -and ($b2.Y -ge ($wa.Y - 2)) -and (($b2.X + $b2.W) -le ($wa.Right + 2)) -and (($b2.Y + $b2.H) -le ($wa.Bottom + 2))
    Check 'bubble-offscreen-clamped-into-workarea' $inside "rect=$($b2.X),$($b2.Y) $($b2.W)x$($b2.H) workarea=$($wa.X),$($wa.Y) $($wa.Width)x$($wa.Height)"
  }
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2

# 11. --settings: 시작하자마자 설정 창('칼퇴 설정')이 뜬다 (데모·실제 모두)
$p = Launch @('--demo','working','--settings')
Dump 'settings-demo' $p; Shot '16-settings-demo'
$sd = SettingsWin $p
Check 'settings-arg-opens-window-demo' ($null -ne $sd) "rect=$($sd.X),$($sd.Y) $($sd.W)x$($sd.H)"
Check 'settings-demo-widget-still-visible' ($null -ne (Widget $p)) ""
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }; Start-Sleep -Seconds 2
$p = Launch @('--settings')
Dump 'settings-real' $p; Shot '17-settings-real'
$sr = SettingsWin $p
Check 'settings-arg-opens-window-real' ($null -ne $sr) "rect=$($sr.X),$($sr.Y) $($sr.W)x$($sr.H)"
Check 'settings-real-widget-still-visible' ($null -ne (Widget $p)) ""
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

Write-Host "--- event log"
Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-15) } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -in '.NET Runtime', 'Application Error' } | ForEach-Object { Write-Host $_.TimeCreated $_.ProviderName; Write-Host $_.Message }
Write-Host "=== FAILED: $($script:failed.Count) [$($script:failed -join ', ')]"
if ($script:failed.Count -gt 0) { exit 1 }
