# Optional, deliberately recoverable credential artifact for the lab exercise.
[CmdletBinding()]
param(
    [switch]$Write,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
if ($Write -eq $Remove) {
    throw 'Specify exactly one action: -Write or -Remove.'
}
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$marker = Join-Path $root '.synthetic-only'
$path = Join-Path $root 'mega-credentials.env'
$notes = Join-Path $root 'operator-notes.txt'
$signature = 'CSWORKSHOP-SYNTHETIC-ONLY'

if ($Remove) {
    Remove-Item -LiteralPath $path, $notes -Force -ErrorAction SilentlyContinue
    Write-Host '[OK] Removed the optional plaintext exercise artifacts'
    return
}
if (-not (Test-Path -LiteralPath $marker) -or
    (Get-Content -LiteralPath $marker -Raw).Trim() -ne $signature) {
    throw 'Synthetic lab marker missing. Run prepare.ps1 first.'
}
if (-not $env:MEGA_EMAIL -or -not $env:MEGA_PASSWORD) {
    throw 'Set MEGA_EMAIL and MEGA_PASSWORD in this PowerShell session.'
}
if ($env:MEGA_EMAIL -match '[\r\n]' -or $env:MEGA_PASSWORD -match '[\r\n]') {
    throw 'Newline characters are not supported in this lab credential artifact.'
}

$lines = @(
    '# SYNTHETIC WORKSHOP ACCOUNT ONLY'
    "# $signature"
    "MEGA_EMAIL=$env:MEGA_EMAIL"
    "MEGA_PASSWORD=$env:MEGA_PASSWORD"
)
[System.IO.File]::WriteAllLines($path, $lines, [System.Text.UTF8Encoding]::new($false))

$run = '(not started)'
$remote = 'workshopmega:CSWorkshop/<host>/<run-id>'
$last = Join-Path $root 'last-run.txt'
if (Test-Path -LiteralPath $last) {
    $run = (Get-Content -LiteralPath $last -Raw).Trim()
    $runFile = Join-Path (Join-Path $root 'runs') "$run.json"
    if (Test-Path -LiteralPath $runFile) {
        $meta = Get-Content -LiteralPath $runFile -Raw | ConvertFrom-Json
        $remote = $meta.RemoteDir
    }
}
@(
    "Synthetic operator notes for $signature"
    "Host: $env:COMPUTERNAME"
    "Last run: $run"
    "Cloud destination: $remote"
    'Staging and transfer logs are under LOCALAPPDATA\CSWorkshop.'
) | Set-Content -LiteralPath $notes -Encoding ASCII

Write-Warning 'Plaintext lab-only MEGA credentials now exist on disk. Rotate them after the exercise.'
Write-Host "[OK] Artifact: $path"
Write-Host "[OK] Notes: $notes"
