import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/widgets/categorized_picker.dart';

void main() {
  const items = [
    PickerItem(id: '1', label: 'ETI · ETIQUETA BLANCA', category: 'Etiquetas'),
    PickerItem(id: '2', label: 'ETI2 · ETIQUETA NEGRA', category: 'Etiquetas'),
    PickerItem(id: '3', label: 'CAJ · CAJA GRANDE', category: 'Empaques'),
  ];

  Widget host(Set<String> selected, ValueChanged<String> onToggle) =>
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: MultiCategorizedPicker(
              label: 'Buscar producto',
              items: items,
              selectedIds: selected,
              onToggle: onToggle,
            ),
          ),
        ),
      );

  testWidgets('checking items keeps the dropdown open for more picks', (
    tester,
  ) async {
    final selected = <String>{};
    await tester.pumpWidget(
      host(selected, (id) {
        if (!selected.add(id)) selected.remove(id);
      }),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text('ETI · ETIQUETA BLANCA'), findsOneWidget);
    expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);

    await tester.tap(find.text('ETI · ETIQUETA BLANCA'));
    await tester.pump();
    expect(selected, {'1'});
    // The overlay is still open (not dismissed by the pick).
    expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);

    await tester.tap(find.text('CAJ · CAJA GRANDE'));
    await tester.pump();
    expect(selected, {'1', '3'});
  });

  testWidgets('typing filters the overlay list', (tester) async {
    final selected = <String>{};
    await tester.pumpWidget(host(selected, (id) => selected.add(id)));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'caja');
    await tester.pump();

    expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);
    expect(find.text('ETI · ETIQUETA BLANCA'), findsNothing);
  });
}
