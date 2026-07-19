import 'package:flutter/material.dart';

import 'domain/brain_client.dart';
import 'network/managed_network.dart';
import 'state/commander_controller.dart';
import 'ui/commander_shell.dart';

final class CommanderApp extends StatefulWidget {
  const CommanderApp({
    required this.client,
    this.managedNetwork = const UnavailableManagedNetworkPlatform(),
    super.key,
  });

  final BrainClient client;
  final ManagedNetworkPlatform managedNetwork;

  @override
  State<CommanderApp> createState() => _CommanderAppState();
}

final class _CommanderAppState extends State<CommanderApp> {
  late final CommanderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CommanderController(widget.client, widget.managedNetwork)
      ..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff415f91);
    return MaterialApp(
      title: 'Evaluetron Commander',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, seed),
      home: CommanderShell(controller: _controller),
    );
  }
}

ThemeData _theme(Brightness brightness, Color seed) {
  final colors = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: .48),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
  );
}
