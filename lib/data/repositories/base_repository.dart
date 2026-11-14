import 'package:supabase_flutter/supabase_flutter.dart';

import '../../controllers/runtime_data_controller.dart';
import '../services/supabase_database_service.dart';

class BaseRepository {
  BaseRepository(this.service, this.client, {this.runtimeData});
  final SupabaseDatabaseService service;
  final SupabaseClient client;

  /// Lets a repository that mutates a table outside of [GenericRepository]
  /// (a dedicated RPC, a direct insert/update/delete) still bump that
  /// table's revision, so `LookupRepository.rows(...)` callers elsewhere in
  /// the app see the change instead of silently keeping a stale cached
  /// copy — `GenericRepository` does this automatically on every
  /// create/update/delete; repositories that bypass it must call
  /// `runtimeData?.tableChanged(...)` themselves after a mutation succeeds.
  final RuntimeDataController? runtimeData;

  String? organizationId;

  String get userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw StateError('No hay una sesión autenticada.');
    return id;
  }

  void setOrganization(String id) => organizationId = id;

  Map<String, dynamic> tenantValues(
    Map<String, dynamic> values, {
    bool includeUser = false,
  }) {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final result = Map<String, dynamic>.from(values)..['organization_id'] = org;
    if (includeUser) result['created_by'] = userId;
    return result;
  }

  Future<List<Map<String, dynamic>>> listTenant(
    String table, {
    Map<String, dynamic> filters = const {},
    String? orderBy,
  }) {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    return service.list(
      table,
      equals: {'organization_id': org, ...filters},
      orderBy: orderBy,
    );
  }
}
