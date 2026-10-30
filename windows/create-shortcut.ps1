$ErrorActionPreference = 'Stop'
$Dir  = $PSScriptRoot
$desk = [Environment]::GetFolderPath('Desktop')

# 1) 控制台启动器（cmd -> bat -> powershell，避免安全软件拦截隐藏窗口的快捷方式）
$bat = Join-Path $desk '刷课控制台.bat'
$batText = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\console.ps1`"`r`n"
Set-Content -LiteralPath $bat -Value $batText -Encoding Default

# 2) 桌面快捷方式
$lnk = Join-Path $desk '刷课控制台.lnk'
$Wsh = New-Object -ComObject WScript.Shell
$sc = $Wsh.CreateShortcut($lnk)
$sc.TargetPath = "$env:SystemRoot\System32\cmd.exe"
$sc.Arguments = '/c "' + $bat + '"'
$sc.WorkingDirectory = $desk
$sc.IconLocation = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0'
$sc.Description = '刷课控制台：后台刷课，显示进度'
$sc.Save()

# 3) 旧的“一键刷课”（会直接弹出浏览器窗口）不再需要
foreach ($name in @('一键刷课.lnk', '一键刷课.bat')) {
    $old = Join-Path $desk $name
    if (Test-Path $old) { Remove-Item -LiteralPath $old -Force }
}

Write-Host ("Created: " + $lnk)
Write-Host ("Fallback: " + $bat)
