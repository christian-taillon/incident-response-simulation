# Return an executable whose bytes match the official pinned Rclone ZIP.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Root)

$ErrorActionPreference = 'Stop'
$version = 'v1.75.2'
$zipName = "rclone-$version-windows-amd64.zip"
# Digest from the official GitHub release asset metadata for v1.75.2.
$zipSHA256 = '8A9DB2BAD1DC79A65B3348FD857069598E2AAB7CF4D118B77B1DF23055AFF818'
$zip = Join-Path $Root $zipName
$bin = Join-Path $Root 'bin'
$rclone = Join-Path $bin 'rclone.exe'
$unpack = Join-Path $Root ('_rclone-check-' + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $zip)) {
    Write-Host '[+] Downloading pinned Rclone archive'
    Invoke-WebRequest -UseBasicParsing -Uri "https://downloads.rclone.org/$version/$zipName" -OutFile $zip
}
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $zipSHA256) {
    throw 'Rclone ZIP does not match the official pinned SHA256.'
}
try {
    New-Item -ItemType Directory -Path $unpack -ErrorAction Stop | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack
    $source = Get-ChildItem -LiteralPath $unpack -Filter rclone.exe -Recurse -File |
        Select-Object -First 1
    if (-not $source) { throw 'Rclone executable missing from verified ZIP.' }
    if (Test-Path -LiteralPath $bin) {
        $binItem = Get-Item -LiteralPath $bin -Force
        if ($binItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Rclone bin directory cannot be a link or junction.'
        }
    }
    else { New-Item -ItemType Directory -Path $bin | Out-Null }
    if (Test-Path -LiteralPath $rclone) {
        $binaryItem = Get-Item -LiteralPath $rclone -Force
        if ($binaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Rclone executable cannot be a link.'
        }
    }
    if (-not (Test-Path -LiteralPath $rclone) -or
        (Get-FileHash -LiteralPath $rclone -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash) {
        Copy-Item -LiteralPath $source.FullName -Destination $rclone -Force
    }
}
finally {
    if (Test-Path -LiteralPath $unpack) { Remove-Item -LiteralPath $unpack -Recurse -Force }
}
Write-Output $rclone
