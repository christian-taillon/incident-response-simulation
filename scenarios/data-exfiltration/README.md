# Synthetic data exfiltration to MEGA

Standalone Windows activity for a CrowdStrike investigation workshop. `prepare.ps1` creates 30 fictional office-style records plus an optional 32 MiB random synthetic evidence blob, so compressed transfer size is meaningful. `execute.ps1` uses native `cmd.exe`, `robocopy.exe`, and `tar.exe` before Rclone uploads **only manifest-verified exercise files** to a disposable MEGA account. Rclone connects directly to MEGA; the MegaSync desktop application is not needed.

## Prerequisites

- Windows 10/11 lab VM with Windows PowerShell 5.1+, `robocopy.exe`, and `tar.exe`.
- A dedicated, disposable MEGA account with keys initialized by logging in through the browser once.
- Internet access to `downloads.rclone.org` and MEGA. The script pins the previously tested Rclone v1.75.2 ZIP and verifies its SHA256 before extraction.
- Falcon sensor if the exercise is intended to generate process telemetry. Leave endpoint protections on and use only approved, endpoint-scoped exceptions.

## Preparation and dry validation

~~~powershell
.\prepare.ps1 -ExtraMiB 32
.\execute.ps1 -ValidateOnly
# Optional offline rehearsal: verifies the source, staged copy, and ZIP contents.
.\execute.ps1 -StageOnly
~~~

Preparation is intentionally non-destructive: an existing dataset is never overwritten. All synthetic files are enumerated with sizes and SHA256 values in `%LOCALAPPDATA%\CSWorkshop\dataset-manifest.csv`. `execute.ps1` refuses unexpected, modified, or linked files at the dataset root and below it. It checks the source, staged copy, and extracted ZIP before any transfer. `-StageOnly` creates local staging and ZIP artifacts but never contacts MEGA or writes a run record.

## Run at the selected incident time

In the **same PowerShell session** as the script execution:

~~~powershell
$env:MEGA_EMAIL = Read-Host 'Dedicated MEGA email'
$secure = Read-Host 'MEGA password' -AsSecureString
$env:MEGA_PASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
Remove-Variable secure

# Optional: deliberately leave plaintext account details for analysts to find.
.\credentials.ps1 -Write

# Generates a failed local Robocopy attempt, saved listing, staging, ZIP,
# small probe upload, and final archive upload.
.\execute.ps1 -AddNoise

# If desired, refresh the operator notes with the completed run destination.
.\credentials.ps1 -Write

# Do not leave credentials in the shell longer than required.
Remove-Item Env:\MEGA_EMAIL, Env:\MEGA_PASSWORD -ErrorAction SilentlyContinue
~~~

`credentials.ps1 -Write` intentionally writes `mega-credentials.env` and `operator-notes.txt` to the **local lab user profile**. This is only for the disposable MEGA account. `credentials.ps1 -Remove` deletes those two intentionally exposed files. The generated `rclone.conf` also contains a **reversibly obscured password**, not encryption.

## Artifacts

All files stay beneath the executing user's `%LOCALAPPDATA%\CSWorkshop` directory:

| Path | Investigation purpose |
| --- | --- |
| `ClientDocuments\` and `dataset-manifest.csv` | Fictional dataset and file hashes |
| `discovery-<run>.txt` | File search output |
| `abandoned-<run>\`, optional | Failed staging attempt |
| `staging-<run>\` and `client-data-<run>.zip` | Collected documents and ZIP |
| `probe-<run>.txt` | Small test upload |
| `rclone-v1.75.2-windows-amd64.zip`, `bin\rclone.exe`, and `rclone.conf` | Pinned transfer tool archive, checked executable, and cloud destination |
| `transfer-<run>.log` | Transfer events |
| `runs\<run>.json`, `last-run.txt` | Exact remote directory and archive SHA256 |
| `mega-credentials.env`, optional | Recoverable lab credentials, plaintext |
| `operator-notes.txt`, optional | Left-behind host and remote hints |

A unique run uploads **`probe.txt` and `client-data.zip`** to:

`workshopmega:CSWorkshop/<host>/<run-id>/`

The probe and main archive are separate transfers. Some EDR products may prevent Rclone execution; that prevention is also useful evidence.

## Analyst recovery and facilitator-authorized deletion

~~~powershell
# Inspect the latest run, with no remote changes.
.\recover.ps1 -Action Inspect

# Download the remote archive and verify SHA256 against run metadata.
.\recover.ps1 -Action Download

# Preview the exact deletion target. Requires the verified local copy.
$run = (Get-Content "$env:LOCALAPPDATA\CSWorkshop\last-run.txt" -Raw).Trim()
.\recover.ps1 -Action Delete -ConfirmRunId $run -WhatIf

# Only after facilitator approval; prompts for confirmation.
.\recover.ps1 -Action Delete -ConfirmRunId $run
~~~

The deletion path cannot accept an arbitrary remote URL, checks the recorded run ID, requires a verified recovered archive, and calls Rclone's single-object `deletefile` only. A recursive JSON inventory must contain only the two allowed files, with unique names and object IDs; their IDs and sizes must still match the inventory saved at download. The verified local ZIP and `verified-inventory.json` remain in `recovery\<run>\`. By default the MEGA backend moves deleted files to Trash, not permanent destruction. Nothing is purged recursively. If you need to use the recovery utility from a separate analyst workstation, securely copy that run's metadata and lab-only Rclone configuration into the equivalent CSWorkshop location first.

## Threat behavior and investigation

This component models local file discovery, collection, archiving, and cloud exfiltration: [ATT&CK T1083](https://attack.mitre.org/techniques/T1083/), [T1005](https://attack.mitre.org/techniques/T1005/), [T1074.001](https://attack.mitre.org/techniques/T1074/001/), [T1560.001](https://attack.mitre.org/techniques/T1560/001/), and [T1567.002](https://attack.mitre.org/techniques/T1567/002/). Google Threat Intelligence reports real intrusions using Rclone, MEGA, local archives, and targeting legal/accounting records in its [ransomware activity analysis](https://cloud.google.com/blog/topics/threat-intelligence/ransomware-ttps-shifting-threat-landscape). The fictional clients, failed local copy, probe, and exact MEGA path are **simulation choices**, not claims about one campaign.

Facilitators should keep the run ID, account, and manifest out of analyst-facing clues until investigators find supporting artifacts. Useful questions are:

1. Which files were discovered, staged, and archived, and were any real files involved?
2. Did the failed Robocopy command precede a successful collection? What does its exit status prove?
3. Does endpoint telemetry establish an attempted transfer, a reported successful upload, or verified remote content?
4. Which local evidence and remote account records should be preserved before containment or deletion?

Falcon Advanced Event Search uses CrowdStrike Query Language, **not** the FQL API filter syntax. A starting query, to scope by host and time in the UI, is:

~~~text
#event_simpleName=ProcessRollup2 event_platform=Win
| CommandLine=/CSWorkshop|rclone|robocopy|tar\.exe/i
| table([@timestamp, aid, ComputerName, ParentBaseFileName, FileName, CommandLine], limit=200)
~~~

Adapt field names and event availability to the tenant. [CrowdStrike's LogScale tutorial](https://library.humio.com/integrations/integrations-crowdstrike-fltr-tutorial-crowdstrike-fltr-tutorial.html) documents this query style. RTR can corroborate the manifest, ZIP, transfer log, and run metadata; process or network events alone cannot prove the bytes stored by MEGA. Rclone's [MEGA backend](https://rclone.org/mega/) does not expose remote hashes and permits duplicate names, so recovery and local SHA256 comparison are needed for content proof.

## Control-validation checkpoints

1. **Executed:** Local run metadata and exit codes show which script phases completed.
2. **Recorded:** Search process ancestry, command lines, file artifacts, and available network events. Missing events are a visibility result.
3. **Detected or prevented:** Record the exact prevention or analytic, if any, separately from execution and telemetry.
4. **Reconstructed:** Compare source, staging, ZIP, transfer log, remote inventory, and recovered SHA256; identify what remains uncertain.
5. **Responded:** Preserve evidence, scope the dedicated account, make an authorized containment choice, and verify its effect.

Reset with a disposable VM snapshot. Remove only the recorded local run's paths when manual cleanup is required; use `recover.ps1` for remote objects. Offline PowerShell 5.1 and 7 regression tests cover the manifest and inventory validators, but the full Windows/Falcon execution path and live MEGA behavior still need hands-on validation. Earlier testing separately established that Rclone could execute after a lab-scoped Application Abuse exception and that MEGA authentication succeeded; those observations do not validate this revised path. The v1.75.2 archive digest is published in the [official GitHub release asset metadata](https://api.github.com/repos/rclone/rclone/releases/tags/v1.75.2), and the verified ZIP is retained and checked before each use.
