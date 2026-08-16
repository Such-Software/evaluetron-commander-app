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

### Local authentication gate

Commander holds operator authority over a whole fleet, so the operating-system
lock screen is not accepted as the only barrier. `LocalAuthGate` adds a
device user-presence check (biometric, PIN, pattern, or password) at five
points:

| Point | Where it is enforced |
| --- | --- |
| Activating a stored credential at launch | `CommanderBrainClient._initialCredential` |
| Returning from the background | `CommanderLockGate` |
| Submitting a job | `CommanderController.submitJob` |
| Pairing a Brain | `CommanderController.pair` |
| Revoking this Commander | `CommanderController.forgetPairing` |

The step-up checks live in the controller rather than in widgets so no UI path
can reach a privileged action without one.

The gate **fails closed**. A device with no enrolled authenticator, or a
platform with no `local_auth` implementation, yields
`LocalAuthOutcome.unavailable`, which refuses the action and says so. It is
never treated as success. A paired session on such a device cannot be
unlocked; the deliberate remedy is to enrol a device screen lock.

Fixture mode is intentionally not gated: it carries no operator authority, and
prompting there would train operators to dismiss the prompt reflexively.
Pairing is gated even in fixture mode, so authority can never be acquired on
an unprotected device in the first place.

`VaultProtection` deliberately has no `userPresence` value. The vault stores
the credential under the operating-system store's at-rest protection and does
not itself require a biometric to read it back; user presence is the separate,
explicit concern owned by `LocalAuthGate`.

Known residual gaps, not closed by this gate:

- Frames stop while the app is backgrounded, so the OS app-switcher snapshot
  is taken *before* the lock screen paints. Blocking it needs `FLAG_SECURE` on
  Android and a privacy overlay on iOS.
- The gate is an application-level check. It does not stop an attacker with
  code execution, a rooted or jailbroken device, or a debug build from reading
  the credential out of the platform store directly.

### Brain certificate pinning

The Commander protocol signs client→server only; nothing in a Brain response
is authenticated. Without pinning, anyone holding a certificate from any CA
the device trusts — including one pushed by enterprise MDM — could fabricate
the entire fleet view, hide activity, and swallow job submissions. The
identity check against locally stored values proves nothing, because an
interceptor simply echoes those values back.

Commander pins the Brain's TLS certificate, recorded at pairing:

- Requests run on an `HttpClient` built from
  `SecurityContext(withTrustedRoots: false)` carrying **only** the pinned
  certificates. A peer that cannot present one is rejected *during the
  handshake*, before any request byte is sent. Hostname verification still
  applies.
- `badCertificateCallback` is never set. It only fires after validation has
  already failed, so it cannot implement pinning; returning `true` there
  would be a TLS bypass.
- **Rotation.** A bare leaf pin would break at every renewal — roughly every
  90 days for an ACME issuer. When a pinned handshake fails, Commander
  re-inspects the peer over `SecureSocket`, which completes a handshake under
  ordinary public-CA validation and yields the leaf certificate **without
  sending any application data**. The new certificate is adopted only if it
  is publicly valid *and* carries the same subject and issuer as the one
  recorded at pairing. Up to three certificates stay trusted at once, which
  keeps a window open across a changeover and tolerates a load balancer that
  serves more than one certificate for the same name.
- **On mismatch it fails closed** with a distinct error naming the old and
  new issuer, and keeps the credential and the pin. The recovery path is to
  pair again from the protected operator console, which requires console
  access. Commander never auto-wipes a credential over a certificate change,
  and never offers a one-tap "trust it anyway".

Residual gaps, stated plainly:

- **Pairing is trust-on-first-use.** The pin can only record whoever answered
  at pairing time. An interceptor already in place during pairing is pinned.
  Out-of-band verification of the first connection is not implemented.
- **Same-issuer forgery is not stopped.** An attacker who can obtain a
  certificate for the same host from the same issuer — via DNS or BGP control
  over an ACME challenge, or by compromising that CA — passes the continuity
  rule. Closing this needs a pin on the issuing CA, which **cannot be built
  from Dart's API**: `SecureSocket.peerCertificate` and
  `HttpClientResponse.certificate` expose the leaf only, never the chain, so
  the intermediate's bytes are never available to persist as an anchor.
- The pin is stored in the operating-system secure store, so it inherits
  exactly the protections described above and no more.

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

### Android release signing

Release builds are **never** signed with the debug keystore. That key ships
with every Flutter installation, so a debug-signed release would let anyone
forge an update to a client holding operator authority over the fleet.

Signing material is supplied out of band through `android/key.properties`,
which is gitignored along with `*.jks`, `*.keystore`, and `*.p12`. No keystore
is generated or committed by this repository.

```properties
storeFile=/absolute/path/to/commander-release.jks
storePassword=…
keyAlias=commander
keyPassword=…
```

`storeFile` is resolved relative to `android/app/` when it is not absolute, so
an absolute path is recommended. All four entries are required; a
`key.properties` that is present but incomplete fails the build with the list
of missing keys.

When `android/key.properties` is absent the release build emits a warning and
produces an **unsigned** artifact. That is deliberate: an unsigned build
cannot be installed or published by accident, whereas a debug-signed one can.

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
