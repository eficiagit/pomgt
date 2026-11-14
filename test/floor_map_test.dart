import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/theme/pomgt_theme.dart';
import 'package:pomgt/data/repositories/production_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:pomgt/features/floor_map/floor_map_data.dart';
import 'package:pomgt/features/floor_map/floor_map_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

FloorRow snapshot() => {
  'machines': [
    {
      'id': 'm1',
      'name': 'Prensa industrial',
      'machine_code': 'PRE-1',
      'status': 'available',
      'is_active': true,
      'serial_number': 'SERIE-COMPLETA',
      'capacity': '50 toneladas',
      'voltage': '220 V',
      'description': 'Prensa de pruebas',
      'setup_hourly_cost': 150,
      'floor_pos_x': 80.0,
      'floor_pos_y': 100.0,
    },
    {
      'id': 'm2',
      'name': 'Impresora',
      'machine_code': 'IMP-1',
      'status': 'maintenance',
      'floor_pos_x': 480.0,
      'floor_pos_y': 100.0,
    },
  ],
  'operations': [
    {
      'id': 'a',
      'machine_id': 'm1',
      'production_order_id': 'o1',
      'sequence_no': 1,
      'name': 'Corte inicial',
      'status': 'in_progress',
    },
    {
      'id': 'b',
      'machine_id': 'm1',
      'production_order_id': 'o2',
      'sequence_no': 1,
      'name': 'Corte especial',
      'status': 'in_progress',
    },
    {
      'id': 'c',
      'machine_id': 'm2',
      'production_order_id': 'o1',
      'sequence_no': 2,
      'name': 'Imprimir',
      'status': 'pending',
    },
  ],
  'orders': [
    {
      'id': 'o1',
      'op_number': 'OP-UNO',
      'product_id': 'p1',
      'product_name': 'Producto uno',
      'status': 'in_progress',
      'planned_quantity': 100,
      'progress_pct': 20,
    },
    {
      'id': 'o2',
      'op_number': 'OP-DOS',
      'product_id': 'p2',
      'product_name': 'Producto dos',
      'status': 'in_progress',
      'planned_quantity': 20,
    },
  ],
  'products': [
    {
      'id': 'p1',
      'sku': 'MP-1',
      'name': 'Papel',
      'product_type': 'raw_material',
      'base_uom_id': 'u1',
    },
    {
      'id': 'p2',
      'sku': 'PT-1',
      'name': 'Caja',
      'product_type': 'finished_good',
      'base_uom_id': 'u1',
    },
  ],
  'units': [
    {'id': 'u1', 'name': 'Piezas', 'symbol': 'pz'},
  ],
  'inventory_available': true,
  'warehouses': [
    {'id': 'w1', 'name': 'Almacén principal', 'code': 'ALM', 'is_active': true},
  ],
  'inventory_stock': [
    {
      'id': 's1',
      'warehouse_id': 'w1',
      'product_id': 'p1',
      'quantity_on_hand': 25,
      'uom_id': 'u1',
    },
  ],
  'floor_zones': [],
  'inventory_movements': [],
};

class FakeFloorRepository extends ProductionRepository {
  FakeFloorRepository(SupabaseClient client)
    : super(SupabaseDatabaseService(client), client);
  int snapshots = 0, details = 0, saves = 0;
  Object? snapshotError, positionError;
  Completer<void>? inventoryWrite;
  final List<FloorRow> inventoryRequests = [];
  final Map<String, Completer<FloorRow>> pendingDetails = {};
  Offset? savedPosition;
  @override
  Future<FloorRow> floorSnapshot() async {
    snapshots++;
    if (snapshotError != null) throw snapshotError!;
    return snapshot();
  }

  @override
  Future<FloorRow> floorOrderDetail(String id) => detail(id);
  @override
  Future<FloorRow> detail(String id) async {
    details++;
    if (pendingDetails.containsKey(id)) return pendingDetails[id]!.future;
    return {
      'order': {'id': id, 'op_number': id == 'o1' ? 'OP-UNO' : 'OP-DOS'},
      'materials': [
        {
          'id': 'mat-$id',
          'material_product_id': 'p1',
          'required_quantity': 100,
          'issued_quantity': details,
          'consumed_quantity': 0,
          'uom_id': 'u1',
        },
      ],
    };
  }

  @override
  Future<void> updateMachinePosition(String id, double x, double y) async {
    saves++;
    savedPosition = Offset(x, y);
    if (positionError != null) throw positionError!;
  }

  @override
  Future<FloorRow> floorProductDetail(String id) async => {
    'revisions': [
      {
        'id': 'rev-1',
        'revision_code': 'V3',
        'status': 'active',
        'description': 'Especificación completa',
      },
    ],
  };
  @override
  Future<void> recordFloorInventoryMovement({
    required String warehouseId,
    required String productId,
    required String movementType,
    required double quantity,
    required String requestId,
    String? notes,
    String? materialId,
  }) async {
    inventoryRequests.add({
      'warehouse': warehouseId,
      'product': productId,
      'type': movementType,
      'quantity': quantity,
      'request': requestId,
      'material': materialId,
    });
    if (inventoryWrite != null) await inventoryWrite!.future;
  }
}

void main() {
  const preview = String.fromEnvironment('POMGT_FLOOR_PREVIEW');
  setUpAll(() async {
    if (preview.isEmpty) return;
    final fonts = FontLoader(PomgtTypography.body);
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/IBMPlexSans-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late SupabaseClient client;
  late FakeFloorRepository repository;
  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test');
    repository = FakeFloorRepository(client);
  });
  tearDown(() => client.dispose());
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1500, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPomgtTheme(),
        home: RepaintBoundary(
          key: const ValueKey('floor-preview'),
          child: FloorMapScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  test('indexes concurrent operations without discarding either order', () {
    final data = FloorData(snapshot());
    expect(data.activeOn('m1').map((o) => o['id']), ['a', 'b']);
    expect(data.status(data.machines.first), 'busy');
    expect(data.operationsByOrder['o1']!.map((o) => o['id']), ['a', 'c']);
    expect(data.status(data.machines.last), 'maintenance');
    expect(
      floorMachineStatus({'is_active': false, 'status': 'available'}, []),
      'inactive',
    );
  });
  test('bounds include distant equipment, warehouses and zones', () {
    final raw = snapshot();
    raw['floor_zones'] = [
      {'id': 'z', 'x': 5000.0, 'y': 7000.0, 'width': 800.0, 'height': 400.0},
    ];
    final data = FloorData(raw);
    final bounds = data.bounds({'machine:m1': const Offset(9000, 100)});
    expect(bounds.width, greaterThan(9200));
    expect(bounds.height, greaterThan(7400));
  });
  testWidgets('preserves zoom and pan during refresh and selection', (
    tester,
  ) async {
    await mount(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final transform = viewer.transformationController!;
    transform.value = Matrix4.identity()
      ..translateByDouble(-50.0, -20.0, 0, 1)
      ..scaleByDouble(.8, .8, 1, 1);
    final expected = transform.value.clone();
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(repository.snapshots, 2);
    expect(
      identical(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController,
        transform,
      ),
      isTrue,
    );
    expect(transform.value, expected);
    await tester.tap(find.text('Prensa industrial').first);
    await tester.pumpAndSettle();
    expect(transform.value, expected);
    expect(
      find.text('Corte inicial', findRichText: true),
      findsNothing,
    ); // step includes its sequence number
    expect(find.text('1. Corte inicial'), findsOneWidget);
    expect(find.text('1. Corte especial'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('shows previously omitted machine fields', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Prensa industrial').first);
    await tester.pumpAndSettle();
    expect(find.text('SERIE-COMPLETA'), findsOneWidget);
    expect(find.text('50 toneladas'), findsOneWidget);
    expect(find.text('220 V'), findsOneWidget);
    expect(find.text('Prensa de pruebas'), findsOneWidget);
    if (preview.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('floor-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(preview).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('selected order materials refresh with the floor snapshot', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Órdenes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OP-UNO').first);
    await tester.pumpAndSettle();
    expect(repository.details, 1);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(repository.details, 2);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('late order response cannot replace the newly selected order', (
    tester,
  ) async {
    repository.pendingDetails['o1'] = Completer<FloorRow>();
    await mount(tester);
    await tester.tap(find.text('Órdenes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OP-UNO').first);
    await tester.pump();
    await tester.tap(find.text('OP-DOS').first);
    await tester.pumpAndSettle();
    repository.pendingDetails['o1']!.complete({
      'order': {'notes': 'RESPUESTA OBSOLETA'},
    });
    await tester.pumpAndSettle();
    expect(find.text('RESPUESTA OBSOLETA'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('phone layout and detail panel have no overflow', (tester) async {
    await mount(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Prensa industrial').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Minimizar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('failed polling retains last map and reports stale connection', (
    tester,
  ) async {
    await mount(tester);
    repository.snapshotError = StateError('Sin conexión');
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Prensa industrial'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets('moving equipment at zoom saves local world coordinates', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Acomodar plano'));
    await tester.pumpAndSettle();
    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    transform.value = Matrix4.identity()..scaleByDouble(.5, .5, 1, 1);
    await tester.pump();
    await tester.drag(
      find.text('Prensa industrial').first,
      const Offset(50, 30),
    );
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(repository.savedPosition!.dx, closeTo(180, 2));
    expect(repository.savedPosition!.dy, closeTo(160, 2));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
  testWidgets(
    'inventory dialog blocks double submit and refreshes after saving',
    (tester) async {
      repository.inventoryWrite = Completer<void>();
      await mount(tester);
      await tester.tap(find.text('Almacenes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movimiento').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cantidad'),
        '1,250.5',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      expect(repository.inventoryRequests, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardando…'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.inventoryRequests.single['quantity'], 1250.5);
      expect(repository.inventoryRequests.single['warehouse'], 'w1');
      final reads = repository.snapshots;
      repository.inventoryWrite!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.snapshots, greaterThan(reads));
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'product specifications can be consulted without leaving the map',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Productos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MP-1 · Papel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Especificaciones y fabricación').first,
      );
      await tester.tap(find.text('Especificaciones y fabricación').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisiones (1)'));
      await tester.pumpAndSettle();
      expect(find.text('V3'), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'slow order detail requests are coalesced across background polls',
    (tester) async {
      repository.pendingDetails['o1'] = Completer<FloorRow>();
      await mount(tester);
      await tester.tap(find.text('Órdenes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OP-UNO').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(repository.details, 1);
      repository.pendingDetails['o1']!.complete({
        'order': {'id': 'o1'},
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );
  testWidgets(
    'failed position write restores the last saved machine location',
    (tester) async {
      repository.positionError = StateError('No fue posible guardar');
      await mount(tester);
      await tester.tap(find.text('Acomodar plano'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Prensa industrial').first,
        const Offset(80, 40),
      );
      await tester.pumpAndSettle();
      final positioned = tester.widget<Positioned>(
        find.byKey(const ValueKey('machine:m1')),
      );
      expect(positioned.left, 80);
      expect(positioned.top, 100);
      expect(repository.saves, 1);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await unmount(tester);
    },
  );
}
