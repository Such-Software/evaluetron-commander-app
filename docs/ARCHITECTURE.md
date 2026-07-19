# Commander architecture

## Boundary

Commander is an operator client, never the source of truth. The Brain remains
authoritative for identity, scopes, job validation, credit accounting, fleet
leases, configuration policy, and audit events. Client-side validation exists
for usability only and cannot replace server-side enforcement.

The UI depends on `BrainClient`, not HTTP. The deterministic
`FixtureBrainClient` keeps every screen testable without a Brain. The live
client switches away from visibly marked fixture data only after pairing,
signed profile verification, and secure credential persistence succeed.

## Production pairing

1. An already-authorized operator asks the Brain for a short-lived,
   single-purpose pairing challenge.
2. Commander scans its QR payload or accepts the code and independently
   verifies the expected HTTPS Brain origin.
3. Commander creates an Ed25519 key pair locally.
4. The Brain atomically consumes the challenge and issues a revocable device
   identity with explicit Commander scopes.
5. Commander proves possession with a signed profile request and stores the
   private seed only through `SecureCredentialVault`.
6. Every request signs the method, path, timestamp, nonce, and exact body hash.
   Accepted nonces persist in PostgreSQL; job requests also carry a signed
   idempotency key.

There is no fallback to a shared token, local plaintext, SharedPreferences, or
fixture credentials. If the operating system cannot offer the required
protection, pairing fails closed.

## Initial scope model

- `brain:read`: profile and overview
- `jobs:create`: submit a schema-bound job
- `jobs:read`: inspect owned or operator-authorized work
- `fleet:read`: inspect node health and capabilities
- `config:read`: inspect redacted settings
- `activity:read`: inspect bounded audit events

High-impact actions such as changing secrets, revoking another device,
settling credits, or changing fleet policy should use separate scopes,
step-up authorization, an explicit confirmation, and append-only audit.

## Transport adapter requirements

The production adapter should be generated from a versioned machine-readable
Brain contract where practical. It must include:

- strict request and response models with bounded decode sizes;
- TLS-only origins outside a local development build;
- credential redaction and safe error mapping;
- connect, request, and stream-idle timeouts;
- cancellation on screen/controller disposal;
- idempotency keys for job creation and safe mutations;
- pagination for jobs, nodes, models, and activity;
- capability/version negotiation;
- an observable connection state that never presents stale fixtures as live;
- no raw request bodies, credentials, or model input in telemetry.

## Platform adapters

`SecureCredentialVault` will have audited adapters for:

- iOS/macOS Keychain, with access-control policy selected during pairing;
- Android Keystore-backed encrypted credential storage;
- Linux Secret Service where available, otherwise pairing unavailable;
- Windows Credential Manager or DPAPI-bound storage.

These adapters are infrastructure dependencies. Screens and domain contracts
remain platform-neutral.

## State and testing

`CommanderController` is deliberately small and dependency-injected. It
coordinates snapshots and mutations without teaching widgets about transport.
As the live API grows, split controllers by feature rather than introducing a
global mutable service locator.

Tests cover phone and desktop adaptation, navigation, fixture job submission,
strict enrollment parsing, the cross-runtime signature vector, vault
serialization, and secret redaction. Release qualification also requires
contract tests against an ephemeral Brain plus platform integration tests for
secure storage and credential revocation.
