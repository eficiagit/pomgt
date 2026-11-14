import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/scroll_to_top.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/material_repository.dart';

class MaterialTypesAdmin extends StatefulWidget {
  const MaterialTypesAdmin({super.key});

  @override
  State<MaterialTypesAdmin> createState() => _MaterialTypesAdminState();
}

class _MaterialTypesAdminState extends State<MaterialTypesAdmin> {
  late Future<_TypeAdminData> _future;
  String _search = '';
  bool? _activeFilter;
  String? _selectedId;
  bool _deleting = false;
  bool _deletePending = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TypeAdminData> _load() async {
    final repo = context.read<MaterialRepository>();
    final generic = context.read<GenericRepository>();
    final results = await Future.wait([
      repo.materialTypes(),
      generic.listRows(Phase1Schema.tables['material_attribute_definitions']!),
      generic.listRows(Phase1Schema.tables['products']!),
    ]);
    return _TypeAdminData(
      types: results[0],
      attributes: results[1],
      products: results[2],
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['material_types']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: row,
        title: row == null
            ? 'Nuevo tipo de material'
            : 'Editar tipo de material',
        icon: LucideIcons.layoutGrid,
      ),
    );
    if (changed == true && mounted) {
      context.read<LookupRepository>().invalidate('material_types');
      _reload();
    }
  }

  Future<void> _setActive(Map<String, dynamic> row, bool active) async {
    await context.read<GenericRepository>().updateRow(
      Phase1Schema.tables['material_types']!,
      row['id'].toString(),
      {'is_active': active},
    );
    if (!mounted) return;
    context.read<LookupRepository>().invalidate('material_types');
    _reload();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_deletePending) return;
    _deletePending = true;
    final repository = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final spec = Phase1Schema.tables['material_types']!;
    try {
      final blocked = await repository.deletionBlockReason(spec, row);
      if (!mounted) return;
      if (blocked != null) {
        await showPomgtDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: pomgtDialogTitle(context, 'Tipo de material en uso'),
            content: Text(blocked),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await showPomgtDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: pomgtDialogTitle(
            context,
            'Eliminar tipo de material',
            onClose: () => Navigator.pop(context, false),
          ),
          content: Text(
            '¿Eliminar “${row['name'] ?? row['code'] ?? 'este tipo de material'}” permanentemente? Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: PomgtColors.danger,
              ),
              icon: const Icon(LucideIcons.trash2, size: 17),
              label: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _deleting = true);
      await repository.deleteRow(spec, row);
      if (!mounted) return;
      lookups.invalidate('material_types');
      _selectedId = null;
      _reload();
      showPomgtSnackBar(context, 'Tipo de material eliminado.');
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      }
    } finally {
      _deletePending = false;
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleting) return const PomgtLoading();
    return FutureBuilder<_TypeAdminData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'No fue posible cargar tipos de material.',
              style: TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final data = snapshot.data ?? _TypeAdminData.empty();
        final rows = data.types.where((row) {
          final query = _search.trim().toLowerCase();
          if (query.isNotEmpty &&
              ![row['code'], row['name'], row['description']].any(
                (v) => v?.toString().toLowerCase().contains(query) ?? false,
              )) {
            return false;
          }
          if (_activeFilter != null &&
              (row['is_active'] == true) != _activeFilter) {
            return false;
          }
          return true;
        }).toList();
        if (rows.isNotEmpty &&
            (_selectedId == null ||
                !rows.any((row) => row['id']?.toString() == _selectedId))) {
          _selectedId = rows.first['id']?.toString();
        }
        final selected = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == _selectedId,
          orElse: () => rows.isEmpty ? null : rows.first,
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final list = _TypeList(
              rows: rows,
              total: data.types.length,
              selectedId: _selectedId,
              loading: snapshot.connectionState == ConnectionState.waiting,
              search: _search,
              activeFilter: _activeFilter,
              onSearch: (value) => setState(() => _search = value),
              onActive: (value) => setState(() => _activeFilter = value),
              onSelect: (id) => setState(() => _selectedId = id),
              onRefresh: _reload,
              onCreate: () => _edit(),
              onEdit: (row) => _edit(row),
              onDelete: _delete,
              onToggleActive: (row, active) => _setActive(row, active),
            );
            final detail = selected == null
                ? const _AdminPanel(
                    child: EmptyState(
                      icon: LucideIcons.layoutGrid,
                      title: 'Selecciona un tipo de material',
                      message: 'Su ficha y atributos aparecerán aquí.',
                    ),
                  )
                : _TypeDetail(
                    key: ValueKey(selected['id']),
                    type: selected,
                    data: data,
                    onEdit: () => _edit(selected),
                    onDelete: () => _delete(selected),
                    onDeactivate: () => _setActive(selected, false),
                    onReactivate: () => _setActive(selected, true),
                    onChanged: _reload,
                  );
            if (narrow) {
              return Column(
                children: [
                  SizedBox(
                    height: (constraints.maxHeight * .36).clamp(230.0, 340.0),
                    child: list,
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: detail),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: 310, child: list),
                const SizedBox(width: 14),
                Expanded(child: detail),
              ],
            );
          },
        );
      },
    );
  }
}

class _TypeList extends StatelessWidget {
  const _TypeList({
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.loading,
    required this.search,
    required this.activeFilter,
    required this.onSearch,
    required this.onActive,
    required this.onSelect,
    required this.onRefresh,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });
  final List<Map<String, dynamic>> rows;
  final int total;
  final String? selectedId;
  final bool loading;
  final String search;
  final bool? activeFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool?> onActive;
  final ValueChanged<String?> onSelect;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final void Function(Map<String, dynamic> row, bool active) onToggleActive;

  @override
  Widget build(BuildContext context) => _AdminPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: onSearch,
                decoration: const InputDecoration(
                  hintText: 'Buscar tipos...',
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(LucideIcons.plus, size: 17),
            label: const Text('Nuevo tipo'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool?>(
          errorBuilder: pomgtValidationMessage,
          initialValue: activeFilter,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Estado'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos')),
            DropdownMenuItem(value: true, child: Text('Activos')),
            DropdownMenuItem(value: false, child: Text('Inactivos')),
          ],
          onChanged: onActive,
        ),
        const SizedBox(height: 12),
        Text(
          '$total tipos de material',
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const PomgtLoading()
              : rows.isEmpty
              ? EmptyState(
                  icon: LucideIcons.layoutGrid,
                  title: 'Aún no hay tipos de material',
                  message:
                      'Crea el primero para empezar a clasificar materiales.',
                  action: FilledButton.icon(
                    label: const Text('Crear tipo'),
                    icon: const Icon(LucideIcons.plus, size: 17),
                    onPressed: onCreate,
                  ),
                )
              : ScrollToTopArea(
                  padding: const EdgeInsets.all(10),
                  builder: (context, controller) => PomgtListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final selected = row['id']?.toString() == selectedId;
                      return InkWell(
                        borderRadius: PomgtRadii.borderSm,
                        onTap: () => onSelect(row['id']?.toString()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? PomgtColors.navySelected
                                : PomgtColors.canvas,
                            borderRadius: PomgtRadii.borderSm,
                            border: Border.all(
                              color: selected
                                  ? PomgtColors.navySelectedBorder
                                  : PomgtColors.line,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.layoutGrid,
                                size: 19,
                                color: PomgtColors.ink,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['name']?.toString() ?? 'Tipo',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${row['code'] ?? '—'} · ${UiCopy.enumLabel(row['system_class']?.toString() ?? 'raw_material')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PomgtColors.muted,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _Dot(active: row['is_active'] == true),
                              PopupMenuButton<String>(
                                popUpAnimationStyle: PomgtMotion.style(context),
                                tooltip: 'Acciones',
                                padding: EdgeInsets.zero,
                                onSelected: (value) {
                                  if (value == 'edit') onEdit(row);
                                  if (value == 'delete') onDelete(row);
                                  if (value == 'toggle') {
                                    onToggleActive(
                                      row,
                                      row['is_active'] != true,
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(LucideIcons.pencil, size: 17),
                                        SizedBox(width: 9),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          LucideIcons.trash2,
                                          size: 17,
                                          color: PomgtColors.danger,
                                        ),
                                        SizedBox(width: 9),
                                        Text(
                                          'Eliminar',
                                          style: TextStyle(
                                            color: PomgtColors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(
                                          row['is_active'] == true
                                              ? LucideIcons.circleOff
                                              : LucideIcons.circleCheck,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 9),
                                        Text(
                                          row['is_active'] == true
                                              ? 'Desactivar'
                                              : 'Reactivar',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    LucideIcons.ellipsisVertical,
                                    size: 17,
                                    color: PomgtColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _TypeDetail extends StatelessWidget {
  const _TypeDetail({
    super.key,
    required this.type,
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onDeactivate,
    required this.onReactivate,
    required this.onChanged,
  });
  final Map<String, dynamic> type;
  final _TypeAdminData data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final id = type['id']?.toString();
    final attrs = data.attributes
        .where((row) => row['material_type_id']?.toString() == id)
        .toList();
    final optionAttrs = attrs.where((row) {
      final type = row['data_type']?.toString();
      return type == 'select' || type == 'multiselect';
    }).toList();
    final optionAttrIds = optionAttrs
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    final materials = data.products
        .where((row) => row['material_type_id']?.toString() == id)
        .toList();
    return _AdminPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${type['code'] ?? '—'} · ${type['name'] ?? 'Tipo de material'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PomgtColors.ink,
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _Status(active: type['is_active'] == true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      UiCopy.enumLabel(
                        type['system_class']?.toString() ?? 'raw_material',
                      ),
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
                final actions = [
                  TextButton.icon(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: PomgtColors.danger,
                    ),
                    icon: const Icon(LucideIcons.trash2, size: 17),
                    label: const Text('Eliminar'),
                  ),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(LucideIcons.pencil, size: 17),
                    label: const Text('Editar'),
                  ),
                  TextButton.icon(
                    onPressed: type['is_active'] == true
                        ? onDeactivate
                        : onReactivate,
                    icon: Icon(
                      type['is_active'] == true
                          ? LucideIcons.pause
                          : LucideIcons.play,
                      size: 17,
                    ),
                    label: Text(
                      type['is_active'] == true ? 'Desactivar' : 'Reactivar',
                    ),
                  ),
                ];
                if (constraints.maxWidth < 680) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleBlock,
                      const SizedBox(height: 8),
                      Wrap(spacing: 4, runSpacing: 4, children: actions),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: titleBlock),
                    ...actions,
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: PomgtTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'General'),
                      Tab(text: 'Atributos'),
                      Tab(text: 'Materiales relacionados'),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ClipRect(
                      child: TabBarView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Wrap(
                              spacing: 28,
                              runSpacing: 18,
                              children: [
                                _Kv('Código', type['code']?.toString() ?? '—'),
                                _Kv('Nombre', type['name']?.toString() ?? '—'),
                                _Kv(
                                  'Clasificación',
                                  UiCopy.enumLabel(
                                    type['system_class']?.toString() ??
                                        'raw_material',
                                  ),
                                ),
                                _Kv(
                                  'Descripción',
                                  type['description']?.toString() ?? '—',
                                ),
                                _Kv(
                                  'Cantidad de atributos',
                                  attrs.length.toString(),
                                ),
                                _Kv(
                                  'Cantidad de materiales',
                                  materials.length.toString(),
                                ),
                                _Kv(
                                  'Estado',
                                  type['is_active'] == true
                                      ? 'Activo'
                                      : 'Inactivo',
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final definitions = EntityCrudPanel(
                                  table: 'material_attribute_definitions',
                                  repository: context.read<GenericRepository>(),
                                  lookups: context.read<LookupRepository>(),
                                  fixedValues: {'material_type_id': id},
                                  title: 'Atributos técnicos',
                                  description: 'Define las especificaciones que se capturan para este tipo de material.',
                                  onChanged: onChanged,
                                  flatList: true,
                                );
                                if (optionAttrs.isEmpty) return definitions;
                                final options = EntityCrudPanel(
                                  table: 'material_attribute_options',
                                  repository: context.read<GenericRepository>(),
                                  lookups: context.read<LookupRepository>(),
                                  title: 'Opciones para selección',
                                  description: 'Opciones permitidas para atributos de tipo selección o selección múltiple.',
                                  referenceRows: {
                                    'attribute_definition_id': optionAttrs,
                                  },
                                  rowFilter: (row) => optionAttrIds.contains(
                                    row['attribute_definition_id']?.toString(),
                                  ),
                                  flatList: true,
                                );
                                if (constraints.maxWidth < 760) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      definitions,
                                      const SizedBox(height: 12),
                                      options,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: definitions),
                                    const SizedBox(width: 12),
                                    Expanded(child: options),
                                  ],
                                );
                              },
                            ),
                          ),
                          _MaterialRows(rows: materials),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialRows extends StatelessWidget {
  const _MaterialRows({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'Sin materiales relacionados.',
          style: TextStyle(color: PomgtColors.muted),
        ),
      );
    }
    return ScrollToTopArea(
      padding: const EdgeInsets.all(10),
      builder: (context, controller) => PomgtListView.separated(
        controller: controller,
        padding: const EdgeInsets.all(18),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            dense: true,
            leading: const Icon(LucideIcons.box, color: PomgtColors.blue),
            title: Text('${row['sku'] ?? '—'} · ${row['name'] ?? 'Material'}'),
            trailing: _Status(active: row['is_active'] == true),
          );
        },
      ),
    );
  }
}

class _AdminPanel extends StatelessWidget {
  const _AdminPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
      boxShadow: PomgtShadows.card,
    ),
    child: child,
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => PomgtAnimatedValue(
    value: active,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(active: active),
        const SizedBox(width: 6),
        Text(
          active ? 'Activo' : 'Inactivo',
          style: TextStyle(
            color: active ? PomgtColors.mint : PomgtColors.danger,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: active ? PomgtColors.mint : PomgtColors.danger,
      shape: BoxShape.circle,
    ),
  );
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TypeAdminData {
  const _TypeAdminData({
    required this.types,
    required this.attributes,
    required this.products,
  });
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> attributes;
  final List<Map<String, dynamic>> products;
  factory _TypeAdminData.empty() =>
      const _TypeAdminData(types: [], attributes: [], products: []);
}
