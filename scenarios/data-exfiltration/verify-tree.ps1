# Verify one complete synthetic file tree against the prepared manifest.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tree,
    [Parameter(Mandatory = $true)][string]$Manifest
)

$ErrorActionPreference = 'Stop'
$root = Get-Item -LiteralPath $Tree -Force
if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "Dataset root is not an ordinary directory: $Tree"
}

$rows = @(Import-Csv -LiteralPath $Manifest)
if ($rows.Count -eq 0) { throw 'Synthetic dataset manifest is empty.' }
$allowedFiles = @{}
$allowedDirs = @{}
foreach ($row in $rows) {
    $rel = [string]$row.RelativePath
    if ([string]::IsNullOrWhiteSpace($rel) -or
        [IO.Path]::IsPathRooted($rel) -or
        $rel -match '(^|[\\/])\.{1,2}([\\/]|$)' -or
        $rel -match ':|[\\/]{2}') {
        throw "Invalid relative path in manifest: $rel"
    }
    $rel = $rel.Replace('/', '\')
    if ($allowedFiles.ContainsKey($rel)) { throw "Duplicate manifest path: $rel" }
    $size = [int64]0
    if (-not [int64]::TryParse([string]$row.SizeBytes, [ref]$size) -or
        $size -lt 0 -or [string]$row.SHA256 -cnotmatch '^[0-9A-Fa-f]{64}$') {
        throw "Invalid manifest size or SHA256: $rel"
    }
    $allowedFiles[$rel] = $row
    # Build directory prefixes from validated relative segments, not from
    # provider-aware Split-Path behavior (which differs across PowerShell versions).
    $parts = $rel.Split([char]'\')
    for ($i = 1; $i -lt $parts.Length; $i++) {
        $allowedDirs[[string]::Join('\', $parts, 0, $i)] = $true
    }
}

# Walk one level at a time so a nested junction is rejected before traversal.
$pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
$pending.Push($root)
$seen = @{}
while ($pending.Count -gt 0) {
    $dir = $pending.Pop()
    foreach ($item in @(Get-ChildItem -LiteralPath $dir.FullName -Force)) {
        $rel = $item.FullName.Substring($root.FullName.Length + 1)
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Link or junction in synthetic dataset: $rel"
        }
        if ($item.PSIsContainer) {
            if (-not $allowedDirs.ContainsKey($rel)) { throw "Unexpected directory: $rel" }
            $pending.Push($item)
            continue
        }
        if (-not $allowedFiles.ContainsKey($rel)) { throw "Unexpected file: $rel" }
        $row = $allowedFiles[$rel]
        if ($item.Length -ne [int64]$row.SizeBytes -or
            (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash -ne $row.SHA256) {
            throw "Dataset integrity failure: $rel"
        }
        $seen[$rel] = $true
    }
}
if ($seen.Count -ne $allowedFiles.Count) {
    throw 'Dataset differs from the manifest (missing files).'
}
Write-Output $seen.Count
