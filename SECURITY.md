# Security Policy

## Supported versions

Only the latest release receives security fixes. Please update before reporting.

## Reporting a vulnerability

Please report security problems privately, not in a public issue.

Use GitHub's private reporting: open the repository's **Security** tab and choose **Report a vulnerability**. This creates a private conversation visible only to the maintainers.

Helpful details:
- What you found and what an attacker could do with it
- The app version (shown in the app's bundle) and your macOS version
- Steps to reproduce, or a proof of concept

**Never include a real printer access code, Bambu account password or token** in a report. Redact them, or use a test account.

This is a small, volunteer-maintained project. Reports are handled on a best-effort basis; expect an acknowledgement within about a week. Please allow time for a fix before disclosing publicly, and you'll be credited in the changelog unless you prefer otherwise.

## What's in scope

- How the app stores secrets (the access code and cloud token are kept in the macOS Keychain)
- Certificate handling for LAN connections (the printer's certificate is pinned on first use)
- Parsing of data received from the network: MQTT messages, printer discovery announcements and camera frames
- Bambu Cloud sign-in handling in the app

## Out of scope

- Vulnerabilities in Bambu Lab's firmware, cloud service or official apps. Report those to Bambu Lab.
- Attacks that need physical access to your Mac or an already-unlocked, compromised account
- The first-launch warning macOS shows, because releases are not notarized by Apple
- Problems caused by the unofficial cloud API changing

## Good to know

- On first connection the app trusts the printer's certificate and pins it. If you connect for the first time on an untrusted network, that first connection could be intercepted. Set up LAN mode on a network you trust.
- The app talks directly to your printer (LAN mode) or to Bambu's servers (cloud mode). It sends nothing to the author or any third party.
