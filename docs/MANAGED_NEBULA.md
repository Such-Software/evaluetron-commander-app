# Optional managed Nebula

Commander supports public, signed HTTPS as its independent baseline connection
to a Brain. A managed Nebula path is optional and may provide private
reachability, but it does not weaken HTTPS authentication or become a general
internet VPN.

## Current implementation state

The Dart application has typed boundaries for:

- Commander-specific network enrollment;
- a secure credential vault;
- platform VPN consent;
- tunnel lifecycle and conflict state;
- an exact-host Brain route;
- public HTTPS and managed-network path selection.

Android includes a permission-gated `VpnService` scaffold and method-channel
bridge. The scaffold reports `engineNotInstalled`, refuses all tunnel
mutations, and never establishes a TUN interface. No Nebula engine, Go mobile
archive, host certificate, or production enrollment endpoint is included in
this milestone.

The Brain can issue a distinct `commander` certificate group with a
control-API-only firewall profile. Commander still needs a live enrollment
adapter and a combined pairing flow before it can consume that contract. The
adapter must also bind an explicit Android or iOS target, expiry, and exact-host
Brain route. Commander rejects worker certificate groups by design.

## Route and consent policy

Managed profiles accept only one private or link-local IPv4 `/32` or IPv6
`/128` route for the Brain. Default routes, subnets, and public addresses are
rejected. Public Brain access remains HTTPS. The managed service URL may use
HTTP only when its numeric host exactly matches that mutually authenticated
overlay route and specifies a port.

Before requesting operating-system VPN consent, the UI must explain:

- which exact Brain host will be routed;
- that the operating system displays VPN status;
- that mobile platforms generally permit one active VPN;
- that Commander will not silently replace another VPN;
- how to disconnect and return to public HTTPS.

The native adapter must protect the Nebula UDP socket from its own TUN route,
close the interface on revocation, and keep an auditable foreground lifecycle
where the platform requires it.

## Source and license audit

Reviewed upstreams:

- `slackhq/nebula` release `v1.10.3`
- `DefinedNet/mobile_nebula` source at
  `9f7ac7dedb5be38d4bddc96ca5266173b2704434`

Nebula core is MIT licensed. The MIT license permits use in a proprietary
application, but its copyright and permission notice must accompany copies or
substantial portions. When the core is embedded, the release must include its
full MIT notice in a third-party notices surface and preserve notices in source
and binary distribution materials.

The Mobile Nebula application repository does not publish a repository-level
license. Its application shell is therefore reference material only and is not
copied into Commander. Commander must build an independent platform adapter or
obtain explicit permission. Transitive Go and native dependencies require a
separate locked dependency and notice audit before release.

No Nebula-derived code or binary is currently shipped, so this private
repository intentionally remains unlicensed and contains no project
`LICENSE` file.

## Production gate

Do not set the native capability to `available` until all of the following are
true:

1. A pinned, reproducible Nebula core build is embedded.
2. The Commander-specific enrollment adapter, combined pairing, and revocation
   flow are deployed.
3. Key and configuration material persist only through the secure vault.
4. Android consent, conflict, foreground service, revoke, and process-death
   tests pass on real devices.
5. The equivalent Network Extension design is approved and implemented for
   Apple platforms.
6. Firewall policy permits only required Brain services.
7. Third-party notices, SBOM, provenance, and security review are complete.
