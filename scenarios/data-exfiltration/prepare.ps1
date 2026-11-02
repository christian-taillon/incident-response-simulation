# Create fictional client documents for the data-exfiltration exercise.
$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$docs = Join-Path $root 'ClientDocuments'
$marker = Join-Path $root '.synthetic-only'
$markerText = 'CSWORKSHOP-SYNTHETIC-ONLY'

# Do not adopt an existing, unrelated document directory.
if ((Test-Path -LiteralPath $docs) -and
    (Get-ChildItem -LiteralPath $docs -Force | Select-Object -First 1) -and
    -not (Test-Path -LiteralPath $marker)) {
    throw "Refusing to use existing unmarked document directory: $docs"
}

New-Item -ItemType Directory -Path $docs -Force | Out-Null
Set-Content -LiteralPath $marker -Value $markerText -Encoding ascii

foreach ($client in @('Redwood', 'Saguaro', 'Aspen')) {
    $dir = Join-Path $docs $client
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    1..8 | ForEach-Object {
        $number = '{0:D3}' -f $_
        @"
$markerText
CONFIDENTIAL - FICTIONAL TRAINING DATA
Client: $client
Matter: MAT-$number
Description: Privileged client correspondence
Status: Internal Review
This file contains no real client data.
"@ | Set-Content -LiteralPath (Join-Path $dir "Matter-$number.txt") -Encoding ascii
    }

    1..100 | ForEach-Object {
        [pscustomobject]@{
            Client = $client
            Matter = ('MAT-{0:D3}' -f $_)
            Amount = $_ * 1250
            Status = 'Confidential - Training'
            Marker = $markerText
        }
    } | Export-Csv -LiteralPath (Join-Path $dir 'Billing.csv') -NoTypeInformation

    @"
{\rtf1\ansi
\b ATTORNEY WORK PRODUCT - TRAINING ONLY\b0\par
$markerText\par
Client: $client\par
Matter: Confidential Acquisition\par
All information is fictional.\par
}
"@ | Set-Content -LiteralPath (Join-Path $dir 'Legal-Memorandum.rtf') -Encoding ascii
}

$count = @(Get-ChildItem -LiteralPath $docs -File -Recurse).Count
Write-Host "[OK] Created $count synthetic documents in $docs"
