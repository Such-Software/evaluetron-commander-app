// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../widgets/page_frame.dart';

final class ActivityPage extends StatelessWidget {
  const ActivityPage({required this.events, super.key});
  final List<ActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Activity',
      subtitle:
          'Operator-visible events without raw secrets or request bodies.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              for (var index = 0; index < events.length; index++)
                _TimelineEvent(
                  event: events[index],
                  last: index == events.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event, required this.last});
  final ActivityEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.action,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text('${event.detail} · ${event.actor}'),
                  const SizedBox(height: 3),
                  Text(
                    _formatUtc(event.occurredAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatUtc(DateTime value) {
  final utc = value.toUtc();
  String two(int input) => input.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}
