import 'package:flutter/services.dart';

import 'managed_network.dart';

/// Android/iOS bridge for the optional managed-network engine.
///
/// The Android scaffold currently reports `engineNotInstalled`; it does not
/// request VPN consent or establish an interface until an audited Nebula mobile
/// engine is embedded.
final class MethodChannelManagedNetworkPlatform
    implements ManagedNetworkPlatform {
  const MethodChannelManagedNetworkPlatform({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName =
      'com.suchsoftware.evaluetron.commander/managed_network';

  final MethodChannel _channel;

  @override
  Future<ManagedNetworkCapability> inspect() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>('inspect');
      if (value == null) return const ManagedNetworkCapability.unsupported();
      return ManagedNetworkCapability(
        availability: switch (value['availability']) {
          'available' => ManagedNetworkAvailability.available,
          'engineNotInstalled' => ManagedNetworkAvailability.engineNotInstalled,
          _ => ManagedNetworkAvailability.unsupportedPlatform,
        },
        platform: value['platform'] as String? ?? 'unknown',
        vpnServiceDeclared: value['vpnServiceDeclared'] as bool? ?? false,
        engineVersion: value['engineVersion'] as String?,
        consentRequired: value['consentRequired'] as bool? ?? false,
      );
    } on MissingPluginException {
      return const ManagedNetworkCapability.unsupported();
    } on PlatformException {
      return const ManagedNetworkCapability.unsupported();
    }
  }

  @override
  Future<TunnelSnapshot> status() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>('status');
      if (value == null) return const TunnelSnapshot.unavailable();
      return _snapshot(value);
    } on MissingPluginException {
      return const TunnelSnapshot.unavailable();
    } on PlatformException {
      return const TunnelSnapshot.unavailable();
    }
  }

  @override
  Future<TunnelConsentResult> requestConsent() async {
    final capability = await inspect();
    if (!capability.canConnect) return TunnelConsentResult.unavailable;
    try {
      final value = await _channel.invokeMethod<String>('requestConsent');
      return switch (value) {
        'granted' => TunnelConsentResult.granted,
        'denied' => TunnelConsentResult.denied,
        _ => TunnelConsentResult.unavailable,
      };
    } on PlatformException {
      return TunnelConsentResult.unavailable;
    }
  }

  @override
  Future<TunnelSnapshot> connect(ManagedNetworkProfile profile) async {
    final capability = await inspect();
    if (!capability.canConnect) return const TunnelSnapshot.unavailable();
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'connect',
        managedProfileToJson(profile),
      );
      return value == null
          ? const TunnelSnapshot.unavailable()
          : _snapshot(value);
    } on PlatformException {
      return const TunnelSnapshot.unavailable();
    }
  }

  @override
  Future<TunnelSnapshot> disconnect() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'disconnect',
      );
      return value == null
          ? const TunnelSnapshot.unavailable()
          : _snapshot(value);
    } on MissingPluginException {
      return const TunnelSnapshot.unavailable();
    } on PlatformException {
      return const TunnelSnapshot.unavailable();
    }
  }

  static TunnelSnapshot _snapshot(Map<String, Object?> value) {
    final lifecycle = switch (value['lifecycle']) {
      'disconnected' => TunnelLifecycle.disconnected,
      'awaitingConsent' => TunnelLifecycle.awaitingConsent,
      'connecting' => TunnelLifecycle.connecting,
      'connected' => TunnelLifecycle.connected,
      'conflict' => TunnelLifecycle.conflict,
      'failed' => TunnelLifecycle.failed,
      _ => TunnelLifecycle.unavailable,
    };
    return TunnelSnapshot(
      lifecycle: lifecycle,
      profileId: value['profileId'] as String?,
      message: value['message'] as String?,
    );
  }
}
