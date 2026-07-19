import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemorySecureStorage implements SecureStorageAdapter {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  final credential = DeviceCredential(
    brainOrigin: Uri(scheme: 'https', host: 'brain.example.com'),
    deviceId: '12345678-1234-4123-8123-123456789abc',
    deviceLabel: 'Test Commander',
    privateSeed: 'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A',
    publicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
    scopes: {'brain:read', 'fleet:read'},
  );

  test('credential string representation is always redacted', () {
    expect(credential.toString(), isNot(contains(credential.privateSeed)));
    expect(credential.toString(), contains('redacted'));
  });

  test('platform vault round-trips a validated active credential', () async {
    final storage = MemorySecureStorage();
    final vault = PlatformSecureCredentialVault(storage);

    expect(await vault.protection(), VaultProtection.operatingSystem);
    await vault.write(credential);

    expect((await vault.readActive())?.deviceId, credential.deviceId);
    expect(storage.values.values.join(), contains(credential.privateSeed));
    await vault.remove(credential.brainOrigin);
    expect(await vault.readActive(), isNull);
  });

  test('unavailable vault fails closed', () async {
    const vault = UnavailableCredentialVault();

    expect(await vault.protection(), VaultProtection.unavailable);
    await expectLater(
      vault.read(credential.brainOrigin),
      throwsUnsupportedError,
    );
    await expectLater(vault.readActive(), throwsUnsupportedError);
  });
}
