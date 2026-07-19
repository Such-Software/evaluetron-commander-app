/// Opaque device credential issued by one Brain.
///
/// Implementations must not expose this value to logs, analytics, crash
/// reports, shared preferences, clipboard state, or ordinary application files.
final class DeviceCredential {
  const DeviceCredential({
    required this.brainOrigin,
    required this.deviceId,
    required this.secret,
    required this.scopes,
  });

  final Uri brainOrigin;
  final String deviceId;
  final String secret;
  final Set<String> scopes;

  @override
  String toString() => 'DeviceCredential(<redacted>)';
}

enum VaultProtection { operatingSystem, userPresence, unavailable }

/// Boundary for Keychain, Android Keystore, and desktop secret-service adapters.
///
/// A production Brain client receives this interface by dependency injection.
/// No SharedPreferences-backed implementation is permitted.
abstract interface class SecureCredentialVault {
  Future<VaultProtection> protection();
  Future<void> write(DeviceCredential credential);
  Future<DeviceCredential?> read(Uri brainOrigin);
  Future<void> remove(Uri brainOrigin);
}

/// Fail-closed placeholder until a platform secure-store adapter is wired.
final class UnavailableCredentialVault implements SecureCredentialVault {
  const UnavailableCredentialVault();

  Never _unsupported() {
    throw UnsupportedError(
      'Platform secure credential storage is not available in this build.',
    );
  }

  @override
  Future<VaultProtection> protection() async => VaultProtection.unavailable;

  @override
  Future<DeviceCredential?> read(Uri brainOrigin) async => _unsupported();

  @override
  Future<void> remove(Uri brainOrigin) async => _unsupported();

  @override
  Future<void> write(DeviceCredential credential) async => _unsupported();
}
