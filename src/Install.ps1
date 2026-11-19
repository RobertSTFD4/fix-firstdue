# Intune Win32 install (SYSTEM): puts the "Fix First Due" tool in C:\ProgramData\FirstDueFix and adds
# shortcuts to the Public Desktop and the all-users Start menu. Detection: version.txt = $Version.
param([string]$Root = "$env:ProgramData\FirstDueFix",
      [string]$Desktop = "$env:PUBLIC\Desktop",
      [string]$StartMenu = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
$ErrorActionPreference = 'Stop'
$Version = '1.0.0'

New-Item -ItemType Directory -Force $Root | Out-Null
foreach ($f in 'Fix-FirstDue.ps1', 'Clear-FirstDueSiteData.ps1', 'app.ico') {
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $Root -Force
}

$shell = New-Object -ComObject WScript.Shell
foreach ($dir in $Desktop, $StartMenu) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lnk = $shell.CreateShortcut((Join-Path $dir 'Fix First Due.lnk'))
  $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Root\Fix-FirstDue.ps1`""
  $lnk.IconLocation = "$Root\app.ico,0"
  $lnk.Description = 'Reset First Due if it hangs or will not load in Edge or Chrome'
  $lnk.WorkingDirectory = $Root
  $lnk.Save()
}

Set-Content -LiteralPath (Join-Path $Root 'version.txt') -Value $Version
exit 0
