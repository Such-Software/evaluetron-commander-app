import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';

/// In-memory stand-in for the operating-system secure store.
final class MemorySecureStorage implements SecureStorageAdapter {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
