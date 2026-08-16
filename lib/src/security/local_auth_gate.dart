import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// The operations that require a fresh local user-presence proof.
///
/// Every value here grants, uses, or destroys operator authority over the
/// fleet, so each one is re-authenticated immediately before it runs rather
/// than relying on a single session-wide unlock.
enum PrivilegedAction { unlockSession, submitJob, pairBrain, revokeAccess }

/// Result of asking the operating system to prove the operator is present.
enum LocalAuthOutcome {
  /// The platform authenticated the operator just now.
  authenticated,

  /// The operator cancelled, failed, or is locked out of the authenticator.
  rejected,

  /// The device has no usable authenticator: no enrolled biometric, no
  /// device passcode, or no platform implementation at all.
  ///
  /// This is never treated as success. Callers must fail closed.
  unavailable,
}

/// Raised when a privileged action was refused because local authentication
/// did not succeed. The message is operator-facing.
final class LocalAuthRequiredException implements Exception {
  const LocalAuthRequiredException(this.message, {required this.outcome});

  final String message;
  final LocalAuthOutcome outcome;

  @override
  String toString() => message;
}

/// Boundary for the platform user-presence check.
///
/// Injected from the composition root so tests can drive every branch
/// without a device.
abstract interface class LocalAuthGate {
  /// Whether this device can prove user presence at all, i.e. it has a
  /// screen lock or enrolled biometric and a platform implementation.
  Future<bool> isEnrolled();

  /// Prompts for user presence. Implementations must never report
  /// [LocalAuthOutcome.authenticated] without a real platform confirmation.
  Future<LocalAuthOutcome> authenticate(PrivilegedAction action);
}

/// Turns a non-authenticated outcome into the operator-facing refusal.
///
/// Shared by every call site so the fail-closed wording stays consistent.
LocalAuthRequiredException localAuthRefusal(
  PrivilegedAction action,
  LocalAuthOutcome outcome,
) {
  final subject = switch (action) {
    PrivilegedAction.unlockSession => 'Unlocking Commander',
    PrivilegedAction.submitJob => 'Submitting a job',
    PrivilegedAction.pairBrain => 'Pairing a Brain',
    PrivilegedAction.revokeAccess => 'Revoking this Commander',
  };
  return LocalAuthRequiredException(switch (outcome) {
    LocalAuthOutcome.authenticated =>
      '$subject was refused despite a successful check.',
    LocalAuthOutcome.rejected =>
      '$subject requires device authentication. The check was cancelled or '
          'did not succeed.',
    LocalAuthOutcome.unavailable =>
      '$subject requires a device screen lock. Enrol a biometric, PIN, '
          'pattern, or password in system settings and try again.',
  }, outcome: outcome);
}

/// Real user-presence check backed by the platform authenticator.
final class PlatformLocalAuthGate implements LocalAuthGate {
  PlatformLocalAuthGate({LocalAuthentication? authentication})
    : _auth = authentication ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isEnrolled() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Desktop platforms without a local_auth implementation land here.
      return false;
    }
  }

  @override
  Future<LocalAuthOutcome> authenticate(PrivilegedAction action) async {
    if (!await isEnrolled()) return LocalAuthOutcome.unavailable;
    try {
      final ok = await _auth.authenticate(
        localizedReason: switch (action) {
          PrivilegedAction.unlockSession => 'Unlock Evaluetron Commander',
          PrivilegedAction.submitJob => 'Confirm submitting a job to the Brain',
          PrivilegedAction.pairBrain => 'Confirm pairing a new Brain',
          PrivilegedAction.revokeAccess =>
            'Confirm revoking this Commander device',
        },
        // Device passcode is accepted as a fallback so that a temporarily
        // failing sensor cannot lock an operator out of their own fleet.
        biometricOnly: false,
        sensitiveTransaction: true,
      );
      return ok ? LocalAuthOutcome.authenticated : LocalAuthOutcome.rejected;
    } on PlatformException catch (error) {
      // `notAvailable`, `notEnrolled` and `passcodeNotSet` mean the device
      // cannot prove presence; everything else (including lockout) is a
      // refusal. Neither is ever treated as success.
      return const {
            'NotAvailable',
            'NotEnrolled',
            'PasscodeNotSet',
          }.contains(error.code)
          ? LocalAuthOutcome.unavailable
          : LocalAuthOutcome.rejected;
    } on MissingPluginException {
      return LocalAuthOutcome.unavailable;
    }
  }
}

/// Gate for builds with no platform authenticator. Always fails closed.
final class UnavailableLocalAuthGate implements LocalAuthGate {
  const UnavailableLocalAuthGate();

  @override
  Future<bool> isEnrolled() async => false;

  @override
  Future<LocalAuthOutcome> authenticate(PrivilegedAction action) async =>
      LocalAuthOutcome.unavailable;
}
