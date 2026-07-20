import 'package:flutter/material.dart';

import 'brand.dart';
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
    return MaterialApp(
      title: 'Evaluetron Commander',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildCommanderTheme(Brightness.light),
      darkTheme: buildCommanderTheme(Brightness.dark),
      home: CommanderShell(controller: _controller),
    );
  }
}

ThemeData buildCommanderTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: CommanderBrand.accent,
        brightness: brightness,
        surface: dark ? const Color(0xFF0F131D) : CommanderBrand.lightSurface,
      ).copyWith(
        primary: dark ? CommanderBrand.accent : const Color(0xFF4058C7),
        tertiary: dark ? CommanderBrand.signal : const Color(0xFF7A4B00),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: dark
        ? CommanderBrand.voidColor
        : CommanderBrand.lightSurface,
    visualDensity: VisualDensity.standard,
    textTheme: Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
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
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: colors.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      selectedIconTheme: IconThemeData(color: colors.onPrimaryContainer),
      selectedLabelTextStyle: TextStyle(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
