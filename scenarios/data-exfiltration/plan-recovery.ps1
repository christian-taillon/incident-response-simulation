# Plan cleanup only for identities belonging to one verified run.
# Pure local checks: does not invoke Rclone or mutate files.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][object]$RunMetadata,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CurrentInventory,
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [Parameter(Mandatory = $true)][string]$SavedInventoryFile
)

$ErrorActionPreference = 'Stop'
$verifyInventory = Join-Path $PSScriptRoot 'verify-remote-inventory.ps1'
$assertInventory = Join-Path $PSScriptRoot 'assert-known-inventory.ps1'
$hasArchive = @($CurrentInventory | Where-Object { $_.Path -ceq 'client-data.zip' }).Count -gt 0

if ($RunMetadata.Uploaded -or $hasArchive) {
    # A complete upload, or any remotely visible archive, demands verified local
    # recovery before deletion. Missing objects are allowed only after recovery.
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $BackupPath -Algorithm SHA256).Hash -ne $RunMetadata.ArchiveSha256) {
        throw 'Download and hash-verify the remote archive with -Action Download before deleting.'
    }
    if (-not (Test-Path -LiteralPath $SavedInventoryFile -PathType Leaf)) {
        throw 'Missing the inventory saved with the verified local recovery.'
    }
    $savedJson = Get-Content -LiteralPath $SavedInventoryFile -Raw
    # Reuse the validated inventory parser; do not rely on PowerShell 5.1
    # ConvertFrom-Json pipeline array semantics.
    $saved = @(& $verifyInventory -InventoryJson $savedJson -ArchiveBytes ([int64]$RunMetadata.ArchiveBytes) -RequireArchive -SavedInventory)
    & $assertInventory -Expected $saved -Current $CurrentInventory -AllowMissing
}
# Otherwise this was a failed, probe-only upload. An explicit matching RunId
# still authorizes deletion, but there is no archive to recover.

foreach ($name in @('client-data.zip', 'probe.txt')) {
    if (@($CurrentInventory | Where-Object { $_.Path -ceq $name }).Count -eq 1) {
        Write-Output $name
    }
}
