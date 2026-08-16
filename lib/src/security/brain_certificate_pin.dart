import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_credential_vault.dart';

/// A TLS leaf certificate as it was actually observed on the wire.
///
/// Deliberately plain data rather than `X509Certificate` so the pinning
/// policy can be exercised in tests without a live TLS peer.
typedef ObservedCertificate = ({
  /// Distinguished name of the certificate subject.
  String subject,

  /// Distinguished name of the issuing CA.
  String issuer,

  /// Lowercase hex SHA-256 over the DER encoding.
  String fingerprint,

  /// PEM encoding, installed verbatim as a trust anchor.
  String pem,

  /// Expiry, kept for diagnostics in operator-facing messages.
  DateTime notAfter,
});

Future<ObservedCertificate> observedCertificate({
  required String subject,
  required String issuer,
  required List<int> der,
  required String pem,
  required DateTime notAfter,
}) async {
  final digest = await Sha256().hash(der);
  return (
    subject: subject,
    issuer: issuer,
    fingerprint: digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(),
    pem: pem,
    notAfter: notAfter,
  );
}

/// What Commander trusts for one Brain origin, recorded at pairing time.
///
/// ## Why this shape
///
/// Dart pins at the trust-anchor level: an `HttpClient` built on
/// `SecurityContext(withTrustedRoots: false)` with only these certificates
/// installed will refuse, *during the handshake*, any peer that does not
/// present one of them. `badCertificateCallback` cannot implement pinning —
/// it only fires once validation has already failed, and returning `true`
/// there would be a bypass, so Commander never sets it.
///
/// The rotation problem is real: a bare leaf pin breaks every time the
/// Brain's certificate is renewed, which for an ACME issuer is roughly every
/// 90 days. Dart exposes only the leaf certificate of a connection
/// (`SecureSocket.peerCertificate` / `HttpClientResponse.certificate`), never
/// the issuing intermediate, so the rotation-proof pin — pinning the issuing
/// CA — cannot be captured through the public API at all.
///
/// Commander therefore pins the leaf and treats a *renewal* as the one
/// permitted change: a previously unseen certificate is accepted only when it
/// still validates against the public trust store **and** carries the same
/// subject and the same issuer as the certificate recorded at pairing. See
/// [allowsRotationTo] for the honest limits of that rule.
final class BrainCertificatePin {
  const BrainCertificatePin({
    required this.subject,
    required this.issuer,
    required this.certificates,
  });

  /// First trust decision for an origin. Trust-on-first-use by nature: it can
  /// only record whoever answered at pairing time.
  factory BrainCertificatePin.of(ObservedCertificate observed) =>
      BrainCertificatePin(
        subject: observed.subject,
        issuer: observed.issuer,
        certificates: [observed],
      );

  /// How many certificates stay trusted at once.
  ///
  /// More than one keeps a renewal window open across the changeover and
  /// tolerates a load balancer that terminates TLS with more than one
  /// certificate for the same name.
  static const retained = 3;

  final String subject;
  final String issuer;

  /// Newest first.
  final List<ObservedCertificate> certificates;

  /// The PEM bundle installed as the *only* trust anchors for this origin.
  String get trustBundle => certificates.map((entry) => entry.pem).join();

  bool contains(String fingerprint) =>
      certificates.any((entry) => entry.fingerprint == fingerprint);

  /// Whether an unrecognised certificate may be adopted as a renewal.
  ///
  /// Honest limits. This stops an attacker holding any other publicly trusted
  /// certificate — including one minted by an enterprise MDM CA installed on
  /// the device, which is the realistic threat. It does **not** stop an
  /// attacker who can obtain a certificate for the same host from the same
  /// issuer, for example by passing an ACME challenge through DNS or BGP
  /// control, or by compromising that CA.
  bool allowsRotationTo(ObservedCertificate observed) =>
      observed.subject == subject && observed.issuer == issuer;

  BrainCertificatePin rotatedWith(ObservedCertificate observed) =>
      BrainCertificatePin(
        subject: subject,
        issuer: issuer,
        certificates: [
          observed,
          ...certificates.where(
            (entry) => entry.fingerprint != observed.fingerprint,
          ),
        ].take(retained).toList(growable: false),
      );

  String encode() => jsonEncode({
    'version': 1,
    'subject': subject,
    'issuer': issuer,
    'certificates': [
      for (final entry in certificates)
        {
          'fingerprint': entry.fingerprint,
          'pem': entry.pem,
          'notAfter': entry.notAfter.toUtc().toIso8601String(),
        },
    ],
  });

  static BrainCertificatePin? decode(String value) {
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['version'] != 1) return null;
      final subject = json['subject'] as String;
      final issuer = json['issuer'] as String;
      final certificates = [
        for (final entry in json['certificates'] as List<dynamic>)
          (
            subject: subject,
            issuer: issuer,
            fingerprint:
                (entry as Map<String, dynamic>)['fingerprint'] as String,
            pem: entry['pem'] as String,
            notAfter: DateTime.parse(entry['notAfter'] as String),
          ),
      ];
      if (certificates.isEmpty) return null;
      return BrainCertificatePin(
        subject: subject,
        issuer: issuer,
        certificates: certificates,
      );
    } on Object {
      // A corrupt record must not strand the operator; it is re-established
      // on the next successful pairing.
      return null;
    }
  }
}

/// Where pins live.
///
/// Backed by the operating-system secure store rather than ordinary
/// preferences: a pin is not secret, but a pin an attacker can overwrite is
/// not a pin.
abstract interface class BrainCertificatePinStore {
  Future<BrainCertificatePin?> read(Uri origin);
  Future<void> write(Uri origin, BrainCertificatePin pin);
  Future<void> remove(Uri origin);
}

final class SecureBrainCertificatePinStore implements BrainCertificatePinStore {
  SecureBrainCertificatePinStore(this._storage);

  static final _sha256 = Sha256();
  final SecureStorageAdapter _storage;

  Future<String> _key(Uri origin) async {
    final digest = await _sha256.hash(utf8.encode(origin.toString()));
    return 'commander.brain-pin.v1.'
        '${base64Url.encode(digest.bytes).replaceAll('=', '')}';
  }

  @override
  Future<BrainCertificatePin?> read(Uri origin) async {
    final value = await _storage.read(await _key(origin));
    return value == null ? null : BrainCertificatePin.decode(value);
  }

  @override
  Future<void> write(Uri origin, BrainCertificatePin pin) async =>
      _storage.write(await _key(origin), pin.encode());

  @override
  Future<void> remove(Uri origin) async => _storage.delete(await _key(origin));
}
