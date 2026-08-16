import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device identity material for one Brain.
final class DeviceCredential {
  const DeviceCredential({
    required this.brainOrigin,
    required this.deviceId,
    required this.deviceLabel,
    required this.privateSeed,
    required this.publicKey,
    required this.scopes,
  });

  final Uri brainOrigin;
  final String deviceId;
  final String deviceLabel;
  final String privateSeed;
  final String publicKey;
  final Set<String> scopes;

  @override
  String toString() => 'DeviceCredential(<redacted>)';
}

/// How well the platform protects credential material at rest.
///
/// There is deliberately no `userPresence` value. This vault stores the
/// credential under the operating-system store's own at-rest protection and
/// does not itself require a biometric or passcode to read it back. The
/// user-presence property is a separate, explicit concern owned by
/// `LocalAuthGate`; advertising it here would overstate what the vault does.
enum VaultProtection { operatingSystem, unavailable }

/// Boundary for Keychain, Android Keystore, and desktop secret-service adapters.
///
/// A production Brain client receives this interface by dependency injection.
/// No SharedPreferences-backed implementation is permitted.
abstract interface class SecureCredentialVault {
  Future<VaultProtection> protection();
  Future<void> write(DeviceCredential credential);
  Future<DeviceCredential?> read(Uri brainOrigin);
  Future<DeviceCredential?> readActive();
  Future<void> remove(Uri brainOrigin);
}

final class UnavailableCredentialVault implements SecureCredentialVault {
  const UnavailableCredentialVault();

  Never _unsupported() {
    throw UnsupportedError(
      'Platform secure credential storage is not available in this build.',
    );
  }

  @override
  Future<VaultProtection> protection() async => VaultProtection.unavailable;

  @override
  Future<DeviceCredential?> read(Uri brainOrigin) async => _unsupported();

  @override
  Future<DeviceCredential?> readActive() async => _unsupported();

  @override
  Future<void> remove(Uri brainOrigin) async => _unsupported();

  @override
  Future<void> write(DeviceCredential credential) async => _unsupported();
}

abstract interface class SecureStorageAdapter {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class FlutterSecureStorageAdapter implements SecureStorageAdapter {
  FlutterSecureStorageAdapter({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(storageNamespace: 'evaluetron_commander'),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
      mOptions: MacOsOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

final class PlatformSecureCredentialVault implements SecureCredentialVault {
  PlatformSecureCredentialVault(this._storage);

  static const _activeKey = 'commander.active-origin.v1';
  static final _sha256 = Sha256();
  final SecureStorageAdapter _storage;

  static void _requireNativeSecureStore() {
    if (kIsWeb) {
      throw UnsupportedError(
        'Commander credentials require a native operating-system secure store.',
      );
    }
  }

  Future<String> _credentialKey(Uri origin) async {
    final digest = await _sha256.hash(utf8.encode(origin.toString()));
    return 'commander.credential.v1.${base64Url.encode(digest.bytes).replaceAll('=', '')}';
  }

  @override
  Future<VaultProtection> protection() async {
    if (kIsWeb) return VaultProtection.unavailable;
    final random = Random.secure();
    final suffix = List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final key = 'commander.secure-store-probe.$suffix';
    final value = 'probe-$suffix';
    try {
      await _storage.write(key, value);
      return await _storage.read(key) == value
          ? VaultProtection.operatingSystem
          : VaultProtection.unavailable;
    } on Object {
      return VaultProtection.unavailable;
    } finally {
      try {
        await _storage.delete(key);
      } on Object {
        // An unavailable store is already reported by the return value.
      }
    }
  }

  @override
  Future<void> write(DeviceCredential credential) async {
    _requireNativeSecureStore();
    final value = jsonEncode({
      'version': 1,
      'brainOrigin': credential.brainOrigin.toString(),
      'deviceId': credential.deviceId,
      'deviceLabel': credential.deviceLabel,
      'privateSeed': credential.privateSeed,
      'publicKey': credential.publicKey,
      'scopes': credential.scopes.toList()..sort(),
    });
    await _storage.write(await _credentialKey(credential.brainOrigin), value);
    await _storage.write(_activeKey, credential.brainOrigin.toString());
  }

  @override
  Future<DeviceCredential?> read(Uri brainOrigin) async {
    _requireNativeSecureStore();
    final value = await _storage.read(await _credentialKey(brainOrigin));
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final origin = Uri.parse(json['brainOrigin'] as String);
      final scopes = (json['scopes'] as List<dynamic>).cast<String>().toSet();
      final credential = DeviceCredential(
        brainOrigin: origin,
        deviceId: json['deviceId'] as String,
        deviceLabel: json['deviceLabel'] as String,
        privateSeed: json['privateSeed'] as String,
        publicKey: json['publicKey'] as String,
        scopes: scopes,
      );
      _validate(credential);
      if (origin != brainOrigin) throw const FormatException('origin mismatch');
      return credential;
    } on Object {
      throw const FormatException('Stored Commander credential is invalid.');
    }
  }

  @override
  Future<DeviceCredential?> readActive() async {
    _requireNativeSecureStore();
    final value = await _storage.read(_activeKey);
    if (value == null) return null;
    final origin = Uri.tryParse(value);
    if (origin == null) {
      throw const FormatException('Stored Commander origin is invalid.');
    }
    return read(origin);
  }

  @override
  Future<void> remove(Uri brainOrigin) async {
    _requireNativeSecureStore();
    await _storage.delete(await _credentialKey(brainOrigin));
    if (await _storage.read(_activeKey) == brainOrigin.toString()) {
      await _storage.delete(_activeKey);
    }
  }

  static void _validate(DeviceCredential value) {
    if (value.brainOrigin.scheme != 'https' ||
        value.brainOrigin.host.isEmpty ||
        value.brainOrigin.path != '' ||
        value.brainOrigin.hasQuery ||
        value.brainOrigin.hasFragment ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(value.deviceId) ||
        !_isBase64Url(value.privateSeed, 32) ||
        !_isBase64Url(value.publicKey, 32) ||
        value.scopes.isEmpty) {
      throw const FormatException('invalid Commander credential');
    }
  }

  static bool _isBase64Url(String value, int byteLength) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) return false;
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      return bytes.length == byteLength &&
          base64Url.encode(bytes).replaceAll('=', '') == value;
    } on FormatException {
      return false;
    }
  }
}
