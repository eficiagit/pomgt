import '../../controllers/runtime_data_controller.dart';
import '../phase1_schema.dart';
import 'generic_repository.dart';

class LookupRepository {
  LookupRepository(this.generic, this.runtimeData);
  final GenericRepository generic;
  final RuntimeDataController runtimeData;
  final Map<String, _LookupCacheEntry> _cache = {};

  Future<List<Map<String, dynamic>>> rows(
    String table, {
    bool refresh = false,
  }) async {
    final cached = _cache[table];
    final currentRevision = runtimeData.revisionFor(table);
    if (!refresh && cached != null && cached.revision == currentRevision) {
      return cached.rows;
    }
    final spec = Phase1Schema.tables[table];
    if (spec == null) return const [];
    final rows = await generic.listRows(spec);
    _cache[table] = _LookupCacheEntry(currentRevision, rows);
    return rows;
  }

  String display(DbTableSpec spec, Map<String, dynamic> row) {
    final values = <String>[];
    for (final field in spec.displayFields) {
      final value = row[field];
      if (value != null && value.toString().trim().isNotEmpty)
        values.add(value.toString());
    }
    if (values.isNotEmpty) return values.join(' · ');
    for (final candidate in const [
      'name',
      'title',
      'code',
      'label',
      'revision_code',
      'order_number',
      'sku',
      'full_name',
    ]) {
      final value = row[candidate];
      if (value != null && value.toString().trim().isNotEmpty)
        return value.toString();
    }
    return 'Registro sin nombre';
  }

  void invalidate(String table) => _cache.remove(table);
  void clear() => _cache.clear();
}

class _LookupCacheEntry {
  const _LookupCacheEntry(this.revision, this.rows);
  final int revision;
  final List<Map<String, dynamic>> rows;
}
