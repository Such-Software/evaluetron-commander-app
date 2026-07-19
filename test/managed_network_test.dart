import 'package:evaluetron_commander_app/src/network/managed_network.dart';
import 'package:evaluetron_commander_app/src/network/secure_managed_network_vault.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('managed route policy', () {
    test('accepts only single-host routes', () {
      expect(ManagedHostRoute.parse('10.42.0.9/32').cidr, '10.42.0.9/32');
      expect(ManagedHostRoute.parse('fd00:42::9/128').cidr, 'fd00:42::9/128');

      expect(
        () => ManagedHostRoute.parse('10.42.0.0/24'),
        throwsFormatException,
      );
      expect(() => ManagedHostRoute.parse('0.0.0.0/0'), throwsFormatException);
      expect(() => ManagedHostRoute.parse('::/0'), throwsFormatException);
      expect(
        () => ManagedHostRoute.parse('fd00::::9/128'),
        throwsFormatException,
      );
      expect(() => ManagedHostRoute.parse('8.8.8.8/32'), throwsFormatException);
    });

    test('requires signed public HTTPS', () {
      expect(
        () => _profile(publicOrigin: Uri.parse('http://brain.example.com')),
        throwsFormatException,
      );
    });

    test('bounds managed HTTP to the exact overlay host and explicit port', () {
      expect(_profile().managedBrainOrigin.port, 8787);
      expect(
        () => _profile(managedOrigin: Uri.parse('http://10.42.0.10:8787')),
        throwsFormatException,
      );
      expect(
        () => _profile(managedOrigin: Uri.parse('http://10.42.0.9')),
        throwsFormatException,
      );
    });
  });

  group('managed credential', () {
    test('is Commander-specific, bounded, and redacted', () {
      final credential = _credential();

      expect(credential.toString(), isNot(contains('host-private-key')));
      expect(
        decodeManagedCredential(
          encodeManagedCredential(credential),
        ).certificateGroups,
        contains('commander'),
      );
      expect(
        () => _credential(certificateGroups: const {'worker'}),
        throwsFormatException,
      );
      expect(
        () => _credential(config: 'tun:\n  unsafe_routes: 0.0.0.0/0'),
        throwsFormatException,
      );
    });

    test('round trips only through the secure storage boundary', () async {
      final storage = _MemorySecureStorage();
      final vault = SecureManagedNetworkVault(storage);
      final credential = _credential();

      await vault.write(credential);
      final restored = await vault.read(credential.profile.id);

      expect(restored?.profile.brainRoute.cidr, '10.42.0.9/32');
      expect(restored?.hostPrivateKey, 'host-private-key');
      expect(storage.keys.single, startsWith('commander.managed-network.v1.'));
      expect(storage.keys.single, isNot(contains(credential.profile.id)));
    });
  });
}

ManagedNetworkProfile _profile({Uri? publicOrigin, Uri? managedOrigin}) =>
    ManagedNetworkProfile(
      id: 'brain-primary',
      displayName: 'Primary Brain',
      publicBrainOrigin: publicOrigin ?? Uri.parse('https://brain.example.com'),
      managedBrainOrigin: managedOrigin ?? Uri.parse('http://10.42.0.9:8787'),
      brainRoute: ManagedHostRoute.parse('10.42.0.9/32'),
      group: 'commander',
      target: ManagedNetworkTarget.android,
      expiresAt: DateTime.utc(2099),
    );

ManagedNetworkCredential _credential({
  Set<String> certificateGroups = const {'commander'},
  String config = 'tun:\n  routes:\n    - 10.42.0.9/32',
}) => ManagedNetworkCredential(
  profile: _profile(),
  certificateGroups: certificateGroups,
  caCertificate: 'ca-certificate',
  hostCertificate: 'host-certificate',
  hostPrivateKey: 'host-private-key',
  nebulaConfiguration: config,
);

final class _MemorySecureStorage implements SecureStorageAdapter {
  final Map<String, String> _values = {};

  Iterable<String> get keys => _values.keys;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
