import '../domain/brain_client.dart';

final class FixtureBrainClient implements BrainClient {
  final List<CommanderJob> _jobs = [
    CommanderJob(
      id: 'job_7XM4',
      modelName: 'Grounded Answer',
      state: JobState.running,
      progress: .64,
      createdAt: DateTime.utc(2026, 7, 19, 17, 4),
      owner: 'Commander fixture',
    ),
    CommanderJob(
      id: 'job_7XK8',
      modelName: 'Studio Image',
      state: JobState.succeeded,
      progress: 1,
      createdAt: DateTime.utc(2026, 7, 19, 16, 42),
      owner: 'Commander fixture',
    ),
    CommanderJob(
      id: 'job_7XH2',
      modelName: 'Voice Draft',
      state: JobState.succeeded,
      progress: 1,
      createdAt: DateTime.utc(2026, 7, 19, 15, 18),
      owner: 'Commander fixture',
    ),
  ];

  Future<T> _answer<T>(T value) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return value;
  }

  /// Fixture mode holds no credential, so there is nothing to list, switch
  /// between, or remove, and nothing is left behind on any Brain.
  @override
  Future<PairingRemoval> forgetPairing({bool localOnly = false}) async =>
      PairingRemoval.revoked;

  @override
  Future<List<PairedBrain>> pairedBrains() async => const [];

  @override
  Future<List<StrandedCommanderDevice>> strandedDevices() async => const [];

  @override
  Future<void> dismissStrandedDevice(String deviceId) async {}

  @override
  Future<PairingRemoval> removePairedBrain(
    Uri origin, {
    bool localOnly = false,
  }) async => PairingRemoval.revoked;

  @override
  Future<BrainProfile> selectPairedBrain(Uri origin) {
    throw UnsupportedError(
      'This build has no live Brain transport. No pairing was selected.',
    );
  }

  @override
  Future<BrainProfile> getProfile() => _answer(
    BrainProfile(
      name: 'Evaluetron fixture brain',
      endpoint: Uri.parse('https://fixture.invalid'),
      mode: ConnectionMode.fixture,
      identity: 'device_fixture_commander',
      scopes: const [
        'brain:read',
        'jobs:create',
        'jobs:read',
        'fleet:read',
        'config:read',
      ],
    ),
  );

  @override
  Future<BrainOverview> getOverview() => _answer(
    const BrainOverview(
      activeJobs: 1,
      readyNodes: 3,
      billing: 'Fixture',
      successRate: .986,
    ),
  );

  @override
  Future<List<ModelCapability>> getCatalog() => _answer(const [
    ModelCapability(
      id: 'llm-grounded',
      name: 'Grounded Answer',
      kind: 'Text',
      summary: 'Structured language generation for research and operations.',
      creditCost: 2,
      inputLabel: 'Request',
      inputHint: 'Summarize the incident timeline and identify open questions…',
    ),
    ModelCapability(
      id: 'image-studio',
      name: 'Studio Image',
      kind: 'Image',
      summary: 'Generate a production image from a bounded prompt.',
      creditCost: 8,
      inputLabel: 'Prompt',
      inputHint: 'A quiet orbital lab above the Atlantic, editorial lighting…',
    ),
    ModelCapability(
      id: 'tts-voice',
      name: 'Voice Draft',
      kind: 'Audio',
      summary: 'Create a review-quality voice render from supplied text.',
      creditCost: 3,
      inputLabel: 'Script',
      inputHint: 'Paste the words to render…',
    ),
  ]);

  @override
  Future<List<CommanderJob>> getJobs() => _answer(List.unmodifiable(_jobs));

  @override
  Future<List<FleetNode>> getFleet() => _answer([
    FleetNode(
      id: 'node_studio',
      name: 'Studio GPU',
      platform: 'Linux · RTX',
      state: NodeState.ready,
      capabilities: const ['Image', 'Text'],
      lastSeen: DateTime.utc(2026, 7, 19, 17, 8),
    ),
    FleetNode(
      id: 'node_s22',
      name: 'Phone S22',
      platform: 'Android · mobile',
      state: NodeState.offline,
      capabilities: const ['Text'],
      lastSeen: DateTime.utc(2026, 7, 19, 13, 21),
    ),
    FleetNode(
      id: 'node_pi',
      name: 'Workshop Pi',
      platform: 'Linux · ARM64',
      state: NodeState.busy,
      capabilities: const ['Audio'],
      lastSeen: DateTime.utc(2026, 7, 19, 17, 7),
    ),
  ]);

  @override
  Future<List<BrainSetting>> getSettings() => _answer(const [
    BrainSetting(
      group: 'Security',
      name: 'Device authentication',
      value: 'Scoped, revocable credentials',
      sensitivity: 'Enforced',
    ),
    BrainSetting(
      group: 'Security',
      name: 'Shared fleet token',
      value: 'Disabled',
      sensitivity: 'Enforced',
    ),
    BrainSetting(
      group: 'Jobs',
      name: 'Global active limit',
      value: '1,000',
      sensitivity: 'Operator',
    ),
    BrainSetting(
      group: 'Billing',
      name: 'Settlement',
      value: 'Enabled',
      sensitivity: 'Sensitive · redacted',
    ),
  ]);

  @override
  Future<List<ActivityEvent>> getActivity() => _answer([
    ActivityEvent(
      id: 'evt_1',
      action: 'Job completed',
      actor: 'Studio GPU',
      occurredAt: DateTime.utc(2026, 7, 19, 16, 44),
      detail: 'job_7XK8 · Studio Image',
    ),
    ActivityEvent(
      id: 'evt_2',
      action: 'Credential revoked',
      actor: 'operator@example.invalid',
      occurredAt: DateTime.utc(2026, 7, 19, 14, 2),
      detail: 'Legacy fleet credential',
    ),
    ActivityEvent(
      id: 'evt_3',
      action: 'Configuration viewed',
      actor: 'Commander fixture',
      occurredAt: DateTime.utc(2026, 7, 19, 13, 46),
      detail: 'Read-only settings scope',
    ),
  ]);

  @override
  Future<CommanderJob> submitJob(JobRequest request) async {
    final catalog = await getCatalog();
    final model = catalog.firstWhere((item) => item.id == request.capabilityId);
    final job = CommanderJob(
      id: 'fixture_${(_jobs.length + 1).toString().padLeft(4, '0')}',
      modelName: model.name,
      state: JobState.queued,
      createdAt: DateTime.utc(2026, 7, 19, 17, 10 + _jobs.length),
      owner: 'Commander fixture',
    );
    _jobs.insert(0, job);
    return _answer(job);
  }

  @override
  Future<BrainProfile> pair(PairingRequest request) {
    throw UnsupportedError(
      'This build has no live Brain transport. Pairing was not attempted.',
    );
  }
}
