# Store readiness

Commander is shaped for Android and Apple distribution, but the current
fixture milestone is not represented as store-ready.

## Required before TestFlight or Play closed testing

- Production Brain API and version negotiation
- Audited Keychain and Android Keystore credential adapters
- QR pairing with accessible manual-code fallback
- Release signing owned by the organization
- Production icons, launch assets, screenshots, and support URLs
- Privacy policy and accurate platform data-safety disclosures
- Network failure, credential expiry, revocation, and offline UX
- Device testing across supported phone and tablet form factors
- Dependency and artifact review in private CI

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
