import 'package:evaluetron_commander_app/src/app.dart';
import 'package:evaluetron_commander_app/src/data/brain_tls_transport.dart';
import 'package:evaluetron_commander_app/src/data/commander_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:evaluetron_commander_app/src/security/local_auth_gate.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_brain_tls_transport.dart';
import 'support/fake_local_auth_gate.dart';
import 'support/memory_pin_store.dart';
import 'support/memory_secure_storage.dart';

const _firstDevice = '12345678-1234-4123-8123-123456789abc';
const _secondDevice = '87654321-4321-4321-9abc-987654321abc';
final _firstOrigin = Uri.parse('https://brain-a.example.com');
final _secondOrigin = Uri.parse('https://brain-b.example.com');

String _enrollment(Uri origin) =>
    'evaluetron-commander://pair?v=1&brain=${Uri.encodeComponent('$origin')}'
    '&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Answers as the Brain that issued [device], for every path this app calls.
BrainResponse Function(String, String, List<int>) _brain(
  String device, {
  String label = 'Operator phone',
  int revokeStatus = 200,
}) {
  return (method, path, body) => switch (path) {
    '/api/commander/v1/pair' => jsonResponse({
      'ok': true,
      'apiVersion': 1,
      'device': {
        'id': device,
        'label': label,
        'scopes': ['brain:read'],
      },
    }),
    '/api/commander/v1/profile' => jsonResponse({
      'ok': true,
      'apiVersion': 1,
      'brain': {'name': 'Brain $label'},
      'device': {
        'id': device,
        'scopes': ['brain:read'],
      },
    }),
    '/api/commander/v1/revoke' => jsonResponse({
      'ok': revokeStatus == 200,
    }, statusCode: revokeStatus),
    '/api/commander/v1/overview' => jsonResponse({
      'ok': true,
      'fleet': {'readyWorkers': 0},
      'jobs': {'active': 0},
    }),
    '/api/commander/v1/catalog' => jsonResponse({
      'ok': true,
      'catalog': {'generators': <Object>[]},
    }),
    _ => jsonResponse({'ok': false}, statusCode: 404),
  };
}

typedef _Setup = ({
  CommanderBrainClient client,
  FakeBrainTlsTransport transport,
  FakeLocalAuthGate gate,
  SecureCredentialVault vault,
});

Future<_Setup> _client() async {
  final transport = FakeBrainTlsTransport(
    peer: await fakeCertificate(name: 'shared'),
    respond: _brain(_firstDevice),
  );
  final gate = FakeLocalAuthGate();
  final vault = PlatformSecureCredentialVault(MemorySecureStorage());
  return (
    client: CommanderBrainClient(
      vault: vault,
      localAuth: gate,
      pins: MemoryBrainCertificatePinStore(),
      transport: transport,
    ),
    transport: transport,
    gate: gate,
    vault: vault,
  );
}

/// Pairs [_firstOrigin] and then [_secondOrigin], as an operator who added a
/// second Brain without touching the first.
Future<_Setup> _pairedTwice() async {
  final setup = await _client();
  await setup.client.pair(
    PairingRequest(enrollmentUri: Uri.parse(_enrollment(_firstOrigin))),
  );
  setup.transport.respond = _brain(_secondDevice, label: 'Lab Brain');
  await setup.client.pair(
    PairingRequest(enrollmentUri: Uri.parse(_enrollment(_secondOrigin))),
  );
  return setup;
}

List<Uri> _revoked(FakeBrainTlsTransport transport) => [
  for (final call in transport.delivered)
    if (call.path == '/api/commander/v1/revoke') call.url.replace(path: ''),
];

void main() {
  group('a second pairing is visible and removable', () {
    test('pairing another Brain keeps and lists both credentials', () async {
      final setup = await _pairedTwice();

      final brains = await setup.client.pairedBrains();

      expect(brains.map((brain) => brain.origin), [
        _secondOrigin,
        _firstOrigin,
      ]);
      expect(brains.first.active, isTrue);
      expect(brains.first.deviceId, _secondDevice);
      expect(brains.last.active, isFalse);
      expect(brains.last.deviceId, _firstDevice);
      // The Brain that is no longer in use was not revoked behind the
      // operator's back either.
      expect(_revoked(setup.transport), isEmpty);
    });

    test('the operator can switch back to the earlier Brain', () async {
      final setup = await _pairedTwice();
      setup.transport.respond = _brain(_firstDevice);

      final profile = await setup.client.selectPairedBrain(_firstOrigin);

      expect(profile.identity, _firstDevice);
      expect(profile.endpoint, _firstOrigin);
      expect(await setup.vault.activeOrigin(), _firstOrigin);
      expect((await setup.client.pairedBrains()).first.origin, _firstOrigin);
    });

    test('removing a pairing revokes it on its own Brain', () async {
      final setup = await _pairedTwice();

      await setup.client.removePairedBrain(_firstOrigin);

      expect(_revoked(setup.transport), [_firstOrigin]);
      expect((await setup.client.pairedBrains()).map((brain) => brain.origin), [
        _secondOrigin,
      ]);
      expect(await setup.vault.read(_firstOrigin), isNull);
      expect(await setup.vault.read(_secondOrigin), isNotNull);
    });

    test('removing the Brain in use falls back to the other one', () async {
      final setup = await _pairedTwice();

      await setup.client.forgetPairing();

      expect(_revoked(setup.transport), [_secondOrigin]);
      expect(await setup.vault.activeOrigin(), _firstOrigin);
      setup.transport.respond = _brain(_firstDevice);
      expect((await setup.client.getProfile()).identity, _firstDevice);
    });

    test('pairing the same Brain again retires the key it replaces', () async {
      final setup = await _client();
      await setup.client.pair(
        PairingRequest(enrollmentUri: Uri.parse(_enrollment(_firstOrigin))),
      );
      setup.transport.respond = _brain(_secondDevice);

      await setup.client.pair(
        PairingRequest(enrollmentUri: Uri.parse(_enrollment(_firstOrigin))),
      );

      // The device row the replaced key belonged to would otherwise stay
      // active on the Brain with nobody holding its key.
      expect(_revoked(setup.transport), [_firstOrigin]);
      final brains = await setup.client.pairedBrains();
      expect(brains, hasLength(1));
      expect(brains.single.deviceId, _secondDevice);
    });
  });

  group('a pairing that cannot be finished leaves nothing behind', () {
    /// Pairs, then fails the profile check that follows it. The Brain has
    /// already committed the device row and spent the enrollment by then.
    Future<_Setup> halfPaired({required bool revokeWorks}) async {
      final setup = await _client();
      setup.transport.respond = (method, path, body) => switch (path) {
        '/api/commander/v1/pair' => jsonResponse({
          'ok': true,
          'apiVersion': 1,
          'device': {
            'id': _firstDevice,
            'label': 'Operator phone',
            'scopes': ['brain:read'],
          },
        }),
        '/api/commander/v1/revoke' => jsonResponse({
          'ok': revokeWorks,
        }, statusCode: revokeWorks ? 200 : 503),
        _ => jsonResponse({
          'ok': false,
          'error': 'profile unavailable',
        }, statusCode: 500),
      };
      return setup;
    }

    test('the device it created is revoked again', () async {
      final setup = await halfPaired(revokeWorks: true);

      await expectLater(
        setup.client.pair(
          PairingRequest(enrollmentUri: Uri.parse(_enrollment(_firstOrigin))),
        ),
        throwsA(
          isA<CommanderTransportException>()
              .having(
                (e) => e.message,
                'message',
                contains('profile unavailable'),
              )
              .having((e) => e.message, 'message', contains('revoked again')),
        ),
      );

      expect(_revoked(setup.transport), [_firstOrigin]);
      expect(await setup.client.pairedBrains(), isEmpty);
      expect(await setup.vault.read(_firstOrigin), isNull);
    });

    test('a failed cleanup names the device id to revoke by hand', () async {
      final setup = await halfPaired(revokeWorks: false);

      await expectLater(
        setup.client.pair(
          PairingRequest(enrollmentUri: Uri.parse(_enrollment(_firstOrigin))),
        ),
        throwsA(
          isA<CommanderTransportException>()
              .having((e) => e.message, 'message', contains(_firstDevice))
              .having(
                (e) => e.message,
                'message',
                contains('operator console'),
              ),
        ),
      );

      expect(_revoked(setup.transport), [_firstOrigin], reason: 'it was tried');
      expect(await setup.vault.read(_firstOrigin), isNull);
    });
  });

  group('a Brain that cannot be reached still lets the device be cleared', () {
    test(
      'an unreachable Brain keeps the credential rather than erroring',
      () async {
        final setup = await _pairedTwice();
        setup.transport.respond = (method, path, body) =>
            throw const BrainNetworkException('Connection refused');

        await expectLater(
          setup.client.removePairedBrain(_secondOrigin),
          throwsA(
            isA<BrainUnreachableException>()
                .having((e) => e.origin, 'origin', _secondOrigin)
                .having((e) => e.deviceId, 'deviceId', _secondDevice)
                .having((e) => e.message, 'message', contains(_secondDevice))
                .having(
                  (e) => e.message,
                  'message',
                  contains('Connection refused'),
                ),
          ),
        );
        // Nothing was removed, so retrying later is still the better option.
        expect(await setup.vault.read(_secondOrigin), isNotNull);
        expect(await setup.vault.activeOrigin(), _secondOrigin);
      },
    );

    test('a local-only removal clears the device and says so', () async {
      final setup = await _pairedTwice();
      setup.transport.respond = (method, path, body) =>
          throw const BrainNetworkException('Connection refused');

      final removal = await setup.client.removePairedBrain(
        _secondOrigin,
        localOnly: true,
      );

      expect(removal, PairingRemoval.consoleRevocationRequired);
      expect(await setup.vault.read(_secondOrigin), isNull);
      expect(await setup.vault.activeOrigin(), _firstOrigin);
    });

    test('a local-only removal does not depend on the unlock', () async {
      final setup = await _pairedTwice();
      // A fresh process, and an operator who cannot pass the check at all.
      setup.gate.outcome = LocalAuthOutcome.rejected;
      final restarted = CommanderBrainClient(
        vault: setup.vault,
        localAuth: setup.gate,
        pins: MemoryBrainCertificatePinStore(),
        transport: setup.transport,
      );

      // Signing a revocation still needs the credential, so it is still gated.
      await expectLater(
        restarted.removePairedBrain(_firstOrigin),
        throwsA(isA<LocalAuthRequiredException>()),
      );
      expect(await setup.vault.read(_firstOrigin), isNotNull);

      // Deleting a credential this device cannot use is not.
      expect(
        await restarted.removePairedBrain(_firstOrigin, localOnly: true),
        PairingRemoval.consoleRevocationRequired,
      );
      expect(await setup.vault.read(_firstOrigin), isNull);
      expect(_revoked(setup.transport), isEmpty);
    });

    test('a revocation that could succeed is never skipped', () async {
      final setup = await _pairedTwice();

      expect(
        await setup.client.removePairedBrain(_secondOrigin),
        PairingRemoval.revoked,
      );
      expect(_revoked(setup.transport), [_secondOrigin]);
    });

    test('a Brain that already revoked us needs no console visit', () async {
      final setup = await _pairedTwice();
      setup.transport.respond = _brain(_secondDevice, revokeStatus: 401);

      expect(
        await setup.client.removePairedBrain(_secondOrigin),
        PairingRemoval.revoked,
      );
      expect(await setup.vault.read(_secondOrigin), isNull);
    });
  });

  testWidgets('the profile dialog lists, switches and removes pairings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = await _pairedTwice();

    await tester.pumpWidget(
      CommanderApp(client: setup.client, localAuth: setup.gate),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();

    expect(find.text(_firstOrigin.host), findsOneWidget);
    expect(find.text(_secondOrigin.host), findsOneWidget);
    expect(find.textContaining(_firstDevice), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    // Switching demands its own presence proof and then commands the other
    // Brain.
    setup.transport.respond = _brain(_firstDevice);
    await tester.tap(find.byTooltip('Command ${_firstOrigin.host}'));
    await tester.pumpAndSettle();

    expect(setup.gate.requested, contains(PrivilegedAction.switchBrain));
    expect(await setup.vault.activeOrigin(), _firstOrigin);

    // Removing the one that is no longer in use clears it from the device.
    await tester.tap(find.byTooltip('Remove ${_secondOrigin.host}'));
    await tester.pumpAndSettle();

    expect(setup.gate.requested, contains(PrivilegedAction.revokeAccess));
    expect(_revoked(setup.transport), [_secondOrigin]);
    expect(await setup.vault.read(_secondOrigin), isNull);
    expect(find.text(_secondOrigin.host), findsNothing);
  });

  testWidgets('an unreachable Brain offers a clearly labelled local removal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = await _pairedTwice();

    await tester.pumpWidget(
      CommanderApp(client: setup.client, localAuth: setup.gate),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();

    // The revoke never lands. Everything else about this Brain still works,
    // which is what keeps the shell readable while the choice is made.
    final reachable = _brain(_secondDevice);
    setup.transport.respond = (method, path, body) =>
        path == '/api/commander/v1/revoke'
        ? throw const BrainNetworkException('Connection refused')
        : reachable(method, path, body);

    await tester.tap(find.byTooltip('Remove ${_firstOrigin.host}'));
    await tester.pumpAndSettle();

    expect(find.text('Remove without revoking?'), findsOneWidget);
    expect(find.textContaining(_firstDevice), findsWidgets);
    expect(
      find.textContaining('revokes it from that Brain\'s console'),
      findsOneWidget,
    );

    // Declining changes nothing at all.
    await tester.tap(find.text('Keep the pairing'));
    await tester.pumpAndSettle();
    expect(await setup.vault.read(_firstOrigin), isNotNull);

    await tester.tap(find.byTooltip('Remove ${_firstOrigin.host}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from this device only'));
    await tester.pumpAndSettle();

    expect(await setup.vault.read(_firstOrigin), isNull);
    expect(await setup.vault.read(_secondOrigin), isNotNull);
    expect(
      find.textContaining('is still active on ${_firstOrigin.host}'),
      findsOneWidget,
    );
  });

  testWidgets('a refused presence proof leaves both pairings alone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = await _pairedTwice();

    await tester.pumpWidget(
      CommanderApp(client: setup.client, localAuth: setup.gate),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();

    setup.gate.outcome = LocalAuthOutcome.rejected;
    await tester.tap(find.byTooltip('Remove ${_firstOrigin.host}'));
    await tester.pumpAndSettle();

    expect(find.textContaining('requires device authentication'), findsWidgets);
    expect(_revoked(setup.transport), isEmpty);
    expect(await setup.vault.read(_firstOrigin), isNotNull);
    expect(await setup.vault.read(_secondOrigin), isNotNull);
  });
}
