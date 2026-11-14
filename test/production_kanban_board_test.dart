import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/features/production/production_screen.dart';

void main() {
  final orders = [
    {
      'id': 'op-1',
      'op_number': 'OP-00001',
      'status': 'ready',
      'priority': 'urgent',
      'product_sku': 'ETI',
      'product_name': 'ETIQUETA BLANCA',
      'planned_quantity': 80000,
      'progress_pct': 0,
      'uom_symbol': 'pz',
    },
    {
      'id': 'op-2',
      'op_number': 'OP-00002',
      'status': 'in_progress',
      'priority': 'normal',
      'product_sku': 'CAJ',
      'product_name': 'CAJA GRANDE',
      'planned_quantity': 500,
      'progress_pct': 40,
      'uom_symbol': 'pz',
    },
  ];

  Widget host({
    required void Function(String, String) onTransition,
    void Function(String)? onOpen,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        // The board shows all 7 status columns side by side (300px each);
        // the default 800x600 test surface is too narrow to reach the
        // rightmost ones, so widen the surface for every test below.
        width: 2600,
        height: 900,
        child: ProductionKanbanBoard(
          orders: orders,
          search: '',
          onSearch: (_) {},
          onOpen: onOpen ?? (_) {},
          onTransition: (id, status) async => onTransition(id, status),
          onError: (_) {},
        ),
      ),
    ),
  );

  Future<void> widenSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders a column per status with the right card counts', (
    tester,
  ) async {
    await widenSurface(tester);
    await tester.pumpWidget(host(onTransition: (_, _) {}));
    await tester.pumpAndSettle();

    expect(find.text('OP-00001'), findsOneWidget);
    expect(find.text('OP-00002'), findsOneWidget);
    // 7 status columns, 2 of them holding exactly one card, the rest empty.
    expect(find.text('Sin órdenes'), findsNWidgets(5));
  });

  testWidgets('tapping a card calls onOpen with its id', (tester) async {
    await widenSurface(tester);
    String? opened;
    await tester.pumpWidget(
      host(onTransition: (_, _) {}, onOpen: (id) => opened = id),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('OP-00001'));
    await tester.pumpAndSettle();
    expect(opened, 'op-1');
  });

  testWidgets('dragging a card to another column transitions its status', (
    tester,
  ) async {
    await widenSurface(tester);
    final calls = <List<String>>[];
    await tester.pumpWidget(
      host(onTransition: (id, status) => calls.add([id, status])),
    );
    await tester.pumpAndSettle();

    final cardCenter = tester.getCenter(find.text('OP-00001'));
    // "En producción" column, where OP-00002 already lives.
    final targetCenter = tester.getCenter(find.text('OP-00002'));

    await tester.drag(find.text('OP-00001'), targetCenter - cardCenter);
    await tester.pumpAndSettle();

    expect(calls, [
      ['op-1', 'in_progress'],
    ]);
  });

  testWidgets('dropping a card back on its own column is a no-op', (
    tester,
  ) async {
    await widenSurface(tester);
    final calls = <List<String>>[];
    await tester.pumpWidget(
      host(onTransition: (id, status) => calls.add([id, status])),
    );
    await tester.pumpAndSettle();

    final cardCenter = tester.getCenter(find.text('OP-00001'));
    final gesture = await tester.startGesture(cardCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(cardCenter + const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
  });
}
