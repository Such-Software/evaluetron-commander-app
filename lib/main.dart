import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/commander_brain_client.dart';
import 'src/security/secure_credential_vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = PlatformSecureCredentialVault(FlutterSecureStorageAdapter());
  runApp(CommanderApp(client: CommanderBrainClient(vault: vault)));
}
