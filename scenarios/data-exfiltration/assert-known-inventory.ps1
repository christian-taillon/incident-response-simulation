# Assert that remote object identities are unchanged, optionally allowing deletions.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Expected,
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Current,
    [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'
if ($Current.Count -gt $Expected.Count -or
    (-not $AllowMissing -and $Current.Count -ne $Expected.Count)) {
    throw 'Remote inventory changed since recovery.'
}
foreach ($item in $Current) {
    $matches = @($Expected | Where-Object {
        $_.Path -ceq $item.Path -and $_.ID -ceq $item.ID -and $_.Size -eq $item.Size
    })
    if ($matches.Count -ne 1) {
        throw 'Remote inventory changed since recovery.'
    }
}
