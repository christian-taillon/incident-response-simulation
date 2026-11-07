# Offline recovery planning regression tests. Run with Windows PowerShell 5.1 and PowerShell 7.
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('IRS-recovery-' + [guid]::NewGuid().ToString('N'))
$data = Join-Path (Split-Path -Parent $PSScriptRoot) 'scenarios\data-exfiltration'
$plan = Join-Path $data 'plan-recovery.ps1'
$assert = Join-Path $data 'assert-known-inventory.ps1'
$verify = Join-Path $data 'verify-remote-inventory.ps1'
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    $message = ''
    try { & $Action | Out-Null }
    catch { $message = $_.Exception.Message }
    if ($message -notmatch $Pattern) { throw "Expected '$Pattern', got '$message'" }
}
try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $backup = Join-Path $root 'client-data.zip'
    $saved = Join-Path $root 'verified-inventory.json'
    [IO.File]::WriteAllText($backup, 'synthetic archive')
    $hash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
    $record = [pscustomobject]@{ Uploaded = $true; ArchiveSha256 = $hash; ArchiveBytes = 17 }
    $fullJson = '[{"Path":"probe.txt","Name":"probe.txt","ID":"probe-id","IsDir":false,"Size":5},{"Path":"client-data.zip","Name":"client-data.zip","ID":"archive-id","IsDir":false,"Size":17}]'
    $probeJson = '[{"Path":"probe.txt","Name":"probe.txt","ID":"probe-id","IsDir":false,"Size":5}]'
    $changedJson = '[{"Path":"probe.txt","Name":"probe.txt","ID":"changed-id","IsDir":false,"Size":5}]'
    $full = @(& $verify -InventoryJson $fullJson -ArchiveBytes 17 -RequireArchive)
    $probe = @(& $verify -InventoryJson $probeJson -ArchiveBytes 17)
    $changed = @(& $verify -InventoryJson $changedJson -ArchiveBytes 17)

    [IO.File]::WriteAllText($saved, (ConvertTo-Json -InputObject ([object[]]$full) -Depth 5))
    $targets = @(& $plan -RunMetadata $record -CurrentInventory $full -BackupPath $backup -SavedInventoryFile $saved)
    if ($targets.Count -ne 2 -or $targets[0] -cne 'client-data.zip' -or $targets[1] -cne 'probe.txt') {
        throw 'Complete recovery was not planned correctly.'
    }

    $targets = @(& $plan -RunMetadata $record -CurrentInventory $probe -BackupPath $backup -SavedInventoryFile $saved)
    if ($targets.Count -ne 1 -or $targets[0] -cne 'probe.txt') {
        throw 'Partial deletion was not resumable.'
    }
    Assert-Rejected {
        & $plan -RunMetadata $record -CurrentInventory $changed -BackupPath $backup -SavedInventoryFile $saved
    } 'Remote inventory changed'

    $failed = [pscustomobject]@{ Uploaded = $false; ArchiveSha256 = $hash; ArchiveBytes = 17 }
    Remove-Item -LiteralPath $saved, $backup -Force
    $targets = @(& $plan -RunMetadata $failed -CurrentInventory $probe -BackupPath $backup -SavedInventoryFile $saved)
    if ($targets.Count -ne 1 -or $targets[0] -cne 'probe.txt') { throw 'Probe-only cleanup was not planned.' }
    Assert-Rejected {
        & $plan -RunMetadata $failed -CurrentInventory $full -BackupPath $backup -SavedInventoryFile $saved
    } 'Download and hash-verify'

    if (@(& $plan -RunMetadata $failed -CurrentInventory @() -BackupPath $backup -SavedInventoryFile $saved).Count -ne 0) {
        throw 'Empty failed run must not plan deletion.'
    }
    Assert-Rejected {
        & $plan -RunMetadata $record -CurrentInventory $probe -BackupPath $backup -SavedInventoryFile $saved
    } 'Download and hash-verify'

    & $assert -Expected $full -Current $probe -AllowMissing
    Assert-Rejected { & $assert -Expected $full -Current $changed -AllowMissing } 'Remote inventory changed'
    Assert-Rejected { & $assert -Expected $full -Current $probe } 'Remote inventory changed'

    [IO.File]::WriteAllText($backup, 'synthetic archive')
    [IO.File]::WriteAllText($saved, (ConvertTo-Json -InputObject ([object[]]$probe) -Depth 5))
    Assert-Rejected {
        & $plan -RunMetadata $record -CurrentInventory $probe -BackupPath $backup -SavedInventoryFile $saved
    } 'Recorded archive is absent'
    Write-Host '[OK] Recovery planning checks passed'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
