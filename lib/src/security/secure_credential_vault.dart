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

/// A device row this app created on a Brain and could not retire.
///
/// Commander can only revoke itself — there is no `commander:admin` scope, so a
/// second device cannot revoke a first. When an automatic cleanup fails, the
/// only remaining route is the Brain's own console, and that needs the device
/// id. Losing it means an active device row nobody holds a key for, invisible
/// from here. So the id is written down rather than reported once and dropped.
final class StrandedDevice {
  const StrandedDevice({
    required this.brainOrigin,
    required this.deviceId,
    required this.reason,
  });

  final Uri brainOrigin;
  final String deviceId;

  /// Why the cleanup could not finish, phrased for the operator.
  final String reason;

  Map<String, Object?> toJson() => {
    'brainOrigin': brainOrigin.toString(),
    'deviceId': deviceId,
    'reason': reason,
  };

  static StrandedDevice? fromJson(Object? value) {
    if (value is! Map) return null;
    final origin = Uri.tryParse('${value['brainOrigin']}');
    final deviceId = value['deviceId'];
    if (origin == null || deviceId is! String || deviceId.isEmpty) return null;
    return StrandedDevice(
      brainOrigin: origin,
      deviceId: deviceId,
      reason: value['reason'] is String ? value['reason'] as String : '',
    );
  }
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

  /// Every Brain origin a credential is stored for, oldest pairing first.
  ///
  /// Without this the store cannot be enumerated at all — credential keys are
  /// hashed — so a second pairing would leave the first one on the device with
  /// no way for the operator to see it, switch back to it, or remove it.
  Future<List<Uri>> origins();

  /// The origin whose credential [readActive] returns.
  Future<Uri?> activeOrigin();

  /// Makes the credential stored for [brainOrigin] the active one.
  Future<void> activate(Uri brainOrigin);

  /// Device rows left active on a Brain because an automatic revoke failed.
  Future<List<StrandedDevice>> strandedDevices();

  /// Records [device] as needing revocation from its Brain's console. Replaces
  /// any earlier record for the same device id.
  Future<void> recordStranded(StrandedDevice device);

  /// Forgets a stranded record once the operator has dealt with it.
  Future<void> clearStranded(String deviceId);
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

  @override
  Future<List<Uri>> origins() async => _unsupported();

  @override
  Future<Uri?> activeOrigin() async => _unsupported();

  @override
  Future<void> activate(Uri brainOrigin) async => _unsupported();

  @override
  Future<List<StrandedDevice>> strandedDevices() async => const [];

  @override
  Future<void> recordStranded(StrandedDevice device) async => _unsupported();

  @override
  Future<void> clearStranded(String deviceId) async => _unsupported();
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
  static const _originsKey = 'commander.origins.v1';
  static const _strandedKey = 'commander.stranded.v1';
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
    final known = await origins();
    if (!known.contains(credential.brainOrigin)) {
      await _writeIndex([...known, credential.brainOrigin]);
    }
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
    final origin = await _readActiveOrigin();
    if (origin == null) return null;
    return read(origin);
  }

  @override
  Future<List<Uri>> origins() async {
    _requireNativeSecureStore();
    final indexed = <Uri>[
      for (final value in await _readIndex()) ?Uri.tryParse(value),
    ];
    // A device paired before this index existed still has an active origin,
    // and losing it here would hide a credential that is very much present.
    final active = await _readActiveOrigin();
    if (active != null && !indexed.contains(active)) indexed.insert(0, active);
    return List.unmodifiable(indexed);
  }

  @override
  Future<Uri?> activeOrigin() async {
    _requireNativeSecureStore();
    return _readActiveOrigin();
  }

  @override
  Future<void> activate(Uri brainOrigin) async {
    _requireNativeSecureStore();
    if (await read(brainOrigin) == null) {
      throw StateError('No Commander credential is stored for $brainOrigin.');
    }
    await _storage.write(_activeKey, brainOrigin.toString());
  }

  @override
  Future<void> remove(Uri brainOrigin) async {
    _requireNativeSecureStore();
    await _storage.delete(await _credentialKey(brainOrigin));
    final remaining = (await origins())
        .where((origin) => origin != brainOrigin)
        .toList(growable: false);
    await _writeIndex(remaining);
    if (await _readActiveOrigin() != brainOrigin) return;
    // A stored credential with nothing pointing at it would be unreachable,
    // so removing the active pairing promotes the most recent survivor.
    if (remaining.isEmpty) {
      await _storage.delete(_activeKey);
    } else {
      await _storage.write(_activeKey, remaining.last.toString());
    }
  }

  @override
  Future<List<StrandedDevice>> strandedDevices() async {
    _requireNativeSecureStore();
    return List.unmodifiable(await _readStranded());
  }

  @override
  Future<void> recordStranded(StrandedDevice device) async {
    _requireNativeSecureStore();
    final kept =
        (await _readStranded())
            .where((entry) => entry.deviceId != device.deviceId)
            .toList()
          ..add(device);
    await _storage.write(
      _strandedKey,
      jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }

  @override
  Future<void> clearStranded(String deviceId) async {
    _requireNativeSecureStore();
    final kept = (await _readStranded())
        .where((entry) => entry.deviceId != deviceId)
        .toList(growable: false);
    if (kept.isEmpty) {
      await _storage.delete(_strandedKey);
      return;
    }
    await _storage.write(
      _strandedKey,
      jsonEncode([for (final entry in kept) entry.toJson()]),
    );
  }

  /// Never throws: this list exists to tell the operator about a cleanup that
  /// already failed, so a damaged record must not become a second failure.
  Future<List<StrandedDevice>> _readStranded() async {
    final value = await _storage.read(_strandedKey);
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return [for (final entry in decoded) ?StrandedDevice.fromJson(entry)];
    } on FormatException {
      return const [];
    }
  }

  Future<Uri?> _readActiveOrigin() async {
    final value = await _storage.read(_activeKey);
    if (value == null) return null;
    final origin = Uri.tryParse(value);
    if (origin == null) {
      throw const FormatException('Stored Commander origin is invalid.');
    }
    return origin;
  }

  Future<List<String>> _readIndex() async {
    final value = await _storage.read(_originsKey);
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List<dynamic> || decoded.any((item) => item is! String)) {
        throw const FormatException();
      }
      return decoded.cast<String>();
    } on Object {
      throw const FormatException('Stored Commander origin list is invalid.');
    }
  }

  Future<void> _writeIndex(List<Uri> origins) => _storage.write(
    _originsKey,
    jsonEncode([for (final origin in origins) origin.toString()]),
  );

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
