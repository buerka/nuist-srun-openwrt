# Security and privacy

Do not attach live authentication captures or configuration files to public
issues, pull requests, commits or releases. Credentials, challenge values,
SRBX1 payloads, tokens and complete authentication URLs may allow password
recovery or access to an account. Replacing only the `password` field is not
sufficient sanitization.

Keep `/etc/nuist-srun.json` on the router with permissions `0600`. An attacker
with root access to the router can read it. The client avoids credential-bearing
command-line arguments, never follows authentication redirects, and suppresses
raw responses in logs. These precautions do not turn an HTTP portal into an
encrypted transport or make SRun's legacy encoding a modern encryption scheme.

Use only your own account or one you have explicit authorization to operate.
The project does not provide identity bypass, account discovery or traffic
capture tools.

For a suspected vulnerability, use GitHub's private vulnerability reporting if
it is available on this repository. Otherwise open an issue containing only a
high-level description and ask for a private contact method. Never publish
working credentials or a live exploit payload in an issue.

If a secret was accidentally published, remove the exposed material and rotate
the affected credential. Deleting a file in a later commit does not remove it
from Git history or from copies already downloaded.
