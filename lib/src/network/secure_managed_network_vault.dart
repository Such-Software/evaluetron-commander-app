import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../security/secure_credential_vault.dart';
import 'managed_network.dart';

/// Stores the complete managed-network credential in the operating-system
/// secure store. No non-secure persistence fallback is permitted.
final class SecureManagedNetworkVault implements ManagedNetworkVault {
  SecureManagedNetworkVault(this._storage);

  static final _sha256 = Sha256();
  final SecureStorageAdapter _storage;

  Future<String> _key(String profileId) async {
    final digest = await _sha256.hash(utf8.encode(profileId));
    final suffix = base64Url.encode(digest.bytes).replaceAll('=', '');
    return 'commander.managed-network.v1.$suffix';
  }

  @override
  Future<ManagedNetworkCredential?> read(String profileId) async {
    _requireNativeSecureStore();
    final encoded = await _storage.read(await _key(profileId));
    if (encoded == null) return null;
    try {
      final value = decodeManagedCredential(encoded);
      if (value.profile.id != profileId) {
        throw const FormatException('profile mismatch');
      }
      return value;
    } on Object {
      throw const FormatException(
        'Stored managed-network credential is invalid.',
      );
    }
  }

  @override
  Future<void> remove(String profileId) async {
    _requireNativeSecureStore();
    await _storage.delete(await _key(profileId));
  }

  @override
  Future<void> write(ManagedNetworkCredential credential) async {
    _requireNativeSecureStore();
    await _storage.write(
      await _key(credential.profile.id),
      encodeManagedCredential(credential),
    );
  }

  static void _requireNativeSecureStore() {
    if (kIsWeb) {
      throw UnsupportedError(
        'Managed-network credentials require a native secure store.',
      );
    }
  }
}
