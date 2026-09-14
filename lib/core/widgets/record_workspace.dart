import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../theme/pomgt_theme.dart';
import '../utils/ui_copy.dart';
import '../utils/error_copy.dart';
import 'empty_state.dart';
import 'entity_crud_panel.dart';
import 'info_tip.dart';
import 'motion.dart';
import 'pomgt_button.dart';
import 'section_header.dart';
import 'status_pill.dart';

class ChildTabDefinition {
  const ChildTabDefinition({
    required this.table,
    required this.label,
    required this.foreignKey,
    required this.help,
  });
  final String table;
  final String label;
  final String foreignKey;
  final String help;
}

class RecordWorkspace extends StatefulWidget {
  const RecordWorkspace({
    super.key,
    required this.title,
    required this.help,
    required this.masterTable,
    required this.controller,
    required this.detailBuilder,
    this.createLabel = 'Nuevo',
    this.createFixedValues = const {},
    this.rowFilter,
    this.enableDelete = true,
    this.createDialogBuilder,
    this.editDialogBuilder,
    this.createDialogTitle,
    this.createDialogDescription,
    this.createDialogIcon,
    this.formHiddenFields = const {},
    this.showRowActions = true,
    this.rowLeadingIcon,
    this.plainRowStatus = false,
  });

  final String title;
  final String help;
  final String masterTable;
  final FeatureSelectionController controller;
  final Widget Function(BuildContext context, Map<String, dynamic> selected)
  detailBuilder;
  final String createLabel;
  final Map<String, dynamic> createFixedValues;
  final bool Function(Map<String, dynamic> row)? rowFilter;
  final bool enableDelete;
  final Widget Function(BuildContext context)? createDialogBuilder;
  final Widget Function(BuildContext context, Map<String, dynamic> row)?
  editDialogBuilder;
  final String? createDialogTitle;
  final String? createDialogDescription;
  final IconData? createDialogIcon;
  final Set<String> formHiddenFields;
  final bool showRowActions;
  final IconData? rowLeadingIcon;
  final bool plainRowStatus;

  @override
  State<RecordWorkspace> createState() => _RecordWorkspaceState();
}

class _RecordWorkspaceState extends State<RecordWorkspace> {
  late Future<List<Map<String, dynamic>>> future;
  late int _seenControllerRevision;
  late int _seenRuntimeRevision;
  String search = '';

  GenericRepository get repository => context.read<GenericRepository>();
  LookupRepository get lookups => context.read<LookupRepository>();
  DbTableSpec get spec => Phase1Schema.tables[widget.masterTable]!;

  @override
  void initState() {
    super.initState();
    future = repository.listRows(spec);
    _seenControllerRevision = widget.controller.revision;
    _seenRuntimeRevision = context.read<RuntimeDataController>().revision;
  }

  @override
  void didUpdateWidget(covariant RecordWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionChanged =
        widget.controller.revision != _seenControllerRevision;
    if (revisionChanged) _seenControllerRevision = widget.controller.revision;
    if (oldWidget.masterTable != widget.masterTable) {
      _seenRuntimeRevision = context.read<RuntimeDataController>().revision;
    }
    if (oldWidget.masterTable != widget.masterTable || revisionChanged) {
      _reload();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revisionChanged =
        widget.controller.revision != _seenControllerRevision;
    final runtimeRevision = context.watch<RuntimeDataController>().revision;
    final runtimeChanged = runtimeRevision != _seenRuntimeRevision;
    if (!revisionChanged && !runtimeChanged) return;
    if (revisionChanged) _seenControllerRevision = widget.controller.revision;
    if (runtimeChanged) _seenRuntimeRevision = runtimeRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      future = repository.listRows(spec);
    });
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        if (row == null && widget.createDialogBuilder != null) {
          return widget.createDialogBuilder!(dialogContext);
        }
        if (row != null && widget.editDialogBuilder != null) {
          return widget.editDialogBuilder!(dialogContext, row);
        }
        return EntityFormDialog(
          spec: spec,
          repository: repository,
          lookups: lookups,
          original: row,
          fixedValues: row == null ? widget.createFixedValues : const {},
          title: row == null ? widget.createDialogTitle : null,
          description: row == null ? widget.createDialogDescription : null,
          icon: row == null ? widget.createDialogIcon : null,
          hiddenFields: widget.formHiddenFields,
        );
      },
    );
    if (changed == true) {
      lookups.invalidate(widget.masterTable);
      widget.controller.refresh();
      _seenControllerRevision = widget.controller.revision;
      _reload();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final label = _MasterList.displayFor(spec, row);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              CupertinoIcons.trash,
              size: 21,
              color: PomgtColors.danger,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Eliminar $label')),
          ],
        ),
        content: const Text(
          'Esta acción no se puede deshacer. Si el registro ya participa en pedidos, producción u otra trazabilidad, la base de datos puede impedir su eliminación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.deleteRow(spec, row);
      lookups.invalidate(widget.masterTable);
      widget.controller.clear();
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_workspaceFriendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(width: 8),
              InfoTip(widget.help, size: 18),
              const Spacer(),
              PomgtButton(
                label: widget.createLabel,
                icon: CupertinoIcons.add,
                onPressed: () => _edit(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return _WorkspaceError(
                    error: snapshot.error!,
                    onRetry: _reload,
                  );
                final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    rows.isEmpty)
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                final visibleRows = widget.rowFilter == null
                    ? rows
                    : rows.where(widget.rowFilter!).toList();
                final filtered = _filter(visibleRows);
                if (filtered.isNotEmpty &&
                    (widget.controller.selectedId == null ||
                        !filtered.any(
                          (r) =>
                              r['id']?.toString() ==
                              widget.controller.selectedId,
                        ))) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => widget.controller.select(
                      filtered.first['id']?.toString(),
                    ),
                  );
                }
                final selected = filtered
                    .cast<Map<String, dynamic>?>()
                    .firstWhere(
                      (r) =>
                          r?['id']?.toString() == widget.controller.selectedId,
                      orElse: () => filtered.isEmpty ? null : filtered.first,
                    );
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1040;
                    if (!wide) {
                      return Column(
                        children: [
                          SizedBox(
                            height: 290,
                            child: _MasterList(
                              spec: spec,
                              rows: filtered,
                              selectedId: selected?['id']?.toString(),
                              search: search,
                              onSearch: (v) => setState(() => search = v),
                              onSelect: widget.controller.select,
                              onEdit: _edit,
                              onDelete: widget.enableDelete ? _delete : null,
                              onRefresh: _reload,
                              showActions: widget.showRowActions,
                              leadingIcon: widget.rowLeadingIcon,
                              plainStatus: widget.plainRowStatus,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: SoftContentSwitch(
                              child: selected == null
                                  ? const _NothingSelected()
                                  : _DetailSurface(
                                      key: ValueKey(
                                        selected['id']?.toString() ?? selected,
                                      ),
                                      child: widget.detailBuilder(
                                        context,
                                        selected,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 330,
                          child: _MasterList(
                            spec: spec,
                            rows: filtered,
                            selectedId: selected?['id']?.toString(),
                            search: search,
                            onSearch: (v) => setState(() => search = v),
                            onSelect: widget.controller.select,
                            onEdit: _edit,
                            onDelete: widget.enableDelete ? _delete : null,
                            onRefresh: _reload,
                            showActions: widget.showRowActions,
                            leadingIcon: widget.rowLeadingIcon,
                            plainStatus: widget.plainRowStatus,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: SoftContentSwitch(
                            child: selected == null
                                ? const _NothingSelected()
                                : _DetailSurface(
                                    key: ValueKey(
                                      selected['id']?.toString() ?? selected,
                                    ),
                                    child: widget.detailBuilder(
                                      context,
                                      selected,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (r) => r.values.any(
            (v) => v != null && v.toString().toLowerCase().contains(q),
          ),
        )
        .toList();
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(
          color: PomgtColors.lineStrong.withValues(alpha: .65),
        ),
        boxShadow: PomgtShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _MasterList extends StatelessWidget {
  const _MasterList({
    required this.spec,
    required this.rows,
    required this.selectedId,
    required this.search,
    required this.onSearch,
    required this.onSelect,
    required this.onEdit,
    required this.onRefresh,
    required this.showActions,
    required this.plainStatus,
    this.leadingIcon,
    this.onDelete,
  });
  final DbTableSpec spec;
  final List<Map<String, dynamic>> rows;
  final String? selectedId;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onSelect;
  final Future<void> Function([Map<String, dynamic>?]) onEdit;
  final Future<void> Function(Map<String, dynamic>)? onDelete;
  final VoidCallback onRefresh;
  final bool showActions;
  final bool plainStatus;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(color: PomgtColors.line),
        boxShadow: PomgtShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextField(
                      onChanged: onSearch,
                      decoration: const InputDecoration(
                        hintText: 'Buscar',
                        prefixIcon: Icon(CupertinoIcons.search, size: 20),
                        prefixIconConstraints: BoxConstraints(minWidth: 46),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: onRefresh,
                  icon: const Icon(CupertinoIcons.refresh, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      search.isEmpty ? 'Sin registros' : 'Sin resultados',
                      style: const TextStyle(color: PomgtColors.muted),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final id = row['id']?.toString();
                      final selected = id == selectedId;
                      final status =
                          row['status']?.toString() ??
                          row['line_status']?.toString();
                      return SmoothHover(
                        selected: selected,
                        selectedColor: PomgtColors.navySelected,
                        hoverColor: PomgtColors.surfaceAlt.withValues(
                          alpha: .55,
                        ),
                        borderColor: selected
                            ? PomgtColors.navySelectedBorder
                            : PomgtColors.line,
                        lift: .2,
                        padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
                        onTap: () => onSelect(id),
                        onDoubleTap: () => onEdit(row),
                        child: Row(
                          children: [
                            if (leadingIcon != null) ...[
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: Icon(
                                  leadingIcon,
                                  size: 16,
                                  color: selected
                                      ? PomgtColors.navy
                                      : PomgtColors.secondaryInk,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayFor(spec, row),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: PomgtColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _subtitle(spec, row),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: PomgtColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (status != null && !showActions)
                              StatusPill(status, plain: plainStatus),
                            if (showActions)
                              PopupMenuButton<String>(
                                tooltip: 'Acciones',
                                padding: EdgeInsets.zero,
                                onSelected: (value) {
                                  if (value == 'edit') onEdit(row);
                                  if (value == 'delete') onDelete?.call(row);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(CupertinoIcons.pencil, size: 17),
                                        SizedBox(width: 9),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  if (onDelete != null)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            CupertinoIcons.trash,
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
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    CupertinoIcons.ellipsis_vertical,
                                    size: 17,
                                    color: PomgtColors.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String displayFor(DbTableSpec spec, Map<String, dynamic> row) {
    final parts = spec.displayFields
        .map((f) => row[f])
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .map((v) => v.toString())
        .toList();
    return parts.isEmpty ? 'Registro' : parts.join(' · ');
  }

  static String _subtitle(DbTableSpec spec, Map<String, dynamic> row) {
    for (final field in spec.fields) {
      if (field.hidden ||
          spec.displayFields.contains(field.name) ||
          field.name == 'status' ||
          field.referenceTable != null)
        continue;
      final value = row[field.name];
      if (value != null && value.toString().trim().isNotEmpty) {
        final shown = field.kind == DbFieldKind.enumValue
            ? UiCopy.enumLabel(value.toString())
            : value.toString();
        return '${UiCopy.fieldLabel(field.name, field.label)}: $shown';
      }
    }
    return UiCopy.tableDescription(spec.table, spec.description);
  }
}

class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.plainStatus = false,
    this.onEdit,
    this.icon,
    required this.help,
  });
  final String title;
  final String? subtitle;
  final String? status;
  final bool plainStatus;
  final VoidCallback? onEdit;
  final IconData? icon;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 18, 19),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: PomgtColors.blue),
                      const SizedBox(width: 9),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 7),
                    InfoTip(help, size: 16),
                    if (status != null) ...[
                      const SizedBox(width: 10),
                      StatusPill(status!, plain: plainStatus),
                    ],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: 'Editar información principal',
              onPressed: onEdit,
              icon: const Icon(CupertinoIcons.pencil, size: 18),
            ),
        ],
      ),
    );
  }
}

class ChildTabs extends StatelessWidget {
  const ChildTabs({
    super.key,
    required this.parentId,
    required this.tabs,
    required this.repository,
    required this.lookups,
    this.referenceRows = const {},
    this.flatList = false,
  });
  final String parentId;
  final List<ChildTabDefinition> tabs;
  final GenericRepository repository;
  final LookupRepository lookups;
  final Map<String, Map<String, List<Map<String, dynamic>>>> referenceRows;
  final bool flatList;

  @override
  Widget build(BuildContext context) {
    if (tabs.length == 1) {
      final t = tabs.first;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: EntityCrudPanel(
          table: t.table,
          repository: repository,
          lookups: lookups,
          fixedValues: {t.foreignKey: parentId},
          title: t.label,
          description: t.help,
          referenceRows: referenceRows[t.table] ?? const {},
          flatList: flatList,
        ),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorColor: PomgtColors.blue,
              labelColor: PomgtColors.ink,
              unselectedLabelColor: PomgtColors.muted,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: tabs
                  .map(
                    (t) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.label),
                          const SizedBox(width: 5),
                          InfoTip(t.help, size: 13),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: tabs
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: EntityCrudPanel(
                        table: t.table,
                        repository: repository,
                        lookups: lookups,
                        fixedValues: {t.foreignKey: parentId},
                        title: t.label,
                        description: t.help,
                        referenceRows: referenceRows[t.table] ?? const {},
                        flatList: flatList,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class NestedRelationPanel extends StatefulWidget {
  const NestedRelationPanel({
    super.key,
    required this.title,
    required this.help,
    required this.parentTable,
    required this.parentFilter,
    required this.childTabs,
    required this.repository,
    required this.lookups,
    this.childReferenceRows = const {},
    this.flatList = false,
  });
  final String title;
  final String help;
  final String parentTable;
  final Map<String, dynamic> parentFilter;
  final List<ChildTabDefinition> childTabs;
  final GenericRepository repository;
  final LookupRepository lookups;
  final Map<String, Map<String, List<Map<String, dynamic>>>> childReferenceRows;
  final bool flatList;

  @override
  State<NestedRelationPanel> createState() => _NestedRelationPanelState();
}

class _NestedRelationPanelState extends State<NestedRelationPanel> {
  String? selected;
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    future = widget.repository.listRows(
      Phase1Schema.tables[widget.parentTable]!,
      filters: widget.parentFilter,
    );
  }

  void reload() {
    setState(() {
      future = widget.repository.listRows(
        Phase1Schema.tables[widget.parentTable]!,
        filters: widget.parentFilter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = Phase1Schema.tables[widget.parentTable]!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: widget.title,
            help: widget.help,
            subtitle: widget.help,
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Expanded(
                  child: _WorkspaceError(
                    error: snapshot.error!,
                    onRetry: reload,
                  ),
                );
              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              if (rows.isEmpty)
                return Expanded(
                  child: EmptyState(
                    title:
                        'Primero agrega ${UiCopy.tableTitle(spec.table, spec.title).toLowerCase()}',
                    message:
                        'Esta sección depende de un registro padre. Créalo en la pestaña correspondiente y vuelve aquí.',
                  ),
                );
              selected ??= rows.first['id']?.toString();
              final current = rows.any((r) => r['id']?.toString() == selected)
                  ? selected
                  : rows.first['id']?.toString();
              selected = current;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: current,
                            decoration: InputDecoration(
                              labelText:
                                  'Seleccionar ${UiCopy.tableTitle(spec.table, spec.title).toLowerCase()}',
                            ),
                            items: rows
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r['id']?.toString(),
                                    child: Text(
                                      widget.lookups.display(spec, r),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => selected = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Actualizar',
                          onPressed: reload,
                          icon: const Icon(CupertinoIcons.refresh, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ChildTabs(
                        parentId: current!,
                        tabs: widget.childTabs,
                        repository: widget.repository,
                        lookups: widget.lookups,
                        referenceRows: widget.childReferenceRows,
                        flatList: widget.flatList,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();
  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: CupertinoIcons.square_list,
    title: 'Selecciona un registro',
    message: 'El detalle y sus relaciones aparecerán aquí.',
  );
}

class _WorkspaceError extends StatelessWidget {
  const _WorkspaceError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: CupertinoIcons.exclamationmark_triangle,
    title: 'No pudimos cargar la información',
    message: ErrorCopy.message(
      error,
      fallback: 'No fue posible cargar los datos. Inténtalo de nuevo.',
    ),
    action: PomgtButton(
      label: 'Reintentar',
      primary: false,
      onPressed: onRetry,
    ),
  );
}

String _workspaceFriendlyError(Object error) => ErrorCopy.message(error);
