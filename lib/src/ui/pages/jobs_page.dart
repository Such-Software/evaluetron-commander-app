// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../widgets/page_frame.dart';
import '../widgets/state_icon.dart';

final class JobsPage extends StatelessWidget {
  const JobsPage({required this.jobs, super.key});
  final List<CommanderJob> jobs;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Jobs',
      subtitle: 'Work accepted by the selected Brain, newest first.',
      child: Card(
        child: Column(
          children: [
            for (var index = 0; index < jobs.length; index++) ...[
              _JobRow(job: jobs[index]),
              if (index != jobs.length - 1)
                const Divider(height: 1, indent: 68),
            ],
          ],
        ),
      ),
    );
  }
}

final class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});
  final CommanderJob job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          StateIcon(state: job.state),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.modelName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${job.id} · ${job.owner}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (job.state == JobState.running) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: job.progress,
                    semanticsLabel: 'Job progress',
                    semanticsValue: '${(job.progress * 100).round()} percent',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Chip(label: Text(jobStateLabel(job.state))),
        ],
      ),
    );
  }
}
