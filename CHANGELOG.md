# Changelog

All notable changes to Bambu Light are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-11

First release.

### Added
- Menu bar app with a one-click light switch, a global ⌃⌥L shortcut and an optional daily on/off schedule.
- Live nozzle, bed and chamber temperatures, print progress and time remaining, shown on a 3D or simple flat drawing of the printer.
- Notification when a print finishes or fails.
- LAN mode with printer discovery on the local network, and Bambu Cloud mode (Global and China regions, with verification and two-factor sign-in).
- Live camera view over LAN for P1S, P1P, A1 and A1 mini.
- Printer model detection from the serial number (P1S, P1P, X1 Carbon, X1, X1E, A1, A1 mini, H2D), with a manual override. The A1 series is drawn as an open frame.
- Status pill showing connected, offline and error states, VoiceOver labels, and a one-time launch-at-login prompt.
- Universal (Apple silicon and Intel) build, unit tests, and CI on GitHub Actions.

### Security
- LAN certificates are pinned on first connection (trust on first use), with a **Forget certificate** button.
- The access code and cloud token are stored in the macOS Keychain, and Keychain failures are reported.

### Reliability
- Automatic reconnection with backoff, reconnecting after sleep, and detection of dead connections.
- An expired cloud session sends you back to sign-in.
- The light switch confirms its state with the printer and corrects itself if the printer doesn't respond.

[Unreleased]: https://github.com/jimbobba2773/Bambu-Labs-Light-Switch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jimbobba2773/Bambu-Labs-Light-Switch/releases/tag/v1.0.0
