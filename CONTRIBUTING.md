# Contributing

Thanks for your interest in Bambu Light! Bug reports, ideas and pull requests are welcome.

## Reporting bugs and suggesting features

Open an [issue](https://github.com/jimbobba2773/Bambu-Labs-Light-Switch/issues). For a bug, please include:
- Your printer model and whether you use LAN or Cloud mode
- Your macOS version and the app version
- What you expected and what happened

Don't post access codes, tokens or serial numbers. For security problems, see [SECURITY.md](SECURITY.md) and report privately instead.

## Setting up

You need macOS 13 or later with Xcode (or its command line tools) installed. There are no dependencies to fetch.

```sh
git clone https://github.com/jimbobba2773/Bambu-Labs-Light-Switch.git
cd Bambu-Labs-Light-Switch
./test.sh      # run the unit tests
./build.sh     # build, sign and install to ~/Applications/BambuLight.app
```

Build output goes to `~/Library/Caches/BambuLight/build`, not the project folder. `build.sh` signs with the first "Apple Development" certificate in your keychain, and falls back to an ad-hoc signature if you don't have one. See the [README](README.md) for more.

## Making a change

1. Fork the repository and create a branch from `main`.
2. Make your change. Keep it focused: one fix or feature per pull request.
3. Run `./test.sh` and make sure it passes. CI runs the same tests on every pull request.
4. Add or update tests when you change behaviour. The parts that are easiest to test, such as the MQTT codec, printer discovery, camera frame parsing and the schedule logic, are kept free of UI and sockets for that reason.
5. Add a line to the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
6. Open a pull request and describe what changed and why.

## Code style

- Match the surrounding code: naming, comment density and idiom.
- Keep the code in small, single-purpose files like the existing ones, and keep network and protocol logic separate from SwiftUI views.
- Prefer clear names over comments, and comment the *why* where it isn't obvious.
- The app runs on macOS 13 and later, so avoid APIs that need anything newer, or guard them.

## Testing against a printer

Unit tests don't need a printer. Changes to connection, camera or light-control behaviour are best tried on a real printer, so please say in your pull request which model you tested with. If you only have one model, that's fine. Just note what you couldn't check.

## Releases

Maintainers publish releases by pushing a `v*` tag, which builds the universal app on GitHub and attaches the zip. See the README for details.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
