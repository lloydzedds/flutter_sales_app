import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/app_settings_controller.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('app renders a provided home widget', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        controller: AppSettingsController.instance,
        home: const Scaffold(body: Center(child: Text('Test Home'))),
      ),
    );
    await tester.pump();

    expect(find.text('Test Home'), findsOneWidget);
  });
}
