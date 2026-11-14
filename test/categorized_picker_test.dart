import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/widgets/categorized_picker.dart';

void main() {
  const items = [
    PickerItem(id: '1', label: 'ETI · ETIQUETA BLANCA', category: 'Etiquetas'),
    PickerItem(id: '2', label: 'ETI2 · ETIQUETA NEGRA', category: 'Etiquetas'),
    PickerItem(id: '3', label: 'CAJ · CAJA GRANDE', category: 'Empaques'),
  ];

  Widget host(ValueChanged<String?> onChanged, {String? value}) => MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: CategorizedSearchPicker(
          label: 'Producto',
          items: items,
          value: value,
          onChanged: onChanged,
        ),
      ),
    ),
  );

  testWidgets(
    'opens the first category and allows expanding another before selection',
    (tester) async {
      String? picked;
      await tester.pumpWidget(host((v) => picked = v));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text('Etiquetas'), findsOneWidget);
      expect(find.text('Empaques'), findsOneWidget);
      expect(find.text('ETI · ETIQUETA BLANCA'), findsNothing);
      expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);

      await tester.tap(find.text('Etiquetas'));
      await tester.pumpAndSettle();
      expect(find.text('ETI · ETIQUETA BLANCA'), findsOneWidget);
      expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);

      await tester.tap(find.text('ETI · ETIQUETA BLANCA'));
      await tester.pumpAndSettle();
      expect(picked, '1');
    },
  );

  testWidgets('typing filters items and opens their category', (tester) async {
    await tester.pumpWidget(host((_) {}));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'caja');
    await tester.pumpAndSettle();

    expect(find.text('CAJ · CAJA GRANDE'), findsOneWidget);
    expect(find.text('ETI · ETIQUETA BLANCA'), findsNothing);
    expect(find.text('Etiquetas'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsOneWidget);
  });
}
