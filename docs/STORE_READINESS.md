# Store readiness

Commander is shaped for Android and Apple distribution and includes its live
signed Brain transport. It is not represented as store-ready until the
remaining release controls are complete.

## Required before TestFlight or Play closed testing

- End-to-end qualification against the production Brain API version
- Keychain and Android Keystore device tests, including backup and migration
- Camera permission, QR pairing, and paste fallback device tests
- Release signing owned by the organization
- Production icons, launch assets, screenshots, and support URLs
- Privacy policy and accurate platform data-safety disclosures
- Network failure, credential expiry, revocation, and offline UX
- Device testing across supported phone and tablet form factors
- Dependency and artifact review in private CI

Implemented foundations include Ed25519 device identity, one-time pairing,
scoped signed requests, durable replay protection, redirect refusal, bounded
responses, Keychain/Android secure storage, Android backup exclusion, camera
QR scanning, and a paste fallback.

## Required before public submission

- Accessibility audit including screen reader, text scaling, contrast, switch
  control, and keyboard-only operation
- Threat-model review and penetration test of pairing and scoped operations
- Account deletion and support behavior where store rules require it
- Crash/analytics policy with model inputs and secrets categorically excluded
- Localization decision and complete store metadata
- Apple privacy manifest and required-reason API inventory
- Google Play Data safety form and current target-SDK compliance
- Incident response, credential rotation, and forced-upgrade strategy

The app identifier is fixed as `com.suchsoftware.evaluetron.commander`.
