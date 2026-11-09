# Deterministic offline regression checks for the workshop guardrails.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$data = Join-Path $repo 'scenarios\data-exfiltration'
$execute = Join-Path $data 'execute.ps1'
$verifyTree = Join-Path $data 'verify-tree.ps1'
$verifyRemote = Join-Path $data 'verify-remote-inventory.ps1'
$oldLocalAppData = $env:LOCALAPPDATA
$temporaryRoot = Join-Path $env:TEMP ("IRS-hardening-" + [guid]::NewGuid().ToString('N'))
$resolved = [IO.Path]::GetFullPath($temporaryRoot)
$tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unexpected test cleanup path.'
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$MessagePattern)
    $message = ''
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    if ($message -notmatch $MessagePattern) {
        throw "Expected rejection matching '$MessagePattern'; got '$message'"
    }
}

# PowerShell resolves this function before the native executable. It creates
# deterministic source changes after initial verification and before copying.
function robocopy.exe {
    param([string]$Source, [string]$Destination)
    $matter = Join-Path $Source 'Redwood\Matter-001.txt'
    switch ($env:IRS_TEST_MUTATION) {
        'added' { Set-Content -LiteralPath (Join-Path $Source 'added.txt') -Value 'unexpected' -Encoding ASCII }
        'modified' { Add-Content -LiteralPath $matter -Value 'changed' }
        'replaced' {
            Remove-Item -LiteralPath $matter -Force
            Set-Content -LiteralPath $matter -Value 'replacement' -Encoding ASCII
        }
    }
    & (Join-Path $env:SystemRoot 'System32\robocopy.exe') $Source $Destination @args | Out-Null
    $global:LASTEXITCODE = 1
}

function tar.exe {
    & (Join-Path $env:SystemRoot 'System32\tar.exe') @args
    $code = $LASTEXITCODE
    if ($env:IRS_TEST_ARCHIVE_MUTATION -eq 'added' -and $code -eq 0) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::Open($args[2], [IO.Compression.ZipArchiveMode]::Update)
        try {
            $entry = $zip.CreateEntry('unexpected.txt')
            $writer = New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write('unexpected archive content') }
            finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
    }
    $global:LASTEXITCODE = $code
}

try {
    $env:LOCALAPPDATA = $temporaryRoot
    & (Join-Path $data 'prepare.ps1') -ExtraMiB 0
    $root = Join-Path $temporaryRoot 'CSWorkshop'
    $docs = Join-Path $root 'ClientDocuments'
    $manifest = Join-Path $root 'dataset-manifest.csv'

    # Nested allowed directories must validate in both PowerShell 5.1 and 7.
    # An unrelated empty directory must still be rejected.
    $fixture = Join-Path $root 'NestedFixture'
    $nestedDir = Join-Path $fixture 'Aspen\Nested'
    New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
    $nestedFile = Join-Path $nestedDir 'example.txt'
    Set-Content -LiteralPath $nestedFile -Value 'fictional' -Encoding ASCII
    $nestedManifest = Join-Path $root 'nested-manifest.csv'
    [pscustomobject]@{
        RelativePath = 'Aspen\Nested\example.txt'
        SizeBytes = (Get-Item -LiteralPath $nestedFile).Length
        SHA256 = (Get-FileHash -LiteralPath $nestedFile -Algorithm SHA256).Hash
    } | Export-Csv -LiteralPath $nestedManifest -NoTypeInformation -Encoding UTF8
    if ((& $verifyTree -Tree $fixture -Manifest $nestedManifest) -ne 1) {
        throw 'Nested manifest directory failed validation.'
    }
    New-Item -ItemType Directory -Path (Join-Path $fixture 'Unexpected') | Out-Null
    Assert-Rejected { & $verifyTree -Tree $fixture -Manifest $nestedManifest } 'Unexpected directory'

    $backed = Join-Path $root 'BackedDocs'
    Move-Item -LiteralPath $docs -Destination $backed
    New-Item -ItemType Junction -Path $docs -Target $backed | Out-Null
    Assert-Rejected { & $execute -ValidateOnly } 'root is not an ordinary directory'
    [IO.Directory]::Delete($docs)
    if (-not (Test-Path -LiteralPath $backed)) { throw 'Root junction removal touched its target.' }
    Move-Item -LiteralPath $backed -Destination $docs

    $outside = Join-Path $root 'Outside'
    New-Item -ItemType Directory -Path $outside | Out-Null
    $nested = Join-Path $docs 'Redwood\NestedLink'
    New-Item -ItemType Junction -Path $nested -Target $outside | Out-Null
    Assert-Rejected { & $execute -ValidateOnly } 'Link or junction'
    [IO.Directory]::Delete($nested)
    if (-not (Test-Path -LiteralPath $outside)) { throw 'Nested junction removal touched its target.' }

    # A real offline staging run must produce an archive with exactly the
    # manifest's files. Direct mutations of the staged tree must be rejected.
    $env:IRS_TEST_MUTATION = ''
    & $execute -StageOnly | Out-Null
    $staging = Get-ChildItem -LiteralPath $root -Directory -Filter 'staging-*' | Select-Object -First 1
    if (-not $staging -or (& $verifyTree -Tree $staging.FullName -Manifest $manifest) -ne 30) {
        throw 'Staged tree did not match the manifest.'
    }
    $extra = Join-Path $staging.FullName 'extra.txt'
    Set-Content -LiteralPath $extra -Value 'unexpected' -Encoding ASCII
    Assert-Rejected { & $verifyTree -Tree $staging.FullName -Manifest $manifest } 'Unexpected file'
    Remove-Item -LiteralPath $extra -Force

    $original = [IO.File]::ReadAllBytes((Join-Path $docs 'Redwood\Matter-001.txt'))
    $archiveCount = @(Get-ChildItem -LiteralPath $root -Filter 'client-data-*.zip').Count
    $env:MEGA_EMAIL = 'lab@example.test'
    $env:MEGA_PASSWORD = 'offline-test-only'
    foreach ($mutation in @('added', 'modified', 'replaced')) {
        $env:IRS_TEST_MUTATION = $mutation
        $pattern = if ($mutation -eq 'added') { 'Unexpected file' } else { 'Dataset integrity failure' }
        Assert-Rejected { & $execute } $pattern
        if (@(Get-ChildItem -LiteralPath $root -Filter 'client-data-*.zip').Count -ne $archiveCount -or
            (Test-Path -LiteralPath (Join-Path $root 'rclone.conf'))) {
            throw "Archive or transfer preparation occurred after a $mutation staging failure."
        }
        $added = Join-Path $docs 'added.txt'
        if (Test-Path -LiteralPath $added) { Remove-Item -LiteralPath $added -Force }
        [IO.File]::WriteAllBytes((Join-Path $docs 'Redwood\Matter-001.txt'), $original)
    }
    $env:IRS_TEST_MUTATION = ''
    $env:IRS_TEST_ARCHIVE_MUTATION = 'added'
    Assert-Rejected { & $execute -StageOnly } 'Unexpected file'
    if (@(Get-ChildItem -LiteralPath $root -Filter 'client-data-*.zip').Count -ne $archiveCount) {
        throw 'Invalid ZIP was retained after archive-content validation failed.'
    }
    $env:IRS_TEST_ARCHIVE_MUTATION = ''

    $good = '[{"Path":"probe.txt","Name":"probe.txt","ID":"probe-id","IsDir":false,"Size":5},{"Path":"client-data.zip","Name":"client-data.zip","ID":"archive-id","IsDir":false,"Size":100}]'
    if (@(& $verifyRemote -InventoryJson $good -ArchiveBytes 100 -RequireArchive).Count -ne 2) {
        throw 'Expected both remote objects.'
    }
    Assert-Rejected { & $verifyRemote -InventoryJson '[{"Path":"nested/other.txt","Name":"other.txt","ID":"x","IsDir":false,"Size":1}]' } 'Unexpected or ambiguous'
    Assert-Rejected { & $verifyRemote -InventoryJson '[{"Path":"nested","Name":"nested","ID":"x","IsDir":true,"Size":0}]' } 'Unexpected remote directory'
    Assert-Rejected { & $verifyRemote -InventoryJson '[{"Path":"probe.txt","Name":"probe.txt","ID":"a","IsDir":false,"Size":1},{"Path":"probe.txt","Name":"probe.txt","ID":"b","IsDir":false,"Size":1}]' } 'Duplicate remote object'
    Assert-Rejected { & $verifyRemote -InventoryJson '[{"Path":"client-data.zip","Name":"client-data.zip","ID":"a","IsDir":false,"Size":99}]' -ArchiveBytes 100 } 'size does not match'
    Assert-Rejected { & $verifyRemote -InventoryJson '[{"Path":"probe.txt","Name":"probe.txt","ID":"","IsDir":false,"Size":1}]' } 'Unexpected or ambiguous'

    $fakeRun = '20261106-120000-abcdef'
    $fakeRecord = [pscustomobject]@{
        RunId = $fakeRun
        Host = 'LABHOST'
        RemoteDir = 'workshopmega:Outside/LABHOST/' + $fakeRun
        ArchiveBytes = 100
        ArchiveSha256 = ('0' * 64)
        Uploaded = $true
    }
    $fakeRecord | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Join-Path $root 'runs') "$fakeRun.json") -Encoding UTF8
    Assert-Rejected { & (Join-Path $data 'recover.ps1') -RunId $fakeRun -Action Delete -ConfirmRunId $fakeRun -WhatIf } 'Remote path does not match'

    $badZip = Join-Path $root 'rclone-v1.75.2-windows-amd64.zip'
    Set-Content -LiteralPath $badZip -Value 'untrusted cached archive' -Encoding ASCII
    Assert-Rejected { & (Join-Path $data 'ensure-rclone.ps1') -Root $root } 'does not match the official pinned SHA256'
    Remove-Item -LiteralPath $badZip -Force

    & (Join-Path $repo 'scenarios\host-discovery\execute.ps1') | Out-Null
    $discovery = Get-ChildItem -LiteralPath $root -Filter 'host-discovery-*.txt' | Select-Object -First 1
    $logText = Get-Content -LiteralPath $discovery.FullName -Raw
    $failedBlock = ($logText -split '== Failed discovery attempt ==')[1] -split '== Synthetic document discovery ==' | Select-Object -First 1
    if ($failedBlock -notmatch 'Started UTC: .+' -or
        $failedBlock -notmatch 'Finished UTC: .+' -or
        $failedBlock -notmatch 'Exit code: [0-9]+' -or
        $failedBlock -notmatch 'no-such-host|timed-out|Non-existent') {
        throw 'Failed DNS lookup did not preserve timestamps, output/error, and exit code.'
    }
    Write-Host '[OK] Hardening regression checks passed'
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Item Env:\IRS_TEST_MUTATION, Env:\MEGA_EMAIL, Env:\MEGA_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:\IRS_TEST_ARCHIVE_MUTATION -ErrorAction SilentlyContinue
    Remove-Item Function:\robocopy.exe -ErrorAction SilentlyContinue
    Remove-Item Function:\tar.exe -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
