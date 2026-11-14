import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';
import '../../core/widgets/scroll_to_top.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/pomgt_button.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/roles_repository.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});
  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  final compactBreakpoint = 640;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;
    return PomgtTabController(
      length: 3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 32,
          compact ? 14 : 18,
          compact ? 12 : 32,
          compact ? 18 : 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Roles y auditoría',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const InfoTip(
                  'Catálogo de roles y matriz de permisos por módulo, más la bitácora automática de altas/cambios/bajas '
                  'en las tablas principales. La matriz aún no restringe botones en el resto de la app: es la base de datos '
                  'lista para ese siguiente paso.',
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PomgtColors.line)),
              ),
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                indicatorColor: PomgtColors.blue,
                labelColor: PomgtColors.ink,
                unselectedLabelColor: PomgtColors.muted,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
                tabs: [
                  Tab(text: 'Roles y permisos'),
                  Tab(text: 'Miembros'),
                  Tab(text: 'Auditoría'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _RolesTab(),
                  const _MembersTab(),
                  Padding(
                    padding: EdgeInsets.all(compact ? 12 : 20),
                    child: EntityCrudPanel(
                      table: 'audit_log',
                      repository: context.read<GenericRepository>(),
                      lookups: context.read<LookupRepository>(),
                      title: 'Auditoría',
                      description: 'Bitácora automática de cambios en clientes, cotizaciones, pedidos, producción, compras e inventario.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RolesTab extends StatefulWidget {
  const _RolesTab();
  @override
  State<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<_RolesTab> {
  late Future<void> _bootstrap;
  List<Map<String, dynamic>> _roles = [];
  String? _selectedRoleId;
  Map<String, Map<String, dynamic>> _permissions = {};
  bool _loadingPermissions = false;

  RolesRepository get _repository => context.read<RolesRepository>();

  @override
  void initState() {
    super.initState();
    _bootstrap = _load();
  }

  Future<void> _load() async {
    await _repository.ensureDefaultRoles();
    final roles = await _repository.roles();
    if (!mounted) return;
    setState(() {
      _roles = roles;
      _selectedRoleId ??= roles.isEmpty ? null : roles.first['id'].toString();
    });
    if (_selectedRoleId != null) await _loadPermissions(_selectedRoleId!);
  }

  Future<void> _loadPermissions(String roleId) async {
    setState(() => _loadingPermissions = true);
    final rows = await _repository.permissionsFor(roleId);
    if (!mounted) return;
    setState(() {
      _permissions = {for (final r in rows) r['module_key'].toString(): r};
      _loadingPermissions = false;
    });
  }

  Future<void> _selectRole(String roleId) async {
    setState(() => _selectedRoleId = roleId);
    await _loadPermissions(roleId);
  }

  Future<void> _togglePermission(
    String moduleKey, {
    bool? view,
    bool? edit,
    bool? delete,
  }) async {
    final roleId = _selectedRoleId;
    if (roleId == null) return;
    final current = _permissions[moduleKey];
    final canView = view ?? (current?['can_view'] == true);
    final canEdit = edit ?? (current?['can_edit'] == true);
    final canDelete = delete ?? (current?['can_delete'] == true);
    setState(() {
      _permissions[moduleKey] = {
        ...?current,
        'module_key': moduleKey,
        'can_view': canView,
        'can_edit': canEdit,
        'can_delete': canDelete,
      };
    });
    try {
      await _repository.setPermission(
        roleId: roleId,
        moduleKey: moduleKey,
        canView: canView,
        canEdit: canEdit,
        canDelete: canDelete,
      );
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
    }
  }

  Future<void> _createRole() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final created = await showPomgtDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: pomgtDialogTitle(
          dialogContext,
          'Nuevo rol',
          onClose: () => Navigator.pop(dialogContext, false),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Código (ej. logistica)',
                hintText: 'Ej. logistica',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Escribe el nombre del rol',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (created != true) return;
    if (codeController.text.trim().isEmpty ||
        nameController.text.trim().isEmpty)
      return;
    try {
      final role = await _repository.createRole(
        code: codeController.text.trim(),
        name: nameController.text.trim(),
      );
      await _load();
      if (!mounted) return;
      await _selectRole(role['id'].toString());
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PomgtLoading();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final roleList = Container(
                width: wide ? 260 : double.infinity,
                decoration: BoxDecoration(
                  color: PomgtColors.canvas,
                  borderRadius: PomgtRadii.borderMd,
                  border: Border.all(
                    color: PomgtColors.lineStrong.withValues(alpha: .55),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: PomgtButton(
                        label: 'Nuevo rol',
                        icon: LucideIcons.plus,
                        primary: false,
                        onPressed: _createRole,
                      ),
                    ),
                    for (final role in _roles)
                      ListTile(
                        selected: role['id'].toString() == _selectedRoleId,
                        selectedTileColor: PomgtColors.navySelected,
                        title: Text(
                          role['name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          role['description']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _selectRole(role['id'].toString()),
                      ),
                  ],
                ),
              );
              final matrix = Expanded(
                child: _loadingPermissions
                    ? const PomgtLoading()
                    : _selectedRoleId == null
                    ? const Center(
                        child: Text(
                          'Selecciona un rol.',
                          style: TextStyle(color: PomgtColors.muted),
                        ),
                      )
                    : ScrollToTopArea(
                        padding: const EdgeInsets.all(12),
                        builder: (context, controller) => SingleChildScrollView(
                          controller: controller,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Módulo')),
                              DataColumn(label: Text('Ver')),
                              DataColumn(label: Text('Editar')),
                              DataColumn(label: Text('Eliminar')),
                            ],
                            rows: [
                              for (final m in RolesRepository.modules)
                                DataRow(
                                  cells: [
                                    DataCell(Text(m.$2)),
                                    DataCell(
                                      Checkbox(
                                        value:
                                            _permissions[m.$1]?['can_view'] ==
                                            true,
                                        onChanged: (v) =>
                                            _togglePermission(m.$1, view: v),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value:
                                            _permissions[m.$1]?['can_edit'] ==
                                            true,
                                        onChanged: (v) =>
                                            _togglePermission(m.$1, edit: v),
                                      ),
                                    ),
                                    DataCell(
                                      Checkbox(
                                        value:
                                            _permissions[m.$1]?['can_delete'] ==
                                            true,
                                        onChanged: (v) =>
                                            _togglePermission(m.$1, delete: v),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 260, child: roleList),
                    const SizedBox(height: 16),
                    matrix,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [roleList, const SizedBox(width: 20), matrix],
              );
            },
          ),
        );
      },
    );
  }
}

class _MembersTab extends StatefulWidget {
  const _MembersTab();
  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  late Future<List<List<Map<String, dynamic>>>> _future;

  RolesRepository get _repository => context.read<RolesRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Future.wait([
      _repository.members(),
      _repository.roles(),
      _repository.invites(),
    ]);
  }

  Future<void> _assign(String memberId, String? roleId) async {
    try {
      await _repository.assignRole(memberId, roleId);
      if (!mounted) return;
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
    }
  }

  Future<void> _revoke(String inviteId) async {
    try {
      await _repository.revokeInvite(inviteId);
      if (!mounted) return;
      setState(_load);
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
    }
  }

  Future<void> _openInviteDialog(List<Map<String, dynamic>> roles) async {
    final emailController = TextEditingController();
    String? roleId;
    final created = await showPomgtDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: pomgtDialogTitle(
            context,
            'Invitar miembro',
            onClose: () => Navigator.pop(dialogContext, false),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'nombre@empresa.com',
                ),
              ),
              const SizedBox(height: 12),
              CategorizedSearchPicker(
                label: 'Rol',
                hint: 'Buscar rol…',
                value: roleId,
                items: [
                  for (final r in roles)
                    PickerItem(
                      id: r['id'].toString(),
                      label: r['name']?.toString() ?? '',
                      category: 'Roles',
                    ),
                ],
                onChanged: (v) => setState(() => roleId = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'La persona debe registrarse en POMGT con este mismo correo y luego pegar el código que te mostraremos aquí.',
                style: TextStyle(fontSize: 11.5, color: PomgtColors.muted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Generar invitación'),
            ),
          ],
        ),
      ),
    );
    if (created != true || emailController.text.trim().isEmpty) return;
    try {
      final token = await _repository.createInvite(
        email: emailController.text.trim(),
        roleId: roleId,
      );
      if (!mounted) return;
      setState(_load);
      await _showTokenDialog(token);
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
    }
  }

  Future<void> _showTokenDialog(String token) async {
    await showPomgtDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: pomgtDialogTitle(
          dialogContext,
          'Invitación generada',
          onClose: () => Navigator.pop(dialogContext),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Comparte este código con la persona invitada. Es válido por 7 días.',
              style: TextStyle(fontSize: 12.5, color: PomgtColors.muted),
            ),
            const SizedBox(height: 12),
            SelectableText(
              token,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              Navigator.pop(dialogContext);
              showPomgtSnackBar(context, 'Código copiado al portapapeles.');
            },
            child: const Text('Copiar y cerrar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const PomgtLoading();
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                ErrorCopy.message(snapshot.error!),
                style: const TextStyle(color: PomgtColors.danger),
              ),
            );
          }
          final members = snapshot.data![0];
          final roles = snapshot.data![1];
          final invites = snapshot.data![2]
              .where((i) => i['status'] == 'pending')
              .toList();
          final roleNames = {
            for (final r in roles) r['id'].toString(): r['name']?.toString(),
          };
          return ScrollToTopArea(
            padding: const EdgeInsets.all(16),
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PomgtButton(
                      label: 'Invitar miembro',
                      icon: LucideIcons.userPlus,
                      onPressed: () => _openInviteDialog(roles),
                    ),
                  ),
                  if (invites.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Invitaciones pendientes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final invite in invites)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: PomgtColors.surfaceAlt,
                          borderRadius: PomgtRadii.borderSm,
                          border: Border.all(color: PomgtColors.line),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${invite['email']} · ${roleNames[invite['role_id']?.toString()] ?? 'Sin rol'}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _showTokenDialog(invite['token'].toString()),
                              child: const Text('Ver código'),
                            ),
                            TextButton(
                              onPressed: () => _revoke(invite['id'].toString()),
                              child: const Text(
                                'Revocar',
                                style: TextStyle(color: PomgtColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Miembros',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Sin miembros.',
                        style: TextStyle(color: PomgtColors.muted),
                      ),
                    )
                  else
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Miembro')),
                        DataColumn(label: Text('Correo')),
                        DataColumn(label: Text('Rol')),
                      ],
                      rows: [
                        for (final m in members)
                          DataRow(
                            cells: [
                              DataCell(Text(m['full_name']?.toString() ?? '—')),
                              DataCell(Text(m['email']?.toString() ?? '—')),
                              DataCell(
                                DropdownButton<String?>(
                                  value: m['role_id']?.toString(),
                                  hint: const Text('Sin rol'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Sin rol'),
                                    ),
                                    for (final r in roles)
                                      DropdownMenuItem<String?>(
                                        value: r['id'].toString(),
                                        child: Text(
                                          r['name']?.toString() ?? '',
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      _assign(m['id'].toString(), v),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
