import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class SupabaseDatabaseService {
  SupabaseDatabaseService(this.client);
  final SupabaseClient client;

  SupabaseQuerySchema get db => client.schema(SupabaseConfig.databaseSchema);

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
