import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/features/production/production_operator_display.dart';
import 'package:pomgt/data/repositories/production_repository.dart';
import 'package:pomgt/data/repositories/routing_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:pomgt/data/utils/operation_materials.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemoryDatabase extends SupabaseDatabaseService {
  MemoryDatabase(super.client, this.tables);
  final Map<String, List<Map<String, dynamic>>> tables;

  @override
  Future<List<Map<String, dynamic>>> list(
    String table, {
    String select = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
    int limit = 500,
  }) async => (tables[table] ?? [])
      .where(
        (row) => equals.entries.every((entry) => row[entry.key] == entry.value),
      )
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  @override
  Future<List<Map<String, dynamic>>> listAll(
    String table, {
    Map<String, dynamic> equals = const {},
    Map<String, List<String>> within = const {},
    int pageSize = 500,
  }) async => (await list(table, equals: equals))
      .where(
        (row) => within.entries.every(
          (e) => e.value.contains(row[e.key]?.toString()),
        ),
      )
      .toList();

  @override
  Future<List<Map<String, dynamic>>> listIn(
    String table,
    String column,
    Iterable<String> values, {
    String select = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
    int limit = 1000,
  }) async {
    final ids = values.toSet();
    final rows = (await list(
      table,
      equals: equals,
    )).where((row) => ids.contains(row[column]?.toString())).toList();
    if (orderBy != null) {
      rows.sort((a, b) {
        final av = a[orderBy], bv = b[orderBy];
        final result = av is num && bv is num
            ? av.compareTo(bv)
            : '${av ?? ''}'.compareTo('${bv ?? ''}');
        return ascending ? result : -result;
      });
    }
    return rows.take(limit).toList();
  }

  @override
  Future<Map<String, dynamic>?> one(
    String table,
    String id, {
    String select = '*',
  }) async {
    for (final row in tables[table] ?? <Map<String, dynamic>>[]) {
      if (row['id'] == id) return Map<String, dynamic>.from(row);
    }
    return null;
  }
}

class WritableMemoryDatabase extends MemoryDatabase {
  WritableMemoryDatabase(super.client, super.tables);
  final writes = <String>[];
  bool missingPrepareRpc = false;

  @override
  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> values,
  ) async {
    writes.add(table);
    final row = tables[table]!.firstWhere((row) => row['id'] == id);
    row.addAll(values);
    return Map.from(row);
  }

  @override
  Future<List<Map<String, dynamic>>> insertMany(
    String table,
    List<Map<String, dynamic>> values,
  ) async {
    writes.add(table);
    final rows = [
      for (var i = 0; i < values.length; i++) {'id': '$table-$i', ...values[i]},
    ];
    tables.putIfAbsent(table, () => []).addAll(rows);
    return rows;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    if (function != 'prepare_production_order') throw StateError(function);
    if (missingPrepareRpc) {
      throw StateError(
        'Could not find the function prepare_production_order in the schema cache',
      );
    }
    return update('production_orders', params!['p_order_id'].toString(), {
      'status': 'ready',
    });
  }
}

class AuthenticatedProductionRepository extends ProductionRepository {
  AuthenticatedProductionRepository(super.service, super.client);
  @override
  String get userId => 'test-user';
}

class DisplayRepository extends ProductionRepository {
  DisplayRepository(SupabaseClient client, this.data)
    : super(MemoryDatabase(client, {}), client);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> detail(String orderId) async => data;
}

void main() {
  late SupabaseClient client;
  setUp(
    () => client = SupabaseClient('https://example.supabase.co', 'test-key'),
  );
  tearDown(() => client.dispose());

  final products = <String, Map<String, dynamic>>{
    'paper-a': {'id': 'paper-a', 'material_type_id': 'paper'},
    'paper-b': {'id': 'paper-b', 'material_type_id': 'paper'},
    'ink': {'id': 'ink', 'material_type_id': 'ink'},
  };
  final materials = <Map<String, dynamic>>[
    {
      'id': 'm1',
      'bom_item_id': 'b1',
      'material_product_id': 'paper-a',
      'required_quantity': 40,
      'uom_id': 'kg',
    },
    {
      'id': 'm2',
      'bom_item_id': 'b2',
      'material_product_id': 'paper-b',
      'required_quantity': 20,
      'uom_id': 'kg',
    },
    {
      'id': 'm3',
      'bom_item_id': 'b3',
      'material_product_id': 'paper-a',
      'required_quantity': 10,
      'uom_id': 'kg',
    },
    {
      'id': 'm4',
      'bom_item_id': 'b4',
      'material_product_id': 'ink',
      'required_quantity': 2,
      'uom_id': 'l',
    },
  ];

  WritableMemoryDatabase unpreparedOrder({bool category = false}) {
    final orders = <Map<String, dynamic>>[
      {
        'id': 'op',
        'product_id': 'product',
        'organization_id': 'org',
        'status': 'draft',
        'planned_quantity': 10,
        'uom_id': 'kg',
      },
    ];
    return WritableMemoryDatabase(client, {
      'production_orders': orders,
      'v_production_order_workspace': orders,
      'products': [
        {'id': 'product', 'category_id': 'cat'},
        {'id': 'paper-a', 'material_type_id': 'paper'},
      ],
      'routings': [
        {
          'id': 'route',
          'organization_id': 'org',
          'is_active': true,
          if (category) 'category_id': 'cat' else 'product_id': 'product',
        },
      ],
      'routing_revisions': [
        {'id': 'route-rev', 'routing_id': 'route', 'status': 'active'},
      ],
      'routing_operations': [
        {
          'id': 'source-step',
          'routing_revision_id': 'route-rev',
          'sequence_no': 1,
          'name': 'Fabricación',
          'operation_type': 'material',
        },
      ],
      'boms': [
        {
          'id': 'bom',
          'organization_id': 'org',
          'product_id': 'product',
          'is_active': true,
        },
      ],
      'bom_revisions': [
        {
          'id': 'bom-rev',
          'bom_id': 'bom',
          'status': 'active',
          'output_uom_id': 'kg',
        },
      ],
      'bom_items': [
        {
          'id': 'bom-item',
          'bom_revision_id': 'bom-rev',
          'line_no': 1,
          'component_product_id': 'paper-a',
          'quantity': 2,
          'uom_id': 'kg',
        },
      ],
      'routing_operation_materials': [
        {
          'id': 'link',
          'routing_operation_id': 'source-step',
          'material_type_id': 'paper',
        },
      ],
    });
  }

  test('floor order detail includes every operation beyond the standard page limit', () async {
    final db = unpreparedOrder();
    db.tables['production_order_operations'] = [
      for (var i = 0; i < 1203; i++)
        {
          'id': 'step-$i',
          'production_order_id': 'op',
          'sequence_no': 1203 - i,
          'name': 'Operación $i',
          'status': 'pending',
          'operation_type': 'activity',
        },
    ];
    final repository = ProductionRepository(db, client)..setOrganization('org');
    final detail = await repository.floorOrderDetail('op');
    final operations = detail['operations'] as List;
    expect(operations.length, 1203);
    expect(operations.first['sequence_no'], 1);
    expect(operations.last['sequence_no'], 1203);
  });

  test('floor product specifications include shared category routing and its steps', () async {
    final db = unpreparedOrder(category: true);
    db.tables['products']!.first['organization_id'] = 'org';
    final repository = ProductionRepository(db, client)..setOrganization('org');
    final detail = await repository.floorProductDetail('product');
    expect((detail['routings'] as List).single['id'], 'route');
    expect(
      (detail['routing_operations'] as List).single['name'],
      'Fabricación',
    );
  });

  for (final category in [false, true]) {
    test(
      'previews linked route without assigned OP revisions; category: $category',
      () async {
        final db = unpreparedOrder(category: category);
        final repository = ProductionRepository(db, client)
          ..setOrganization('org');
        final data = await repository.detail('op');
        expect(
          (data['operations'] as List).single['id'],
          'routing:source-step',
        );
        expect((data['materials'] as List).single['required_quantity'], 20);
        expect(
          (data['operation_materials'] as Map)['source-step'],
          hasLength(1),
        );
        expect(db.writes, isEmpty);
        expect(
          db.tables['production_orders']!.single['routing_revision_id'],
          isNull,
        );
      },
    );

    for (final fallback in [false, true]) {
      test(
        'prepares and freezes linked route once; category: $category, RPC fallback: $fallback',
        () async {
          final db = unpreparedOrder(category: category)
            ..missingPrepareRpc = fallback;
          final repository = AuthenticatedProductionRepository(db, client)
            ..setOrganization('org');
          final data = await repository.ensureOperationalSnapshot('op');
          expect(
            (data['operations'] as List).single['id'],
            'production_order_operations-0',
          );
          expect(
            db.tables['production_orders']!.single['routing_revision_id'],
            'route-rev',
          );
          expect(
            db.tables['production_orders']!.single['bom_revision_id'],
            'bom-rev',
          );
          expect(db.tables['production_orders']!.single['status'], 'ready');
          await repository.ensureOperationalSnapshot('op');
          expect(db.tables['production_order_operations'], hasLength(1));
          expect(db.tables['production_order_materials'], hasLength(1));
        },
      );
    }
  }

  testWidgets(
    'operator display opens existing OP with linked category route and no assigned revision',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = unpreparedOrder(category: true);
      final repository = ProductionRepository(db, client)
        ..setOrganization('org');
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionOperatorDisplay(
            orderId: 'op',
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('La OP no tiene secuencia operativa'),
        findsNothing,
      );
      expect(find.text('Fabricación'), findsWidgets);
      expect(db.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'uses category route when product has only an inactive revision',
    () async {
      final db = unpreparedOrder(category: true);
      db.tables['routings']!.add({
        'id': 'inactive-route',
        'product_id': 'product',
        'organization_id': 'org',
        'is_active': true,
      });
      db.tables['routing_revisions']!.add({
        'id': 'inactive-rev',
        'routing_id': 'inactive-route',
        'status': 'draft',
      });
      final repository = ProductionRepository(db, client)
        ..setOrganization('org');
      final data = await repository.detail('op');
      expect((data['order'] as Map)['routing_revision_id'], 'route-rev');
    },
  );

  test(
    'preserves explicit OP revision and prefers product route over category',
    () async {
      final db = unpreparedOrder(category: true);
      db.tables['routings']!.add({
        'id': 'own-route',
        'product_id': 'product',
        'organization_id': 'org',
        'is_active': true,
      });
      db.tables['routing_revisions']!.add({
        'id': 'own-rev',
        'routing_id': 'own-route',
        'status': 'active',
      });
      final repository = ProductionRepository(db, client)
        ..setOrganization('org');
      expect(
        ((await repository.detail('op'))['order']
            as Map)['routing_revision_id'],
        'own-rev',
      );
      db.tables['production_orders']!.single['routing_revision_id'] =
          'route-rev';
      expect(
        ((await repository.detail('op'))['operations'] as List)
            .single['routing_operation_id'],
        'source-step',
      );
    },
  );

  test(
    'never uses another organization or draft routes as an active sequence',
    () async {
      final db = unpreparedOrder();
      db.tables['routings']!.single['organization_id'] = 'another-org';
      final repository = ProductionRepository(db, client)
        ..setOrganization('org');
      expect((await repository.detail('op'))['operations'], isEmpty);
      db.tables['routings']!.single['organization_id'] = 'org';
      db.tables['routing_revisions']!.single['status'] = 'draft';
      expect((await repository.detail('op'))['operations'], isEmpty);
    },
  );

  test('resolves all matching BOM lines, preserving quantity, unit and repeated material', () {
    final links = resolveOperationMaterialTypes(
      [
        {'material_type_id': 'paper'},
      ],
      materials,
      products,
    );
    expect(links.map((row) => row['bom_item_id']), ['b1', 'b2', 'b3']);
    expect(links.map((row) => row['quantity_override']), [40, 20, 10]);
    expect(links.map((row) => row['uom_id']), everyElement('kg'));
    expect(
      resolveOperationMaterialTypes(
        [
          {'material_type_id': 'missing'},
        ],
        materials,
        products,
      ),
      isEmpty,
    );
  });

  test('duplicate type assignments do not duplicate BOM materials', () {
    expect(
      resolveOperationMaterialTypes(
        [
          {'material_type_id': 'paper'},
          {'material_type_id': 'paper'},
        ],
        materials,
        products,
      ),
      hasLength(3),
    );
  });

  test('product routing keeps its concrete material assignment', () {
    final link = {
      'id': 'link',
      'material_product_id': 'paper-a',
      'bom_item_id': 'b1',
      'quantity_override': 5,
    };
    expect(resolveOperationMaterialTypes([link], materials, products), [link]);
  });

  test('category choices include types from all its products, excluding other categories', () async {
    final db = MemoryDatabase(client, {
      'products': [
        {'id': 'p1', 'organization_id': 'org', 'category_id': 'cat'},
        {'id': 'p2', 'organization_id': 'org', 'category_id': 'cat'},
        {'id': 'other', 'organization_id': 'org', 'category_id': 'other-cat'},
        ...products.values,
      ],
      'boms': [
        for (final id in ['p1', 'p2', 'other'])
          {
            'id': 'bom-$id',
            'product_id': id,
            'organization_id': 'org',
            'is_active': true,
          },
      ],
      'bom_revisions': [
        for (final id in ['p1', 'p2', 'other'])
          {'id': 'rev-$id', 'bom_id': 'bom-$id', 'status': 'active'},
      ],
      'bom_items': [
        {'bom_revision_id': 'rev-p1', 'component_product_id': 'paper-a'},
        {'bom_revision_id': 'rev-p1', 'component_product_id': 'paper-b'},
        {'bom_revision_id': 'rev-p2', 'component_product_id': 'ink'},
        {'bom_revision_id': 'rev-other', 'component_product_id': 'unrelated'},
      ],
      'material_types': [
        for (final id in ['paper', 'ink', 'unrelated'])
          {'id': id, 'organization_id': 'org'},
      ],
    });
    final repository = RoutingRepository(db, client)..setOrganization('org');
    expect(
      (await repository.categoryMaterialTypes('cat')).map((row) => row['id']),
      ['paper', 'ink'],
    );
  });

  test('order detail resolves shared routing separately for each product without phantom materials', () async {
    final db = MemoryDatabase(client, {
      'v_production_order_workspace': [
        {'id': 'op-a', 'product_id': 'p1', 'uom_id': 'kg'},
        {'id': 'op-b', 'product_id': 'p2', 'uom_id': 'kg'},
      ],
      'production_order_operations': [
        for (final id in ['op-a', 'op-b'])
          {
            'id': 'step-$id',
            'production_order_id': id,
            'routing_operation_id': 'shared-step',
            'operation_type': 'material',
          },
      ],
      'production_order_materials': [
        {...materials[0], 'production_order_id': 'op-a'},
        {...materials[1], 'production_order_id': 'op-b'},
        {...materials[3], 'production_order_id': 'op-b'},
      ],
      'routing_operation_materials': [
        {
          'id': 'link',
          'routing_operation_id': 'shared-step',
          'material_type_id': 'paper',
        },
      ],
      'products': products.values.toList(),
    });
    final repository = ProductionRepository(db, client)..setOrganization('org');
    final a = await repository.detail('op-a');
    final b = await repository.detail('op-b');
    final aLinks = (a['operation_materials'] as Map)['shared-step'] as List;
    final bLinks = (b['operation_materials'] as Map)['shared-step'] as List;
    expect(aLinks.single['material_product_id'], 'paper-a');
    expect(aLinks.single['quantity_override'], 40);
    expect(bLinks.single['material_product_id'], 'paper-b');
    expect(bLinks.single['quantity_override'], 20);
    expect(a['materials'], hasLength(1));
    expect(b['materials'], hasLength(2));
    db.tables['routing_operation_materials']!.single['material_type_id'] =
        'missing';
    final noMatch = await repository.detail('op-a');
    expect((noMatch['operation_materials'] as Map)['shared-step'], isEmpty);
    expect(noMatch['materials'], hasLength(1));
  });
  testWidgets(
    'operator display shows matching materials and no whole-BOM fallback for an unmatched type',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final typeId in ['paper', 'missing']) {
        final data = <String, dynamic>{
          'order': {'op_number': 'OP-TEST'},
          'operations': [
            {
              'id': 'step',
              'routing_operation_id': 'shared-step',
              'name': 'Consumo',
              'sequence_no': 1,
              'status': 'in_progress',
              'operation_type': 'material',
            },
          ],
          'materials': materials,
          'products': {
            for (final entry in products.entries)
              entry.key: {
                ...entry.value,
                'sku': entry.key,
                'name': 'Material ${entry.key}',
              },
          },
          'operation_materials': {
            'shared-step': resolveOperationMaterialTypes(
              [
                {'material_type_id': typeId},
              ],
              materials,
              products,
            ),
          },
        };
        await tester.pumpWidget(
          MaterialApp(
            home: ProductionOperatorDisplay(
              key: ValueKey(typeId),
              orderId: 'op',
              repository: DisplayRepository(client, data),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('paper-a - Material paper-a'),
          typeId == 'paper' ? findsNWidgets(2) : findsNothing,
        );
        expect(
          find.text('paper-b - Material paper-b'),
          typeId == 'paper' ? findsOneWidget : findsNothing,
        );
        expect(find.text('ink - Material ink'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
