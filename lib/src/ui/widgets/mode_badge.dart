// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';

final class ModeBadge extends StatelessWidget {
  const ModeBadge({required this.profile, super.key});

  final BrainProfile profile;

  @override
  Widget build(BuildContext context) {
    final fixture = profile.mode == ConnectionMode.fixture;
    return Tooltip(
      message: fixture
          ? 'Deterministic local data; no Brain network calls'
          : 'Paired to ${profile.endpoint.host}',
      child: Chip(
        avatar: Icon(
          fixture ? Icons.science_outlined : Icons.verified_user_outlined,
          size: 18,
        ),
        label: Text(fixture ? 'Fixture' : 'Paired'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
