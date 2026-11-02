# Incident Response Simulation

Small, independent scenario components for generating investigation evidence on authorized lab systems.

## Available scenarios

| Component | Activity | Platform |
| --- | --- | --- |
| [Data exfiltration](scenarios/data-exfiltration/README.md) | Synthetic documents, Robocopy, Tar, Rclone, MEGA | Windows |

Each component has its own preparation, manual execution, and investigation instructions. Components can be run independently and later combined into **playbooks** describing complete incident sequences. No playbook runner or shared framework is required.

Only use disposable or explicitly authorized test hosts and dedicated test accounts. Do not use real or sensitive documents. Never commit credentials, transfer logs, or generated artifacts.
