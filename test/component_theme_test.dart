import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/theme/component_theme.dart';
import 'package:pomgt/core/widgets/status_pill.dart';

void main() {
  // Run on Chrome too: native tests do not exercise DDC icon initialization.
  testWidgets('component themes initialize and render a status badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PomgtComponentTheme(child: child!),
        home: const Scaffold(body: Center(child: StatusPill('draft'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Borrador'), findsOneWidget);
  });
}
