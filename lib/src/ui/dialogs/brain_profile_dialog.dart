// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/material.dart';

import '../../brand.dart';
import '../../domain/brain_client.dart';
import '../../state/commander_controller.dart';
import 'enrollment_scanner_dialog.dart';
import 'paired_brain_rows.dart';
import 'managed_network_dialog.dart';

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
                        managedAvailabilityLabel(
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
                  StrandedDeviceRow(
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
                        PairedBrainRow(
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
              if (cameraScanningSupported) ...[
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
      builder: (context) => const EnrollmentScannerDialog(),
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
            removal: () =>
                widget.controller.removePairing(brain.origin, localOnly: true),
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
        PairingRemovalOutcome.consoleRevocationRequired =>
          brain.readable
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
    builder: (context) => LocalRemovalDialog(
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
        LocalRemovalDialog(brain: brain, reason: attempt.message),
  );
  if (confirmed != true) return attempt;
  return removal(localOnly: true);
}
