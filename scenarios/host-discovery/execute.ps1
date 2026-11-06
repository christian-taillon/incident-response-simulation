# Native Windows discovery activity on an authorized training host.
[CmdletBinding()]
param(
    [switch]$AttemptLabDomain,
    [string]$LabDomain
)

$ErrorActionPreference = 'Stop'
if ($AttemptLabDomain -and ($LabDomain -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{1,252}$')) {
    throw 'Pass a specific, authorized lab domain using -LabDomain.'
}
$root = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $root "host-discovery-$stamp.txt"

function Invoke-Probe {
    param([string]$Label, [string]$Executable, [string[]]$Arguments)

    Add-Content -LiteralPath $log -Value ("== " + $Label + " ==")
    Add-Content -LiteralPath $log -Value ("Started UTC: " + [datetime]::UtcNow.ToString('o'))
    $exitCode = 'unavailable'
    $tool = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $tool) {
        Add-Content -LiteralPath $log -Value "Unavailable: $Executable"
    }
    else {
        try {
            # Windows PowerShell 5.1 can promote native stderr to a terminating
            # error when the caller uses Stop. Preserve output and the exit code.
            $ErrorActionPreference = 'Continue'
            & $tool.Source @Arguments 2>&1 |
                Out-File -LiteralPath $log -Append -Encoding UTF8
            $exitCode = [string]$LASTEXITCODE
        }
        catch {
            Add-Content -LiteralPath $log -Value "Command failed: $($_.Exception.Message)"
            if ($null -ne $LASTEXITCODE) { $exitCode = [string]$LASTEXITCODE }
        }
        finally {
            $ErrorActionPreference = 'Stop'
        }
    }
    Add-Content -LiteralPath $log -Value "Exit code: $exitCode"
    Add-Content -LiteralPath $log -Value ("Finished UTC: " + [datetime]::UtcNow.ToString('o'))
}

Invoke-Probe 'Current identity and groups' 'whoami.exe' @('/all')
Invoke-Probe 'System identity' 'hostname.exe' @()
Invoke-Probe 'Network configuration' 'ipconfig.exe' @('/all')
Invoke-Probe 'Routing table' 'route.exe' @('print')
Invoke-Probe 'Mapped network shares' 'net.exe' @('use')
Invoke-Probe 'Local accounts' 'net.exe' @('user')

# An intentionally unsuccessful lookup produces evidence without touching AD.
Invoke-Probe 'Failed discovery attempt' 'nslookup.exe' @('no-such-host.invalid')

# Optional domain discovery is limited to the exact domain supplied by the operator.
if ($AttemptLabDomain) {
    Invoke-Probe 'Lab domain controller DNS lookup' 'nslookup.exe' @('-type=SRV', "_ldap._tcp.dc._msdcs.$LabDomain")
    Invoke-Probe 'Lab domain controller discovery' 'nltest.exe' @("/dsgetdc:$LabDomain")
}

$docs = Join-Path $root 'ClientDocuments'
if (Test-Path -LiteralPath $docs) {
    $cmdLine = 'dir /s /b "' + $docs + '"'
    Invoke-Probe 'Synthetic document discovery' 'cmd.exe' @('/d', '/c', $cmdLine)
}
Write-Host "[OK] Host discovery activity finished: $log"
