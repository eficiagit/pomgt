import 'package:flutter/foundation.dart';
import '../data/services/supabase_database_service.dart';
import '../core/utils/error_copy.dart';
import '../data/repositories/base_repository.dart';

class OrganizationController extends ChangeNotifier {
  OrganizationController(this.db, this.repositories);
  final SupabaseDatabaseService db;
  final List<BaseRepository> repositories;

  bool loading = true;
  String? organizationId;
  Map<String, dynamic>? organization;
  String? error;

  Future<void> loadForUser(String userId) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final memberships = await db.serviceListMembers(userId);
      if (memberships.isEmpty) {
        organizationId = null;
        organization = null;
      } else {
        organizationId = memberships.first['organization_id'] as String;
        organization = await db.one('organizations', organizationId!);
        for (final repo in repositories) {
          repo.setOrganization(organizationId!);
        }
      }
    } catch (e) {
      error = ErrorCopy.message(
        e,
        fallback: 'No fue posible cargar tu organización.',
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> bootstrap({
    required String code,
    required String legalName,
    required String displayName,
  }) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await db.rpc(
        'bootstrap_organization',
        params: {
          'p_code': code.trim().toUpperCase(),
          'p_legal_name': legalName.trim(),
          'p_display_name': displayName.trim(),
        },
      );
      final id = result is String ? result : result.toString();
      organizationId = id;
      organization = await db.one('organizations', id);
      for (final repo in repositories) {
        repo.setOrganization(id);
      }
    } catch (e) {
      error = ErrorCopy.message(
        e,
        fallback: 'No fue posible crear la organización.',
      );
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

extension OrganizationMemberQueries on SupabaseDatabaseService {
  Future<List<Map<String, dynamic>>> serviceListMembers(String userId) {
    return list(
      'organization_members',
      equals: {'user_id': userId, 'is_active': true},
    );
  }
}
