import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secure_credential_vault.dart';

final class CommanderEnrollment {
  const CommanderEnrollment({required this.brainOrigin, required this.token});

  final Uri brainOrigin;
  final String token;

  static CommanderEnrollment parse(Uri uri) {
    if (uri.scheme != 'evaluetron-commander' ||
        uri.host != 'pair' ||
        uri.path.isNotEmpty ||
        uri.queryParameters.length != 3 ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters['v'] != '1') {
      throw const FormatException('Invalid Commander enrollment URI.');
    }
    final brain = Uri.tryParse(uri.queryParameters['brain'] ?? '');
    final token = uri.queryParameters['token'] ?? '';
    if (brain == null ||
        brain.scheme != 'https' ||
        brain.host.isEmpty ||
        brain.userInfo.isNotEmpty ||
        (brain.path.isNotEmpty && brain.path != '/') ||
        brain.hasQuery ||
        brain.hasFragment ||
        !RegExp(r'^evc_[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Invalid Commander enrollment URI.');
    }
    return CommanderEnrollment(
      brainOrigin: brain.replace(path: ''),
      token: token,
    );
  }
}

final class CommanderDeviceSigner {
  CommanderDeviceSigner({Ed25519? algorithm, Random? random})
    : _algorithm = algorithm ?? Ed25519(),
      _random = random ?? Random.secure();

  final Ed25519 _algorithm;
  final Random _random;

  Future<({String seed, String publicKey})> createKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return (seed: _base64Url(seed), publicKey: _base64Url(publicKey.bytes));
  }

  Future<Map<String, String>> signedHeaders({
    required DeviceCredential credential,
    required String method,
    required String path,
    required List<int> body,
    DateTime? now,
    List<int>? nonce,
  }) async {
    final timestamp =
        ((now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000)
            .toString();
    final nonceBytes =
        nonce ?? List<int>.generate(16, (_) => _random.nextInt(256));
    if (nonceBytes.length != 16) throw ArgumentError.value(nonceBytes, 'nonce');
    final nonceValue = _base64Url(nonceBytes);
    final canonical = await canonicalRequest(
      timestamp: timestamp,
      nonce: nonceValue,
      method: method,
      path: path,
      body: body,
    );
    final keyPair = await _algorithm.newKeyPairFromSeed(
      base64Url.decode(base64Url.normalize(credential.privateSeed)),
    );
    final signature = await _algorithm.sign(
      utf8.encode(canonical),
      keyPair: keyPair,
    );
    return {
      'X-Evaluetron-Device-Id': credential.deviceId,
      'X-Evaluetron-Timestamp': timestamp,
      'X-Evaluetron-Nonce': nonceValue,
      'X-Evaluetron-Signature': _base64Url(signature.bytes),
    };
  }

  static Future<String> canonicalRequest({
    required String timestamp,
    required String nonce,
    required String method,
    required String path,
    required List<int> body,
  }) async {
    final digest = await Sha256().hash(body);
    final bodyHash = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return [
      'v1',
      timestamp,
      nonce,
      method.toUpperCase(),
      path,
      bodyHash,
    ].join('\n');
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
