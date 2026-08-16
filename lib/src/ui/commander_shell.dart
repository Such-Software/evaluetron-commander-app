import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../brand.dart';
import '../domain/brain_client.dart';
import '../network/managed_network.dart';
import '../state/commander_controller.dart';

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
        _ModeBadge(profile: widget.controller.profile!),
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
          _ModeBadge(profile: profile),
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

final class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.profile});
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

final class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (action case final widget?) ...[
                    const SizedBox(width: 16),
                    widget,
                  ],
                ],
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

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
              trailing: _ModeBadge(profile: profile),
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
                leading: _StateIcon(state: job.state),
                title: Text(job.modelName),
                subtitle: Text(job.id),
                trailing: Text(_jobStateLabel(job.state)),
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

final class RunPage extends StatefulWidget {
  const RunPage({
    required this.controller,
    required this.onJobCreated,
    super.key,
  });

  final CommanderController controller;
  final VoidCallback onJobCreated;

  @override
  State<RunPage> createState() => _RunPageState();
}

final class _RunPageState extends State<RunPage> {
  final _formKey = GlobalKey<FormState>();
  final _input = TextEditingController();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.controller.catalog.firstOrNull?.id;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.catalog
        .where((item) => item.id == _selectedId)
        .firstOrNull;
    final canSubmit =
        widget.controller.profile?.scopes.contains('jobs:create') ?? false;
    return PageFrame(
      title: 'Run a model',
      subtitle:
          'Choose a capability, review its cost, and submit bounded input.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Capability',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 920
                    ? 3
                    : (constraints.maxWidth >= 560 ? 2 : 1);
                final cardWidth =
                    (constraints.maxWidth - ((columns - 1) * 12)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final model in widget.controller.catalog)
                      SizedBox(
                        width: cardWidth,
                        child: _ModelCard(
                          model: model,
                          selected: model.id == _selectedId,
                          onTap: () => setState(() {
                            _selectedId = model.id;
                            _input.clear();
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (!canSubmit) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'This Commander can inspect capabilities but is not '
                          'authorized to submit jobs.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (selected != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        selected.inputLabel,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: ValueKey(selected.id),
                        controller: _input,
                        minLines: 5,
                        maxLines: 10,
                        maxLength: 8000,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: selected.inputHint,
                          helperText:
                              'Input is validated again by the Brain before dispatch.',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '${selected.inputLabel} is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.end,
                        spacing: 14,
                        runSpacing: 10,
                        children: [
                          Text(
                            '${selected.creditCost} credits',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          FilledButton.icon(
                            onPressed:
                                widget.controller.submitting || !canSubmit
                                ? null
                                : () => _submit(selected),
                            icon: widget.controller.submitting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              widget.controller.submitting
                                  ? 'Submitting…'
                                  : 'Submit job',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(ModelCapability model) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final job = await widget.controller.submitJob(
        JobRequest(capabilityId: model.id, input: _input.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller.profile?.mode == ConnectionMode.fixture
                ? '${job.id} queued in the local fixture. No network request was made.'
                : '${job.id} was accepted by the paired Brain.',
          ),
          action: SnackBarAction(
            label: 'View jobs',
            onPressed: widget.onJobCreated,
          ),
        ),
      );
      _input.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Job could not be submitted: $error')),
      );
    }
  }
}

final class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final ModelCapability model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: selected ? colors.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.kind.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, color: colors.primary, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                model.name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                model.summary,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Text('${model.creditCost} credits'),
            ],
          ),
        ),
      ),
    );
  }
}

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
          _StateIcon(state: job.state),
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
          Chip(label: Text(_jobStateLabel(job.state))),
        ],
      ),
    );
  }
}

final class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});
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

String _jobStateLabel(JobState state) => switch (state) {
  JobState.queued => 'Queued',
  JobState.running => 'Running',
  JobState.succeeded => 'Succeeded',
  JobState.failed => 'Failed',
};

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

final class BrainProfileDialog extends StatefulWidget {
  const BrainProfileDialog({required this.controller, super.key});
  final CommanderController controller;

  @override
  State<BrainProfileDialog> createState() => _BrainProfileDialogState();
}

final class _BrainProfileDialogState extends State<BrainProfileDialog> {
  final _enrollment = TextEditingController();
  String? _message;

  /// What just happened, when it is not a failure. Kept apart from [_message]
  /// so "removed, but still active on the Brain" does not read as an error the
  /// operator can ignore.
  String? _notice;
  bool _busy = false;

  @override
  void dispose() {
    _enrollment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listens, because switching or removing a pairing changes the very list
    // this dialog is showing.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _dialog(context),
    );
  }

  Widget _dialog(BuildContext context) {
    final profile = widget.controller.profile!;
    return AlertDialog(
      title: const Row(
        children: [
          EvaluetronMark(size: 34),
          SizedBox(width: 12),
          Expanded(child: Text('Brain profile')),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (profile.mode == ConnectionMode.fixture)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.science_outlined),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Fixture mode is active. Every value is deterministic '
                          'local test data and no Brain request is made.',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                profile.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              SelectableText(profile.identity),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final scope in profile.scopes)
                    Chip(
                      avatar: const Icon(Icons.key_outlined, size: 16),
                      label: Text(scope),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Connection path',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.https_outlined),
                      title: Text('Public signed HTTPS'),
                      subtitle: Text(
                        'Supported independently of managed networking.',
                      ),
                      trailing: Icon(Icons.check_circle_outline),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lan_outlined),
                      title: const Text('Managed Nebula'),
                      subtitle: Text(
                        _managedAvailabilityLabel(
                          widget.controller.managedNetworkCapability,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showManagedNetwork,
                    ),
                  ],
                ),
              ),
              if (widget.controller.strandedDevices.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Left on a Brain',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Commander created these devices but could not retire them. '
                  'It cannot revoke them now — only the Brain\'s own console '
                  'can, and only if it is given the id. Clear an entry once '
                  'you have done that.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final stranded in widget.controller.strandedDevices)
                  _StrandedDeviceRow(
                    device: stranded,
                    busy: _busy,
                    onClear: () => _clearStranded(stranded),
                  ),
              ],
              if (widget.controller.pairedBrains.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Paired Brains',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Every pairing kept on this device is a separate identity on '
                  'that Brain, and stays valid until it is removed here or '
                  'revoked from that Brain\'s console.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      for (final (index, brain)
                          in widget.controller.pairedBrains.indexed) ...[
                        if (index != 0) const Divider(height: 1),
                        _PairedBrainRow(
                          brain: brain,
                          busy: _busy,
                          onUse: () => _select(brain),
                          onRemove: () => _remove(brain),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Pair another Brain',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _enrollment,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Commander enrollment URI',
                  hintText: 'evaluetron-commander://pair?v=1&brain=…&token=…',
                  prefixIcon: Icon(Icons.qr_code_2),
                ),
              ),
              if (_cameraScanningSupported) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _scanEnrollment,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan pairing QR'),
                  ),
                ),
              ],
              if (_message case final message?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_notice case final notice?) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(notice)),
              ],
              const SizedBox(height: 12),
              Text(
                'The Brain origin and one-time token come from the protected '
                'operator console. Commander creates the private key locally '
                'and stores it only in the operating-system secure store.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (profile.mode == ConnectionMode.paired)
          TextButton(
            onPressed: _forgetPairing,
            child: const Text('Revoke and remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _pair,
          icon: const Icon(Icons.phonelink_lock),
          label: const Text('Pair securely'),
        ),
      ],
    );
  }

  Future<void> _pair() async {
    final enrollment = Uri.tryParse(_enrollment.text.trim());
    if (enrollment == null) {
      setState(() => _message = 'Enter a valid Commander enrollment URI.');
      return;
    }
    try {
      await widget.controller.pair(PairingRequest(enrollmentUri: enrollment));
      if (!mounted) return;
      final notice = widget.controller.takePairingNotice();
      Navigator.pop(context);
      // Retaining the previous pairing is the deliberate choice, but it leaves
      // a live identity on another Brain, so it must not be a silent one.
      if (notice != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    }
  }

  Future<void> _scanEnrollment() async {
    final scanned = await showDialog<String>(
      context: context,
      builder: (context) => const _EnrollmentScannerDialog(),
    );
    if (scanned == null || !mounted) return;
    _enrollment.text = scanned;
    setState(() => _message = null);
  }

  /// Removes the pairing in use. The list is authoritative about which one
  /// that is; the profile only stands in when a credential is stored but no
  /// longer readable.
  Future<void> _forgetPairing() async {
    final profile = widget.controller.profile!;
    final active =
        widget.controller.pairedBrains
            .where((brain) => brain.active)
            .firstOrNull ??
        PairedBrain(
          origin: profile.endpoint,
          deviceId: profile.identity,
          deviceLabel: profile.name,
          active: true,
        );
    final outcome = await _remove(active);
    if (!mounted) return;
    // Closes only when the removal was clean and no pairing is left to look
    // at. "Still active on the Brain" is the one message that must not
    // disappear with the dialog that raised it.
    if (outcome == PairingRemovalOutcome.revoked &&
        widget.controller.profile?.mode != ConnectionMode.paired) {
      Navigator.pop(context);
    }
  }

  /// Commands a different Brain this device is already paired to.
  Future<void> _select(PairedBrain brain) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.controller.selectPairedBrain(brain.origin);
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Revokes one pairing on its own Brain and deletes it from this device.
  /// Clears the local reminder only. The operator is asserting they have
  /// already retired the device from the Brain's console; nothing here can
  /// verify that, so the confirmation says so plainly.
  Future<void> _clearStranded(StrandedCommanderDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this reminder?'),
        content: Text(
          'Commander cannot revoke ${device.deviceId} and cannot check whether '
          'you have. Clearing removes the reminder from this device only. If '
          'the device is still active on ${device.origin.host}, it stays '
          'active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.controller.dismissStrandedDevice(device.deviceId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PairingRemovalOutcome> _remove(PairedBrain brain) async {
    setState(() {
      _busy = true;
      _message = null;
      _notice = null;
    });
    // An unreadable record cannot sign a revocation, so attempting the server
    // path first would only fail. Go straight to local removal; the notice
    // below still tells the operator the Brain may hold a live row.
    final result = brain.readable
        ? await removePairingWithOfflineFallback(
            context: context,
            brain: brain,
            removal: ({bool localOnly = false}) => widget.controller
                .removePairing(brain.origin, localOnly: localOnly),
          )
        : await removeUnreadablePairing(
            context: context,
            brain: brain,
            removal: () => widget.controller.removePairing(
              brain.origin,
              localOnly: true,
            ),
          );
    if (!mounted) return result.outcome;
    setState(() {
      _busy = false;
      _message = switch (result.outcome) {
        PairingRemovalOutcome.brainUnreachable ||
        PairingRemovalOutcome.refused ||
        PairingRemovalOutcome.failed => result.message,
        PairingRemovalOutcome.revoked ||
        PairingRemovalOutcome.consoleRevocationRequired => null,
      };
      _notice = switch (result.outcome) {
        PairingRemovalOutcome.revoked =>
          '${brain.origin.host} was revoked and removed from this device.',
        PairingRemovalOutcome.consoleRevocationRequired => brain.readable
            ? 'Removed from this device. Device ${brain.deviceId} is still '
                  'active on ${brain.origin.host} — revoke it from that '
                  'Brain\'s console.'
            : 'Removed from this device. This record could not be read, so any '
                  'device it held on ${brain.origin.host} must be found and '
                  'revoked from that Brain\'s console.',
        PairingRemovalOutcome.brainUnreachable ||
        PairingRemovalOutcome.refused ||
        PairingRemovalOutcome.failed => null,
      };
    });
    return result.outcome;
  }

  Future<void> _showManagedNetwork() {
    return showDialog<void>(
      context: context,
      builder: (context) => ManagedNetworkDialog(controller: widget.controller),
    );
  }
}

/// Removes a pairing, and only if the Brain could not be reached to revoke it,
/// offers to remove it from this device alone.
///
/// The server-side revocation is always attempted first and is never skipped
/// because it might fail: a credential that can still be revoked must be. The
/// offline path exists so that a Brain which is down, unreachable, or refusing
/// its own certificate cannot leave the operator with a device they are unable
/// to clear.
/// Removes a stored record that no longer parses.
///
/// There is no server attempt to make: the record cannot sign a revocation, so
/// trying would only produce a failure the operator can do nothing with. The
/// confirmation is still required, because deleting it gives up the last local
/// trace of whatever device it held.
Future<PairingRemovalResult> removeUnreadablePairing({
  required BuildContext context,
  required PairedBrain brain,
  required Future<PairingRemovalResult> Function() removal,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _LocalRemovalDialog(
      brain: brain,
      reason:
          'This record cannot be read, so Commander cannot revoke it. Removing '
          'it clears this device only.',
    ),
  );
  if (confirmed != true) {
    return (outcome: PairingRemovalOutcome.refused, message: null);
  }
  return removal();
}

Future<PairingRemovalResult> removePairingWithOfflineFallback({
  required BuildContext context,
  required PairedBrain? brain,
  required Future<PairingRemovalResult> Function({bool localOnly}) removal,
}) async {
  final attempt = await removal();
  if (attempt.outcome != PairingRemovalOutcome.brainUnreachable ||
      !context.mounted) {
    return attempt;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _LocalRemovalDialog(brain: brain, reason: attempt.message),
  );
  if (confirmed != true) return attempt;
  return removal(localOnly: true);
}

final class _LocalRemovalDialog extends StatelessWidget {
  const _LocalRemovalDialog({required this.brain, required this.reason});

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

final class _PairedBrainRow extends StatelessWidget {
  const _PairedBrainRow({
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

String _managedAvailabilityLabel(ManagedNetworkCapability capability) {
  return switch (capability.availability) {
    ManagedNetworkAvailability.available =>
      'Native engine available; enrollment is still required.',
    ManagedNetworkAvailability.engineNotInstalled =>
      'Optional · native engine not embedded in this build.',
    ManagedNetworkAvailability.unsupportedPlatform =>
      'Optional · unavailable on this platform build.',
  };
}

String _tunnelLifecycleLabel(TunnelLifecycle lifecycle) {
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
                    label: Text(_tunnelLifecycleLabel(tunnel.lifecycle)),
                  ),
                  Chip(label: Text(capability.platform)),
                  if (capability.consentRequired)
                    const Chip(label: Text('System consent required')),
                ],
              ),
              const SizedBox(height: 12),
              Text(_managedAvailabilityLabel(capability)),
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

bool get _cameraScanningSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

final class _EnrollmentScannerDialog extends StatefulWidget {
  const _EnrollmentScannerDialog();

  @override
  State<_EnrollmentScannerDialog> createState() =>
      _EnrollmentScannerDialogState();
}

final class _EnrollmentScannerDialogState
    extends State<_EnrollmentScannerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan pairing QR'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(
            onDetect: (capture) {
              if (_accepted) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue)
                  .whereType<String>()
                  .where(
                    (candidate) =>
                        candidate.startsWith('evaluetron-commander://pair?'),
                  )
                  .firstOrNull;
              if (value == null) return;
              _accepted = true;
              Navigator.pop(context, value);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// One device row this app left active on a Brain.
final class _StrandedDeviceRow extends StatelessWidget {
  const _StrandedDeviceRow({
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
