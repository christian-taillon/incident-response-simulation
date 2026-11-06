# Generate or decode native Windows PowerShell -EncodedCommand arguments.
# This helper only writes command text; it never executes the result.
[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'File')]
    [string]$Path,

    [Parameter(Mandatory = $true, ParameterSetName = 'Url')]
    [ValidatePattern('^https://')]
    [string]$Url,

    [Parameter(Mandatory = $true, ParameterSetName = 'Decode')]
    [string]$Decode,

    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Decode') {
    $text = [System.Text.Encoding]::Unicode.GetString(
        [System.Convert]::FromBase64String($Decode)
    )
    if ($OutputFile) {
        [System.IO.File]::WriteAllText($OutputFile, $text, [System.Text.UTF8Encoding]::new($false))
    }
    else {
        Write-Output $text
    }
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Url') {
    $quotedUrl = $Url.Replace("'", "''")
    $source = "Invoke-RestMethod -Uri '$quotedUrl' | Invoke-Expression"
}
else {
    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $source = [System.IO.File]::ReadAllText($fullPath)
}

$base64 = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($source)
)
$command = 'powershell.exe -NoProfile -EncodedCommand ' + $base64
if ($command.Length -gt 7000) {
    Write-Warning 'Long encoded commands may exceed the Windows cmd.exe command-line limit. Use a shorter reviewed HTTPS script URL.'
}

if ($OutputFile) {
    [System.IO.File]::WriteAllText($OutputFile, $command, [System.Text.Encoding]::ASCII)
    Write-Host "[OK] Encoded command saved: $OutputFile"
}
else {
    Write-Output $command
}
