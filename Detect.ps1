# Intune Win32 detection: installed when version.txt matches and the desktop shortcut exists.
$root = "$env:ProgramData\FirstDueFix"
if ((Test-Path "$env:PUBLIC\Desktop\Fix First Due.lnk") -and
    (Test-Path "$root\version.txt") -and ((Get-Content "$root\version.txt" -Raw).Trim() -eq '1.0.0')) {
  Write-Output 'Fix First Due 1.0.0 installed'
}
exit 0
