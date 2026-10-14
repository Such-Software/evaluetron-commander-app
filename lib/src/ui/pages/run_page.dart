// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../domain/brain_client.dart';
import '../../state/commander_controller.dart';
import '../widgets/page_frame.dart';

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
