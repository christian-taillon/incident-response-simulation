# PowerShell encoding helper

`encode.ps1` produces, but **never executes**, a native Windows `powershell.exe -NoProfile -EncodedCommand` string. Its Base64 representation contains **UTF-16LE** source text, as required by PowerShell.

The relevant behavior is [ATT&CK T1059.001](https://attack.mitre.org/techniques/T1059/001/) for PowerShell execution and, for an approved fetched script, [T1105](https://attack.mitre.org/techniques/T1105/) for tool transfer. ATT&CK documents encoded PowerShell and downloaded scripts in real intrusions; the URL and script in this repository are **facilitator choices**. This helper itself creates no attack telemetry beyond its own execution and optional output file.

~~~powershell
# Encode a short local script for a lab demonstration:
.\encode.ps1 -Path ..\host-discovery\execute.ps1 -OutputFile "$env:TEMP\encoded-command.txt"

# Prefer an operator-reviewed, version-pinned URL for longer scripts:
.\encode.ps1 -Url 'https://gist.githubusercontent.com/OWNER/ID/raw/REVISION/script.ps1'

# Decode a captured Base64 argument for investigation:
.\encode.ps1 -Decode '<Base64Value>'
~~~

`-Path` encodes an entire file. Long script bodies may exceed Windows command-line length limits; use `-Url` for a short, reviewed HTTPS fetcher command instead. The script uses `Invoke-RestMethod` and `Invoke-Expression` in the **generated text only**, and is not itself a downloader or execution service.

For a Cloudflare Quick Tunnel demonstration, deploy a **separate, approved static HTTP server** and point `-Url` to its HTTPS tunnel address. This repository does not deploy infrastructure, create public tunnels, or host credentials. Never put secrets in hosted PowerShell payloads.

Run only on a disposable Windows lab VM with a reviewed local script or version-pinned HTTPS content. An operator must manually execute the generated command to create the intended process/network evidence. Keep a copy and SHA256 of the reviewed source so investigators can distinguish the intended payload from what the endpoint may have fetched.

Investigation questions: What does the Base64 decode to? Was the content local or retrieved over HTTPS? Which child processes or files demonstrate that the script ran? Does the available telemetry contain the fetched body, or only a URL and command line? What corroboration would prove the fetched revision and effect?

Falcon Advanced Event Search **CQL** starting point, scoped to the lab host and time:

~~~text
#event_simpleName=ProcessRollup2 event_platform=Win
| CommandLine=/EncodedCommand|Invoke-RestMethod|gist\.githubusercontent/i
| table([@timestamp, aid, ComputerName, ParentBaseFileName, FileName, CommandLine], limit=200)
~~~

This is not FQL API syntax; [CrowdStrike's LogScale tutorial](https://library.humio.com/integrations/integrations-crowdstrike-fltr-tutorial-crowdstrike-fltr-tutorial.html) documents the query form. Record execution, sensor telemetry, analytic or prevention result, reconstruction, and response outcome separately. A process command line may be truncated; downloaded content and PowerShell Script Block Logging depend on host configuration. Delete only the optional local encoded-command output file to reset; restore the VM snapshot after execution. Encoding round-trip is tested offline in PowerShell 5.1 and 7; a sensor-equipped execution is still unvalidated.

Microsoft reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe
