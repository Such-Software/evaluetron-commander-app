import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/fixture_brain_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CommanderApp(client: FixtureBrainClient()));
}
