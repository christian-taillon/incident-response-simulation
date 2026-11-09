# Validate the complete Rclone lsjson -R inventory for one recorded run directory.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InventoryJson,
    [int64]$ArchiveBytes = -1,
    [switch]$RequireArchive,
    [switch]$SavedInventory
)

$ErrorActionPreference = 'Stop'
if (-not $InventoryJson.TrimStart().StartsWith('[')) {
    throw 'Remote inventory is not a JSON array.'
}
$parsed = ConvertFrom-Json -InputObject $InventoryJson
$items = @()
if ($null -ne $parsed) { $items = @($parsed) }
$seenNames = @{}
$seenIds = @{}
$validated = @()
foreach ($item in $items) {
    if ($null -eq $item -or
        ($null -ne $item.IsDir -and $item.IsDir -ne $false) -or
        (-not $SavedInventory -and $item.IsDir -ne $false)) {
        throw 'Unexpected remote directory or invalid inventory item.'
    }
    $name = [string]$item.Path
    $id = [string]$item.ID
    # Rclone lsjson includes Name and IsDir; locally saved, already validated
    # inventories contain only Path, ID, and Size. Reject inconsistent values
    # if the optional fields are present in either format.
    if ($name -cnotin @('probe.txt', 'client-data.zip') -or
        ((-not $SavedInventory -or $null -ne $item.Name) -and $item.Name -cne $name) -or
        [string]::IsNullOrWhiteSpace($id)) {
        throw "Unexpected or ambiguous remote object: $name"
    }
    if ($seenNames.ContainsKey($name) -or $seenIds.ContainsKey($id)) {
        throw "Duplicate remote object name or ID: $name"
    }
    $size = [int64]0
    if (-not [int64]::TryParse([string]$item.Size, [ref]$size) -or $size -lt 0) {
        throw "Invalid remote object size: $name"
    }
    if ($name -ceq 'client-data.zip' -and $ArchiveBytes -ge 0 -and $size -ne $ArchiveBytes) {
        throw 'Remote archive size does not match the recorded run.'
    }
    $seenNames[$name] = $true
    $seenIds[$id] = $true
    $validated += [pscustomobject]@{ Path = $name; ID = $id; Size = $size }
}
if ($RequireArchive -and -not $seenNames.ContainsKey('client-data.zip')) {
    throw 'Recorded archive is absent from the remote inventory.'
}
Write-Output ($validated | Sort-Object Path)
