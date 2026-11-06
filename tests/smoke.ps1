# Offline smoke test for Windows PowerShell 5.1+. No MEGA account or network needed.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$oldLocalAppData = $env:LOCALAPPDATA
$temporaryRoot = Join-Path $env:TEMP ("IRS-smoke-" + [guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA = $temporaryRoot

try {
    $data = Join-Path $repo 'scenarios\data-exfiltration'
    & (Join-Path $data 'prepare.ps1') -ExtraMiB 1
    & (Join-Path $data 'execute.ps1') -ValidateOnly

    $docs = Join-Path $temporaryRoot 'CSWorkshop\ClientDocuments'
    $files = @(Get-ChildItem -LiteralPath $docs -Recurse -File)
    if ($files.Count -ne 31) { throw "Expected 31 synthetic files, got $($files.Count)" }

    # The transfer must refuse a modified document before any network activity.
    $matter = Join-Path $docs 'Redwood\Matter-001.txt'
    Add-Content -LiteralPath $matter -Value 'Unexpected modification'
    $rejected = $false
    try { & (Join-Path $data 'execute.ps1') -ValidateOnly } catch { $rejected = $true }
    if (-not $rejected) { throw 'Dataset modification was not rejected.' }

    $sample = Join-Path $temporaryRoot 'sample.ps1'
    [System.IO.File]::WriteAllText($sample, 'Write-Output "smoke"')
    $encoder = Join-Path $repo 'scenarios\remote-execution\encode.ps1'
    $command = & $encoder -Path $sample
    $encoded = ($command -split ' ')[-1]
    $decoded = & $encoder -Decode $encoded
    if ($decoded -cne 'Write-Output "smoke"') { throw 'EncodedCommand round-trip failed.' }

    Write-Host '[OK] Offline smoke tests passed'
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
