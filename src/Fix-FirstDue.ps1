<#
.SYNOPSIS
  "Fix First Due" desktop shortcut: closes Edge and Chrome, clears First Due's saved site data for the
  signed-in user, then reopens First Due in Edge.

.DESCRIPTION
  Self-service version of the fix for First Due hanging (RESULT_CODE_HUNG) in a normal window while
  InPrivate works. The clearing itself is Clear-FirstDueSiteData.ps1 next to this file.
  Installed to C:\ProgramData\FirstDueFix by Install.ps1; log in %LOCALAPPDATA%\FirstDueFix\fix.log.

  -Quiet (testing): no dialogs, doesn't close or open browsers; passes -UserDataRoots through.
#>
param([string[]]$UserDataRoots, [switch]$Quiet)

$FirstDueUrl = 'https://sizeup.firstduesizeup.com/'
$logDir = Join-Path $env:LOCALAPPDATA 'FirstDueFix'
New-Item -ItemType Directory -Force $logDir | Out-Null
function Log([string]$m) { Add-Content -Path (Join-Path $logDir 'fix.log') -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) }

Add-Type -AssemblyName System.Windows.Forms
function Show-Box([string]$text, [string]$buttons = 'OK', [string]$icon = 'Information') {
  if ($Quiet) { return 'Yes' }
  $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
  try { [System.Windows.Forms.MessageBox]::Show($owner, $text, 'Fix First Due',
          [System.Windows.Forms.MessageBoxButtons]$buttons, [System.Windows.Forms.MessageBoxIcon]$icon).ToString() }
  finally { $owner.Dispose() }
}

$answer = Show-Box ("This will close Edge and Chrome, then clear First Due's saved data on this computer so it loads fresh. " +
  "You will need to sign in to First Due again.`n`n" +
  "Before you continue: make sure any report you have open is saved and uploaded. " +
  "Reports saved offline that have not uploaded yet will be lost.`n`nContinue?") 'YesNo' 'Warning'
if ($answer -ne 'Yes') { Log 'cancelled by user'; exit 0 }

if (-not $Quiet) {
  $session = (Get-Process -Id $PID).SessionId
  $mine = { @(Get-Process -Name msedge, chrome -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session) }
  # Ask every browser window to close (saves the session), then stop whatever is left after 15 s.
  $deadline = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $deadline) {
    $windowed = & $mine | Where-Object { $_.MainWindowHandle -ne 0 }
    if (-not $windowed) { break }
    $windowed | ForEach-Object { [void]$_.CloseMainWindow() }
    Start-Sleep -Milliseconds 750
  }
  & $mine | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
}

$clearArgs = @{}
if ($UserDataRoots) { $clearArgs.UserDataRoots = $UserDataRoots }
if ($Quiet) { $clearArgs.SkipProcessCheck = $true }
$out = & (Join-Path $PSScriptRoot 'Clear-FirstDueSiteData.ps1') @clearArgs 2>&1 | Out-String
$code = $LASTEXITCODE
Log "exit=$code $($out.Trim())"

if ($code -eq 0) {
  if (-not $Quiet) { Start-Process 'msedge.exe' $FirstDueUrl }
  [void](Show-Box "Done. First Due has been reset.`n`nEdge is opening First Due now; sign in again.")
} else {
  [void](Show-Box ("First Due could not be fully reset.`n`n$($out.Trim())`n`n" +
    "Close every Edge and Chrome window and try again. If it still fails, contact IT.") 'OK' 'Error')
}
exit $code
