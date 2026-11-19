# Creates the "Fix First Due" Win32 app from out\Install.intunewin in the CONNECTED tenant and assigns it
# Required to -GroupId. Needs an existing Graph connection (Connect-MgGraph) to -TenantId.
param([Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$GroupId,
      [string]$IntuneWin = "$PSScriptRoot\out\Install.intunewin",
      [string]$Publisher = 'IT')
$ErrorActionPreference = 'Stop'
if ((Get-MgContext).TenantId -ne $TenantId) { throw "Not connected to $TenantId" }
$g = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
$name = 'Fix First Due'

$existing = (Invoke-MgGraphRequest GET "$g`?`$filter=displayName eq '$name'&`$select=id,displayName").value
if ($existing) { "exists: $($existing[0].id) (skipped)"; return }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmp = Join-Path $env:TEMP "fixfd-iw-$(Get-Random)"; New-Item -ItemType Directory $tmp | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($IntuneWin)
$zip.Entries | Where-Object { $_.Name -in 'Detection.xml', 'IntunePackage.intunewin' } |
  ForEach-Object { [IO.Compression.ZipFileExtensions]::ExtractToFile($_, (Join-Path $tmp $_.Name), $true) }
$zip.Dispose()
[xml]$det = Get-Content "$tmp\Detection.xml"
$ai = $det.ApplicationInfo; $enc = $ai.EncryptionInfo
$payload = "$tmp\IntunePackage.intunewin"
$detect = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PSScriptRoot\Detect.ps1"))

$app = @{
  '@odata.type'                  = '#microsoft.graph.win32LobApp'
  displayName                    = $name
  description                    = 'Puts a "Fix First Due" shortcut on the desktop and Start menu. It closes Edge and Chrome, clears First Due''s saved site data for the signed-in user (fixes First Due hanging / RESULT_CODE_HUNG while InPrivate works) and reopens First Due. Unsynced offline ePCRs are lost; the dialog warns first. Source: https://github.com/RobertSTFD4/fix-firstdue'
  publisher                      = $Publisher
  displayVersion                 = '1.0.0'
  fileName                       = $ai.FileName
  setupFilePath                  = 'Install.ps1'
  installCommandLine             = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1'
  uninstallCommandLine           = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1'
  installExperience              = @{ runAsAccount = 'system'; deviceRestartBehavior = 'suppress'; maxRunTimeInMinutes = 15 }
  applicableArchitectures        = 'x86,x64'
  minimumSupportedWindowsRelease = '1607'
  rules                          = @(@{ '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptRule'; ruleType = 'detection'
                                        scriptContent = $detect; enforceSignatureCheck = $false; runAs32Bit = $false })
  returnCodes                    = @(@{ returnCode = 0; type = 'success' }, @{ returnCode = 3010; type = 'softReboot' },
                                     @{ returnCode = 1641; type = 'hardReboot' }, @{ returnCode = 1618; type = 'retry' })
}
$new = Invoke-MgGraphRequest POST $g -Body ($app | ConvertTo-Json -Depth 10)
$id = $new.id; "app $id"

$cv = Invoke-MgGraphRequest POST "$g/$id/microsoft.graph.win32LobApp/contentVersions" -Body '{}'
$fileBody = @{ '@odata.type' = '#microsoft.graph.mobileAppContentFile'; name = $ai.FileName; size = [long]$ai.UnencryptedContentSize; sizeEncrypted = (Get-Item $payload).Length; isDependency = $false } | ConvertTo-Json
$f = Invoke-MgGraphRequest POST "$g/$id/microsoft.graph.win32LobApp/contentVersions/$($cv.id)/files" -Body $fileBody
$fUri = "$g/$id/microsoft.graph.win32LobApp/contentVersions/$($cv.id)/files/$($f.id)"
do { Start-Sleep 3; $f = Invoke-MgGraphRequest GET $fUri } while ($f.uploadState -eq 'azureStorageUriRequestPending')
if ($f.uploadState -ne 'azureStorageUriRequestSuccess') { throw "SAS request: $($f.uploadState)" }

# Small package: one block. The body must be [byte[]] (an object[] body makes the commit fail).
$sas = $f.azureStorageUri
$bid = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('0000'))
[byte[]]$bytes = [IO.File]::ReadAllBytes($payload)
Invoke-WebRequest "$sas&comp=block&blockid=$([uri]::EscapeDataString($bid))" -Method Put -Body $bytes -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -UseBasicParsing | Out-Null
Invoke-WebRequest "$sas&comp=blocklist" -Method Put -Body "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList><Latest>$bid</Latest></BlockList>" -ContentType 'application/xml' -UseBasicParsing | Out-Null

$commit = @{ fileEncryptionInfo = @{
  encryptionKey = $enc.EncryptionKey; macKey = $enc.MacKey; initializationVector = $enc.InitializationVector; mac = $enc.Mac
  profileIdentifier = 'ProfileVersion1'; fileDigest = $enc.FileDigest; fileDigestAlgorithm = $enc.FileDigestAlgorithm } } | ConvertTo-Json
Invoke-MgGraphRequest POST "$fUri/commit" -Body $commit | Out-Null
do { Start-Sleep 5; $f = Invoke-MgGraphRequest GET $fUri } while ($f.uploadState -eq 'commitFilePending')
if ($f.uploadState -ne 'commitFileSuccess') { throw "commit: $($f.uploadState)" }
Invoke-MgGraphRequest PATCH "$g/$id" -Body (@{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = $cv.id } | ConvertTo-Json) | Out-Null
Remove-Item $tmp -Recurse -Force
"committed content version $($cv.id)"

$assign = @{ mobileAppAssignments = @(@{
  '@odata.type' = '#microsoft.graph.mobileAppAssignment'; intent = 'required'
  target   = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $GroupId }
  settings = @{ '@odata.type' = '#microsoft.graph.win32LobAppAssignmentSettings'; notifications = 'hideAll'; deliveryOptimizationPriority = 'notConfigured' } }) }
Invoke-MgGraphRequest POST "$g/$id/assign" -Body ($assign | ConvertTo-Json -Depth 10) | Out-Null

$rb = Invoke-MgGraphRequest GET "$g/$id`?`$expand=assignments"
"READBACK $name $id | published=$($rb.publishingState) committed=$($rb.committedContentVersion) | " +
  (($rb.assignments | ForEach-Object { "$($_.intent):$($_.target.groupId)" }) -join '; ')
