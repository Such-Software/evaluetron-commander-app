import 'package:evaluetron_commander_app/src/app.dart';
import 'package:evaluetron_commander_app/src/data/commander_brain_client.dart';
import 'package:evaluetron_commander_app/src/data/fixture_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:evaluetron_commander_app/src/network/managed_network.dart';
import 'package:evaluetron_commander_app/src/security/local_auth_gate.dart';
import 'package:evaluetron_commander_app/src/security/secure_credential_vault.dart';
import 'package:evaluetron_commander_app/src/state/commander_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_local_auth_gate.dart';
import 'support/memory_pin_store.dart';
import 'support/memory_secure_storage.dart';

final _credential = DeviceCredential(
  brainOrigin: Uri(scheme: 'https', host: 'brain.example.com'),
  deviceId: '12345678-1234-4123-8123-123456789abc',
  deviceLabel: 'Test Commander',
  privateSeed: 'nWGxne_9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A',
  publicKey: '11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo',
  scopes: {'brain:read', 'jobs:create'},
);

CommanderController _controller(BrainClient client, FakeLocalAuthGate gate) =>
    CommanderController(
      client,
      const UnavailableManagedNetworkPlatform(),
      gate,
    );

void main() {
  group('privileged actions require a fresh local authentication', () {
    test(
      'a refused check blocks job submission before the client is called',
      () async {
        final client = _RecordingBrainClient();
        final gate = FakeLocalAuthGate.rejecting();

        await expectLater(
          _controller(client, gate).submitJob(
            const JobRequest(capabilityId: 'llm-grounded', input: 'hello'),
          ),
          throwsA(isA<LocalAuthRequiredException>()),
        );
        expect(gate.requested, [PrivilegedAction.submitJob]);
        expect(client.submitted, isEmpty);
      },
    );

    test(
      'an unenrolled device fails closed rather than skipping the gate',
      () async {
        final client = _RecordingBrainClient();
        final gate = FakeLocalAuthGate.unavailable();

        await expectLater(
          _controller(client, gate).submitJob(
            const JobRequest(capabilityId: 'llm-grounded', input: 'hello'),
          ),
          throwsA(
            isA<LocalAuthRequiredException>()
                .having(
                  (e) => e.outcome,
                  'outcome',
                  LocalAuthOutcome.unavailable,
                )
                .having((e) => e.message, 'message', contains('screen lock')),
          ),
        );
        expect(client.submitted, isEmpty);
      },
    );

    test('pairing a new Brain is gated', () async {
      final client = _RecordingBrainClient();
      final gate = FakeLocalAuthGate.rejecting();

      await expectLater(
        _controller(client, gate).pair(
          PairingRequest(
            enrollmentUri: Uri.parse(
              'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com'
              '&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            ),
          ),
        ),
        throwsA(isA<LocalAuthRequiredException>()),
      );
      expect(gate.requested, [PrivilegedAction.pairBrain]);
      expect(client.paired, isFalse);
    });

    test(
      'self-revocation cannot be triggered without authentication',
      () async {
        final client = _RecordingBrainClient()..paired = true;
        final gate = FakeLocalAuthGate.rejecting();
        final controller = _controller(client, gate);

        await controller.forgetPairing();

        expect(gate.requested, [PrivilegedAction.revokeAccess]);
        // The legitimate operator still has their pairing.
        expect(client.paired, isTrue);
        expect(controller.error, isA<LocalAuthRequiredException>());
      },
    );

    test('an authenticated operator is still allowed through', () async {
      final client = _RecordingBrainClient()..paired = true;
      final gate = FakeLocalAuthGate();

      await _controller(client, gate).forgetPairing();

      expect(gate.requested, contains(PrivilegedAction.revokeAccess));
      expect(client.paired, isFalse);
    });
  });

  group('launch gate on the stored credential', () {
    test(
      'a stored credential is not activated without user presence',
      () async {
        final storage = MemorySecureStorage();
        final vault = PlatformSecureCredentialVault(storage);
        await vault.write(_credential);
        final gate = FakeLocalAuthGate.unavailable();
        final client = CommanderBrainClient(
          vault: vault,
          localAuth: gate,
          pins: MemoryBrainCertificatePinStore(),
        );

        await expectLater(
          client.getProfile(),
          throwsA(isA<LocalAuthRequiredException>()),
        );
        expect(gate.requested, [PrivilegedAction.unlockSession]);
      },
    );

    test(
      'a refused unlock can be retried rather than poisoning the session',
      () async {
        final storage = MemorySecureStorage();
        final vault = PlatformSecureCredentialVault(storage);
        await vault.write(_credential);
        final gate = FakeLocalAuthGate.rejecting();
        final client = CommanderBrainClient(
          vault: vault,
          localAuth: gate,
          pins: MemoryBrainCertificatePinStore(),
        );

        await expectLater(client.getProfile(), throwsA(isA<Exception>()));
        await expectLater(client.getProfile(), throwsA(isA<Exception>()));

        expect(gate.requested, [
          PrivilegedAction.unlockSession,
          PrivilegedAction.unlockSession,
        ]);
      },
    );

    test(
      'fixture mode raises no prompt because it holds no authority',
      () async {
        final vault = PlatformSecureCredentialVault(MemorySecureStorage());
        final gate = FakeLocalAuthGate();
        final client = CommanderBrainClient(
          vault: vault,
          localAuth: gate,
          pins: MemoryBrainCertificatePinStore(),
        );

        expect((await client.getProfile()).mode, ConnectionMode.fixture);
        expect(gate.requested, isEmpty);
      },
    );
  });

  testWidgets('a paired session re-locks when Commander is backgrounded', (
    tester,
  ) async {
    final gate = FakeLocalAuthGate();
    await tester.pumpWidget(
      CommanderApp(client: _PairedBrainClient(), localAuth: gate),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active jobs'), findsOneWidget);

    // The operator hands the unlocked phone over. Coming back demands a fresh
    // proof, and a refused proof keeps the fleet hidden.
    gate.outcome = LocalAuthOutcome.rejected;
    await _background(tester);
    await _foreground(tester);

    expect(find.text('Commander is locked'), findsOneWidget);
    expect(find.text('Active jobs'), findsNothing);
    expect(find.textContaining('cancelled or did not succeed'), findsOneWidget);

    // A retry that fails keeps it locked.
    await tester.tap(find.text('Unlock Commander'));
    await tester.pumpAndSettle();
    expect(find.text('Commander is locked'), findsOneWidget);

    gate.outcome = LocalAuthOutcome.authenticated;
    await tester.tap(find.text('Unlock Commander'));
    await tester.pumpAndSettle();
    expect(find.text('Commander is locked'), findsNothing);
    expect(find.text('Active jobs'), findsOneWidget);
    expect(gate.requested, everyElement(PrivilegedAction.unlockSession));
  });

  testWidgets('an unenrolled device cannot unlock a paired session', (
    tester,
  ) async {
    await tester.pumpWidget(
      CommanderApp(
        client: _PairedBrainClient(),
        localAuth: FakeLocalAuthGate.unavailable(),
      ),
    );
    await tester.pumpAndSettle();

    await _background(tester);
    await _foreground(tester);

    expect(find.text('Commander is locked'), findsOneWidget);
    expect(
      find.textContaining('requires a device screen lock'),
      findsOneWidget,
    );
    await tester.tap(find.text('Unlock Commander'));
    await tester.pumpAndSettle();
    expect(find.text('Commander is locked'), findsOneWidget);
    expect(find.text('Active jobs'), findsNothing);
  });

  testWidgets('fixture sessions are not re-locked', (tester) async {
    await tester.pumpWidget(
      CommanderApp(
        client: FixtureBrainClient(),
        localAuth: FakeLocalAuthGate(),
      ),
    );
    await tester.pumpAndSettle();

    await _background(tester);
    await _foreground(tester);

    expect(find.text('Commander is locked'), findsNothing);
  });
}

/// Drives a real foreground -> background transition. Flutter only accepts
/// adjacent lifecycle states, and it stops producing frames once the app is
/// hidden, so the repaint only lands after [_foreground].
Future<void> _background(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

class _RecordingBrainClient implements BrainClient {
  final FixtureBrainClient _fixture = FixtureBrainClient();
  final submitted = <JobRequest>[];
  bool paired = false;

  @override
  Future<void> forgetPairing() async => paired = false;

  @override
  Future<List<ActivityEvent>> getActivity() => _fixture.getActivity();

  @override
  Future<List<ModelCapability>> getCatalog() => _fixture.getCatalog();

  @override
  Future<List<FleetNode>> getFleet() => _fixture.getFleet();

  @override
  Future<List<CommanderJob>> getJobs() => _fixture.getJobs();

  @override
  Future<BrainOverview> getOverview() => _fixture.getOverview();

  @override
  Future<BrainProfile> getProfile() => _fixture.getProfile();

  @override
  Future<List<BrainSetting>> getSettings() => _fixture.getSettings();

  @override
  Future<BrainProfile> pair(PairingRequest request) async {
    paired = true;
    return _fixture.getProfile();
  }

  @override
  Future<CommanderJob> submitJob(JobRequest request) {
    submitted.add(request);
    return _fixture.submitJob(request);
  }
}

final class _PairedBrainClient extends _RecordingBrainClient {
  @override
  Future<BrainProfile> getProfile() async => BrainProfile(
    name: 'Paired Brain',
    endpoint: Uri.parse('https://brain.example.com'),
    mode: ConnectionMode.paired,
    identity: 'device_paired',
    scopes: const ['brain:read'],
  );
}
