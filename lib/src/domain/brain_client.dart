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

/// What removing a pairing left behind on the Brain.
enum PairingRemoval {
  /// Nothing. The Brain revoked the device, or had already revoked it.
  revoked,

  /// The device is still active on the Brain, and can now only be revoked
  /// there: this device no longer holds the key to revoke itself with.
  consoleRevocationRequired,
}

/// The Brain could not be reached to revoke a device, so nothing was removed.
///
/// Distinct from a Brain that answered, because the caller's remedy is
/// different: retry later, or delete the local credential knowingly and revoke
/// [deviceId] from the operator console instead. The credential is deliberately
/// still on the device when this is thrown.
final class BrainUnreachableException implements Exception {
  const BrainUnreachableException({
    required this.origin,
    required this.deviceId,
    required this.message,
  });

  final Uri origin;
  final String deviceId;
  final String message;

  @override
  String toString() => message;
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
    this.readable = true,
  });

  /// A stored record that no longer parses.
  ///
  /// It was previously skipped, which made it invisible and unremovable: it
  /// cannot be signed with, switched to, or revoked, and nothing else on this
  /// device mentions it. Listing it as unusable is what gives the operator a
  /// way to delete it; hiding it only made the store impossible to clean.
  factory PairedBrain.unreadable({required Uri origin, required bool active}) =>
      PairedBrain(
        origin: origin,
        deviceId: '',
        deviceLabel: '',
        active: active,
        readable: false,
      );

  final Uri origin;
  final String deviceId;
  final String deviceLabel;

  /// Whether requests are currently signed with this credential.
  final bool active;

  /// Whether the stored record could be read at all. When false every other
  /// field is empty and the only action available is local removal.
  final bool readable;
}

/// A device row this app created on a Brain and could not retire.
///
/// Surfaced until the operator clears it, because Commander cannot revoke
/// another device — only the Brain's console can, and only if it knows the id.
final class StrandedCommanderDevice {
  const StrandedCommanderDevice({
    required this.origin,
    required this.deviceId,
    required this.reason,
  });

  final Uri origin;
  final String deviceId;
  final String reason;
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
  Future<PairingRemoval> forgetPairing({bool localOnly = false});

  /// Every Brain a credential is held for, the active one first.
  ///
  /// Pairing a second Brain keeps the first credential, so this is how the
  /// operator sees what this device can still command.
  Future<List<PairedBrain>> pairedBrains();

  /// Device rows this app left active on a Brain after a failed cleanup.
  Future<List<StrandedCommanderDevice>> strandedDevices();

  /// Forgets a stranded record once the operator has retired it from the
  /// console. This only clears the local reminder; it revokes nothing.
  Future<void> dismissStrandedDevice(String deviceId);

  /// Signs every later request with the credential stored for [origin].
  Future<BrainProfile> selectPairedBrain(Uri origin);

  /// Revokes this device on [origin], then deletes the local credential.
  ///
  /// Throws [BrainUnreachableException] and changes nothing when the Brain
  /// could not be asked to revoke it. [localOnly] is the escape hatch for that
  /// case: it deletes the local credential without contacting the Brain, which
  /// leaves the device active there. Never take it without the operator's
  /// explicit consent — a revocation that could have succeeded must not be
  /// skipped silently.
  Future<PairingRemoval> removePairedBrain(
    Uri origin, {
    bool localOnly = false,
  });

  /// Exchanges a one-time enrollment for a locally generated, revocable
  /// public-key device identity.
  Future<BrainProfile> pair(PairingRequest request);
}
