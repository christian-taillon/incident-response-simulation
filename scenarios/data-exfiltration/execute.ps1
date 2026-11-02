# Stage, archive, and upload only synthetic workshop documents to MEGA.
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$docs = Join-Path $root 'ClientDocuments'
$marker = Join-Path $root '.synthetic-only'
$markerText = 'CSWORKSHOP-SYNTHETIC-ONLY'
$bin = Join-Path $root 'bin'
$rclone = Join-Path $bin 'rclone.exe'
$config = Join-Path $root 'rclone.conf'

if (-not (Test-Path -LiteralPath $marker) -or
    (Get-Content -LiteralPath $marker -Raw).Trim() -ne $markerText) {
    throw 'Run prepare.ps1 first: synthetic-data marker not found.'
}
if (-not (Test-Path -LiteralPath $docs)) {
    throw 'Synthetic documents not found.'
}
if (-not $env:MEGA_EMAIL -or -not $env:MEGA_PASSWORD) {
    throw 'Set MEGA_EMAIL and MEGA_PASSWORD in the current PowerShell session.'
}

# Refuse unexpected files or links: no real documents should be uploaded.
$links = @(Get-ChildItem -LiteralPath $docs -Recurse -Force |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
if ($links.Count -gt 0) { throw 'Reparse points are not allowed in synthetic documents.' }

$files = @(Get-ChildItem -LiteralPath $docs -Recurse -File)
if ($files.Count -eq 0) { throw 'Synthetic document folder is empty.' }
foreach ($file in $files) {
    if ($file.Extension -notin @('.txt', '.csv', '.rtf') -or
        -not (Select-String -LiteralPath $file.FullName -Pattern $markerText -SimpleMatch -Quiet)) {
        throw "Non-synthetic or unsupported file found: $($file.FullName)"
    }
}

# Use the same portable Rclone version already tested for this workshop.
if (-not (Test-Path -LiteralPath $rclone)) {
    $version = 'v1.75.2'
    $name = "rclone-$version-windows-amd64.zip"
    $zip = Join-Path $root $name
    $unpack = Join-Path $root '_rclone-download'
    New-Item -ItemType Directory -Path $bin, $unpack -Force | Out-Null

    Write-Host '[+] Downloading Rclone from downloads.rclone.org'
    Invoke-WebRequest -UseBasicParsing -Uri "https://downloads.rclone.org/$version/$name" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
    $source = Get-ChildItem -LiteralPath $unpack -Filter 'rclone.exe' -File -Recurse |
        Select-Object -First 1
    if (-not $source) { throw 'Rclone executable not found in downloaded archive.' }
    Copy-Item -LiteralPath $source.FullName -Destination $rclone -Force
    Remove-Item -LiteralPath $zip -Force
    Remove-Item -LiteralPath $unpack -Recurse -Force
}

& $rclone version
if ($LASTEXITCODE -ne 0) {
    throw 'Rclone could not execute. Check CrowdStrike Application Abuse events.'
}

# Rclone config contains a reversibly obscured password, not encryption.
$obscured = $env:MEGA_PASSWORD | & $rclone obscure -
if ($LASTEXITCODE -ne 0 -or -not $obscured) {
    throw 'Could not configure MEGA password.'
}
$content = @"
[workshopmega]
type = mega
user = $env:MEGA_EMAIL
pass = $obscured
use_https = true
"@
[System.IO.File]::WriteAllText($config, $content, [System.Text.UTF8Encoding]::new($false))

$run = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$staging = Join-Path $root "staging-$run"
$archive = Join-Path $root "client-data-$run.zip"
$log = Join-Path $root "transfer-$run.log"
$remoteDir = "workshopmega:CSWorkshop/$env:COMPUTERNAME/$run"
$destination = "$remoteDir/client-data.zip"

Write-Host '[+] Staging synthetic documents with Robocopy'
& robocopy.exe $docs $staging /E /XJ /R:0 /W:0
if ($LASTEXITCODE -ge 8) { throw 'Robocopy failed.' }

Write-Host '[+] Creating ZIP archive with Tar'
& tar.exe -a -cf $archive -C $staging .
if ($LASTEXITCODE -ne 0) { throw 'Archive creation failed.' }

Write-Host '[+] Uploading synthetic archive to MEGA'
& $rclone --config $config copyto $archive $destination --log-level INFO --log-file $log
if ($LASTEXITCODE -ne 0) { throw "Transfer failed; check $log" }

& $rclone --config $config ls $remoteDir
if ($LASTEXITCODE -ne 0) { throw 'Remote listing failed after transfer.' }

Write-Host "[OK] Uploaded $archive to $destination"
Write-Host "[OK] Transfer log: $log"
