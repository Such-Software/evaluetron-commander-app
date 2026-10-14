// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../../state/commander_controller.dart';
import '../widgets/mode_badge.dart';
import '../widgets/page_frame.dart';
import '../widgets/state_icon.dart';

final class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.controller, super.key});
  final CommanderController controller;

  @override
  Widget build(BuildContext context) {
    final overview = controller.overview!;
    return PageFrame(
      title: 'Good afternoon',
      subtitle:
          'A scoped operational view of this Brain and the work it coordinates.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 960 ? 4 : (width >= 560 ? 2 : 1);
              final itemWidth = (width - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    width: itemWidth,
                    label: 'Active jobs',
                    value: '${overview.activeJobs}',
                    icon: Icons.pending_actions_outlined,
                  ),
                  _MetricCard(
                    width: itemWidth,
                    label: 'Ready nodes',
                    value: '${overview.readyNodes}',
                    icon: Icons.devices_other_outlined,
                  ),
                  _MetricCard(
                    width: itemWidth,
                    label: 'Billing context',
                    value: overview.billing,
                    icon: Icons.toll_outlined,
                  ),
                  _MetricCard(
                    width: itemWidth,
                    label: 'Success · 24h',
                    value: overview.successRate == null
                        ? 'N/A'
                        : '${(overview.successRate! * 100).toStringAsFixed(1)}%',
                    icon: Icons.auto_graph_outlined,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final security = _SecurityCard(profile: controller.profile!);
              final recent = _RecentJobsCard(
                jobs: controller.jobs.take(3).toList(),
              );
              if (!wide) {
                return Column(
                  children: [security, const SizedBox(height: 16), recent],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: security),
                  const SizedBox(width: 16),
                  Expanded(child: recent),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

final class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.profile});
  final BrainProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.shield_outlined,
              title: 'Security posture',
              trailing: ModeBadge(profile: profile),
            ),
            const SizedBox(height: 18),
            const _CheckLine('Scoped device identity'),
            const _CheckLine('No shared fleet credential'),
            const _CheckLine('Sensitive values are redacted'),
            const SizedBox(height: 8),
            Text(
              profile.mode == ConnectionMode.fixture
                  ? 'Fixture mode does not make network requests or retain credentials.'
                  : 'Credential storage is delegated to the platform secure store.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

final class _CheckLine extends StatelessWidget {
  const _CheckLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

final class _RecentJobsCard extends StatelessWidget {
  const _RecentJobsCard({required this.jobs});
  final List<CommanderJob> jobs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.bolt_outlined,
              title: 'Recent work',
            ),
            const SizedBox(height: 10),
            for (final job in jobs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: StateIcon(state: job.state),
                title: Text(job.modelName),
                subtitle: Text(job.id),
                trailing: Text(jobStateLabel(job.state)),
              ),
          ],
        ),
      ),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
