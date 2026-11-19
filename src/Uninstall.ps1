# Intune Win32 uninstall (SYSTEM): removes the "Fix First Due" shortcuts and C:\ProgramData\FirstDueFix.
param([string]$Root = "$env:ProgramData\FirstDueFix",
      [string]$Desktop = "$env:PUBLIC\Desktop",
      [string]$StartMenu = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs")
foreach ($dir in $Desktop, $StartMenu) { Remove-Item -LiteralPath (Join-Path $dir 'Fix First Due.lnk') -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
exit 0
