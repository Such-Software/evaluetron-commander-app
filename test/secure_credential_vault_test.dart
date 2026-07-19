import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('credential string representation is always redacted', () {
    final credential = DeviceCredential(
      brainOrigin: Uri.parse('https://brain.example.com'),
      deviceId: 'commander_1',
      secret: 'must-never-appear',
      scopes: const {'brain:read'},
    );

    expect(credential.toString(), isNot(contains('must-never-appear')));
    expect(credential.toString(), contains('redacted'));
  });

  test('unavailable vault fails closed', () async {
    const vault = UnavailableCredentialVault();

    expect(await vault.protection(), VaultProtection.unavailable);
    await expectLater(
      vault.read(Uri.parse('https://brain.example.com')),
      throwsUnsupportedError,
    );
  });
}
