import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_secure_storage.dart';

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

  final second = DeviceCredential(
    brainOrigin: Uri(scheme: 'https', host: 'brain-two.example.com'),
    deviceId: '87654321-4321-4321-9abc-987654321abc',
    deviceLabel: 'Second Commander',
    privateSeed: 'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A',
    publicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
    scopes: {'brain:read'},
  );

  test('pairing a second Brain does not orphan the first', () async {
    final vault = PlatformSecureCredentialVault(MemorySecureStorage());
    await vault.write(credential);
    await vault.write(second);

    expect(await vault.origins(), [credential.brainOrigin, second.brainOrigin]);
    expect(await vault.activeOrigin(), second.brainOrigin);
    // The first credential is still there, which is exactly why the operator
    // has to be able to see it.
    expect((await vault.read(credential.brainOrigin))?.deviceId, credential.deviceId);
  });

  test('the active credential can be switched between pairings', () async {
    final vault = PlatformSecureCredentialVault(MemorySecureStorage());
    await vault.write(credential);
    await vault.write(second);

    await vault.activate(credential.brainOrigin);

    expect((await vault.readActive())?.deviceId, credential.deviceId);
    expect(await vault.activeOrigin(), credential.brainOrigin);
    await expectLater(
      vault.activate(Uri(scheme: 'https', host: 'unpaired.example.com')),
      throwsStateError,
    );
  });

  test('removing the active pairing promotes a survivor', () async {
    final vault = PlatformSecureCredentialVault(MemorySecureStorage());
    await vault.write(credential);
    await vault.write(second);

    await vault.remove(second.brainOrigin);

    expect(await vault.origins(), [credential.brainOrigin]);
    expect((await vault.readActive())?.deviceId, credential.deviceId);
    expect(await vault.read(second.brainOrigin), isNull);

    await vault.remove(credential.brainOrigin);
    expect(await vault.origins(), isEmpty);
    expect(await vault.activeOrigin(), isNull);
  });

  test('a pairing stored before the index existed is still listed', () async {
    final storage = MemorySecureStorage();
    final vault = PlatformSecureCredentialVault(storage);
    await vault.write(credential);
    storage.values.remove('commander.origins.v1');

    expect(await vault.origins(), [credential.brainOrigin]);
  });

  test('unavailable vault fails closed', () async {
    const vault = UnavailableCredentialVault();

    expect(await vault.protection(), VaultProtection.unavailable);
    await expectLater(
      vault.read(credential.brainOrigin),
      throwsUnsupportedError,
    );
    await expectLater(vault.readActive(), throwsUnsupportedError);
    await expectLater(vault.origins(), throwsUnsupportedError);
    await expectLater(vault.activeOrigin(), throwsUnsupportedError);
    await expectLater(
      vault.activate(credential.brainOrigin),
      throwsUnsupportedError,
    );
  });
}
