# Bambu Light

[![Tests](https://github.com/jimbobba2773/Bambu-Labs-Light-Switch/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/jimbobba2773/Bambu-Labs-Light-Switch/actions/workflows/test.yml)

A small macOS menu bar app for turning your Bambu Lab printer's light on and off, with live temperatures and print progress.

- One-click chamber light switch (or **⌃⌥L** from anywhere)
- Nozzle, bed and chamber temperatures, print progress and time remaining
- 3D or simple flat view of the printer
- Notification when a print finishes or fails
- Optional daily on/off schedule for the light
- Live camera view on P1S, P1P, A1 and A1 mini over LAN (turn on LAN mode liveview on the printer)
- Works over your local network (LAN mode) or through Bambu Cloud
- Finds printers on your network automatically

Requires macOS 13 or later.

## Setup

### LAN mode (recommended)

1. On the printer, enable **LAN Mode** and note the IP address, serial number and access code (Settings → WLAN / LAN).
2. Open the app from the menu bar, pick **Local (LAN)**, and choose your printer from **Find printers** (or type the IP and serial).
3. Enter the access code and click **Save & Connect**.

The printer's certificate is pinned the first time you connect. If it later changes (printer replaced or reset), the app refuses to connect and shows "Certificate changed"; use **Forget certificate** to trust it again.

### Bambu Cloud

Pick **Bambu Cloud**, choose your region (Global or China), sign in (verification and two-factor codes are supported) and choose a printer. China-region endpoints are untested.

### Models

The model is detected from the serial number (P1S, P1P, X1 Carbon, X1, X1E, A1, A1 mini, H2D) and can be overridden in settings. The model decides which light is controlled and whether a chamber temperature is shown. The A1 and A1 mini are drawn as open frames; other models are drawn as an enclosed P1S.

## Building

```sh
./build.sh      # build, sign, install to ~/Applications/BambuLight.app
./test.sh       # run the unit tests
```

- Build output goes to `~/Library/Caches/BambuLight/build` (override with `BAMBULIGHT_BUILD_DIR`) rather than the project folder, because SwiftPM's caches break on network shares.
- The app is signed with the first "Apple Development" certificate in your keychain, which keeps Keychain access grants across rebuilds. Override with `SIGN_ID="..."`; it falls back to ad-hoc signing if none is found.
- Set the version with `VERSION=1.1.0 ./build.sh`. The build number is a timestamp.

## Changes

See the [changelog](CHANGELOG.md).

## Sharing

```sh
./package.sh   # builds a universal (Apple silicon + Intel) app and writes dist/BambuLight-<version>.zip
```

The app is signed with a development certificate, not notarized by Apple, so macOS will warn on the first launch on someone else's Mac. They can unzip it, move it to Applications, then right-click the app, choose **Open**, and confirm. If macOS says the app is damaged, run `xattr -dr com.apple.quarantine /Applications/BambuLight.app` once. Notarizing needs a paid Apple Developer ID.

## Project layout

| File | Purpose |
| --- | --- |
| `App.swift` | Menu bar entry point, popover, settings UI |
| `Printer.swift` | State, connection management, Keychain and certificate pinning |
| `MQTT.swift`, `MQTTCodec.swift` | MQTT 3.1.1 client over TLS, and the testable packet codec |
| `Cloud.swift` | Unofficial Bambu Cloud sign-in and device list |
| `Discovery.swift` | Finds printers on the LAN via SSDP |
| `Model.swift` | Printer model details |
| `Extras.swift` | Global shortcut and notifications |
| `Camera.swift`, `TLSSupport.swift` | Live camera stream, and TLS pinning shared with MQTT |
| `Printer3DView.swift`, `PrinterRig.swift`, `PrinterView.swift` | 3D and flat printer views |

## Privacy and security

- The access code and cloud token are stored in the macOS Keychain. Your cloud password is never stored.
- LAN traffic stays on your network. Cloud mode talks only to Bambu's servers.
- The cloud API is unofficial and may change or block clients without notice.
- Not affiliated with Bambu Lab.

## License

[MIT](LICENSE)
