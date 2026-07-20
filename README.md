# Evaluetron Commander

Private, adaptive operator client for an Evaluetron Brain. Commander is a
native Flutter application for phones, tablets, and keyboard/mouse desktops;
it is not a web admin console wrapped in a WebView.

The application includes a deterministic fixture mode and a live Brain
transport. Live pairing creates an Ed25519 device identity, verifies a signed
profile request, and stores the private seed through the operating-system
secure store.

## Product surfaces

- Scoped Brain profile and secure pairing design
- Operational overview
- Model catalog and bounded job submission
- Job monitoring
- Worker fleet visibility and app-based enrollment preview
- Redacted configuration view
- Operator-safe activity history
- Optional, consented managed-Nebula foundation with narrow Brain routing

## Security boundary

Pairing exchanges a short-lived enrollment for a revocable, least-privilege
device identity. Secret material is only handled through
the `SecureCredentialVault` abstraction backed by Keychain, Android Keystore,
or an equivalent operating-system store. It must never be put in
SharedPreferences, ordinary files, logs, analytics, or crash reports.

`BrainClient` is the transport-independent application contract.
`FixtureBrainClient` is deterministic local data for development and tests.
`CommanderBrainClient` switches from fixture data only after authenticated
pairing succeeds.

## Distribution direction

The application targets Android, iOS, macOS, Linux, and Windows. Android and
iOS packaging is prepared for internal sideload/TestFlight and closed testing;
store submission still requires production API qualification, platform secure
storage device qualification, privacy disclosures, signing, accessibility
review, and store assets.

Bundle/application ID: `com.suchsoftware.evaluetron.commander`

See [architecture](docs/ARCHITECTURE.md) and
[store readiness](docs/STORE_READINESS.md) for the production boundary and
remaining release work.

The optional managed-network design and upstream license audit are documented
in [managed Nebula](docs/MANAGED_NEBULA.md).
Visual identity and reproducible platform-asset generation are documented in
[brand system](docs/BRAND.md).

## Development

```sh
flutter analyze
flutter test
flutter run
```

Copyright © 2026 Such Software. All rights reserved.

This repository is private and proprietary. No license is granted. No
`LICENSE` file is intentionally present.
