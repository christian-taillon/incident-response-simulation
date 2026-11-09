# Prepare exclusively fictional documents for the incident simulation.
[CmdletBinding()]
param(
    [ValidateRange(0, 64)]
    [int]$ExtraMiB = 32
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$docs = Join-Path $root 'ClientDocuments'
$marker = Join-Path $root '.synthetic-only'
$manifest = Join-Path $root 'dataset-manifest.csv'
$signature = 'CSWORKSHOP-SYNTHETIC-ONLY'

if (Test-Path -LiteralPath $docs) {
    if ((Test-Path -LiteralPath $marker) -and (Test-Path -LiteralPath $manifest)) {
        Write-Host "[OK] Dataset already exists: $docs (not overwritten)"
        return
    }
    throw "Refusing to overwrite an unverified or incomplete dataset: $docs"
}

New-Item -ItemType Directory -Path $docs -Force | Out-Null
Set-Content -LiteralPath $marker -Value $signature -Encoding ASCII

foreach ($client in @('Redwood', 'Saguaro', 'Aspen')) {
    $dir = Join-Path $docs $client
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    1..8 | ForEach-Object {
        $number = '{0:D3}' -f $_
        $matterText = @"
$signature
CONFIDENTIAL - FICTIONAL TRAINING DATA
Client: $client
Matter: MAT-$number
Subject: Privileged client correspondence
This document contains no real client information.
"@
        Set-Content -LiteralPath (Join-Path $dir "Matter-$number.txt") -Value $matterText -Encoding ASCII
    }

    1..100 | ForEach-Object {
        [pscustomobject]@{
            Marker = $signature
            Client = $client
            Matter = ('MAT-{0:D3}' -f $_)
            Amount = $_ * 1250
            Status = 'Fictional - Training'
        }
    } | Export-Csv -LiteralPath (Join-Path $dir 'Billing.csv') -NoTypeInformation -Encoding UTF8

    $memo = @"
{\rtf1\ansi
\b ATTORNEY WORK PRODUCT - FICTIONAL TRAINING DATA\b0\par
$signature\par
Client: $client\par
Matter: Confidential Acquisition\par
All content is fictional.\par
}
"@
    Set-Content -LiteralPath (Join-Path $dir 'Legal-Memorandum.rtf') -Value $memo -Encoding ASCII
}

# Incompressible random bytes keep the uploaded ZIP large enough to investigate
# network-volume questions. No source documents or existing files are sampled.
if ($ExtraMiB -gt 0) {
    $binary = Join-Path $docs 'Saguaro\Synthetic-Evidence.bin'
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $stream = [System.IO.File]::Open($binary, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $header = [System.Text.Encoding]::ASCII.GetBytes($signature + [Environment]::NewLine)
        $stream.Write($header, 0, $header.Length)
        $block = [byte[]]::new(1048576)
        for ($i = 0; $i -lt $ExtraMiB; $i++) {
            $rng.GetBytes($block)
            $stream.Write($block, 0, $block.Length)
        }
    }
    finally {
        $stream.Dispose()
        $rng.Dispose()
    }
}

# Resolve the root before making relative manifest paths. Windows CI uses a
# shortened %TEMP% path (RUNNER~1), while FileInfo.FullName expands it.
# Using the caller's string length would create invalid paths such as ts\Aspen\...
$canonicalDocs = (Get-Item -LiteralPath $docs).FullName.TrimEnd('\')
$docsPrefix = $canonicalDocs + '\'
$rows = @(
    Get-ChildItem -LiteralPath $docs -Recurse -File -Force |
        Sort-Object FullName |
        ForEach-Object {
            if (-not $_.FullName.StartsWith($docsPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Synthetic file escaped the dataset root: $($_.FullName)"
            }
            [pscustomobject]@{
                RelativePath = $_.FullName.Substring($docsPrefix.Length)
                SizeBytes = $_.Length
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        }
)
$rows | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding UTF8
$total = ($rows | Measure-Object -Property SizeBytes -Sum).Sum
Write-Host "[OK] Prepared $($rows.Count) fictional files ($([math]::Round($total / 1MB, 1)) MiB)"
Write-Host "[OK] Manifest: $manifest"
