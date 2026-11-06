# Host discovery

Native, low-dependency Windows process activity to give analysts discovery and reconnaissance evidence. No agent, network scanner, Docker host, or malware is needed.

~~~powershell
.\execute.ps1

# Optional: only against a domain explicitly authorized for the exercise
.\execute.ps1 -AttemptLabDomain -LabDomain training.example.test
~~~

The default script runs `whoami /all`, `hostname`, `ipconfig /all`, `route print`, `net use`, and `net user`, plus a deliberately unsuccessful DNS lookup of `no-such-host.invalid`. If the synthetic dataset exists, it also uses `cmd.exe` to enumerate that directory. Every command's output and exit code are saved to `%LOCALAPPDATA%\CSWorkshop\host-discovery-<timestamp>.txt`.

`-AttemptLabDomain` adds a DNS SRV lookup and an `nltest` domain-controller lookup for **only the specific lab domain provided**. It is opt-in to avoid unintentional queries of a real joined domain.

Analysts should identify the individual process executions, distinguish successful and unsuccessful discovery, find the output file, and decide whether the discovery explains later synthetic file staging. Falcon visibility varies by configuration; validate against the target sensor.
