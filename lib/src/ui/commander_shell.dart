import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand.dart';
import '../domain/brain_client.dart';
import '../state/commander_controller.dart';
import 'dialogs/brain_profile_dialog.dart';
import 'pages/activity_page.dart';
import 'pages/configure_page.dart';
import 'pages/fleet_page.dart';
import 'pages/jobs_page.dart';
import 'pages/overview_page.dart';
import 'pages/run_page.dart';
import 'widgets/mode_badge.dart';

const _destinations = [
  (label: 'Overview', icon: Icons.space_dashboard_outlined),
  (label: 'Run', icon: Icons.play_circle_outline),
  (label: 'Jobs', icon: Icons.view_list_outlined),
  (label: 'Fleet', icon: Icons.devices_other_outlined),
  (label: 'Configure', icon: Icons.tune_outlined),
  (label: 'Activity', icon: Icons.manage_history_outlined),
];

const _shortcutKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
];

final class CommanderShell extends StatefulWidget {
  const CommanderShell({required this.controller, super.key});

  final CommanderController controller;

  @override
  State<CommanderShell> createState() => _CommanderShellState();
}

final class _CommanderShellState extends State<CommanderShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.loading) {
          return const _LoadingView();
        }
        if (widget.controller.error case final error?) {
          return _FailureView(
            error: error,
            retry: widget.controller.load,
            resetPairing: widget.controller.forgetPairing,
          );
        }
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            for (var index = 0; index < _destinations.length; index++)
              SingleActivator(_shortcutKeys[index], control: true):
                  _NavigateIntent(index),
          },
          child: Actions(
            actions: {
              _NavigateIntent: CallbackAction<_NavigateIntent>(
                onInvoke: (intent) {
                  setState(() => _index = intent.index);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return constraints.maxWidth < 720
                      ? _phoneScaffold(context)
                      : _wideScaffold(context, constraints.maxWidth);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _phoneScaffold(BuildContext context) {
    return Scaffold(
      appBar: _appBar(context),
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
              tooltip: destination.label,
            ),
        ],
      ),
    );
  }

  Widget _wideScaffold(BuildContext context, double width) {
    final extended = width >= 1180;
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              extended: extended,
              minExtendedWidth: 220,
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                child: extended
                    ? const EvaluetronLockup()
                    : const EvaluetronMark(
                        semanticLabel: 'Evaluetron Commander',
                      ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: extended
                        ? FilledButton.tonalIcon(
                            onPressed: () => _showBrain(context),
                            icon: const Icon(Icons.shield_outlined),
                            label: const Text('Brain profile'),
                          )
                        : IconButton.filledTonal(
                            onPressed: () => _showBrain(context),
                            tooltip: 'Brain profile',
                            icon: const Icon(Icons.shield_outlined),
                          ),
                  ),
                ),
              ),
              destinations: [
                for (final destination in _destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _DesktopHeader(
                  title: _destinations[_index].label,
                  profile: widget.controller.profile!,
                  onBrainPressed: () => _showBrain(context),
                ),
                Expanded(child: _page()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      toolbarHeight: 72,
      title: Row(
        children: [
          const EvaluetronMark(size: 34, semanticLabel: 'Evaluetron Commander'),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'evaluetron',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'COMMANDER · ${_destinations[_index].label.toUpperCase()}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ModeBadge(profile: widget.controller.profile!),
        IconButton(
          onPressed: () => _showBrain(context),
          tooltip: 'Brain profile',
          icon: const Icon(Icons.account_circle_outlined),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _page() {
    return switch (_index) {
      0 => OverviewPage(controller: widget.controller),
      1 => RunPage(
        controller: widget.controller,
        onJobCreated: () => setState(() => _index = 2),
      ),
      2 => JobsPage(jobs: widget.controller.jobs),
      3 => FleetPage(nodes: widget.controller.fleet),
      4 => ConfigurePage(settings: widget.controller.settings),
      _ => ActivityPage(events: widget.controller.activity),
    };
  }

  Future<void> _showBrain(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => BrainProfileDialog(controller: widget.controller),
    );
  }
}

final class _NavigateIntent extends Intent {
  const _NavigateIntent(this.index);
  final int index;
}

final class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.title,
    required this.profile,
    required this.onBrainPressed,
  });

  final String title;
  final BrainProfile profile;
  final VoidCallback onBrainPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ModeBadge(profile: profile),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onBrainPressed,
            tooltip: 'Open Brain profile',
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
    );
  }
}

final class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Loading Commander',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EvaluetronMark(size: 52),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

final class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.error,
    required this.retry,
    required this.resetPairing,
  });
  final Object error;
  final VoidCallback retry;
  final Future<PairingRemovalResult> Function({bool localOnly}) resetPairing;

  /// Removes the pairing from the one screen an operator reaches when nothing
  /// else works, so a Brain that is down cannot trap them here.
  Future<void> _removePairing(BuildContext context) async {
    final result = await removePairingWithOfflineFallback(
      context: context,
      brain: null,
      removal: resetPairing,
    );
    if (!context.mounted) return;
    final message = switch (result.outcome) {
      PairingRemovalOutcome.revoked => null,
      PairingRemovalOutcome.consoleRevocationRequired =>
        'Removed from this device. It is still active on the Brain until an '
            'operator revokes it from the Brain console.',
      PairingRemovalOutcome.brainUnreachable ||
      PairingRemovalOutcome.refused ||
      PairingRemovalOutcome.failed => result.message,
    };
    if (message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EvaluetronMark(
                  size: 52,
                  semanticLabel: 'Evaluetron Commander',
                ),
                const SizedBox(height: 16),
                Text(
                  'Commander could not load',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _removePairing(context),
                      icon: const Icon(Icons.phonelink_erase),
                      label: const Text('Remove paired Brain'),
                    ),
                    FilledButton.icon(
                      onPressed: retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
