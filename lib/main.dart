import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/commander_brain_client.dart';
import 'src/network/platform_managed_network.dart';
import 'src/security/local_auth_gate.dart';
import 'src/security/secure_credential_vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = PlatformSecureCredentialVault(FlutterSecureStorageAdapter());
  final localAuth = PlatformLocalAuthGate();
  runApp(
    CommanderApp(
      client: CommanderBrainClient(vault: vault, localAuth: localAuth),
      localAuth: localAuth,
      managedNetwork: const MethodChannelManagedNetworkPlatform(),
    ),
  );
}
