// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';

final class LocalRemovalDialog extends StatelessWidget {
  const LocalRemovalDialog({
    super.key,
    required this.brain,
    required this.reason,
  });

  final PairedBrain? brain;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final host = brain?.origin.host;
    return AlertDialog(
      icon: const Icon(Icons.link_off),
      title: const Text('Remove without revoking?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Commander could not reach ${host ?? 'the paired Brain'} to '
              'revoke this device, so nothing has been removed yet.',
            ),
            if (reason case final message?) ...[
              const SizedBox(height: 10),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 14),
            Text(
              brain == null
                  ? 'Removing it here deletes only the key held on this '
                        'device. The device stays active on the Brain until an '
                        'operator revokes it from the Brain console.'
                  : 'Removing it here deletes only the key held on this '
                        'device. Device ${brain!.deviceId} stays active on '
                        '$host until an operator revokes it from that Brain\'s '
                        'console.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep the pairing'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove from this device only'),
        ),
      ],
    );
  }
}

final class PairedBrainRow extends StatelessWidget {
  const PairedBrainRow({
    super.key,
    required this.brain,
    required this.busy,
    required this.onUse,
    required this.onRemove,
  });

  final PairedBrain brain;
  final bool busy;
  final VoidCallback onUse;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        !brain.readable
            ? Icons.report_gmailerrorred_outlined
            : brain.active
            ? Icons.verified_user_outlined
            : Icons.dns_outlined,
      ),
      title: Text(brain.origin.host),
      subtitle: Text(
        brain.readable
            ? '${brain.deviceLabel} · ${brain.deviceId}'
            : 'Stored record cannot be read. It cannot command this Brain or '
                  'revoke itself; removing it here only clears this device.',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!brain.readable)
            const Chip(
              label: Text('Unusable'),
              visualDensity: VisualDensity.compact,
            )
          else if (brain.active)
            const Chip(
              label: Text('Active'),
              visualDensity: VisualDensity.compact,
            )
          else
            Tooltip(
              message: 'Command ${brain.origin.host}',
              child: TextButton(
                onPressed: busy ? null : onUse,
                child: const Text('Use'),
              ),
            ),
          IconButton(
            onPressed: busy ? null : onRemove,
            tooltip: 'Remove ${brain.origin.host}',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// One device row this app left active on a Brain.
final class StrandedDeviceRow extends StatelessWidget {
  const StrandedDeviceRow({
    super.key,
    required this.device,
    required this.busy,
    required this.onClear,
  });

  final StrandedCommanderDevice device;
  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.link_off_outlined, color: scheme.error),
      title: Text(device.deviceId),
      subtitle: Text(
        '${device.origin.host} · ${device.reason}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: busy ? null : onClear,
        child: const Text('Clear'),
      ),
    );
  }
}
