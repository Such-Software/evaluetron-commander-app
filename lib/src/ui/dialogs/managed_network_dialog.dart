// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../network/managed_network.dart';
import '../../state/commander_controller.dart';

final class ManagedNetworkDialog extends StatefulWidget {
  const ManagedNetworkDialog({required this.controller, super.key});

  final CommanderController controller;

  @override
  State<ManagedNetworkDialog> createState() => _ManagedNetworkDialogState();
}

final class _ManagedNetworkDialogState extends State<ManagedNetworkDialog> {
  bool _routeConsent = false;
  bool _conflictConsent = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final capability = widget.controller.managedNetworkCapability;
    final tunnel = widget.controller.tunnel;
    final canRequest =
        capability.canConnect &&
        _routeConsent &&
        _conflictConsent &&
        !widget.controller.networkBusy;
    return AlertDialog(
      icon: const Icon(Icons.lan_outlined),
      title: const Text('Managed network'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Network status',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.shield_outlined, size: 18),
                    label: Text(tunnelLifecycleLabel(tunnel.lifecycle)),
                  ),
                  Chip(label: Text(capability.platform)),
                  if (capability.consentRequired)
                    const Chip(label: Text('System consent required')),
                ],
              ),
              const SizedBox(height: 12),
              Text(managedAvailabilityLabel(capability)),
              if (tunnel.message case final message?) ...[
                const SizedBox(height: 6),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.radio_button_checked),
                      title: Text('Use public signed HTTPS'),
                      subtitle: Text(
                        'Current path. Managed networking is never required '
                        'to operate Commander.',
                      ),
                      trailing: Chip(label: Text('Current')),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.radio_button_unchecked),
                      title: Text('Use managed Nebula'),
                      subtitle: Text(
                        'Requires a Commander-specific enrollment and audited '
                        'native engine.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _routeConsent,
                onChanged: (value) =>
                    setState(() => _routeConsent = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I understand the route boundary'),
                subtitle: const Text(
                  'Only the enrolled Brain host route enters this tunnel. '
                  'Commander does not request a default internet route.',
                ),
              ),
              CheckboxListTile(
                value: _conflictConsent,
                onChanged: (value) =>
                    setState(() => _conflictConsent = value ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I understand the VPN conflict'),
                subtitle: const Text(
                  'Mobile operating systems allow one active VPN. Commander '
                  'must not silently replace another VPN connection.',
                ),
              ),
              if (_message case final message?) ...[
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(message)),
              ],
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: canRequest ? _requestConsent : null,
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(
                  widget.controller.networkBusy
                      ? 'Checking…'
                      : 'Review system VPN consent',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'No enrollment, certificate, private key, or tunnel is created '
                'from this screen in the current build.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _requestConsent() async {
    final result = await widget.controller.requestTunnelConsent();
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        TunnelConsentResult.granted =>
          'System VPN consent is available. No tunnel was started.',
        TunnelConsentResult.denied => 'System VPN consent was declined.',
        TunnelConsentResult.unavailable =>
          'VPN consent is unavailable until the native engine is installed.',
      };
    });
  }
}

/// How this build describes its managed-network engine.
String managedAvailabilityLabel(ManagedNetworkCapability capability) {
  return switch (capability.availability) {
    ManagedNetworkAvailability.available =>
      'Native engine available; enrollment is still required.',
    ManagedNetworkAvailability.engineNotInstalled =>
      'Optional · native engine not embedded in this build.',
    ManagedNetworkAvailability.unsupportedPlatform =>
      'Optional · unavailable on this platform build.',
  };
}

/// One word for where the tunnel currently is.
String tunnelLifecycleLabel(TunnelLifecycle lifecycle) {
  return switch (lifecycle) {
    TunnelLifecycle.unavailable => 'Unavailable',
    TunnelLifecycle.disconnected => 'Disconnected',
    TunnelLifecycle.awaitingConsent => 'Awaiting consent',
    TunnelLifecycle.connecting => 'Connecting',
    TunnelLifecycle.connected => 'Connected',
    TunnelLifecycle.conflict => 'VPN conflict',
    TunnelLifecycle.failed => 'Failed',
  };
}
