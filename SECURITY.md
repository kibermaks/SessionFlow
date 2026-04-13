# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older releases | No |

## Reporting a Vulnerability

If you discover a security vulnerability in SessionFlow, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email **kibermaks@gmail.com** with:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
3. You will receive an acknowledgment within 48 hours

## Scope

SessionFlow is a macOS-only desktop app that interacts with:
- Apple Calendar (EventKit) — read/write access to user calendars
- UserDefaults — local preferences storage
- No network requests, no external APIs, no telemetry

## Security Considerations

- All data stays local on the user's machine
- Calendar access requires explicit macOS permission grants
- No user data is collected or transmitted
