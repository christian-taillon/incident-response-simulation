# Scenario development roadmap (design only)

This is a prioritized backlog, not executable activity. The existing components remain the only implemented scenarios. Every proposed component is limited to a disposable Windows lab, synthetic data, and named exercise accounts or shares. Falcon observations, alerts, and response outcomes must be measured separately during a sensor-equipped rehearsal.

## Research basis and priorities

Google Threat Intelligence Group [reported](https://cloud.google.com/blog/topics/threat-intelligence/ransomware-ttps-shifting-threat-landscape) real intrusions that targeted legal, accounting, and other business records, staged archives, and used Rclone or MEGA for theft. [ATT&CK T1083](https://attack.mitre.org/techniques/T1083/) describes file discovery, while [T1039](https://attack.mitre.org/techniques/T1039/) documents collection from network shares. [ATT&CK T1059.001](https://attack.mitre.org/techniques/T1059/001/) includes encoded PowerShell and retrieved scripts. The failed commands, small probes, and imperfect cleanup below are deliberate **simulation choices** to expose investigative distinctions; they are not attributed to a named intrusion.

| Priority | Independent component | Investigation value | Effort / infrastructure | Decision |
| --- | --- | --- | --- | --- |
| 1 | Selective local document search | High: establishes searched, ignored, and collected files | Small / local VM | Build next |
| 2 | Scoped share discovery and collection | High: tests scope and failed access interpretation | Medium / one synthetic SMB share | Build next |
| 3 | Reviewed remote PowerShell retrieval | High: separates command line, fetched content, and effects | Medium / pinned Gist or optional local server | Build next |
| 4 | Interrupted and resumed transfer | High: separates attempts from verified upload | Medium / disposable MEGA account | Wait for live MEGA validation |
| 5 | Recoverable operator configuration | Medium: connects account, endpoint, and local artifacts | Small / local VM | After top three |
| 6 | Partial local cleanup | Medium: tests surviving evidence after deletion | Small / local VM | After collection scenarios |

The top three add distinct evidence relationships with little infrastructure. Transfer retries should wait until the hardened single transfer is exercised against MEGA. No new scenario should assume an alert or require Falcon to produce a particular event.

## 1. Selective local document search — build next

**Narrative and precedent.** An operator with a normal user session searches a prepared fictional client tree for legal and billing records, opens a few candidates, ignores decoys, and collects a chosen subset. GTIG reports real theft operations targeting legal and accounting data and using selective file-type collection in its [ransomware analysis](https://cloud.google.com/blog/topics/threat-intelligence/ransomware-ttps-shifting-threat-landscape). Map to [T1083](https://attack.mitre.org/techniques/T1083/), [T1005](https://attack.mitre.org/techniques/T1005/), and [T1074.001](https://attack.mitre.org/techniques/T1074/001/).

**Files and execution.** Add `scenarios/selective-file-collection/prepare.ps1`, `execute.ps1`, and `README.md`, plus `tests/selective-file-collection.ps1`. Preparation creates a separate synthetic tree with useful files, false leads, and a signed manifest. Execution uses bounded `dir`, `findstr`, and exact-path `Copy-Item` or `robocopy` commands; it leaves a search transcript and a partial staging directory. It must never search a caller-supplied arbitrary root.

**Evidence and questions.** Expected artifacts: process command lines, search output with timestamps and access failures, file access where available, and a staged subset manifest. Analysts should ask: (1) What terms and extensions were searched? (2) Which files were found but not collected? (3) Did the operator encounter an inaccessible file? (4) What would prove that the archive contained only selected files?

**Controls, reset, acceptance.** Validate process ancestry, file access visibility, prevention, and RTR collection independently. A snapshot or exact run-directory removal resets the component. Acceptance: deterministic synthetic-only validation; one failed access; a staged subset whose hashes match its selection record; a question that cannot be answered from the execution command alone. No network or administrator access required.

**Implementation plan.** First add fixture generation and a file allowlist. Then add a short command sequence that records searches, selections, and failed reads. Last add tests for unexpected files, links, incorrect hashes, and repeat runs. Keep its output compatible with the current data-exfiltration component without requiring it.

## 2. Scoped share discovery and collection — build next

**Narrative and precedent.** A user explores one authorized lab file server, finds a share, fails to read one protected folder, and copies a small synthetic subset from another. [ATT&CK T1135](https://attack.mitre.org/techniques/T1135/) describes share discovery before collection; [T1039](https://attack.mitre.org/techniques/T1039/) cites real use of mapped drives and Robocopy. The one-server limit and planned failure are simulation choices.

**Files and execution.** Add `scenarios/scoped-share-collection/prepare.ps1`, `execute.ps1`, `README.md`, and `tests/scoped-share-collection.ps1`. Preparation records the exact UNC host/share allowlist and places synthetic files on a disposable SMB share. Execution uses `net view`, `dir`, `net use` only if needed, and bounded Robocopy with no recursive domain or subnet scan. The default is offline validation; share access requires explicit `-LabShare` matching the prepared record.

**Evidence and questions.** Expected artifacts: SMB connection attempts, `net`/`cmd`/Robocopy process lines, share-side access logs if enabled, failed-access output, and local copied hashes. Analysts should ask: (1) Which share was enumerated versus accessed? (2) Which identity had the effective permission? (3) Did denied access stop the operator or redirect collection? (4) What evidence is needed from the server to establish scope?

**Controls, reset, acceptance.** Validate SMB policy, endpoint process/network events, server auditing, and containment of the lab account separately. Restore the share and VM snapshots. Acceptance: no access outside the exact recorded UNC; one intentional denial; successful copies hash-match synthetic source; exercises run with an ordinary user account and no live domain requirement. Infrastructure: one lab SMB share; medium effort.

**Implementation plan.** Start with one named share and two permission tiers. Implement strict UNC parsing and a dry run before any copy. Add fixtures for allowed, denied, and missing paths. Test that an altered host, share, junction, or unexpected file fails before collection. Then document host-side and server-side evidence separately.

## 3. Reviewed remote PowerShell retrieval — build next

**Narrative and precedent.** An operator runs a short encoded PowerShell command that fetches a reviewed script and then performs one existing benign lab activity. [ATT&CK T1059.001](https://attack.mitre.org/techniques/T1059/001/) documents encoded and downloaded PowerShell in intrusions; [T1105](https://attack.mitre.org/techniques/T1105/) covers ingress tool transfer. The Gist or temporary tunnel is a simulation delivery choice, not attribution to a specific actor.

**Files and execution.** Add `scenarios/reviewed-script-retrieval/prepare.ps1`, `execute.ps1`, `README.md`, and `tests/reviewed-script-retrieval.ps1`. Preparation pins the script bytes and SHA256. Execution accepts only an exact reviewed HTTPS URL and expected hash, downloads to a lab-only path, checks the hash, and invokes the approved local activity. A [revision-specific Gist raw URL](https://docs.github.com/en/rest/gists/gists) is the default option; a [Cloudflare Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) is optional and requires a separately approved server. The current `encode.ps1` remains a helper, not a dependency.

**Evidence and questions.** Expected artifacts: encoded command line, DNS/HTTPS connection, downloaded file and hash, PowerShell logs if enabled, and child processes from the underlying activity. Analysts should ask: (1) What does the encoded command request? (2) Was the fetched content the reviewed revision? (3) Did the command merely download, or execute? (4) Which child events prove the underlying activity ran?

**Controls, reset, acceptance.** Validate outbound policy, script logging, process ancestry, content inspection, and prevention independently. Remove the exact run's downloaded file or restore the VM. Acceptance: wrong URL/hash fails before execution; no credentials in hosted content; offline tests cover decoding and hash gates; a sensor-equipped run compares direct local execution with retrieved execution. Medium effort; HTTPS hosting is the only external dependency.

**Implementation plan.** Define the allowlisted URL and signed facilitator manifest. Add a download-only mode and explicit execution step. Test wrong revision, altered content, timeout, and retry without executing unreviewed bytes. Rehearse with a pinned Gist first; treat the tunnel as an optional delivery variant.

## 4. Interrupted and resumed transfer

An operator sends a small probe, attempts a larger transfer, encounters a controlled failure, and retries. GTIG reports Rclone/MEGA use in theft operations; the interruption and retry are simulation choices to test outcome attribution ([T1567.002](https://attack.mitre.org/techniques/T1567/002/)). Proposed files: `scenarios/transfer-retry/prepare.ps1`, `execute.ps1`, `README.md`, `tests/transfer-retry.ps1`. The sequence must use only the existing synthetic archive and dedicated account, with exact run paths and a bounded retry count. Evidence: separate process invocations, transfer logs, partial or complete remote objects, timestamps, and final recovered hash. Questions: Which attempt failed? Did any bytes reach MEGA? What proved the retry succeeded? Which evidence survives if the endpoint is isolated mid-transfer? Validate egress controls, Rclone status, remote inventory, and recovery independently. Reset with the hardened recovery tool and account review. Acceptance: deterministic offline failure simulation and live proof that a successful outcome is distinguished from an attempt. Medium effort; live MEGA access required.

## 5. Recoverable operator configuration

An operator leaves a lab-only connection note and a reversible Rclone configuration while moving between steps. Rclone's [MEGA documentation](https://rclone.org/mega/) requires an obscured password, which is not a secret-storage boundary; real intrusions use Rclone as described by [GTIG](https://cloud.google.com/blog/topics/threat-intelligence/ransomware-ttps-shifting-threat-landscape). This is an intentional operator-mistake simulation tied to [T1552.001](https://attack.mitre.org/techniques/T1552/001/). Proposed files: `scenarios/operator-config-exposure/prepare.ps1`, `execute.ps1`, `README.md`, and a focused test. Use only a disposable account or synthetic placeholder, never a production secret. Evidence: local note, configuration path, file timestamps, and subsequent process use. Questions: Which account and destination does the file suggest? Was it actually used? Who can access it? What authorization is needed before account recovery or rotation? Validate file permissions, RTR access, credential handling, and response procedure. Reset by deleting only the recorded artifacts and rotating the lab account. Small effort; no new infrastructure beyond an optional lab account.

## 6. Partial local cleanup

After collection, an operator deletes one staging directory but overlooks a log or archive. [ATT&CK T1070.004](https://attack.mitre.org/techniques/T1070/004/) describes deletion of intrusion artifacts. Proposed files: `scenarios/partial-cleanup/prepare.ps1`, `execute.ps1`, `README.md`, and a test. Preparation copies known synthetic run artifacts into a dedicated cleanup fixture; execution deletes only named files under that fixture, without secure wiping or arbitrary paths. Evidence: deletion commands, remaining file hashes, directory metadata, and retained archive or logs. Questions: What was removed? What survived? Can original contents be reconstructed? Which preservation step should precede further containment? Validate file-deletion telemetry, RTR collection, and evidence preservation separately. Reset from the fixture manifest or snapshot. Small effort, local VM only. Acceptance: exact-path deletion, dry-run preview, no impact on the original dataset, and at least two independent surviving clues.

## Future incident playbooks (manual facilitator sequences)

These are narratives, not an orchestration engine. Each step is manually triggered and recorded by the facilitator.

### Legal-record theft after routine discovery

- **Timeline:** T0 run existing host discovery; T+5m run selective local search; T+15m stage the chosen subset; T+25m run the hardened MEGA transfer.
- **Triggers and first clue:** The facilitator schedules each step and hands analysts only a `robocopy.exe` or `rclone.exe` process lead.
- **Milestones:** Reconstruct the preceding searches, distinguish ignored from collected files, verify the ZIP and remote recovery, and identify any gaps in file access telemetry.
- **Response discussion:** Endpoint isolation timing, account containment, evidence preservation, disclosure threshold, and proof of remote cleanup.

### Share access denial followed by alternate collection

- **Timeline:** T0 run scoped share discovery; T+8m attempt a denied folder; T+12m collect from an accessible share; T+20m run partial local cleanup.
- **Triggers and first clue:** The facilitator provides a failed SMB access event or `net view` process event, then releases server-side audit data only if analysts request it.
- **Milestones:** Identify the account and exact share, separate enumeration from reads, find the copied subset, and recover surviving artifacts after deletion.
- **Response discussion:** Scope of share access, server versus endpoint evidence, account disablement, and preservation before cleanup.

### Encoded retrieval and uncertain exfiltration

- **Timeline:** T0 prepare a pinned reviewed script; T+3m run encoded retrieval; T+10m run existing data discovery; T+20m run an interrupted transfer and later retry.
- **Triggers and first clue:** The facilitator gives an encoded PowerShell command line and withholds the downloaded script hash until requested.
- **Milestones:** Decode the command, corroborate retrieved content, tie child processes to the activity, and distinguish failed transfer from recovered remote content.
- **Response discussion:** Network blocking, script logging gaps, timing of isolation, account review, and evidence needed before declaring data loss.
