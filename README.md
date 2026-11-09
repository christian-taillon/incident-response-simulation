# Incident Response Simulation

Reusable, deliberately small activity components for security investigations on **authorized, disposable lab hosts**. A component is a piece of a larger incident, not a full attack chain.

## Components

| Component | Activity | OS |
| --- | --- | --- |
| [Data exfiltration](scenarios/data-exfiltration/README.md) | Fictional files, discovery, Robocopy, Tar, Rclone to a dedicated MEGA test account, evidence recovery | Windows |
| [Host discovery](scenarios/host-discovery/README.md) | Native host/network/account discovery, optional specific lab-domain lookups, recoverable output | Windows |
| [Remote execution](scenarios/remote-execution/README.md) | Generate/decode Base64 UTF-16LE PowerShell command text for reviewed local or HTTPS scripts | Windows |

Each component is self-contained and manually executed. There is no shared runner, Docker requirement, ClickFix integration, or background task.

## Basic workflow

1. On a **Windows lab VM**, run `scenarios/data-exfiltration/prepare.ps1` to create only fictional data.
2. Optionally run host discovery or create an encoded command for a reviewed script.
3. Supply a **disposable MEGA account** through ephemeral environment variables. Run the exfiltration `execute.ps1` intentionally.
4. Review process events, file artifacts, Rclone logs, and the remote account. Use `recover.ps1` to inspect, download, and optionally remove only the exercise objects.

The [data exfiltration README](scenarios/data-exfiltration/README.md) contains exact commands and facilitator checkpoints.

For live acceptance, follow the [MEGA/Falcon facilitator rehearsal](docs/live-mega-falcon-validation.md) and record redacted outcomes in [issue #2](https://github.com/christian-taillon/incident-response-simulation/issues/2). Offline checks cannot validate MEGA behavior or Falcon detections.

## Verification

Run `.\tests\smoke.ps1`, `.\tests\hardening.ps1`, and `.\tests\recovery.ps1` on a Windows lab host with Windows PowerShell 5.1 or PowerShell 7. These offline checks cover encoding, source/staged/archive integrity, junction rejection, forced staging changes, remote-inventory validation, recovery planning, and failed-discovery logging. They do not contact MEGA. GitHub Actions runs all three test scripts on pull requests and updates to `main` under both PowerShell versions.

The combined transfer, RTR visibility, and Falcon queries **still require verification on a sensor-equipped Windows VM**. An executable running does not guarantee a Falcon detection.

## Future playbooks

A future `playbooks/` directory can describe how to combine these independent components with ClickFix, remote access, persistence, or extortion injects. It does not need an orchestration framework. ClickFix and Beaconator are **not** included in this repository.

The [scenario roadmap](ROADMAP.md) prioritizes proposed components and playbooks. Those activities are designs, not implemented or lab-validated scenarios.

## Guardrails

Never run against production data. Exfiltration checks a generated file manifest before uploading, and the recovery tool only operates on a recorded run and exact object names. These checks support a controlled workshop; they do not establish a security sandbox.

Never commit passwords, Rclone configs, generated files, or recovery artifacts. A plaintext lab credential artifact is **opt-in**. Restrict your MEGA account and rotate credentials after the exercise. Endpoint controls remain enabled; any prevention exception should be approved and lab-scoped.
