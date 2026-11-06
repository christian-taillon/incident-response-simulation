# PowerShell encoding helper

`encode.ps1` produces, but **never executes**, a native Windows `powershell.exe -NoProfile -EncodedCommand` string. Its Base64 representation contains **UTF-16LE** source text, as required by PowerShell.

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

This component is for comparing visible process command lines, encoded script content, and follow-on process creation. Falcon process telemetry may not contain the full streamed script, and Script Block Logging is configuration-dependent.

Microsoft reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe
