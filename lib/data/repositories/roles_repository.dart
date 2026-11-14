import 'base_repository.dart';

/// Roles and the module permission matrix. Custom (not Phase1Schema-driven)
/// because editing a role means editing many `role_permissions` rows at
/// once as a grid, which the generic single-row form doesn't fit.
///
/// Scope note: this manages the data and seeds sensible defaults, but no
/// screen in the app yet reads this matrix to gate its own buttons — see the
/// comment at the top of the roles_and_audit migration.
class RolesRepository extends BaseRepository {
  RolesRepository(super.service, super.client);

  static const modules = [
    ('dashboard', 'Inicio'),
    ('customers', 'Clientes'),
    ('orders', 'Pedidos'),
    ('products', 'Productos'),
    ('materials', 'Materiales'),
    ('bom', 'Estructuras de fabricación'),
    ('routings', 'Rutas de fabricación'),
    ('production', 'Producción'),
    ('documents', 'Documentos'),
    ('master_data', 'Datos maestros'),
    ('roles', 'Roles y auditoría'),
  ];

  Future<void> ensureDefaultRoles() async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    await service.rpc('ensure_default_roles', params: {'p_org': org});
  }

  Future<List<Map<String, dynamic>>> roles() =>
      listTenant('roles', orderBy: 'name');

  Future<List<Map<String, dynamic>>> permissionsFor(String roleId) =>
      service.list('role_permissions', equals: {'role_id': roleId});

  Future<Map<String, dynamic>> createRole({
    required String code,
    required String name,
    String? description,
  }) async {
    final role = await service.insert(
      'roles',
      tenantValues({'code': code, 'name': name, 'description': description}),
    );
    final roleId = role['id'].toString();
    await service.insertMany('role_permissions', [
      for (final m in modules)
        {
          'role_id': roleId,
          'module_key': m.$1,
          'can_view': true,
          'can_edit': false,
          'can_delete': false,
        },
    ]);
    return role;
  }

  Future<void> updateRole({
    required String roleId,
    required String name,
    String? description,
  }) => service.update('roles', roleId, {
    'name': name,
    'description': description,
  });

  Future<void> deleteRole(String roleId) => service.delete('roles', roleId);

  Future<void> setPermission({
    required String roleId,
    required String moduleKey,
    required bool canView,
    required bool canEdit,
    required bool canDelete,
  }) async {
    final existing = await service.list(
      'role_permissions',
      equals: {'role_id': roleId, 'module_key': moduleKey},
    );
    final values = {
      'role_id': roleId,
      'module_key': moduleKey,
      'can_view': canView,
      'can_edit': canEdit,
      'can_delete': canDelete,
    };
    if (existing.isEmpty) {
      await service.insert('role_permissions', values);
    } else {
      await service.update(
        'role_permissions',
        existing.first['id'].toString(),
        values,
      );
    }
  }

  Future<List<Map<String, dynamic>>> members() =>
      listTenant('organization_members', orderBy: 'full_name');

  Future<void> assignRole(String memberId, String? roleId) =>
      service.update('organization_members', memberId, {'role_id': roleId});

  Future<List<Map<String, dynamic>>> auditLog({int limit = 200}) =>
      service.list(
        'audit_log',
        equals: {'organization_id': organizationId},
        orderBy: 'changed_at',
        ascending: false,
        limit: limit,
      );

  /// Creates an invite and returns its token. There is no server-side
  /// account-creation path in this app (no Edge Functions, no service_role
  /// key), so the invitee must sign up themselves with this exact email and
  /// then redeem the token — see [acceptInvite].
  Future<String> createInvite({required String email, String? roleId}) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final result = await service.rpc(
      'create_organization_invite',
      params: {'p_org': org, 'p_email': email, 'p_role_id': roleId},
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> invites() =>
      listTenant('organization_invites', orderBy: 'created_at');

  Future<void> revokeInvite(String inviteId) =>
      service.update('organization_invites', inviteId, {'status': 'revoked'});
}
