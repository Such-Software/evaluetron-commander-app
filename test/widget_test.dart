import 'package:evaluetron_commander_app/src/app.dart';
import 'package:evaluetron_commander_app/src/data/fixture_brain_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone shell visibly identifies fixture data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(CommanderApp(client: FixtureBrainClient()));
    await tester.pumpAndSettle();

    expect(find.text('Good afternoon'), findsOneWidget);
    expect(find.text('Fixture'), findsWidgets);
    expect(find.text('Active jobs'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('Run a model'), findsOneWidget);
    expect(find.text('Grounded Answer'), findsOneWidget);
  });

  testWidgets('desktop shell supports navigation and local job submission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(CommanderApp(client: FixtureBrainClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Create a bounded fixture response.',
    );
    await tester.tap(find.text('Submit job'));
    await tester.pumpAndSettle();

    expect(find.textContaining('queued in the local fixture'), findsOneWidget);
    expect(find.textContaining('No network request was made'), findsOneWidget);
  });

  testWidgets('pairing fails closed when no live transport is installed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(CommanderApp(client: FixtureBrainClient()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Brain profile'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no live API or credential store'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Short-lived pairing code'),
      'ABCD-1234',
    );
    await tester.tap(find.text('Pair securely'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no live Brain transport'), findsOneWidget);
  });
}
