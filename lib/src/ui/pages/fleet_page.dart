// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../widgets/page_frame.dart';

final class FleetPage extends StatelessWidget {
  const FleetPage({required this.nodes, super.key});
  final List<FleetNode> nodes;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Fleet',
      subtitle:
          'Each worker is a separately enrolled device with revocable identity.',
      action: FilledButton.tonalIcon(
        onPressed: () => _showEnrollmentPreview(context),
        icon: const Icon(Icons.add),
        label: const Text('Enroll'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 850 ? 3 : 1;
          final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final node in nodes)
                SizedBox(
                  width: width,
                  child: _NodeCard(node: node),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showEnrollmentPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.phonelink_lock_outlined),
        title: const Text('App-based enrollment'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const Text(
            'The production flow will display a short-lived QR code in the '
            'operator console. The Worker app scans it, creates a device key, '
            'and receives only its required scopes. This fixture build does '
            'not mint or retain credentials.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

final class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});
  final FleetNode node;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (node.state) {
      NodeState.ready => ('Ready', Colors.green.shade700),
      NodeState.busy => ('Busy', Theme.of(context).colorScheme.primary),
      NodeState.offline => ('Offline', Theme.of(context).colorScheme.outline),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  node.platform.startsWith('Android')
                      ? Icons.smartphone
                      : Icons.computer,
                ),
                const Spacer(),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(label),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              node.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              node.platform,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final capability in node.capabilities)
                  Chip(
                    label: Text(capability),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
