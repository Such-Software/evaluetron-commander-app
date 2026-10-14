// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../widgets/page_frame.dart';

final class ConfigurePage extends StatelessWidget {
  const ConfigurePage({required this.settings, super.key});
  final List<BrainSetting> settings;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<BrainSetting>>{};
    for (final setting in settings) {
      grouped.putIfAbsent(setting.group, () => []).add(setting);
    }
    return PageFrame(
      title: 'Configure',
      subtitle: 'Read-only in this build. Mutations require explicit scopes.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MaterialBanner(
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            leading: const Icon(Icons.lock_outline),
            content: const Text(
              'Fixture values are illustrative. Secrets never cross this '
              'interface; sensitive settings are represented as redacted state.',
            ),
            actions: const [SizedBox.shrink()],
          ),
          const SizedBox(height: 16),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
              child: Text(
                entry.key,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < entry.value.length; index++) ...[
                    ListTile(
                      title: Text(entry.value[index].name),
                      subtitle: Text(entry.value[index].sensitivity),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          entry.value[index].value,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (index != entry.value.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
