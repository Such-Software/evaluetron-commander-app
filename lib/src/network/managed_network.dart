import 'dart:convert';
import 'dart:io';

/// Optional network path for reaching a paired Brain.
///
/// Public, signed HTTPS remains supported independently of managed networking.
enum BrainNetworkPath { publicHttps, managedNebula }

enum ManagedNetworkAvailability {
  unsupportedPlatform,
  engineNotInstalled,
  available,
}

enum TunnelLifecycle {
  unavailable,
  disconnected,
  awaitingConsent,
  connecting,
  connected,
  conflict,
  failed,
}

enum TunnelConsentResult { granted, denied, unavailable }

enum ManagedNetworkTarget { android, ios }

/// A single-host route admitted to the managed tunnel.
///
/// Commander does not accept default routes or arbitrary private subnets.
final class ManagedHostRoute {
  ManagedHostRoute._(this.cidr);

  final String cidr;
  String get address => cidr.substring(0, cidr.lastIndexOf('/'));

  static ManagedHostRoute parse(String value) {
    final pieces = value.split('/');
    if (pieces.length != 2) {
      throw const FormatException('Managed route must use CIDR notation.');
    }
    final parsedAddress = InternetAddress.tryParse(pieces[0]);
    final prefix = int.tryParse(pieces[1]);
    final isIpv4 = parsedAddress?.type == InternetAddressType.IPv4;
    final isIpv6 = parsedAddress?.type == InternetAddressType.IPv6;
    if ((!isIpv4 || prefix != 32) && (!isIpv6 || prefix != 128)) {
      throw const FormatException(
        'Commander managed routes must target exactly one host.',
      );
    }
    if (!_isPrivateOrLinkLocal(parsedAddress!)) {
      throw const FormatException(
        'Commander managed routes must use a private overlay address.',
      );
    }
    return ManagedHostRoute._('${parsedAddress.address.toLowerCase()}/$prefix');
  }

  static bool _isPrivateOrLinkLocal(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv6) {
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
    }
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }

  @override
  bool operator ==(Object other) =>
      other is ManagedHostRoute && other.cidr == cidr;

  @override
  int get hashCode => cidr.hashCode;
}

/// Non-secret, locally displayable network policy.
final class ManagedNetworkProfile {
  ManagedNetworkProfile({
    required this.id,
    required this.displayName,
    required this.publicBrainOrigin,
    required this.managedBrainOrigin,
    required this.brainRoute,
    required this.group,
    required this.target,
    required this.expiresAt,
  }) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$').hasMatch(id) ||
        displayName.trim().isEmpty ||
        displayName.length > 80 ||
        !_isHttpsOrigin(publicBrainOrigin) ||
        !_isManagedOrigin(managedBrainOrigin, brainRoute) ||
        group != 'commander' ||
        expiresAt.isBefore(DateTime.now().toUtc())) {
      throw const FormatException('Invalid managed network profile.');
    }
  }

  final String id;
  final String displayName;
  final Uri publicBrainOrigin;
  final Uri managedBrainOrigin;
  final ManagedHostRoute brainRoute;
  final String group;
  final ManagedNetworkTarget target;
  final DateTime expiresAt;

  static bool _isHttpsOrigin(Uri value) =>
      value.scheme == 'https' &&
      value.host.isNotEmpty &&
      value.userInfo.isEmpty &&
      (value.path.isEmpty || value.path == '/') &&
      !value.hasQuery &&
      !value.hasFragment;

  static bool _isManagedOrigin(Uri value, ManagedHostRoute route) {
    final originShape =
        value.host.isNotEmpty &&
        value.userInfo.isEmpty &&
        (value.path.isEmpty || value.path == '/') &&
        !value.hasQuery &&
        !value.hasFragment &&
        value.host.toLowerCase() == route.address.toLowerCase();
    if (!originShape) return false;
    if (value.scheme == 'https') return true;
    return value.scheme == 'http' && value.hasPort;
  }
}

/// Secret enrollment result that must only be stored in a secure vault.
///
/// A Commander enrollment is intentionally role-specific. Current
/// worker-oriented enrollment artifacts must be rejected by a live adapter.
final class ManagedNetworkCredential {
  ManagedNetworkCredential({
    required this.profile,
    required this.certificateGroups,
    required this.caCertificate,
    required this.hostCertificate,
    required this.hostPrivateKey,
    required this.nebulaConfiguration,
  }) {
    if (!certificateGroups.contains('commander') ||
        certificateGroups.contains('worker') ||
        caCertificate.trim().isEmpty ||
        hostCertificate.trim().isEmpty ||
        hostPrivateKey.trim().isEmpty ||
        nebulaConfiguration.trim().isEmpty) {
      throw const FormatException(
        'Managed enrollment must be a complete Commander credential.',
      );
    }
    final lowered = nebulaConfiguration.toLowerCase();
    if (lowered.contains('0.0.0.0/0') ||
        lowered.contains('::/0') ||
        lowered.contains('ca.key')) {
      throw const FormatException(
        'Managed enrollment contains a forbidden route or CA key reference.',
      );
    }
  }

  final ManagedNetworkProfile profile;
  final Set<String> certificateGroups;
  final String caCertificate;
  final String hostCertificate;
  final String hostPrivateKey;
  final String nebulaConfiguration;

  @override
  String toString() => 'ManagedNetworkCredential(<redacted>)';
}

/// One-time enrollment input. Its URI can contain a bearer secret.
final class ManagedNetworkEnrollmentRequest {
  const ManagedNetworkEnrollmentRequest({
    required this.enrollmentUri,
    required this.userConfirmed,
  });

  final Uri enrollmentUri;
  final bool userConfirmed;

  @override
  String toString() => 'ManagedNetworkEnrollmentRequest(<redacted>)';
}

final class ManagedNetworkCapability {
  const ManagedNetworkCapability({
    required this.availability,
    required this.platform,
    required this.vpnServiceDeclared,
    required this.engineVersion,
    this.consentRequired = false,
  });

  const ManagedNetworkCapability.unsupported()
    : availability = ManagedNetworkAvailability.unsupportedPlatform,
      platform = 'unsupported',
      vpnServiceDeclared = false,
      engineVersion = null,
      consentRequired = false;

  final ManagedNetworkAvailability availability;
  final String platform;
  final bool vpnServiceDeclared;
  final String? engineVersion;
  final bool consentRequired;

  bool get canConnect =>
      availability == ManagedNetworkAvailability.available &&
      vpnServiceDeclared &&
      engineVersion != null;
}

final class TunnelSnapshot {
  const TunnelSnapshot({required this.lifecycle, this.profileId, this.message});

  const TunnelSnapshot.unavailable()
    : lifecycle = TunnelLifecycle.unavailable,
      profileId = null,
      message = 'Managed network engine is unavailable.';

  final TunnelLifecycle lifecycle;
  final String? profileId;
  final String? message;
}

/// Platform boundary for user consent and a native Nebula tunnel.
abstract interface class ManagedNetworkPlatform {
  Future<ManagedNetworkCapability> inspect();
  Future<TunnelSnapshot> status();
  Future<TunnelConsentResult> requestConsent();
  Future<TunnelSnapshot> connect(ManagedNetworkProfile profile);
  Future<TunnelSnapshot> disconnect();
}

/// Server boundary for role-specific managed-network enrollment.
abstract interface class ManagedNetworkEnrollmentClient {
  Future<ManagedNetworkCredential> enroll(
    ManagedNetworkEnrollmentRequest request,
  );
}

/// Secure storage boundary for all Nebula configuration and key material.
abstract interface class ManagedNetworkVault {
  Future<void> write(ManagedNetworkCredential credential);
  Future<ManagedNetworkCredential?> read(String profileId);
  Future<void> remove(String profileId);
}

final class UnavailableManagedNetworkPlatform
    implements ManagedNetworkPlatform {
  const UnavailableManagedNetworkPlatform();

  @override
  Future<TunnelSnapshot> connect(ManagedNetworkProfile profile) async =>
      const TunnelSnapshot.unavailable();

  @override
  Future<TunnelSnapshot> disconnect() async =>
      const TunnelSnapshot.unavailable();

  @override
  Future<ManagedNetworkCapability> inspect() async =>
      const ManagedNetworkCapability.unsupported();

  @override
  Future<TunnelConsentResult> requestConsent() async =>
      TunnelConsentResult.unavailable;

  @override
  Future<TunnelSnapshot> status() async => const TunnelSnapshot.unavailable();
}

Map<String, Object?> managedProfileToJson(ManagedNetworkProfile profile) => {
  'version': 1,
  'id': profile.id,
  'displayName': profile.displayName,
  'publicBrainOrigin': profile.publicBrainOrigin.toString(),
  'managedBrainOrigin': profile.managedBrainOrigin.toString(),
  'brainRoute': profile.brainRoute.cidr,
  'group': profile.group,
  'target': profile.target.name,
  'expiresAt': profile.expiresAt.toUtc().toIso8601String(),
};

ManagedNetworkProfile managedProfileFromJson(Map<String, Object?> json) {
  if (json['version'] != 1) {
    throw const FormatException('Unsupported managed profile version.');
  }
  return ManagedNetworkProfile(
    id: json['id'] as String,
    displayName: json['displayName'] as String,
    publicBrainOrigin: Uri.parse(json['publicBrainOrigin'] as String),
    managedBrainOrigin: Uri.parse(json['managedBrainOrigin'] as String),
    brainRoute: ManagedHostRoute.parse(json['brainRoute'] as String),
    group: json['group'] as String,
    target: ManagedNetworkTarget.values.byName(json['target'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
  );
}

String encodeManagedCredential(ManagedNetworkCredential value) => jsonEncode({
  ...managedProfileToJson(value.profile),
  'certificateGroups': value.certificateGroups.toList()..sort(),
  'caCertificate': value.caCertificate,
  'hostCertificate': value.hostCertificate,
  'hostPrivateKey': value.hostPrivateKey,
  'nebulaConfiguration': value.nebulaConfiguration,
});

ManagedNetworkCredential decodeManagedCredential(String encoded) {
  final json = jsonDecode(encoded) as Map<String, Object?>;
  return ManagedNetworkCredential(
    profile: managedProfileFromJson(json),
    certificateGroups: (json['certificateGroups'] as List<dynamic>)
        .cast<String>()
        .toSet(),
    caCertificate: json['caCertificate'] as String,
    hostCertificate: json['hostCertificate'] as String,
    hostPrivateKey: json['hostPrivateKey'] as String,
    nebulaConfiguration: json['nebulaConfiguration'] as String,
  );
}
