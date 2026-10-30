param([string]$Url = '', [switch]$Hidden)

$ErrorActionPreference = 'Stop'
$Dir        = $PSScriptRoot
$EdgeExe    = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$Port       = 9222

$ProfilePointer = Join-Path $Dir 'profile_dir.txt'
$ProfileDir = ''
if (Test-Path $ProfilePointer) {
    $candidate = (Get-Content -LiteralPath $ProfilePointer -TotalCount 1).Trim()
    if ($candidate -and (Test-Path $candidate)) { $ProfileDir = $candidate }
}
if (-not $ProfileDir) { $ProfileDir = Join-Path $env:LOCALAPPDATA 'ChaoxingStudyEdge' }

if (-not $Url) {
    $urlFile = Join-Path $Dir 'course_url.txt'
    if (Test-Path $urlFile) { $Url = (Get-Content -LiteralPath $urlFile -TotalCount 1).Trim() }
}
if (-not $Url) { $Url = 'https://i.chaoxing.com' }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BrushWin32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@

# Is a course page already open?
$hasCourse = $false
try {
    $tabs = Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
    $hasCourse = @($tabs | Where-Object { $_.type -eq 'page' -and $_.url -like '*studentstudy*' }).Count -gt 0
} catch { }

# Find the main window of the dedicated profile
$cand = $null
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")) {
    if (-not $p.CommandLine -or -not $p.CommandLine.Contains($ProfileDir)) { continue }
    $gp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
    if ($gp -and $gp.MainWindowHandle -ne 0) { $cand = $gp; break }
}

if ($cand) {
    if ($Hidden) {
        & (Join-Path $Dir 'show-window.ps1') -X -2000 -Y -2000 -W 1100 -H 900
    } else {
        [void][BrushWin32]::ShowWindow($cand.MainWindowHandle, 9)
        [void][BrushWin32]::SetForegroundWindow($cand.MainWindowHandle)
    }
    if (-not $hasCourse) {
        Start-Process -FilePath $EdgeExe -ArgumentList @("--user-data-dir=$ProfileDir", "--remote-debugging-port=$Port", $Url)
        Write-Host 'Opened the course page in a new tab.'
    } else {
        Write-Host 'Already running; window focused.'
    }
    exit 0
}

& (Join-Path $Dir 'launch.ps1') -Url $Url -Hidden:$Hidden
