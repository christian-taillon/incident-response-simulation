# Inspect, recover, or explicitly delete only objects from one recorded lab run.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$RunId,
    [ValidateSet('Inspect', 'Download', 'Delete')]
    [string]$Action = 'Inspect',
    [string]$ConfirmRunId
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$config = Join-Path $root 'rclone.conf'
$verifyInventory = Join-Path $PSScriptRoot 'verify-remote-inventory.ps1'
$assertInventory = Join-Path $PSScriptRoot 'assert-known-inventory.ps1'
$planRecovery = Join-Path $PSScriptRoot 'plan-recovery.ps1'
$ensureRclone = Join-Path $PSScriptRoot 'ensure-rclone.ps1'

if (-not $RunId) {
    $last = Join-Path $root 'last-run.txt'
    if (-not (Test-Path -LiteralPath $last)) { throw 'Specify -RunId or copy last-run.txt to this lab workspace.' }
    $RunId = (Get-Content -LiteralPath $last -Raw).Trim()
}
if ($RunId -cnotmatch '^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$') {
    throw 'Invalid exercise RunId format.'
}
$runFile = Join-Path (Join-Path $root 'runs') "$RunId.json"
if (-not (Test-Path -LiteralPath $runFile)) { throw "Missing run record: $runFile" }
$meta = Get-Content -LiteralPath $runFile -Raw | ConvertFrom-Json
if ($meta.RunId -cne $RunId -or [string]$meta.Host -notmatch '^[A-Za-z0-9_-]{1,63}$') {
    throw 'Invalid run record.'
}
$remoteDir = "workshopmega:CSWorkshop/$($meta.Host)/$RunId"
if ($meta.RemoteDir -cne $remoteDir) { throw 'Remote path does not match recorded lab scope.' }
if ($meta.ArchiveSha256 -notmatch '^[0-9a-fA-F]{64}$' -or [int64]$meta.ArchiveBytes -le 0) {
    throw 'Invalid archive hash or size in run record.'
}
if (-not (Test-Path -LiteralPath $config)) {
    throw 'The matching lab-only rclone.conf must be available in this workspace.'
}
$rclone = & $ensureRclone -Root $root

function Get-RunInventory {
    $listing = @(& $rclone --config $config lsjson $remoteDir --recursive --no-mimetype --no-modtime)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list the remote lab directory.' }
    & $verifyInventory -InventoryJson ($listing -join [Environment]::NewLine) -ArchiveBytes ([int64]$meta.ArchiveBytes)
}

Write-Host "[+] Inspecting $remoteDir"
$inventory = @(Get-RunInventory)
$names = @($inventory | ForEach-Object { $_.Path })
Write-Host "Remote files: $($names -join ', ')"
if ($Action -eq 'Inspect') { return }

$backup = Join-Path (Join-Path (Join-Path $root 'recovery') $RunId) 'client-data.zip'
$inventoryFile = Join-Path (Split-Path -Parent $backup) 'verified-inventory.json'
$remoteArchive = "$remoteDir/client-data.zip"

if ($Action -eq 'Download') {
    # A transfer may finish remotely before the local Uploaded flag is saved.
    # Hash verification, not that flag alone, establishes a valid recovery.
    if ($names -notcontains 'client-data.zip') {
        throw 'Remote archive absent. Inspect the run before attempting download.'
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    & $rclone --config $config copyto $remoteArchive $backup
    if ($LASTEXITCODE -ne 0) { throw 'Downloading remote archive failed.' }
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $meta.ArchiveSha256) {
        throw 'Recovered archive hash does not match the local run record.'
    }
    # Explicit -InputObject preserves the JSON array, including one-object inventories.
    $serialized = ConvertTo-Json -InputObject ([object[]]$inventory) -Depth 5
    [System.IO.File]::WriteAllText(
        $inventoryFile, $serialized, [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "[OK] Verified recovered archive: $backup"
    Write-Host "[OK] SHA256: $($meta.ArchiveSha256)"
    return
}

if ($ConfirmRunId -cne $RunId) { throw 'Deletion requires -ConfirmRunId matching this exact run.' }
$targets = @(& $planRecovery -RunMetadata $meta -CurrentInventory $inventory -BackupPath $backup -SavedInventoryFile $inventoryFile)
if ($targets.Count -eq 0) {
    Write-Host '[OK] No remote lab objects remain.'
    return
}

if ($PSCmdlet.ShouldProcess($remoteDir, "Delete recorded synthetic objects: $($targets -join ', ')")) {
    # The pre-prompt inventory must still match after operator confirmation.
    $current = @(Get-RunInventory)
    & $assertInventory -Expected $inventory -Current $current

    foreach ($name in $targets) {
        # Recheck before each path-based delete. MEGA operations are not atomic;
        # never continue if names, IDs, or sizes diverge mid-cleanup.
        $fresh = @(Get-RunInventory)
        & $assertInventory -Expected $current -Current $fresh
        if (@($current | Where-Object { $_.Path -ceq $name }).Count -ne 1) {
            throw "Expected remote object is no longer present: $name"
        }
        & $rclone --config $config deletefile "$remoteDir/$name"
        if ($LASTEXITCODE -ne 0) {
            throw "Remote deletion failed for $name. Inspect before retrying."
        }
        $current = @($current | Where-Object { $_.Path -cne $name })
    }
    $after = @(Get-RunInventory)
    & $assertInventory -Expected $current -Current $after
    Write-Host "[OK] Deleted $($targets.Count) specified lab object(s) (MEGA may retain them in Trash)."
}
