# 把副屏那个 Edge 窗口从"被最小化 / 被挪到屏幕外"的状态恢复回来。
#
# 关窗口后 Chromium 进程常常继续存活、页面转入隐藏状态，此时视频会被节流停住。
# 这种情况下不需要重开浏览器——把窗口恢复可见即可，还能保住当前播放位置。
#
# 优先用 SetWindowPos + SWP_NOACTIVATE：改位置和大小但不激活窗口，
# 免得把正在全屏游戏的主屏弹回桌面。
$ErrorActionPreference = 'Stop'

$Dir        = $PSScriptRoot
$ProfilePointer = Join-Path $Dir 'profile_dir.txt'
$ProfileDir = ''
if (Test-Path $ProfilePointer) {
    $candidate = (Get-Content -LiteralPath $ProfilePointer -TotalCount 1).Trim()
    if ($candidate -and (Test-Path $candidate)) { $ProfileDir = $candidate }
}
if (-not $ProfileDir) { $ProfileDir = Join-Path $Dir 'edge-profile' }
$PosX = -1600
$PosY = -541
$WinW = 1067
$WinH = 820

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RestoreWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after,
        int X, int Y, int cx, int cy, uint flags);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

$SWP_NOZORDER   = 0x0004
$SWP_NOACTIVATE = 0x0010
$SWP_SHOWWINDOW = 0x0040
$flags = $SWP_NOZORDER -bor $SWP_NOACTIVATE -bor $SWP_SHOWWINDOW

# 只挑"属于本 profile 且真的有窗口"的进程，否则会拿到一堆辅助进程
$cand = $null
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")) {
    if (-not $p.CommandLine -or -not $p.CommandLine.Contains($ProfileDir)) { continue }
    $gp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
    if ($gp -and $gp.MainWindowHandle -ne 0) { $cand = $gp; break }
}
if (-not $cand) { throw '找不到副屏实例中有窗口的 Edge 进程' }

$h = $cand.MainWindowHandle
Write-Host "PID=$($cand.Id) hwnd=$h 最小化=$([RestoreWin32]::IsIconic($h)) 可见=$([RestoreWin32]::IsWindowVisible($h))"

if ([RestoreWin32]::IsIconic($h)) {
    # 先试 SW_SHOWNOACTIVATE(4)：能还原最小化窗口，但**不抢前台焦点**，
    # 不会把正在全屏游戏的主屏弹出来。
    Write-Host '窗口处于最小化，先试 SW_SHOWNOACTIVATE（不抢焦点）'
    [void][RestoreWin32]::ShowWindow($h, 4)
    Start-Sleep -Milliseconds 500
}
if ([RestoreWin32]::IsIconic($h)) {
    # 上一步不生效才退回 SW_RESTORE(9)，代价是会把窗口带到前台。
    Write-Host '仍未还原，退回 SW_RESTORE（会抢前台焦点）'
    [void][RestoreWin32]::ShowWindow($h, 9)
    Start-Sleep -Milliseconds 500
}

[void][RestoreWin32]::SetWindowPos($h, [IntPtr]::Zero, $PosX, $PosY, $WinW, $WinH, $flags)
Start-Sleep -Milliseconds 300
Write-Host "已恢复到 ($PosX,$PosY) ${WinW}x${WinH}"
