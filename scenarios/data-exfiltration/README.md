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
~~~

Preparation is intentionally non-destructive: an existing dataset is never overwritten. All synthetic files are enumerated with sizes and SHA256 values in `%LOCALAPPDATA%\CSWorkshop\dataset-manifest.csv`. `execute.ps1` refuses unexpected, modified, or linked files.

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
| `bin\rclone.exe` and `rclone.conf` | Transfer tool and cloud destination |
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

The deletion path cannot accept an arbitrary remote URL, checks the recorded run ID and allowed filenames, requires a verified recovered archive, and calls Rclone's single-object `deletefile` only. By default the MEGA backend moves deleted files to Trash, not permanent destruction. Nothing is purged recursively. If you need to use the recovery utility from a separate analyst workstation, securely copy that run's metadata and lab-only Rclone configuration into the equivalent CSWorkshop location first.

## CrowdStrike investigation checkpoints

1. Identify `cmd.exe`, `robocopy.exe` (including the failed attempt), `tar.exe`, and `rclone.exe` process trees and command lines in Falcon Advanced Event Search (`ProcessRollup2`).
2. Locate the source, staging destination, archive, and transfer configuration through RTR. Keep recovered credentials out of shared logs and screenshots.
3. Correlate small and large uploads and any Falcon network telemetry. Network activity alone does not prove successful transfer.
4. Validate the remote listing, recover the ZIP, and compare the recorded SHA256.
5. Discuss containment, authorization to use recovered account access, preservation, disclosure, and when a deletion attempt is appropriate.

The queries and the full Windows/Falcon execution path still need hands-on validation. Earlier testing separately established that Rclone could execute after a lab-scoped Application Abuse exception and that MEGA authentication succeeded.
