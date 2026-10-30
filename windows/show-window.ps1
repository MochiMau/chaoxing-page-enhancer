# Move the dedicated Edge window onto the primary display so the user can log in.
param(
    [int]$X = 100,
    [int]$Y = 80,
    [int]$W = 1100,
    [int]$H = 900
)
$ErrorActionPreference = 'Stop'
$ProfilePointer = Join-Path $PSScriptRoot 'profile_dir.txt'
$ProfileDir = ''
if (Test-Path $ProfilePointer) {
    $candidate = (Get-Content -LiteralPath $ProfilePointer -TotalCount 1).Trim()
    if ($candidate -and (Test-Path $candidate)) { $ProfileDir = $candidate }
}
if (-not $ProfileDir) { $ProfileDir = Join-Path $PSScriptRoot 'edge-profile' }
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$cand = $null
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")) {
    if (-not $p.CommandLine -or -not $p.CommandLine.Contains($ProfileDir)) { continue }
    $gp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
    if ($gp -and $gp.MainWindowHandle -ne 0) { $cand = $gp; break }
}
if (-not $cand) { throw 'no Edge window for this profile' }
[void][W32]::ShowWindow($cand.MainWindowHandle, 9)
[void][W32]::SetWindowPos($cand.MainWindowHandle, [IntPtr]::Zero, $X, $Y, $W, $H, 0x0040)
# 移到屏幕外时不要把焦点抢过去（否则键盘输入会落到看不见的窗口）
if ($X -gt -1000 -and $Y -gt -1000) { [void][W32]::SetForegroundWindow($cand.MainWindowHandle) }
Write-Host "moved pid=$($cand.Id) to ($X,$Y) ${W}x${H}"
