# MEGA and Falcon live rehearsal

Facilitator acceptance procedure for [issue #2](https://github.com/christian-taillon/incident-response-simulation/issues/2). This is a manual lab exercise. Offline CI does **not** prove remote MEGA operations or CrowdStrike telemetry.

## Boundaries

- Disposable Windows 10/11 VM with CrowdStrike Falcon, dedicated disposable MEGA account, and only synthetic data from the included preparation script.
- Leave endpoint protections enabled. Record prevention and any individually approved, lab-scoped exception rather than silently bypassing controls.
- No production accounts, data, or arbitrary remote directories. Restrict operations to the run recorded under CSWorkshop on the lab host.
- Do not upload credentials, Rclone config, synthetic archives, or unredacted endpoint event details to GitHub.
- Stop if source hashes, expected names, remote object IDs, or the recorded remote scope differ. Preserve evidence before deletion.

## 1. Preflight without MEGA

Start in a clean VM snapshot at the repository root. Use a Windows PowerShell session:

~~~powershell
[datetime]::UtcNow.ToString('o')
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
$PSVersionTable.PSVersion
Set-Location .\scenarios\data-exfiltration
.\prepare.ps1 -ExtraMiB 32
.\execute.ps1 -ValidateOnly
.\execute.ps1 -StageOnly
~~~

Expected: 31 synthetic files and a relative-path manifest; all source, staged, and extracted ZIP validation succeeds. The StageOnly step performs no network upload. If preparation reports existing data, restore the disposable snapshot rather than overriding the files. Record the Falcon sensor version and active policy separately.

## 2. Live transfer

Use credentials **only** for the dedicated test account and keep them out of transcripts. The example deliberately omits the optional plaintext-credential artifact.

~~~powershell
$env:MEGA_EMAIL = Read-Host 'Disposable MEGA email'
$secure = Read-Host 'Disposable MEGA password' -AsSecureString
$env:MEGA_PASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
Remove-Variable secure
try {
    .\execute.ps1 -AddNoise
}
finally {
    Remove-Item Env:\MEGA_EMAIL, Env:\MEGA_PASSWORD -ErrorAction SilentlyContinue
}
~~~

If Falcon prevents execution or egress is blocked, record that outcome, including the step and event identifier. Do not infer a completed transfer.

After an upload completes, capture the exact run and read-only remote inventory:

~~~powershell
$lab = Join-Path $env:LOCALAPPDATA 'CSWorkshop'
$run = (Get-Content -LiteralPath (Join-Path $lab 'last-run.txt') -Raw).Trim()
$record = Get-Content -LiteralPath (Join-Path $lab "runs\$run.json") -Raw | ConvertFrom-Json
$record | Select-Object RunId, Host, RemoteDir, ArchiveSha256, ArchiveBytes, ProbeUploaded, Uploaded, TimestampUtc

$rclone = Join-Path $lab 'bin\rclone.exe'
$listing = (& $rclone --config (Join-Path $lab 'rclone.conf') lsjson $record.RemoteDir --recursive --no-mimetype --no-modtime) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) { throw 'Remote inventory failed.' }
$remoteItems = ConvertFrom-Json -InputObject $listing
foreach ($item in $remoteItems) { $item | Select-Object Path, ID, Size }
~~~

Expected: exactly probe.txt and client-data.zip with unique remote IDs, and archive size matching the run record. Transfer exit status alone is not remote-content proof.

## 3. Recover before deleting anything

~~~powershell
.\recover.ps1 -RunId $run -Action Inspect
.\recover.ps1 -RunId $run -Action Download
$recovered = Join-Path $lab "recovery\$run\client-data.zip"
if ((Get-FileHash -LiteralPath $recovered -Algorithm SHA256).Hash -ne $record.ArchiveSha256) {
    throw 'Recovery hash mismatch.'
}
.\recover.ps1 -RunId $run -Action Delete -ConfirmRunId $run -WhatIf
~~~

Repeat the read-only inventory from section 2 before and after WhatIf. It must be unchanged. Retain the recovered hash and the saved verified-inventory.json as evidence; do not upload the archive or config.

After explicit facilitator approval, execute the deletion and its confirmation prompt, then inspect the remote prefix and MEGA Trash separately:

~~~powershell
.\recover.ps1 -RunId $run -Action Delete -ConfirmRunId $run
.\recover.ps1 -RunId $run -Action Inspect
~~~

If the backend removes an empty run directory and the final Inspect command cannot list it, verify the recorded prefix from the dedicated MEGA account before marking the outcome. An empty prefix does not prove permanent erasure from the account.

## 4. Negative cases, each on a separate disposable run

| Case | Required observation |
| --- | --- |
| Archive upload interrupted after probe is present | Inspect and confirmed cleanup handle the probe-only state |
| Cleanup interrupted after archive deletion | Retry removes only the remaining probe whose saved ID and size match |
| Unexpected nested object or duplicate remote name | Inventory verification rejects ambiguous contents |
| Remote object replaced after download | Delete refuses changed ID or size |
| Falcon prevention or blocked egress | Report attempted versus completed transfer independently |

Do not mutate the main evidence run to manufacture negative cases. Where a case cannot be reproduced safely using the dedicated MEGA account, mark it Not tested, not Pass. Never use recursive cloud deletion to reset a run.

## 5. Record Falcon and analyst outcomes

Use the scoped Advanced Event Search starting query in the [data-exfiltration guide](../scenarios/data-exfiltration/README.md#threat-behavior-and-investigation). Look for PowerShell, cmd.exe, robocopy.exe, tar.exe, and rclone.exe ancestry, plus available file, DNS, and network events. Record actual event IDs, UTC timestamps, and visibility gaps.

Report these outcomes **separately**: executed, Falcon-recorded, detected or prevented, analyst-reconstructed, and response taken. Successful execution is not a Falcon detection.

## 6. Redacted issue #2 evidence record

| Field | Result |
| --- | --- |
| UTC test window, OS build, PowerShell version, Falcon sensor and policy | |
| Test host, run ID and lab remote prefix | |
| Synthetic manifest count, recorded archive size and SHA256 | |
| Upload exit code, probe/archive names, IDs and sizes | Pass / Fail / Not tested |
| Recovered archive SHA256 comparison | Pass / Fail / Not tested |
| WhatIf did not change remote inventory | Pass / Fail / Not tested |
| Facilitator-approved deletion, post-delete inspection and MEGA Trash | Pass / Fail / Not tested |
| Each negative case and observed refusal or recovery | Pass / Fail / Not tested |
| Falcon process/file/DNS/network evidence, with redacted event IDs | Present / Missing / Not tested |
| Falcon analytic or prevention ID and actual outcome | ID / None / Not tested |
| Analyst reconstruction, response actions, uncertainties | |
| Blockers and next steps | |

Post a redacted record to issue #2 or link an access-controlled evidence document. **Close the issue only after live transfer, verified recovery, authorized cleanup, and Falcon outcome have actually been observed.** Offline tests and this procedure alone are not acceptance evidence.
