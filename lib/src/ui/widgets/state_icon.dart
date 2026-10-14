// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';

final class StateIcon extends StatelessWidget {
  const StateIcon({required this.state, super.key});

  final JobState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state) {
      JobState.queued => (
        Icons.schedule_outlined,
        Theme.of(context).colorScheme.tertiary,
      ),
      JobState.running => (Icons.sync, Theme.of(context).colorScheme.primary),
      JobState.succeeded => (Icons.check_circle_outline, Colors.green.shade700),
      JobState.failed => (
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: .12),
      foregroundColor: color,
      child: Icon(icon),
    );
  }
}

/// The word beside a [StateIcon]. Public because two pages show the same
/// state and must not drift into calling it different things.
String jobStateLabel(JobState state) => switch (state) {
  JobState.queued => 'Queued',
  JobState.running => 'Running',
  JobState.succeeded => 'Succeeded',
  JobState.failed => 'Failed',
};
