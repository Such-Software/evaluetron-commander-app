import 'dart:convert';

import 'package:evaluetron_commander_app/src/data/brain_tls_transport.dart';
import 'package:evaluetron_commander_app/src/data/commander_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:evaluetron_commander_app/src/security/brain_certificate_pin.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_brain_tls_transport.dart';
import 'support/fake_local_auth_gate.dart';
import 'support/memory_pin_store.dart';
import 'support/memory_secure_storage.dart';

final _origin = Uri.parse('https://brain.example.com');
const _deviceId = '12345678-1234-4123-8123-123456789abc';
const _enrollment =
    'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com'
    '&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

BrainResponseBuilder _brain() =>
    (method, path, body) => switch (path) {
      '/api/commander/v1/pair' => jsonResponse({
        'ok': true,
        'apiVersion': 1,
        'device': {
          'id': _deviceId,
          'label': 'Test Commander',
          'scopes': ['brain:read', 'jobs:create'],
        },
      }),
      '/api/commander/v1/profile' => jsonResponse({
        'ok': true,
        'apiVersion': 1,
        'brain': {'name': 'Test Brain'},
        'device': {
          'id': _deviceId,
          'scopes': ['brain:read', 'jobs:create'],
        },
      }),
      '/api/commander/v1/overview' => jsonResponse({
        'ok': true,
        'fleet': {'readyWorkers': 2},
        'jobs': {'active': 1},
      }),
      '/api/commander/v1/revoke' => jsonResponse({'ok': true}),
      _ => jsonResponse({'ok': false}, statusCode: 404),
    };

typedef BrainResponseBuilder =
    BrainResponse Function(String method, String path, List<int> body);

({
  CommanderBrainClient client,
  FakeBrainTlsTransport transport,
  MemoryBrainCertificatePinStore pins,
})
_client(ObservedCertificate peer) {
  final transport = FakeBrainTlsTransport(peer: peer, respond: _brain());
  final pins = MemoryBrainCertificatePinStore();
  return (
    client: CommanderBrainClient(
      vault: PlatformSecureCredentialVault(MemorySecureStorage()),
      localAuth: FakeLocalAuthGate(),
      pins: pins,
      transport: transport,
    ),
    transport: transport,
    pins: pins,
  );
}

Future<
  ({
    CommanderBrainClient client,
    FakeBrainTlsTransport transport,
    MemoryBrainCertificatePinStore pins,
  })
>
_paired(ObservedCertificate peer) async {
  final setup = _client(peer);
  await setup.client.pair(
    PairingRequest(enrollmentUri: Uri.parse(_enrollment)),
  );
  return setup;
}

void main() {
  group('pin policy', () {
    test('adopts a renewal that keeps the same subject and issuer', () async {
      final first = await fakeCertificate(name: 'first');
      final renewed = await fakeCertificate(name: 'renewed');
      final pin = BrainCertificatePin.of(first);

      expect(pin.allowsRotationTo(renewed), isTrue);
      final rotated = pin.rotatedWith(renewed);
      expect(rotated.certificates.first.fingerprint, renewed.fingerprint);
      expect(rotated.contains(first.fingerprint), isTrue);
      expect(rotated.trustBundle, contains(first.pem));
      expect(rotated.trustBundle, contains(renewed.pem));
    });

    test('refuses a certificate from a different issuer', () async {
      final pin = BrainCertificatePin.of(await fakeCertificate(name: 'first'));

      expect(
        pin.allowsRotationTo(
          await fakeCertificate(name: 'mitm', issuer: 'CN=Corp MDM Root'),
        ),
        isFalse,
      );
      expect(
        pin.allowsRotationTo(
          await fakeCertificate(name: 'other', subject: 'CN=evil.example.com'),
        ),
        isFalse,
      );
    });

    test('retains a bounded rotation window', () async {
      var pin = BrainCertificatePin.of(await fakeCertificate(name: 'c0'));
      for (var index = 1; index < 6; index++) {
        pin = pin.rotatedWith(await fakeCertificate(name: 'c$index'));
      }

      expect(pin.certificates, hasLength(BrainCertificatePin.retained));
      expect(pin.certificates.first.pem, contains('c5'));
      expect(
        pin.contains((await fakeCertificate(name: 'c0')).fingerprint),
        isFalse,
      );
    });

    test('survives a serialization round trip', () async {
      final pin = BrainCertificatePin.of(
        await fakeCertificate(name: 'first'),
      ).rotatedWith(await fakeCertificate(name: 'second'));

      final decoded = BrainCertificatePin.decode(pin.encode())!;
      expect(decoded.subject, pin.subject);
      expect(decoded.issuer, pin.issuer);
      expect(decoded.trustBundle, pin.trustBundle);
    });

    test('a corrupt record decodes to nothing instead of throwing', () {
      expect(BrainCertificatePin.decode('not json'), isNull);
      expect(BrainCertificatePin.decode('{"version":2}'), isNull);
      expect(
        BrainCertificatePin.decode(
          '{"version":1,"subject":"a","issuer":"b",'
          '"certificates":[]}',
        ),
        isNull,
      );
    });
  });

  group('pinned transport', () {
    test('pairing records the certificate that answered', () async {
      final peer = await fakeCertificate(name: 'first');
      final setup = await _paired(peer);

      final pin = await setup.pins.read(_origin);
      expect(pin, isNotNull);
      expect(pin!.contains(peer.fingerprint), isTrue);
      // Even the enrollment token went out over a pinned handshake.
      expect(setup.transport.bundles, everyElement(isNotNull));
      expect(setup.transport.probes, 1);
    });

    test('later requests present only the pinned anchor', () async {
      final peer = await fakeCertificate(name: 'first');
      final setup = await _paired(peer);
      setup.transport.bundles.clear();

      await setup.client.getOverview();

      expect(setup.transport.bundles.single, contains(peer.pem));
    });

    test('a renewal is adopted without operator involvement', () async {
      final setup = await _paired(await fakeCertificate(name: 'first'));
      final renewed = await fakeCertificate(name: 'renewed');
      setup.transport.peer = renewed;

      final overview = await setup.client.getOverview();

      expect(overview.readyNodes, 2);
      expect(
        (await setup.pins.read(_origin))!.contains(renewed.fingerprint),
        isTrue,
      );
    });

    test('an impostor is refused and receives no signed request', () async {
      final first = await fakeCertificate(name: 'first');
      final setup = await _paired(first);
      setup.transport
        ..peer = await fakeCertificate(name: 'mitm', issuer: 'CN=Corp MDM Root')
        ..delivered.clear();

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>()
              .having((e) => e.certificateChanged, 'certificateChanged', isTrue)
              .having((e) => e.message, 'message', contains('Corp MDM Root'))
              .having(
                (e) => e.message,
                'message',
                contains('pairing has been kept'),
              ),
        ),
      );

      // Nothing was handed to the impostor, and the pin was not rewritten.
      expect(setup.transport.delivered, isEmpty);
      expect(
        (await setup.pins.read(_origin))!.contains(first.fingerprint),
        isTrue,
      );
      expect((await setup.pins.read(_origin))!.certificates, hasLength(1));
    });

    test('a peer that no longer validates publicly is refused', () async {
      final setup = await _paired(await fakeCertificate(name: 'first'));
      setup.transport
        ..peer = await fakeCertificate(name: 'unknown')
        ..publiclyValid = false;

      await expectLater(
        setup.client.getOverview(),
        throwsA(
          isA<CommanderTransportException>().having(
            (e) => e.certificateChanged,
            'certificateChanged',
            isTrue,
          ),
        ),
      );
    });

    test('revocation clears the pin so re-pairing is possible', () async {
      final setup = await _paired(await fakeCertificate(name: 'first'));

      await setup.client.forgetPairing();

      expect(await setup.pins.read(_origin), isNull);
    });

    test('a changed certificate never strands the operator', () async {
      final setup = await _paired(await fakeCertificate(name: 'first'));
      setup.transport.peer = await fakeCertificate(
        name: 'mitm',
        issuer: 'CN=Corp MDM Root',
      );

      // Revocation cannot reach the Brain, but must still complete locally.
      await setup.client.forgetPairing();

      expect(await setup.pins.read(_origin), isNull);
      expect((await setup.client.getProfile()).mode, ConnectionMode.fixture);
    });
  });

  test('the pin store round-trips through the secure store', () async {
    final storage = MemorySecureStorage();
    final store = SecureBrainCertificatePinStore(storage);
    final pin = BrainCertificatePin.of(await fakeCertificate(name: 'first'));

    await store.write(_origin, pin);
    expect((await store.read(_origin))!.trustBundle, pin.trustBundle);
    expect(storage.values.keys.single, startsWith('commander.brain-pin.v1.'));
    expect(
      jsonDecode(storage.values.values.single),
      isA<Map<String, dynamic>>(),
    );

    await store.remove(_origin);
    expect(await store.read(_origin), isNull);
  });
}
