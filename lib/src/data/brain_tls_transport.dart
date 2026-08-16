import 'dart:convert';
import 'dart:io';

import '../security/brain_certificate_pin.dart';

/// One HTTP exchange with a Brain, reduced to what the client actually needs.
typedef BrainResponse = ({
  int statusCode,

  /// MIME type only, without parameters.
  String? contentType,

  /// Raw `Retry-After` header, if the Brain sent one.
  String? retryAfter,
  List<int> body,
});

/// Raised when a Brain could not be reached at all.
final class BrainNetworkException implements Exception {
  const BrainNetworkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Raised when the TLS handshake itself failed.
///
/// Distinct from [BrainNetworkException] because a failed handshake against a
/// pinned origin is the signal that the Brain's certificate changed, and the
/// two need very different operator-facing messages.
final class BrainHandshakeException implements Exception {
  const BrainHandshakeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The TLS boundary.
///
/// Owning the whole exchange here keeps every transport-level guard —
/// timeouts, redirect refusal, response size cap, and the trust anchors in
/// force — in one auditable place, and lets the Brain client be tested
/// without a live socket.
abstract interface class BrainTlsTransport {
  /// Sends one request.
  ///
  /// When [trustBundle] is non-null the handshake trusts **only** the PEM
  /// certificates it contains; the public root store is not consulted.
  /// Hostname verification still applies in both modes.
  Future<BrainResponse> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required List<int> body,
    required String? trustBundle,
  });

  /// Completes a TLS handshake against [origin] using ordinary public-CA
  /// validation and reports the leaf certificate **without sending any
  /// application data**.
  ///
  /// This is what makes a safe rotation check possible: the signed request,
  /// and any job payload in it, is never handed to a peer whose identity has
  /// not been re-established first.
  Future<ObservedCertificate> peerCertificate(Uri origin);
}

final class PlatformBrainTlsTransport implements BrainTlsTransport {
  PlatformBrainTlsTransport({HttpClient? httpClient})
    : _unpinned = httpClient ?? _client(null);

  static const _connectTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 20);
  static const _maxResponseBytes = 1024 * 1024;

  final HttpClient _unpinned;
  final _pinned = <String, HttpClient>{};

  static HttpClient _client(String? trustBundle) {
    final client = trustBundle == null
        ? HttpClient()
        // Trust is replaced, not extended: `withTrustedRoots: false` means a
        // peer chaining to any other public or enterprise CA is rejected
        // during the handshake, before a byte of the request is sent.
        : HttpClient(
            context: SecurityContext(withTrustedRoots: false)
              ..setTrustedCertificatesBytes(utf8.encode(trustBundle)),
          );
    return client..connectionTimeout = _connectTimeout;
  }

  @override
  Future<BrainResponse> send({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required List<int> body,
    required String? trustBundle,
  }) async {
    final client = trustBundle == null
        ? _unpinned
        : _pinned.putIfAbsent(trustBundle, () => _client(trustBundle));
    final HttpClientRequest request;
    try {
      request = await client.openUrl(method, url).timeout(_requestTimeout);
    } on HandshakeException catch (error) {
      throw BrainHandshakeException('$error');
    } on TlsException catch (error) {
      throw BrainHandshakeException('$error');
    } on Object catch (error) {
      throw BrainNetworkException('$error');
    }
    request.followRedirects = false;
    request.maxRedirects = 0;
    headers.forEach(request.headers.set);
    if (body.isNotEmpty) {
      request.contentLength = body.length;
      request.add(body);
    }
    final HttpClientResponse response;
    try {
      response = await request.close().timeout(_requestTimeout);
    } on HandshakeException catch (error) {
      throw BrainHandshakeException('$error');
    } on TlsException catch (error) {
      throw BrainHandshakeException('$error');
    } on Object catch (error) {
      throw BrainNetworkException('$error');
    }
    if (response.isRedirect) {
      await response.drain<void>();
      throw const BrainNetworkException('Brain redirects are not accepted.');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(_requestTimeout)) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const BrainNetworkException(
          'Brain response exceeded the safety limit.',
        );
      }
      bytes.addAll(chunk);
    }
    return (
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      retryAfter: response.headers.value(HttpHeaders.retryAfterHeader),
      body: bytes,
    );
  }

  @override
  Future<ObservedCertificate> peerCertificate(Uri origin) async {
    final SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        origin.host,
        origin.port,
        timeout: _connectTimeout,
      );
    } on HandshakeException catch (error) {
      throw BrainHandshakeException('$error');
    } on TlsException catch (error) {
      throw BrainHandshakeException('$error');
    } on Object catch (error) {
      throw BrainNetworkException('$error');
    }
    try {
      final certificate = socket.peerCertificate;
      if (certificate == null) {
        throw const BrainHandshakeException(
          'The Brain presented no TLS certificate.',
        );
      }
      return await observedCertificate(
        subject: certificate.subject,
        issuer: certificate.issuer,
        der: certificate.der,
        pem: certificate.pem,
        notAfter: certificate.endValidity,
      );
    } finally {
      socket.destroy();
    }
  }
}
