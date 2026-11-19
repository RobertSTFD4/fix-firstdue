<#
.SYNOPSIS
  Clears First Due's stored site data from the signed-in user's Edge and Chrome profiles.

.DESCRIPTION
  File-level equivalent of edge://settings/content/all -> search "firstdue" -> Remove all shown,
  which fixed First Due hanging (RESULT_CODE_HUNG) in normal windows while InPrivate worked
  (November 2026). Chrome/Edge 136+ refuse remote debugging on the real profile,
  so the browser can't be driven to do it; the data is removed from disk with the browser closed.

  Per profile (Default, Profile N):
    - cookies whose host contains "firstdue"            (Network\Cookies, row delete)
    - IndexedDB\https_*firstdue*                         (per-site folders)
    - WebStorage buckets whose storage key has firstdue  (folders + QuotaManager rows; covers
      Cache Storage and third-party storage partitioned under First Due)
    - Local Storage, Service Worker, Cache, Code Cache   (shared stores with no per-site split:
      reset for ALL sites. Logins are cookies and are kept; sites rebuild these on next visit.)

  WARNING: First Due keeps offline-saved, not-yet-uploaded ePCRs in IndexedDB. Those are deleted.

  A browser with an open window is skipped (nothing touched) and reported. A browser running only
  in the background (Edge startup boost, Chrome background apps) has no window and is stopped first.

  Runs as the signed-in user (Intune remediation: run as logged-on credentials, 64-bit).
  Exit 0 = cleared or nothing to clear; exit 1 = at least one browser was skipped or failed.
#>
param(
  [string[]]$UserDataRoots = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:LOCALAPPDATA\Google\Chrome\User Data"),
  [switch]$SkipProcessCheck,  # testing only: don't look for running browsers
  [switch]$ReportOnly         # list what would be removed, change nothing
)

$ErrorActionPreference = 'Stop'
$Match = 'firstdue'

if (-not ('FdSql' -as [type])) {
  Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class FdSql {
  [DllImport("winsqlite3.dll", CharSet=CharSet.Unicode)] static extern int sqlite3_open16(string f, out IntPtr db);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_close(IntPtr db);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_busy_timeout(IntPtr db, int ms);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_prepare16_v2(IntPtr db, [MarshalAs(UnmanagedType.LPWStr)] string sql, int n, out IntPtr st, IntPtr tail);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_step(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_finalize(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_column_count(IntPtr st);
  [DllImport("winsqlite3.dll")] static extern IntPtr sqlite3_column_text16(IntPtr st, int i);
  [DllImport("winsqlite3.dll")] static extern int sqlite3_changes(IntPtr db);
  public static List<string[]> Run(string file, string sql, out int changes) {
    IntPtr db; var rows = new List<string[]>(); changes = 0;
    if (sqlite3_open16(file, out db) != 0) { sqlite3_close(db); throw new Exception("cannot open " + file); }
    try {
      sqlite3_busy_timeout(db, 5000);
      IntPtr st;
      if (sqlite3_prepare16_v2(db, sql, -1, out st, IntPtr.Zero) != 0) throw new Exception("bad sql: " + sql);
      try {
        int rc;
        while ((rc = sqlite3_step(st)) == 100) {
          int n = sqlite3_column_count(st); var r = new string[n];
          for (int i = 0; i < n; i++) r[i] = Marshal.PtrToStringUni(sqlite3_column_text16(st, i));
          rows.Add(r);
        }
        if (rc != 101) throw new Exception("sqlite step rc=" + rc + " on " + file);
      } finally { sqlite3_finalize(st); }
      changes = sqlite3_changes(db);
    } finally { sqlite3_close(db); }
    return rows;
  }
}
'@
}

function Invoke-Sql([string]$File, [string]$Sql) {
  $n = 0; $rows = [FdSql]::Run($File, $Sql, [ref]$n); [pscustomobject]@{ Rows = $rows; Changes = $n }
}

function Remove-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  if ($ReportOnly) { return 1 }
  # Windows PowerShell 5.1's Remove-Item -Recurse fails on some nested browser files (seen on Cache\index-dir),
  # so delete through .NET with retries and fall back to rd.
  for ($i = 0; $i -lt 3 -and (Test-Path -LiteralPath $Path); $i++) {
    try { [IO.Directory]::Delete($Path, $true) } catch { Start-Sleep -Seconds 1 }
  }
  if (Test-Path -LiteralPath $Path) { cmd.exe /c rd /s /q "`"$Path`"" 2>$null | Out-Null }
  if (Test-Path -LiteralPath $Path) { throw "could not delete $Path" }
  1
}

function Clear-Profile([string]$ProfileDir) {
  $r = [ordered]@{ cookies = 0; idb = 0; buckets = 0; shared = 0 }

  foreach ($db in @("$ProfileDir\Network\Cookies", "$ProfileDir\Cookies")) {
    if (-not (Test-Path -LiteralPath $db)) { continue }
    if ($ReportOnly) { $r.cookies += (Invoke-Sql $db "select count(*) from cookies where host_key like '%$Match%'").Rows[0][0] }
    else { $r.cookies += (Invoke-Sql $db "delete from cookies where host_key like '%$Match%'").Changes }
  }

  if (Test-Path -LiteralPath "$ProfileDir\IndexedDB") {
    Get-ChildItem -LiteralPath "$ProfileDir\IndexedDB" -Directory | Where-Object Name -like "*$Match*" |
      ForEach-Object { $r.idb += Remove-Dir $_.FullName }
  }

  $qm = "$ProfileDir\WebStorage\QuotaManager"
  if (Test-Path -LiteralPath $qm) {
    $ids = (Invoke-Sql $qm "select id from buckets where storage_key like '%$Match%'").Rows | ForEach-Object { $_[0] }
    foreach ($id in $ids) { [void](Remove-Dir "$ProfileDir\WebStorage\$id"); $r.buckets++ }
    if ($ids -and -not $ReportOnly) { [void](Invoke-Sql $qm "delete from buckets where storage_key like '%$Match%'") }
  }

  foreach ($d in 'Local Storage', 'Service Worker', 'Cache', 'Code Cache') { $r.shared += Remove-Dir "$ProfileDir\$d" }
  $r
}

$lines = @(); $failed = $false
foreach ($root in $UserDataRoots) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  $browser = if ($root -match 'Chrome') { 'Chrome' } else { 'Edge' }
  $exe = if ($browser -eq 'Chrome') { 'chrome' } else { 'msedge' }

  if (-not $SkipProcessCheck) {
    $session = (Get-Process -Id $PID).SessionId
    $procs = @(Get-Process -Name $exe -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session)
    if ($procs | Where-Object { $_.MainWindowHandle -ne 0 }) {
      $lines += "${browser}: OPEN - skipped, close it and run again"; $failed = $true; continue
    }
    if ($procs -and -not $ReportOnly) {
      $procs | Stop-Process -Force -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 3
    }
  }

  $profiles = Get-ChildItem -LiteralPath $root -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Preferences') }
  foreach ($p in $profiles) {
    try {
      $r = Clear-Profile $p.FullName
      $lines += "${browser}/$($p.Name): cookies=$($r.cookies) idb=$($r.idb) buckets=$($r.buckets) shared=$($r.shared)"
    } catch {
      $lines += "${browser}/$($p.Name): FAILED $($_.Exception.Message)"; $failed = $true
    }
  }
}

$mode = if ($ReportOnly) { 'REPORT ONLY' } else { 'cleared' }
if (-not $lines) { $lines = @('no Edge/Chrome profiles found') }
Write-Output ("First Due site data $mode for ${env:USERNAME}: " + ($lines -join '; '))
if ($failed) { exit 1 } else { exit 0 }
