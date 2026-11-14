import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';

class SupabaseDatabaseService {
  SupabaseDatabaseService(this.client);
  final SupabaseClient client;

  SupabaseQuerySchema get db => client.schema(SupabaseConfig.databaseSchema);

  /// Stable pagination, including installations whose API caps rows at 500.
  Future<List<Map<String, dynamic>>> listAll(
    String table, {
    Map<String, dynamic> equals = const {},
    Map<String, List<String>> within = const {},
    int pageSize = 500,
  }) async {
    if (pageSize < 1 || pageSize > 500) {
      throw ArgumentError.value(pageSize, 'pageSize');
    }
    if (within.values.any((ids) => ids.isEmpty)) return [];
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += pageSize) {
      dynamic query = db.from(table).select();
      for (final entry in equals.entries) {
        if (entry.value != null) query = query.eq(entry.key, entry.value);
      }
      for (final entry in within.entries) {
        query = query.inFilter(entry.key, entry.value);
      }
      final page = List<Map<String, dynamic>>.from(
        await query
                .order('id', ascending: true)
                .range(offset, offset + pageSize - 1)
            as List,
      );
      result.addAll(page);
      if (page.length < pageSize) return result;
    }
  }

  Future<List<Map<String, dynamic>>> list(
    String table, {
    String select = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
    int limit = 500,
  }) async {
    dynamic query = db.from(table).select(select);
    for (final entry in equals.entries) {
      if (entry.value != null) query = query.eq(entry.key, entry.value);
    }
    if (orderBy != null) query = query.order(orderBy, ascending: ascending);
    query = query.limit(limit);
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>?> one(
    String table,
    String id, {
    String select = '*',
  }) async {
    final row = await db.from(table).select(select).eq('id', id).maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Fetches every row of [table] whose [column] is one of [values] in a
  /// single round trip, instead of callers looping and awaiting [one] or
  /// [list] once per id - the N+1 pattern that makes screens with many
  /// related rows (operations, materials, their reference data) slow to
  /// open. Returns `[]` without a network call when [values] is empty.
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
    final ids = values.toSet().toList();
    if (ids.isEmpty) return [];
    dynamic query = db.from(table).select(select).inFilter(column, ids);
    for (final entry in equals.entries) {
      if (entry.value != null) query = query.eq(entry.key, entry.value);
    }
    if (orderBy != null) query = query.order(orderBy, ascending: ascending);
    query = query.limit(limit);
    final rows = await query;
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    final row = await db.from(table).insert(values).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> insertMany(
    String table,
    List<Map<String, dynamic>> values,
  ) async {
    final rows = await db.from(table).insert(values).select();
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> values,
  ) async {
    final row = await db
        .from(table)
        .update(values)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> delete(String table, String id) async {
    await db.from(table).delete().eq('id', id);
  }

  Future<void> deleteWhere(String table, Map<String, dynamic> equals) async {
    dynamic query = db.from(table).delete();
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }

  Future<Map<String, dynamic>> updateWhere(
    String table,
    Map<String, dynamic> equals,
    Map<String, dynamic> values,
  ) async {
    dynamic query = db.from(table).update(values);
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    final row = await query.select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    return db.rpc(function, params: params);
  }
}
