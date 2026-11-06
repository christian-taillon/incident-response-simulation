# Host discovery

Native, low-dependency Windows process activity to give analysts discovery and reconnaissance evidence. No agent, network scanner, Docker host, or malware is needed.

The behavior maps to [ATT&CK T1033](https://attack.mitre.org/techniques/T1033/), [T1016](https://attack.mitre.org/techniques/T1016/), [T1087.001](https://attack.mitre.org/techniques/T1087/001/), [T1083](https://attack.mitre.org/techniques/T1083/), and, when the domain option is used, [T1018](https://attack.mitre.org/techniques/T1018/). These are technique mappings, not attribution. [MITRE's network share discovery research](https://attack.mitre.org/techniques/T1135/) describes share enumeration as a precursor to collection; this component deliberately stays on one lab host.

## Prerequisites and execution scope

Use Windows PowerShell 5.1+ on a disposable lab VM. The default commands read local host state; the failed `.invalid` lookup can contact the configured DNS resolver. `-AttemptLabDomain` sends lookups only for the explicitly supplied, authorized lab domain. No administrator rights are required for the default activity. Prepare the synthetic data component first if file discovery should be part of the sequence.

~~~powershell
.\execute.ps1

# Optional: only against a domain explicitly authorized for the exercise
.\execute.ps1 -AttemptLabDomain -LabDomain training.example.test
~~~

The default script runs `whoami /all`, `hostname`, `ipconfig /all`, `route print`, `net use`, and `net user`, plus a deliberately unsuccessful DNS lookup of `no-such-host.invalid`. If the synthetic dataset exists, it also uses `cmd.exe` to enumerate that directory. Each command's start/end UTC time, output or error, and exit code are saved to `%LOCALAPPDATA%\CSWorkshop\host-discovery-<timestamp>.txt`.

`-AttemptLabDomain` adds a DNS SRV lookup and an `nltest` domain-controller lookup for **only the specific lab domain provided**. It is opt-in to avoid unintentional queries of a real joined domain.

## Investigation and control validation

Analysts should answer: Which account ran discovery? Which commands completed or failed? Did the operator inspect synthetic documents before staging? What domain, if any, was queried? Which conclusions come from Falcon process/network events and which require the saved output file?

Start with this **Falcon Advanced Event Search CQL** query, scoped to the lab host and run time in the UI:

~~~text
#event_simpleName=ProcessRollup2 event_platform=Win
| CommandLine=/whoami|ipconfig|route print|net use|net user|nslookup|nltest|ClientDocuments/i
| table([@timestamp, aid, ComputerName, ParentBaseFileName, FileName, CommandLine], limit=200)
~~~

This is CQL, not FQL API syntax; [CrowdStrike's LogScale tutorial](https://library.humio.com/integrations/integrations-crowdstrike-fltr-tutorial-crowdstrike-fltr-tutorial.html) shows the event and field syntax. Process events may establish execution without proving command results. Compare the host log and, when enabled, DNS/network telemetry. Record separately: script execution, sensor recording, detection/prevention, analyst reconstruction, and the response decision. Reset by removing this run's exact output file or restoring the VM snapshot. Offline regression tests cover output preservation; Falcon event availability and alerts remain unvalidated.
