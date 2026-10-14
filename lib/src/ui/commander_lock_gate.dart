import 'dart:async';

import 'package:flutter/material.dart';

import '../brand.dart';
import '../domain/brain_client.dart';
import '../security/local_auth_gate.dart';
import '../state/commander_controller.dart';

/// Re-locks the operator session whenever Commander leaves the foreground.
///
/// The launch-time gate lives in `CommanderBrainClient`, which refuses to
/// activate a stored credential without a user-presence proof. This widget
/// covers the other half: a device handed over while Commander is already
/// running and unlocked.
///
/// Only a paired session is re-locked. Fixture mode carries no operator
/// authority, so prompting there would train operators to dismiss the prompt
/// without protecting anything.
final class CommanderLockGate extends StatefulWidget {
  const CommanderLockGate({
    required this.controller,
    required this.localAuth,
    required this.child,
    super.key,
  });

  final CommanderController controller;
  final LocalAuthGate localAuth;
  final Widget child;

  @override
  State<CommanderLockGate> createState() => _CommanderLockGateState();
}

final class _CommanderLockGateState extends State<CommanderLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authenticating = false;

  String? _refusal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _protectsAuthority =>
      widget.controller.profile?.mode == ConnectionMode.paired;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `paused` means the app is genuinely backgrounded. `inactive` also
      // fires for transient system overlays — including the authentication
      // prompt itself — so locking on it would deadlock the unlock.
      case AppLifecycleState.paused:
        if (_protectsAuthority && !_locked && !_authenticating) {
          setState(() {
            _locked = true;
            _refusal = null;
          });
        }
      case AppLifecycleState.resumed:
        if (_locked && !_authenticating) unawaited(_unlock());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _refusal = null;
    });
    try {
      final outcome = await widget.localAuth.authenticate(
        PrivilegedAction.unlockSession,
      );
      if (!mounted) return;
      setState(() {
        _locked = !localAuthPermits(outcome);
        _refusal = _locked
            ? localAuthRefusal(PrivilegedAction.unlockSession, outcome).message
            : null;
      });
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return _LockedScreen(
        busy: _authenticating,
        refusal: _refusal,
        onUnlock: _unlock,
      );
    }
    return widget.child;
  }
}

final class _LockedScreen extends StatelessWidget {
  const _LockedScreen({
    required this.busy,
    required this.refusal,
    required this.onUnlock,
  });

  final bool busy;
  final String? refusal;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
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
                  'Commander is locked',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This device holds operator authority over the fleet. '
                  'Confirm it is you before continuing.',
                  textAlign: TextAlign.center,
                ),
                if (refusal case final message?) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : onUnlock,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open),
                  label: Text(busy ? 'Verifying…' : 'Unlock Commander'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
