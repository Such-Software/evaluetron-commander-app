# Evaluetron Commander

Private, adaptive operator client for an Evaluetron Brain. Commander is a
native Flutter application for phones, tablets, and keyboard/mouse desktops;
it is not a web admin console wrapped in a WebView.

The current milestone is a fixture-backed product shell. It exercises
the intended screens and typed client boundary without claiming a live Brain
connection. Every fixture surface is visibly labeled, pairing fails closed,
and no secret is stored.

## Product surfaces

- Scoped Brain profile and secure pairing design
- Operational overview
- Model catalog and bounded job submission
- Job monitoring
- Worker fleet visibility and app-based enrollment preview
- Redacted configuration view
- Operator-safe activity history

## Security boundary

Production pairing must exchange a short-lived code for a revocable,
least-privilege device identity. Secret material may only be handled through
the `SecureCredentialVault` abstraction backed by Keychain, Android Keystore,
or an equivalent operating-system store. It must never be put in
SharedPreferences, ordinary files, logs, analytics, or crash reports.

`BrainClient` is the transport-independent application contract.
`FixtureBrainClient` is deterministic local data for development and tests.
An authenticated implementation can replace it without coupling screens
to HTTP or generated API types.

## Distribution direction

The application targets Android, iOS, macOS, Linux, and Windows. Android and
iOS packaging is prepared for internal sideload/TestFlight and closed testing;
store submission still requires production API integration, platform secure
storage, privacy disclosures, signing, accessibility review, and store assets.

Bundle/application ID: `com.suchsoftware.evaluetron.commander`

See [architecture](docs/ARCHITECTURE.md) and
[store readiness](docs/STORE_READINESS.md) for the production boundary and
remaining release work.

## Development

```sh
flutter analyze
flutter test
flutter run
```

Copyright © 2026 Such Software. All rights reserved.

This repository is private and proprietary. No license is granted. No
`LICENSE` file is intentionally present.
