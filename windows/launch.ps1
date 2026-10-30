# 在副屏启动一个独立的 Edge 实例，用于静音挂载超星学习通课程视频。
# 独立 user-data-dir => 不影响正在运行的主 Edge，且启动参数全部生效。
#
# 用法：launch.ps1 [-Url "课程页地址"]
# 传 -Url 可以直接恢复到某一章，不用从首页重新点进去。
param(
    [string]$Url = '',
    [switch]$Hidden
)

# 课程页 URL 带 & 等字符，用 -File 传参会被 PowerShell 解析坏；
# 支持用环境变量 COURSE_URL 传，绕开引号地狱。
if (-not $Url -and $env:COURSE_URL) { $Url = $env:COURSE_URL }
if (-not $Url) { $Url = 'https://i.chaoxing.com' }

$ErrorActionPreference = 'Stop'

$EdgeExe    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

# 浏览器配置目录：优先读 profile_dir.txt（本机路径，已被 .gitignore 排除）；
# 没有就用 %LOCALAPPDATA%\ChaoxingStudyEdge（换电脑首次运行会自动新建，需要重新登录并装篡改猴）。
$ProfilePointer = Join-Path $PSScriptRoot 'profile_dir.txt'
$ProfileDir = ''
if (Test-Path $ProfilePointer) {
    $candidate = (Get-Content -LiteralPath $ProfilePointer -TotalCount 1).Trim()
    if ($candidate -and (Test-Path $candidate)) { $ProfileDir = $candidate }
}
if (-not $ProfileDir) { $ProfileDir = Join-Path $env:LOCALAPPDATA 'ChaoxingStudyEdge' }
$Port       = 9222

# 默认放在主屏可见位置；-Hidden 时移到屏幕外，播放不中断但用户看不到。
if ($Hidden) {
    $PosX = -2000
    $PosY = -2000
} else {
    $PosX = 100
    $PosY = 80
}
$WinW = 1100
$WinH = 900

if (-not (Test-Path $EdgeExe)) { throw "找不到 Edge: $EdgeExe" }
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GuardWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@

$edgeArgs = @(
    "--user-data-dir=$ProfileDir"
    "--remote-debugging-port=$Port"
    "--remote-allow-origins=*"
    '--no-first-run'
    '--no-default-browser-check'
    '--disable-sync'
    '--disable-component-update'
    '--disable-session-crashed-bubble'
    '--hide-crash-restore-bubble'
    '--mute-audio'
    '--autoplay-policy=no-user-gesture-required'
    '--disable-background-timer-throttling'
    '--disable-backgrounding-occluded-windows'
    '--disable-renderer-backgrounding'
    "--window-position=$PosX,$PosY"
    "--window-size=$WinW,$WinH"
    $Url
)

Start-Process -FilePath $EdgeExe -ArgumentList $edgeArgs
Write-Host "已启动独立 Edge 实例 (profile: $ProfileDir)"

# 等 CDP 端点就绪
$ready = $false
foreach ($i in 1..60) {
    try {
        Invoke-RestMethod "http://127.0.0.1:$Port/json/version" -TimeoutSec 1 | Out-Null
        $ready = $true
        break
    } catch { Start-Sleep -Milliseconds 250 }
}
if (-not $ready) { throw "CDP 端口 $Port 未就绪，启动可能失败" }
Write-Host "CDP 端点就绪: http://127.0.0.1:$Port"

# 负坐标在 --window-position 上可能被钳制，用 MoveWindow 强制挪到副屏
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    $p = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
         Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileDir) } |
         Select-Object -First 1
    if ($p) {
        $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne 0) {
            [GuardWin32]::MoveWindow($proc.MainWindowHandle, $PosX, $PosY, $WinW, $WinH, $true) | Out-Null
            Write-Host "窗口已定位到副屏: ($PosX,$PosY) ${WinW}x${WinH}"
            break
        }
    }
    Start-Sleep -Milliseconds 400
}

Write-Host ''
Write-Host '下一步：在这个新窗口里登录学习通并打开课程视频页，然后运行 guard.py。'
