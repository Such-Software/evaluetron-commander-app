import 'dart:convert';

import 'package:evaluetron_commander_app/src/data/brain_tls_transport.dart';
import 'package:evaluetron_commander_app/src/security/brain_certificate_pin.dart';

/// Builds an [ObservedCertificate] without a live TLS peer.
///
/// The PEM body is only ever compared for containment, so a marker string is
/// enough to model which anchors a bundle carries.
Future<ObservedCertificate> fakeCertificate({
  required String name,
  String subject = 'CN=brain.example.com',
  String issuer = 'CN=Public Issuing CA',
}) => observedCertificate(
  subject: subject,
  issuer: issuer,
  der: utf8.encode('der-$name'),
  pem: '-----BEGIN CERTIFICATE-----\n$name\n-----END CERTIFICATE-----\n',
  notAfter: DateTime.utc(2030),
);

/// In-memory [BrainTlsTransport] that models the handshake behaviour the
/// probe against real Dart TLS confirmed: a pinned client connects only when
/// the peer's certificate is one of the installed anchors, and hands over no
/// application data otherwise.
final class FakeBrainTlsTransport implements BrainTlsTransport {
  FakeBrainTlsTransport({required this.peer, required this.respond});

  /// Certificate the peer currently presents.
  ObservedCertificate peer;

  /// Whether the peer's certificate still validates against public roots.
  bool publiclyValid = true;

  /// Responses by request path.
  BrainResponse Function(String method, String path, List<int> body) respond;

  /// Trust bundles used by handshakes that succeeded.
  final bundles = <String?>[];

  /// Request bodies that actually reached the peer.
  final delivered = <({String path, List<int> body})>[];

  /// How many times the certificate was re-inspected.
  int probes = 0;

  @override
  Future<BrainResponse> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required List<int> body,
    required String? trustBundle,
  }) async {
    if (trustBundle != null && !trustBundle.contains(peer.pem)) {
      throw const BrainHandshakeException(
        'HandshakeException: CERTIFICATE_VERIFY_FAILED',
      );
    }
    if (trustBundle == null && !publiclyValid) {
      throw const BrainHandshakeException(
        'HandshakeException: CERTIFICATE_VERIFY_FAILED',
      );
    }
    bundles.add(trustBundle);
    delivered.add((path: url.path, body: body));
    return respond(method, url.path, body);
  }

  @override
  Future<ObservedCertificate> peerCertificate(Uri origin) async {
    probes++;
    if (!publiclyValid) {
      throw const BrainHandshakeException(
        'HandshakeException: CERTIFICATE_VERIFY_FAILED',
      );
    }
    return peer;
  }
}

BrainResponse jsonResponse(Object body, {int statusCode = 200}) => (
  statusCode: statusCode,
  contentType: 'application/json',
  retryAfter: null,
  body: utf8.encode(jsonEncode(body)),
);
