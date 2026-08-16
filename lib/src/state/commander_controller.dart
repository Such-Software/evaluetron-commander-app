import 'package:flutter/foundation.dart';

import '../domain/brain_client.dart';
import '../network/managed_network.dart';
import '../security/local_auth_gate.dart';

/// What an attempt to remove a pairing achieved.
enum PairingRemovalOutcome {
  /// Removed from this device and revoked on the Brain.
  revoked,

  /// Removed from this device only. The device is still active on the Brain
  /// until an operator revokes it from the console there.
  consoleRevocationRequired,

  /// Nothing changed: the Brain could not be reached to revoke this device.
  /// The operator may retry, or remove the credential locally on purpose.
  brainUnreachable,

  /// Nothing changed: local authentication did not succeed.
  refused,

  /// Nothing changed: the removal failed for some other reason.
  failed,
}

/// Outcome of a removal, with the operator-facing reason whenever the removal
/// changed nothing.
typedef PairingRemovalResult = ({
  PairingRemovalOutcome outcome,
  String? message,
});

final class CommanderController extends ChangeNotifier {
  CommanderController(this._client, this._managedNetwork, this._localAuth);

  final BrainClient _client;
  final ManagedNetworkPlatform _managedNetwork;
  final LocalAuthGate _localAuth;

  bool loading = true;
  bool submitting = false;
  bool networkBusy = false;
  Object? error;
  BrainProfile? profile;
  BrainOverview? overview;
  List<ModelCapability> catalog = const [];
  List<CommanderJob> jobs = const [];
  List<FleetNode> fleet = const [];
  List<BrainSetting> settings = const [];
  List<ActivityEvent> activity = const [];
  List<PairedBrain> pairedBrains = const [];

  /// Device rows left active on a Brain after a cleanup this app could not
  /// finish. Only the Brain's console can retire them, and only if it is told
  /// which id, so this stays visible until the operator clears it.
  List<StrandedCommanderDevice> strandedDevices = const [];
  ManagedNetworkCapability managedNetworkCapability =
      const ManagedNetworkCapability.unsupported();
  TunnelSnapshot tunnel = const TunnelSnapshot.unavailable();

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final loadedProfile = await _client.getProfile();
      final scopes = loadedProfile.scopes.toSet();
      final values = await Future.wait<Object>([
        _client.getOverview(),
        _client.getCatalog(),
        scopes.contains('jobs:read')
            ? _client.getJobs()
            : Future.value(const <CommanderJob>[]),
        scopes.contains('fleet:read')
            ? _client.getFleet()
            : Future.value(const <FleetNode>[]),
        scopes.contains('config:read')
            ? _client.getSettings()
            : Future.value(const <BrainSetting>[]),
        scopes.contains('activity:read')
            ? _client.getActivity()
            : Future.value(const <ActivityEvent>[]),
      ]);
      profile = loadedProfile;
      pairedBrains = await _client.pairedBrains();
      strandedDevices = await _client.strandedDevices();
      overview = values[0] as BrainOverview;
      catalog = values[1] as List<ModelCapability>;
      jobs = values[2] as List<CommanderJob>;
      fleet = values[3] as List<FleetNode>;
      settings = values[4] as List<BrainSetting>;
      activity = values[5] as List<ActivityEvent>;
      await refreshManagedNetwork(notify: false);
    } catch (caught) {
      error = caught;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshManagedNetwork({bool notify = true}) async {
    try {
      managedNetworkCapability = await _managedNetwork.inspect();
      tunnel = await _managedNetwork.status();
    } on Object {
      managedNetworkCapability = const ManagedNetworkCapability.unsupported();
      tunnel = const TunnelSnapshot.unavailable();
    }
    if (notify) notifyListeners();
  }

  Future<TunnelConsentResult> requestTunnelConsent() async {
    if (!managedNetworkCapability.canConnect) {
      return TunnelConsentResult.unavailable;
    }
    networkBusy = true;
    notifyListeners();
    try {
      final result = await _managedNetwork.requestConsent();
      tunnel = await _managedNetwork.status();
      return result;
    } finally {
      networkBusy = false;
      notifyListeners();
    }
  }

  Future<TunnelSnapshot> connectManagedNetwork(
    ManagedNetworkProfile profile,
  ) async {
    if (!managedNetworkCapability.canConnect) {
      return const TunnelSnapshot.unavailable();
    }
    networkBusy = true;
    notifyListeners();
    try {
      tunnel = await _managedNetwork.connect(profile);
      return tunnel;
    } finally {
      networkBusy = false;
      notifyListeners();
    }
  }

  Future<TunnelSnapshot> disconnectManagedNetwork() async {
    networkBusy = true;
    notifyListeners();
    try {
      tunnel = await _managedNetwork.disconnect();
      return tunnel;
    } finally {
      networkBusy = false;
      notifyListeners();
    }
  }

  /// Demands a fresh user-presence proof immediately before a privileged
  /// action. Anything other than a successful check throws, so no caller can
  /// proceed by ignoring a return value.
  Future<void> _stepUp(PrivilegedAction action) async {
    final outcome = await _localAuth.authenticate(action);
    if (!localAuthPermits(outcome)) {
      throw localAuthRefusal(action, outcome);
    }
  }

  Future<CommanderJob> submitJob(JobRequest request) async {
    await _stepUp(PrivilegedAction.submitJob);
    submitting = true;
    notifyListeners();
    try {
      final job = await _client.submitJob(request);
      if (profile?.scopes.contains('jobs:read') ?? false) {
        jobs = await _client.getJobs();
      }
      overview = await _client.getOverview();
      return job;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<BrainProfile> pair(PairingRequest request) async {
    await _stepUp(PrivilegedAction.pairBrain);
    final paired = await _client.pair(request);
    await load();
    // Pairing an additional Brain deliberately does not offer to revoke the
    // one already held: holding several is a supported workflow, and a mis-tap
    // must not destroy access the operator never asked to give up. What it
    // must not do is leave that a silent state -- each retained pairing is a
    // live identity on another Brain. Say so once, here, rather than relying
    // on the operator opening the profile dialog to discover it.
    final others = pairedBrains.where((brain) => !brain.active).length;
    pairingNotice = others == 0
        ? null
        : 'This device now commands ${others + 1} Brains. The other $others '
              '${others == 1 ? 'is a live identity' : 'are live identities'} '
              'until removed in Brain profile.';
    notifyListeners();
    return paired;
  }

  /// Set after a pairing that left other pairings in place. Cleared once read
  /// by the surface that shows it.
  String? pairingNotice;

  String? takePairingNotice() {
    final notice = pairingNotice;
    pairingNotice = null;
    return notice;
  }

  /// Commands a different Brain this device is already paired to.
  ///
  /// Gated like every other use of operator authority: it activates a stored
  /// credential that was not in use a moment ago.
  Future<void> selectPairedBrain(Uri origin) async {
    await _stepUp(PrivilegedAction.switchBrain);
    await _client.selectPairedBrain(origin);
    await load();
  }

  /// Revokes and removes this Commander.
  ///
  /// Reports why nothing happened rather than throwing, so the caller can show
  /// it where the operator asked instead of dropping the whole shell into its
  /// failure state over a cancelled prompt or an unreachable Brain.
  /// Clears the local reminder for [deviceId]. Revokes nothing: the operator
  /// is asserting they have already retired it from the Brain's console.
  Future<void> dismissStrandedDevice(String deviceId) async {
    await _client.dismissStrandedDevice(deviceId);
    strandedDevices = await _client.strandedDevices();
    notifyListeners();
  }

  Future<PairingRemovalResult> forgetPairing({bool localOnly = false}) =>
      _removePairing(() => _client.forgetPairing(localOnly: localOnly));

  /// Revokes and removes one paired Brain, which may not be the active one.
  Future<PairingRemovalResult> removePairing(
    Uri origin, {
    bool localOnly = false,
  }) => _removePairing(
    () => _client.removePairedBrain(origin, localOnly: localOnly),
  );

  Future<PairingRemovalResult> _removePairing(
    Future<PairingRemoval> Function() removal,
  ) async {
    try {
      await _stepUp(PrivilegedAction.revokeAccess);
    } on LocalAuthRequiredException catch (refusal) {
      return (outcome: PairingRemovalOutcome.refused, message: refusal.message);
    }
    loading = true;
    error = null;
    notifyListeners();
    final PairingRemoval removed;
    try {
      removed = await removal();
    } on BrainUnreachableException catch (unreachable) {
      // Not a shell-wide failure: the pairing is intact and the operator has a
      // decision to make about it.
      loading = false;
      notifyListeners();
      return (
        outcome: PairingRemovalOutcome.brainUnreachable,
        message: unreachable.message,
      );
    } catch (caught) {
      loading = false;
      notifyListeners();
      return (outcome: PairingRemovalOutcome.failed, message: '$caught');
    }
    await load();
    return (
      outcome: switch (removed) {
        PairingRemoval.revoked => PairingRemovalOutcome.revoked,
        PairingRemoval.consoleRevocationRequired =>
          PairingRemovalOutcome.consoleRevocationRequired,
      },
      message: null,
    );
  }
}
