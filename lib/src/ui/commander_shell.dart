import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/brain_client.dart';
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
          return _FailureView(error: error, retry: widget.controller.load);
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
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ProductMark(),
                          SizedBox(width: 12),
                          Text(
                            'COMMANDER',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      )
                    : const _ProductMark(),
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
      title: Row(
        children: [
          const _ProductMark(size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(_destinations[_index].label)),
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

final class _ProductMark extends StatelessWidget {
  const _ProductMark({this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Evaluetron Commander',
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.tertiary,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(size * .3),
          ),
          child: Icon(
            Icons.hub_outlined,
            size: size * .58,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
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
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

final class _FailureView extends StatelessWidget {
  const _FailureView({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

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
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Commander could not load',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
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
          'A calm, scoped view of this Brain and the work it coordinates.',
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
                    label: 'Credits',
                    value: '${overview.credits}',
                    icon: Icons.toll_outlined,
                  ),
                  _MetricCard(
                    width: itemWidth,
                    label: 'Success · 24h',
                    value:
                        '${(overview.successRate * 100).toStringAsFixed(1)}%',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
                            onPressed: widget.controller.submitting
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
            '${job.id} queued in the local fixture. No network request was made.',
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
  final _endpoint = TextEditingController(text: 'https://brain.example.com');
  final _deviceLabel = TextEditingController(text: 'My Commander');
  final _pairingCode = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _endpoint.dispose();
    _deviceLabel.dispose();
    _pairingCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile!;
    return AlertDialog(
      title: const Row(
        children: [
          _ProductMark(size: 34),
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
                        'local test data; no live API or credential store is '
                        'implemented in this build.',
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
              const SizedBox(height: 24),
              Text(
                'Pair another Brain',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _endpoint,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
                decoration: const InputDecoration(
                  labelText: 'HTTPS Brain endpoint',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deviceLabel,
                decoration: const InputDecoration(
                  labelText: 'Device label',
                  prefixIcon: Icon(Icons.devices),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairingCode,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Short-lived pairing code',
                  prefixIcon: Icon(Icons.password),
                ),
              ),
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
              const SizedBox(height: 12),
              Text(
                'Production pairing must pin the expected Brain origin, create '
                'a device key in platform secure storage, exchange the code '
                'once, and request only approved scopes.',
                style: Theme.of(context).textTheme.bodySmall,
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
        FilledButton.icon(
          onPressed: _pair,
          icon: const Icon(Icons.phonelink_lock),
          label: const Text('Pair securely'),
        ),
      ],
    );
  }

  Future<void> _pair() async {
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      setState(() => _message = 'Enter a valid HTTPS Brain endpoint.');
      return;
    }
    if (_deviceLabel.text.trim().isEmpty || _pairingCode.text.trim().isEmpty) {
      setState(() => _message = 'Device label and pairing code are required.');
      return;
    }
    try {
      await widget.controller.pair(
        PairingRequest(
          endpoint: endpoint,
          deviceLabel: _deviceLabel.text.trim(),
          pairingCode: _pairingCode.text.trim(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = '$error');
    }
  }
}
