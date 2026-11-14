import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/controllers/runtime_data_controller.dart';
import 'package:pomgt/core/utils/action_exception.dart';
import 'package:pomgt/data/phase1_schema.dart';
import 'package:pomgt/data/repositories/generic_repository.dart';
import 'package:pomgt/data/repositories/lookup_repository.dart';
import 'package:pomgt/data/repositories/material_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:pomgt/features/master_data/material_types_admin.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TypeDatabase extends SupabaseDatabaseService {
  TypeDatabase(super.client);
  final tables = <String, List<Map<String, dynamic>>>{
    'material_types': [
      {
        'id': 'type',
        'organization_id': 'org',
        'name': 'Papel',
        'code': 'PAP',
        'is_active': true,
      },
    ],
  };
  final deleted = <String>[];
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
      .take(limit)
      .toList();
  @override
  Future<void> delete(String table, String id) async {
    deleted.add('$table:$id');
    tables[table]!.removeWhere((row) => row['id'] == id);
  }
}

void main() {
  late SupabaseClient client;
  late TypeDatabase db;
  late GenericRepository generic;
  late RuntimeDataController runtime;
  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test');
    db = TypeDatabase(client);
    runtime = RuntimeDataController();
    generic = GenericRepository(db, client, runtimeData: runtime)
      ..setOrganization('org');
  });
  tearDown(() async {
    runtime.dispose();
    await client.dispose();
  });

  Future<void> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: runtime),
          Provider.value(value: generic),
          Provider.value(value: LookupRepository(generic, runtime)),
          Provider.value(
            value: MaterialRepository(db, client)..setOrganization('org'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: MaterialTypesAdmin())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'type menu offers permanent deletion, confirms and refreshes list',
    (tester) async {
      await host(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar').last);
      await tester.pumpAndSettle();
      expect(find.text('Eliminar tipo de material'), findsOneWidget);
      expect(db.deleted, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();
      expect(db.deleted, ['material_types:type']);
      expect(find.text('Aún no hay tipos de material'), findsOneWidget);
      expect(runtime.revisionFor('material_types'), 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail offers deletion and cancellation keeps the type', (
    tester,
  ) async {
    await host(tester);
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(db.tables['material_types'], hasLength(1));
    expect(db.deleted, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final table in [
    'products',
    'routing_operation_materials',
    'material_attribute_definitions',
  ]) {
    test(
      'blocks type referenced by $table with an actionable reason',
      () async {
        db.tables[table] = [
          {
            'id': 'related',
            'organization_id': 'org',
            'material_type_id': 'type',
          },
        ];
        final spec = Phase1Schema.tables['material_types']!;
        final type = db.tables['material_types']!.single;
        expect(await generic.deletionBlockReason(spec, type), isNotEmpty);
        await expectLater(
          generic.deleteRow(spec, type),
          throwsA(isA<ActionException>()),
        );
        expect(db.deleted, isEmpty);
        expect(db.tables[table], hasLength(1));
      },
    );
  }
}
