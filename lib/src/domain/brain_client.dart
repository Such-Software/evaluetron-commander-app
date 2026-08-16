enum ConnectionMode { fixture, paired }

enum JobState { queued, running, succeeded, failed }

enum NodeState { ready, busy, offline }

final class BrainProfile {
  const BrainProfile({
    required this.name,
    required this.endpoint,
    required this.mode,
    required this.identity,
    required this.scopes,
  });

  final String name;
  final Uri endpoint;
  final ConnectionMode mode;
  final String identity;
  final List<String> scopes;
}

final class BrainOverview {
  const BrainOverview({
    required this.activeJobs,
    required this.readyNodes,
    required this.billing,
    required this.successRate,
  });

  final int activeJobs;
  final int readyNodes;
  final String billing;
  final double? successRate;
}

final class ModelCapability {
  const ModelCapability({
    required this.id,
    required this.name,
    required this.kind,
    required this.summary,
    required this.creditCost,
    required this.inputLabel,
    required this.inputHint,
    this.parameterName = 'text',
    this.model,
  });

  final String id;
  final String name;
  final String kind;
  final String summary;
  final int creditCost;
  final String inputLabel;
  final String inputHint;
  final String parameterName;
  final String? model;
}

final class CommanderJob {
  const CommanderJob({
    required this.id,
    required this.modelName,
    required this.state,
    required this.createdAt,
    required this.owner,
    this.progress = 0,
  });

  final String id;
  final String modelName;
  final JobState state;
  final DateTime createdAt;
  final String owner;
  final double progress;
}

final class FleetNode {
  const FleetNode({
    required this.id,
    required this.name,
    required this.platform,
    required this.state,
    required this.capabilities,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final NodeState state;
  final List<String> capabilities;
  final DateTime lastSeen;
}

final class BrainSetting {
  const BrainSetting({
    required this.group,
    required this.name,
    required this.value,
    required this.sensitivity,
  });

  final String group;
  final String name;
  final String value;
  final String sensitivity;
}

final class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.action,
    required this.actor,
    required this.occurredAt,
    required this.detail,
  });

  final String id;
  final String action;
  final String actor;
  final DateTime occurredAt;
  final String detail;
}

final class JobRequest {
  const JobRequest({required this.capabilityId, required this.input});

  final String capabilityId;
  final String input;
}

final class PairingRequest {
  const PairingRequest({required this.enrollmentUri});

  final Uri enrollmentUri;
}

/// One Brain this Commander holds a device credential for.
///
/// Deliberately carries no key material. The private seed stays in the vault
/// and the data layer; only the identity an operator can already read off the
/// Brain's own console — origin, device id, label — is describable here.
final class PairedBrain {
  const PairedBrain({
    required this.origin,
    required this.deviceId,
    required this.deviceLabel,
    required this.active,
  });

  final Uri origin;
  final String deviceId;
  final String deviceLabel;

  /// Whether requests are currently signed with this credential.
  final bool active;
}

abstract interface class BrainClient {
  Future<BrainProfile> getProfile();
  Future<BrainOverview> getOverview();
  Future<List<ModelCapability>> getCatalog();
  Future<List<CommanderJob>> getJobs();
  Future<List<FleetNode>> getFleet();
  Future<List<BrainSetting>> getSettings();
  Future<List<ActivityEvent>> getActivity();
  Future<CommanderJob> submitJob(JobRequest request);

  /// Revokes and removes the pairing currently in use.
  Future<void> forgetPairing();

  /// Every Brain a credential is held for, the active one first.
  ///
  /// Pairing a second Brain keeps the first credential, so this is how the
  /// operator sees what this device can still command.
  Future<List<PairedBrain>> pairedBrains();

  /// Signs every later request with the credential stored for [origin].
  Future<BrainProfile> selectPairedBrain(Uri origin);

  /// Revokes this device on [origin], then deletes the local credential.
  Future<void> removePairedBrain(Uri origin);

  /// Exchanges a one-time enrollment for a locally generated, revocable
  /// public-key device identity.
  Future<BrainProfile> pair(PairingRequest request);
}
