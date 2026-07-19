import 'package:flutter/foundation.dart';

import '../domain/brain_client.dart';
import '../network/managed_network.dart';

final class CommanderController extends ChangeNotifier {
  CommanderController(this._client, this._managedNetwork);

  final BrainClient _client;
  final ManagedNetworkPlatform _managedNetwork;

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

  Future<CommanderJob> submitJob(JobRequest request) async {
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
    final paired = await _client.pair(request);
    await load();
    return paired;
  }

  Future<void> forgetPairing() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _client.forgetPairing();
    } catch (caught) {
      error = caught;
      loading = false;
      notifyListeners();
      return;
    }
    await load();
  }
}
