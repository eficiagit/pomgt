import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/utils/action_exception.dart';
import 'package:pomgt/core/utils/error_copy.dart';
import 'package:pomgt/data/phase1_schema.dart';
import 'package:pomgt/data/repositories/generic_repository.dart';
import 'package:pomgt/data/services/supabase_database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnitDatabase extends SupabaseDatabaseService {
  UnitDatabase(super.client);
  final units = <Map<String, dynamic>>[];
  final deleted = <String>[];

  @override
  Future<List<Map<String, dynamic>>> list(
    String table, {
    String select = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
    int limit = 500,
  }) async => units
      .where(
        (row) => equals.entries.every((entry) => row[entry.key] == entry.value),
      )
      .take(limit)
      .toList();

  @override
  Future<void> delete(String table, String id) async =>
      deleted.add('$table:$id');
}

void main() {
  late SupabaseClient client;
  late UnitDatabase db;
  late GenericRepository repository;
  final spec = Phase1Schema.tables['uom_categories']!;
  final category = {'id': 'mass', 'organization_id': 'org', 'name': 'Masa'};
  setUp(() {
    client = SupabaseClient('https://example.supabase.co', 'test');
    db = UnitDatabase(client);
    repository = GenericRepository(db, client)..setOrganization('org');
  });
  tearDown(() => client.dispose());

  test('category in use names its units and prevents deletion', () async {
    db.units.add({
      'id': 'kg',
      'organization_id': 'org',
      'category_id': 'mass',
      'name': 'Kilogramo',
      'symbol': 'kg',
      'is_active': false,
    });
    final reason = await repository.deletionBlockReason(spec, category);
    expect(reason, contains('Kilogramo (kg)'));
    expect(reason, contains('Unidades de medida'));
    await expectLater(
      repository.deleteRow(spec, category),
      throwsA(isA<ActionException>()),
    );
    expect(db.deleted, isEmpty);
    expect(db.units, hasLength(1));
  });

  test('empty category deletes normally and ignores unrelated units', () async {
    db.units.addAll([
      {'organization_id': 'another-org', 'category_id': 'mass'},
      {'organization_id': 'org', 'category_id': 'length'},
    ]);
    await repository.deleteRow(spec, category);
    expect(db.deleted, ['uom_categories:mass']);
    expect(db.units, hasLength(2));
  });

  test('deletion of other catalogs retains its normal behavior', () async {
    await repository.deleteRow(Phase1Schema.tables['product_categories']!, {
      'id': 'product-category',
    });
    expect(db.deleted, ['product_categories:product-category']);
  });

  test('action and category foreign-key errors show actionable copy', () {
    expect(
      ErrorCopy.message(const ActionException('Mensaje específico')),
      'Mensaje específico',
    );
    expect(
      ErrorCopy.message(
        const PostgrestException(
          message: 'violates foreign key constraint "units_of_measure_category_id_fkey"',
          code: '23503',
        ),
      ),
      contains('Reasígnalas'),
    );
    expect(
      ErrorCopy.message(
        const PostgrestException(message: 'other foreign key', code: '23503'),
      ),
      contains('relacionado con otra información'),
    );
  });
}
