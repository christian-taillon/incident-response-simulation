# Data exfiltration: synthetic documents to MEGA

A standalone Windows activity component for CrowdStrike investigation exercises. `prepare.ps1` creates **30 fictional files**. Running `execute.ps1` separately stages them with `robocopy.exe`, creates a ZIP using `tar.exe`, downloads Rclone if needed, and uploads the archive to a dedicated MEGA account. No Docker, ClickFix, or administrator privileges are required by the scripts themselves.

## Prerequisites

- Authorized Windows 10/11 lab VM with PowerShell 5.1+, `robocopy.exe`, and `tar.exe`.
- Internet access to `downloads.rclone.org` and MEGA.
- Dedicated MEGA test account with its encryption keys initialized by a browser login.
- Endpoint protections kept enabled; investigate any prevention, and use only an approved lab-scoped exception if required.

## Run

In PowerShell on the lab VM, from this directory:

```powershell
# One-time dataset setup; rerunnable
.\prepare.ps1

# Set credentials for this PowerShell session (not saved in the scripts)
$env:MEGA_EMAIL = Read-Host 'MEGA email'
$secure = Read-Host 'MEGA password' -AsSecureString
$env:MEGA_PASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
Remove-Variable secure

# Trigger the activity manually at the desired exercise time
.\execute.ps1

# Clear the session credentials when finished
Remove-Item Env:\MEGA_EMAIL, Env:\MEGA_PASSWORD -ErrorAction SilentlyContinue
```

The credentials must be available in the **same PowerShell process** that invokes `execute.ps1`, or inherited by its child PowerShell process. You can also stream the script from a reviewed, version-pinned remote source; neither script depends on `$PSScriptRoot`.

## Artifacts

Created under `%LOCALAPPDATA%\CSWorkshop` for the executing Windows user:

| Path | Purpose |
| --- | --- |
| `ClientDocuments\` | Fictional client records only |
| `bin\rclone.exe` | Portable Rclone, downloaded from the official site |
| `rclone.conf` | MEGA remote with a **reversibly obscured** password |
| `staging-<timestamp>\` | Copy of synthetic documents |
| `client-data-<timestamp>.zip` | Uploaded archive |
| `transfer-<timestamp>.log` | Rclone transfer log |

Each execution uploads to `workshopmega:CSWorkshop/<hostname>/<timestamp>/client-data.zip`. The script refuses to run without the synthetic-data marker or if the document folder contains files without the training marker. The generated Rclone config stays on the VM to support investigation, so remove it or rotate the account after the exercise. Neither the config nor plaintext credentials belong in Git.

## Investigation prompts

1. Find `robocopy.exe`, `tar.exe`, and `rclone.exe` process executions, command lines, and parent processes in Falcon Advanced Event Search (`ProcessRollup2`).
2. Identify the staging directory, ZIP file, Rclone remote name, and possible network destinations.
3. Use RTR, where authorized, to inspect the archive, logs, and Rclone configuration; **redact the credential fields** before sharing evidence.
4. Corroborate successful upload using the MEGA test account. A network connection alone does not prove file contents or successful exfiltration.
5. Discuss scoping, containment, escalation, and notification decisions based on the evidence available.

The earlier workshop validated Rclone execution and MEGA authentication separately. **This combined script has not yet been end-to-end tested on a Windows/Falcon VM.** Validate it in the lab before using it in a live session.
