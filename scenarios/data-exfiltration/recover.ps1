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
if (-not (Test-Path -LiteralPath $config)) {
    throw 'The matching lab-only rclone.conf must be available in this workspace.'
}
$rclone = & $ensureRclone -Root $root

function Get-RunInventory {
    $listing = @(& $rclone --config $config lsjson $remoteDir --recursive --no-mimetype --no-modtime)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list the remote lab directory.' }
    & $verifyInventory -InventoryJson ($listing -join [Environment]::NewLine) -ArchiveBytes ([int64]$meta.ArchiveBytes)
}

function Assert-SameInventory {
    param([object[]]$Expected, [object[]]$Current)
    if ($Expected.Count -ne $Current.Count) { throw 'Remote inventory changed since recovery.' }
    foreach ($item in $Current) {
        $match = @($Expected | Where-Object { $_.Path -ceq $item.Path -and $_.ID -ceq $item.ID -and $_.Size -eq $item.Size })
        if ($match.Count -ne 1) { throw 'Remote inventory changed since recovery.' }
    }
}

Write-Host "[+] Inspecting $remoteDir"
$inventory = @(Get-RunInventory)
$names = @($inventory | ForEach-Object { $_.Path })
Write-Host "Remote files: $($names -join ', ')"
if ($Action -eq 'Inspect') { return }

if (-not $meta.Uploaded -or $names -notcontains 'client-data.zip') {
    throw 'Recorded upload not complete or archive absent from the remote.'
}
$backup = Join-Path (Join-Path (Join-Path $root 'recovery') $RunId) 'client-data.zip'
$inventoryFile = Join-Path (Split-Path -Parent $backup) 'verified-inventory.json'
$remoteArchive = "$remoteDir/client-data.zip"

if ($Action -eq 'Download') {
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    & $rclone --config $config copyto $remoteArchive $backup
    if ($LASTEXITCODE -ne 0) { throw 'Downloading remote archive failed.' }
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $meta.ArchiveSha256) {
        throw 'Recovered archive hash does not match the local run record.'
    }
    $inventory | ConvertTo-Json | Set-Content -LiteralPath $inventoryFile -Encoding UTF8
    Write-Host "[OK] Verified recovered archive: $backup"
    Write-Host "[OK] SHA256: $($meta.ArchiveSha256)"
    return
}

# Deliberate authorization gates for remote changes.
if ($ConfirmRunId -cne $RunId) { throw 'Deletion requires -ConfirmRunId matching this exact run.' }
if (-not (Test-Path -LiteralPath $backup) -or
    (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $meta.ArchiveSha256) {
    throw 'Download and hash-verify the remote archive with -Action Download before deleting.'
}
if (-not (Test-Path -LiteralPath $inventoryFile)) {
    throw 'Missing the inventory saved with the verified local recovery.'
}
$saved = @(Get-Content -LiteralPath $inventoryFile -Raw | ConvertFrom-Json)
Assert-SameInventory -Expected $saved -Current $inventory
if ($names -notcontains 'client-data.zip') { throw 'Remote archive missing.' }

if ($PSCmdlet.ShouldProcess($remoteDir, 'Delete the recorded synthetic archive and probe only')) {
    # Recheck after the confirmation prompt, immediately before deletion.
    $current = @(Get-RunInventory)
    Assert-SameInventory -Expected $saved -Current $current
    & $rclone --config $config deletefile $remoteArchive
    if ($LASTEXITCODE -ne 0) { throw 'Remote archive deletion failed.' }
    if ($names -contains 'probe.txt') {
        & $rclone --config $config deletefile "$remoteDir/probe.txt"
        if ($LASTEXITCODE -ne 0) { throw 'Remote probe deletion failed.' }
    }
    Write-Host '[OK] Deleted the two specified lab objects (MEGA may retain them in Trash).'
}
