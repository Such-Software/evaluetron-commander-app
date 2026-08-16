import 'package:evaluetron_commander_app/src/security/local_auth_gate.dart';

/// Scriptable [LocalAuthGate] for tests.
///
/// Records every action it was asked to confirm so tests can assert that a
/// step-up actually happened rather than only that the call succeeded.
final class FakeLocalAuthGate implements LocalAuthGate {
  FakeLocalAuthGate({
    this.outcome = LocalAuthOutcome.authenticated,
    this.enrolled = true,
  });

  /// A device that could prove presence but has no screen lock enrolled.
  /// Fails closed: the operator can fix this.
  factory FakeLocalAuthGate.notEnrolled() => FakeLocalAuthGate(
    outcome: LocalAuthOutcome.notEnrolled,
    enrolled: false,
  );

  /// A platform with no local authentication implementation at all, such as
  /// Linux desktop. Permits the action and reports the session unprotected.
  factory FakeLocalAuthGate.unsupportedPlatform() => FakeLocalAuthGate(
    outcome: LocalAuthOutcome.unsupportedPlatform,
    enrolled: false,
  );

  /// A gate where the operator cancels or fails the prompt.
  factory FakeLocalAuthGate.rejecting() =>
      FakeLocalAuthGate(outcome: LocalAuthOutcome.rejected);

  LocalAuthOutcome outcome;
  bool enrolled;
  final requested = <PrivilegedAction>[];

  @override
  Future<bool> isEnrolled() async => enrolled;

  @override
  Future<LocalAuthOutcome> authenticate(PrivilegedAction action) async {
    requested.add(action);
    return outcome;
  }
}
