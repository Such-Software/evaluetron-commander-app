import 'package:evaluetron_commander_app/src/app.dart';
import 'package:evaluetron_commander_app/src/data/fixture_brain_client.dart';
import 'package:evaluetron_commander_app/src/domain/brain_client.dart';
import 'package:evaluetron_commander_app/src/network/managed_network.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_local_auth_gate.dart';

void main() {
  testWidgets('phone shell visibly identifies fixture data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CommanderApp(
        client: FixtureBrainClient(),
        localAuth: FakeLocalAuthGate(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Good afternoon'), findsOneWidget);
    expect(find.text('Fixture'), findsWidgets);
    expect(find.text('Active jobs'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('Run a model'), findsOneWidget);
    expect(find.text('Grounded Answer'), findsOneWidget);
  });

  testWidgets('desktop shell supports navigation and local job submission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CommanderApp(
        client: FixtureBrainClient(),
        localAuth: FakeLocalAuthGate(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Create a bounded fixture response.',
    );
    await tester.tap(find.text('Submit job'));
    await tester.pumpAndSettle();

    expect(find.textContaining('queued in the local fixture'), findsOneWidget);
    expect(find.textContaining('No network request was made'), findsOneWidget);
  });

  testWidgets('pairing fails closed when no live transport is installed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CommanderApp(
        client: FixtureBrainClient(),
        localAuth: FakeLocalAuthGate(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fixture mode is active'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Commander enrollment URI'),
      'evaluetron-commander://pair?v=1&brain=https%3A%2F%2Fbrain.example.com&token=evc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.tap(find.text('Pair securely'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no live Brain transport'), findsOneWidget);
  });

  testWidgets('failed paired state can return safely to pairing', (
    tester,
  ) async {
    final client = _RecoveringBrainClient();

    await tester.pumpWidget(
      CommanderApp(client: client, localAuth: FakeLocalAuthGate()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commander could not load'), findsOneWidget);
    await tester.tap(find.text('Remove paired Brain'));
    await tester.pumpAndSettle();

    expect(client.paired, isFalse);
    expect(find.text('Commander could not load'), findsNothing);
    expect(find.text('Fixture'), findsWidgets);
  });

  testWidgets('read-only pairing loads without requesting optional scopes', (
    tester,
  ) async {
    await tester.pumpWidget(
      CommanderApp(
        client: _ReadOnlyBrainClient(),
        localAuth: FakeLocalAuthGate(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commander could not load'), findsNothing);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not authorized to submit jobs'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is FilledButton && widget.onPressed == null,
      ),
      findsOneWidget,
    );
  });

  testWidgets('managed networking is optional and reports missing engine', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CommanderApp(
        client: FixtureBrainClient(),
        localAuth: FakeLocalAuthGate(),
        managedNetwork: const _EngineMissingManagedNetwork(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Managed Nebula'));
    await tester.tap(find.text('Managed Nebula'));
    await tester.pumpAndSettle();

    expect(find.text('Managed network'), findsOneWidget);
    expect(find.text('Use public signed HTTPS'), findsOneWidget);
    expect(find.textContaining('native engine not embedded'), findsWidgets);
    expect(
      find.textContaining('must not silently replace another VPN'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Review system VPN consent'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed,
      isNull,
    );
  });
}

class _RecoveringBrainClient implements BrainClient {
  final FixtureBrainClient _fixture = FixtureBrainClient();
  bool paired = true;

  @override
  Future<void> forgetPairing() async {
    paired = false;
  }

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
  Future<BrainProfile> getProfile() {
    if (paired) throw StateError('Paired Brain authorization was rejected.');
    return _fixture.getProfile();
  }

  @override
  Future<List<BrainSetting>> getSettings() => _fixture.getSettings();

  @override
  Future<BrainProfile> pair(PairingRequest request) => _fixture.pair(request);

  @override
  Future<CommanderJob> submitJob(JobRequest request) =>
      _fixture.submitJob(request);
}

final class _ReadOnlyBrainClient extends _RecoveringBrainClient {
  _ReadOnlyBrainClient() {
    paired = false;
  }

  @override
  Future<BrainProfile> getProfile() async => BrainProfile(
    name: 'Read-only Brain',
    endpoint: Uri.parse('https://brain.example.com'),
    mode: ConnectionMode.paired,
    identity: 'device_read_only',
    scopes: const ['brain:read'],
  );

  @override
  Future<List<ActivityEvent>> getActivity() =>
      throw StateError('activity:read was not granted');

  @override
  Future<List<FleetNode>> getFleet() =>
      throw StateError('fleet:read was not granted');

  @override
  Future<List<CommanderJob>> getJobs() =>
      throw StateError('jobs:read was not granted');

  @override
  Future<List<BrainSetting>> getSettings() =>
      throw StateError('config:read was not granted');
}

final class _EngineMissingManagedNetwork implements ManagedNetworkPlatform {
  const _EngineMissingManagedNetwork();

  @override
  Future<TunnelSnapshot> connect(ManagedNetworkProfile profile) async =>
      const TunnelSnapshot.unavailable();

  @override
  Future<TunnelSnapshot> disconnect() async =>
      const TunnelSnapshot.unavailable();

  @override
  Future<ManagedNetworkCapability> inspect() async =>
      const ManagedNetworkCapability(
        availability: ManagedNetworkAvailability.engineNotInstalled,
        platform: 'android',
        vpnServiceDeclared: true,
        engineVersion: null,
      );

  @override
  Future<TunnelConsentResult> requestConsent() async =>
      TunnelConsentResult.unavailable;

  @override
  Future<TunnelSnapshot> status() async => const TunnelSnapshot.unavailable();
}
