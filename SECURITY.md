# Security Policy

Sumi Browser is currently in Alpha and does not have a stable public release yet. The current `main` branch represents active Alpha development, and Sumi is not recommended as a primary browser at this time.

## Supported Versions

| Version | Security support |
| --- | --- |
| Current `main` branch / latest Alpha state | Reviewed as active development |
| Future public Alpha releases | Supported when available |
| Older experimental builds or local snapshots | Best effort only |

## Reporting Vulnerabilities

Please do not disclose security vulnerabilities in public GitHub issues.

If GitHub Security Advisories are available for this repository, use private vulnerability reporting there. If private advisories are not available to you, contact the maintainer through the contact information on their GitHub profile.

Useful reports include the affected version or commit, a clear description of the impact, and minimal reproduction steps. Do not include real credentials, password-manager vault data, API keys, cookies, private browsing data, or other sensitive personal data.

Security-sensitive areas include:

- Browser session, profile, and site data
- WebKit configuration and navigation handling
- Safari extension compatibility
- Native messaging
- Content script, MAIN world, and isolated world boundaries
- Privacy and adblock modules
- Backup and restore
- Sparkle update mechanism and update notifications
