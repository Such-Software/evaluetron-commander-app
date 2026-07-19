import 'package:flutter/foundation.dart';

import '../domain/brain_client.dart';

final class CommanderController extends ChangeNotifier {
  CommanderController(this._client);

  final BrainClient _client;

  bool loading = true;
  bool submitting = false;
  Object? error;
  BrainProfile? profile;
  BrainOverview? overview;
  List<ModelCapability> catalog = const [];
  List<CommanderJob> jobs = const [];
  List<FleetNode> fleet = const [];
  List<BrainSetting> settings = const [];
  List<ActivityEvent> activity = const [];

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait<Object>([
        _client.getProfile(),
        _client.getOverview(),
        _client.getCatalog(),
        _client.getJobs(),
        _client.getFleet(),
        _client.getSettings(),
        _client.getActivity(),
      ]);
      profile = values[0] as BrainProfile;
      overview = values[1] as BrainOverview;
      catalog = values[2] as List<ModelCapability>;
      jobs = values[3] as List<CommanderJob>;
      fleet = values[4] as List<FleetNode>;
      settings = values[5] as List<BrainSetting>;
      activity = values[6] as List<ActivityEvent>;
    } catch (caught) {
      error = caught;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<CommanderJob> submitJob(JobRequest request) async {
    submitting = true;
    notifyListeners();
    try {
      final job = await _client.submitJob(request);
      jobs = await _client.getJobs();
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
}
