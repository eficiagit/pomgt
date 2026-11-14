import 'motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../controllers/runtime_data_controller.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../theme/pomgt_theme.dart';
import '../utils/app_notice.dart';
import '../utils/ui_copy.dart';
import '../utils/error_copy.dart';
import 'categorized_picker.dart';
import 'empty_state.dart';
import 'info_tip.dart';
import 'number_input.dart';
import 'pomgt_button.dart';
import 'scroll_to_top.dart';
import 'section_header.dart';
import 'status_pill.dart';
import 'pomgt_date_picker.dart';

class EntityCrudPanel extends StatefulWidget {
  const EntityCrudPanel({
    super.key,
    required this.table,
    required this.repository,
    required this.lookups,
    this.fixedValues = const {},
    this.title,
    this.description,
    this.compact = false,
    this.onChanged,
    this.referenceFilters = const {},
    this.referenceRows = const {},
    this.rowFilter,
    this.flatList = false,
    this.tableView = false,
  });

  final String table;
  final GenericRepository repository;
  final LookupRepository lookups;
  final Map<String, dynamic> fixedValues;
  final String? title;
  final String? description;
  final bool compact;
  final VoidCallback? onChanged;
  final Map<String, Map<String, dynamic>> referenceFilters;
  final Map<String, List<Map<String, dynamic>>> referenceRows;
  final bool Function(Map<String, dynamic>)? rowFilter;
  final bool flatList;
  final bool tableView;

  @override
  State<EntityCrudPanel> createState() => _EntityCrudPanelState();
}

class _EntityCrudPanelState extends State<EntityCrudPanel> {
  late Future<List<Map<String, dynamic>>> _future;
  Future<Map<String, List<Map<String, dynamic>>>>? _refFuture;
  late int _seenRuntimeRevision;
  String _search = '';
  final Set<String> _selectedIds = {};

  DbTableSpec get spec => Phase1Schema.tables[widget.table]!;

  @override
  void initState() {
    super.initState();
    _seenRuntimeRevision = context.read<RuntimeDataController>().revisionFor(
      widget.table,
    );
    _reload();
  }

  @override
  void didUpdateWidget(covariant EntityCrudPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table ||
        oldWidget.fixedValues.toString() != widget.fixedValues.toString() ||
        oldWidget.referenceRows.toString() != widget.referenceRows.toString() ||
        oldWidget.rowFilter != widget.rowFilter) {
      _seenRuntimeRevision = context.read<RuntimeDataController>().revisionFor(
        widget.table,
      );
      _reload();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<RuntimeDataController>().revisionFor(
      widget.table,
    );
    if (revision == _seenRuntimeRevision) return;
    _seenRuntimeRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    _selectedIds.clear();
    _future = widget.repository
        .listRows(spec, filters: widget.fixedValues)
        .then(
          (rows) => widget.rowFilter == null
              ? rows
              : rows.where(widget.rowFilter!).toList(),
        );
    if (widget.tableView) {
      final refTables = spec.fields
          .where((f) => !f.hidden && f.referenceTable != null)
          .map((f) => f.referenceTable!)
          .toSet();
      _refFuture = Future.wait(
        refTables.map(
          (t) => widget.lookups.rows(t).then((rows) => MapEntry(t, rows)),
        ),
      ).then(Map.fromEntries);
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (spec.readOnly) return;
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: spec,
        repository: widget.repository,
        lookups: widget.lookups,
        original: row,
        fixedValues: widget.fixedValues,
        referenceFilters: widget.referenceFilters,
        referenceRows: widget.referenceRows,
      ),
    );
    if (changed == true) {
      widget.lookups.invalidate(widget.table);
      _reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    try {
      final blocked = await widget.repository.deletionBlockReason(spec, row);
      if (!mounted) return;
      if (blocked != null) {
        await showPomgtDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: pomgtDialogTitle(
              context,
              spec.table == 'material_types'
                  ? 'Tipo de material en uso'
                  : 'Categoría en uso',
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Text(blocked),
            ),
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
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, _friendlyError(e), isError: true);
      }
      return;
    }
    final ok = await showPomgtDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          'Eliminar registro',
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'Esta acción no se puede deshacer. Los registros relacionados pueden impedir la eliminación para proteger la trazabilidad.',
          ),
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
    if (ok != true) return;
    try {
      await widget.repository.deleteRow(spec, row);
      widget.lookups.invalidate(widget.table);
      _reload();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(context, _friendlyError(e), isError: true);
    }
  }

  Future<void> _removeSelected(List<Map<String, dynamic>> rows) async {
    final selected = rows
        .where((r) => _selectedIds.contains(r['id']?.toString()))
        .toList();
    if (selected.isEmpty) return;
    final ok = await showPomgtDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          selected.length == 1
              ? 'Eliminar registro'
              : 'Eliminar ${selected.length} registros',
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'Esta acción no se puede deshacer. Los registros relacionados pueden impedir la eliminación para proteger la trazabilidad.',
          ),
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
    if (ok != true) return;
    var deleted = 0;
    var blocked = 0;
    for (final row in selected) {
      try {
        final reason = await widget.repository.deletionBlockReason(spec, row);
        if (reason != null) {
          blocked++;
          continue;
        }
        await widget.repository.deleteRow(spec, row);
        deleted++;
      } catch (_) {
        blocked++;
      }
    }
    widget.lookups.invalidate(widget.table);
    _reload();
    widget.onChanged?.call();
    if (!mounted) return;
    showPomgtSnackBar(
      context,
      blocked == 0
          ? (deleted == 1
                ? 'Registro eliminado.'
                : '$deleted registros eliminados.')
          : '$deleted eliminados, $blocked no se pudieron eliminar (tienen registros relacionados).',
      isError: blocked > 0 && deleted == 0,
    );
  }

  bool get _hasActiveFilters => _search.trim().isNotEmpty;

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (row) => row.values.any(
            (v) => v != null && v.toString().toLowerCase().contains(q),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final rows = _filter(snapshot.data ?? const []);
        // The empty state below already offers its own "Crear registro"
        // button; showing "Nuevo" here too would just duplicate it.
        final showHeaderCreate = !spec.readOnly && !(!loading && rows.isEmpty);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: widget.title ?? UiCopy.tableTitle(spec.table, spec.title),
              help:
                  widget.description ??
                  UiCopy.tableDescription(spec.table, spec.description),
              subtitle:
                  widget.description ??
                  UiCopy.tableDescription(spec.table, spec.description),
              trailing: showHeaderCreate
                  ? PomgtButton(
                      label: 'Nuevo',
                      icon: LucideIcons.plus,
                      onPressed: () => _edit(),
                    )
                  : null,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar…',
                      prefixIcon: Icon(LucideIcons.search, size: 19),
                      prefixIconConstraints: BoxConstraints(minWidth: 34),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  tooltip: 'Actualizar información',
                  onPressed: _reload,
                  icon: const Icon(LucideIcons.refreshCw),
                ),
              ],
            ),
            if (widget.tableView) ...[
              const SizedBox(height: 14),
              Builder(
                builder: (context) {
                  final selected = rows
                      .where((r) => _selectedIds.contains(r['id']?.toString()))
                      .toList();
                  return _SelectionToolbar(
                    selectedCount: selected.length,
                    onEdit: !spec.readOnly && selected.length == 1
                        ? () => _edit(selected.first)
                        : null,
                    onDelete: !spec.readOnly && selected.isNotEmpty
                        ? () => _removeSelected(rows)
                        : null,
                    onClear: () => setState(_selectedIds.clear),
                  );
                },
              ),
            ],
            const SizedBox(height: 18),
            Expanded(child: _body(snapshot, loading, rows)),
          ],
        );
      },
    );
  }

  Widget _body(
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
    bool loading,
    List<Map<String, dynamic>> rows,
  ) {
    if (snapshot.hasError) {
      return _ErrorState(
        message: _friendlyError(snapshot.error!),
        onRetry: _reload,
      );
    }
    if (!loading && rows.isEmpty) {
      return EmptyState(
        title: _hasActiveFilters
            ? 'Sin resultados'
            : 'Todavía no hay registros',
        message: _hasActiveFilters
            ? 'Prueba con otro término de búsqueda o quita algún filtro.'
            : 'Agrega el primer registro para comenzar a utilizar esta sección.',
        action: spec.readOnly
            ? null
            : PomgtButton(
                label: 'Crear registro',
                icon: LucideIcons.plus,
                onPressed: () => _edit(),
              ),
      );
    }
    final displayRows = loading
        ? List.generate(
            5,
            (_) => <String, dynamic>{
              'id': 'loading',
              for (final f in spec.displayFields) f: 'Cargando información',
            },
          )
        : rows;
    return TickerMode(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: Skeletonizer(
        enabled: loading,
        child: widget.tableView
            ? FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _refFuture,
                builder: (context, refSnapshot) => _RecordTable(
                  spec: spec,
                  rows: displayRows,
                  lookups: widget.lookups,
                  refMap: refSnapshot.data ?? const {},
                  selectedIds: _selectedIds,
                  enabled: !loading,
                  onToggleRow: (id, value) => setState(() {
                    if (value) {
                      _selectedIds.add(id);
                    } else {
                      _selectedIds.remove(id);
                    }
                  }),
                  onToggleAll: (ids, select) => setState(() {
                    if (select) {
                      _selectedIds.addAll(ids);
                    } else {
                      _selectedIds.removeAll(ids);
                    }
                  }),
                ),
              )
            : _RecordList(
                spec: spec,
                rows: displayRows,
                onEdit: spec.readOnly ? null : _edit,
                onDelete: spec.readOnly ? null : _remove,
                flat: widget.flatList,
              ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.spec,
    required this.rows,
    required this.flat,
    this.onEdit,
    this.onDelete,
  });
  final DbTableSpec spec;
  final List<Map<String, dynamic>> rows;
  final bool flat;
  final void Function(Map<String, dynamic>)? onEdit;
  final void Function(Map<String, dynamic>)? onDelete;

  @override
  Widget build(BuildContext context) {
    final visibleFields = spec.fields
        .where((f) => !f.hidden && !f.readOnly && f.referenceTable == null)
        .take(6)
        .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        border: flat
            ? null
            : Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
        borderRadius: PomgtRadii.borderMd,
      ),
      child: ClipRRect(
        borderRadius: PomgtRadii.borderMd,
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(10),
          builder: (context, controller) => PomgtListView.separated(
            controller: controller,
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: PomgtColors.line),
            itemBuilder: (context, index) {
              final row = rows[index];
              final title = _display(spec, row);
              final status = row['status']?.toString();
              return InkWell(
                onTap: onEdit == null ? null : () => onEdit!(row),
                hoverColor: PomgtColors.surfaceAlt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      color: PomgtColors.ink,
                                    ),
                                  ),
                                ),
                                if (status != null) ...[
                                  const SizedBox(width: 10),
                                  StatusPill(status),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 22,
                              runSpacing: 6,
                              children: visibleFields
                                  .where(
                                    (f) =>
                                        row[f.name] != null &&
                                        !spec.displayFields.contains(f.name) &&
                                        f.name != 'status',
                                  )
                                  .take(4)
                                  .map((f) {
                                    final raw = row[f.name];
                                    final value =
                                        f.kind == DbFieldKind.enumValue
                                        ? UiCopy.enumLabel(raw.toString())
                                        : _short(raw);
                                    return Text.rich(
                                      TextSpan(
                                        text:
                                            '${UiCopy.fieldLabel(f.name, f.label)} ',
                                        style: const TextStyle(
                                          color: PomgtColors.muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: value,
                                            style: const TextStyle(
                                              color: PomgtColors.secondaryInk,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  })
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                      if (onEdit != null)
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => onEdit!(row),
                          icon: const Icon(LucideIcons.pencil, size: 18),
                        ),
                      if (onDelete != null)
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () => onDelete!(row),
                          icon: const Icon(LucideIcons.trash2, size: 18),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static String _display(DbTableSpec spec, Map<String, dynamic> row) {
    final parts = spec.displayFields
        .map((f) => row[f])
        .where((v) => v != null && v.toString().isNotEmpty)
        .map((e) => e.toString())
        .toList();
    return parts.isEmpty ? 'Registro' : parts.join(' · ');
  }

  static String _short(dynamic value) {
    if (value is Map || value is List) return jsonEncode(value);
    final text = value.toString();
    return text.length > 80 ? '${text.substring(0, 77)}…' : text;
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    this.onEdit,
    this.onDelete,
    this.onClear,
  });

  final int selectedCount;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PomgtColors.surfaceAlt,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(color: PomgtColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              LucideIcons.listChecks,
              size: 16,
              color: selectedCount > 0 ? PomgtColors.blue : PomgtColors.muted,
            ),
            const SizedBox(width: 8),
            Text(
              selectedCount == 0
                  ? 'Selecciona registros para editarlos o eliminarlos'
                  : selectedCount == 1
                  ? '1 seleccionado'
                  : '$selectedCount seleccionados',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selectedCount > 0 ? PomgtColors.ink : PomgtColors.muted,
              ),
            ),
            if (selectedCount > 0) ...[
              const SizedBox(width: 10),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Deseleccionar',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(LucideIcons.pencil, size: 15),
              label: const Text('Ver / Editar'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(LucideIcons.trash2, size: 15),
              label: const Text('Eliminar'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12.5),
                foregroundColor: PomgtColors.danger,
                side: BorderSide(
                  color: onDelete == null
                      ? PomgtColors.line
                      : PomgtColors.danger.withValues(alpha: .5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTable extends StatefulWidget {
  const _RecordTable({
    required this.spec,
    required this.rows,
    required this.lookups,
    required this.refMap,
    required this.selectedIds,
    required this.onToggleRow,
    required this.onToggleAll,
    this.enabled = true,
  });

  final DbTableSpec spec;
  final List<Map<String, dynamic>> rows;
  final LookupRepository lookups;
  final Map<String, List<Map<String, dynamic>>> refMap;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggleRow;
  final void Function(List<String> ids, bool select) onToggleAll;
  final bool enabled;

  @override
  State<_RecordTable> createState() => _RecordTableState();
}

class _RecordTableState extends State<_RecordTable> {
  String? _sortField;
  bool _sortAscending = true;

  static const double _minColWidth = 170;
  static const double _checkboxWidth = 44;

  DbTableSpec get spec => widget.spec;

  List<DbFieldSpec> _columns(double maxWidth) {
    final candidates = <DbFieldSpec>[];
    final seen = <String>{};
    DbFieldSpec? byName(String name) {
      for (final f in spec.fields) {
        if (f.name == name) return f;
      }
      return null;
    }

    for (final name in spec.displayFields) {
      final f = byName(name);
      if (f != null && !f.hidden && seen.add(f.name)) candidates.add(f);
    }
    for (final f in spec.fields) {
      if (f.hidden || f.readOnly) continue;
      if (seen.add(f.name)) candidates.add(f);
    }
    if (candidates.isEmpty) return candidates;
    final available = (maxWidth - _checkboxWidth).clamp(
      _minColWidth,
      double.infinity,
    );
    final maxCols = (available / _minColWidth).floor().clamp(
      1,
      candidates.length,
    );
    return candidates.take(maxCols).toList();
  }

  Map<String, dynamic>? _refRow(DbFieldSpec field, dynamic raw) {
    if (raw == null) return null;
    final rows = widget.refMap[field.referenceTable!] ?? const [];
    for (final r in rows) {
      if (r[field.referenceColumn]?.toString() == raw.toString()) return r;
    }
    return null;
  }

  String _cellText(DbFieldSpec f, Map<String, dynamic> row) {
    final raw = row[f.name];
    if (raw == null) return '—';
    if (f.referenceTable != null) {
      final refSpec = Phase1Schema.tables[f.referenceTable!];
      final match = _refRow(f, raw);
      if (refSpec == null || match == null) return raw.toString();
      return widget.lookups.display(refSpec, match);
    }
    if (f.kind == DbFieldKind.enumValue)
      return UiCopy.enumLabel(raw.toString());
    if (f.kind == DbFieldKind.booleanValue) return raw == true ? 'Sí' : 'No';
    if (f.kind == DbFieldKind.dateTimeValue ||
        f.kind == DbFieldKind.dateValue) {
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw.toString()));
      } catch (_) {
        return raw.toString();
      }
    }
    final text = raw.toString();
    return text.length > 60 ? '${text.substring(0, 57)}…' : text;
  }

  int _compare(DbFieldSpec f, Map<String, dynamic> a, Map<String, dynamic> b) {
    final ra = a[f.name];
    final rb = b[f.name];
    if (ra == null && rb == null) return 0;
    if (ra == null) return -1;
    if (rb == null) return 1;
    if (f.kind == DbFieldKind.numberValue ||
        f.kind == DbFieldKind.integerValue) {
      final na = num.tryParse(ra.toString());
      final nb = num.tryParse(rb.toString());
      if (na != null && nb != null) return na.compareTo(nb);
    }
    if (f.kind == DbFieldKind.booleanValue) {
      return (ra == true ? 1 : 0).compareTo(rb == true ? 1 : 0);
    }
    return _cellText(
      f,
      a,
    ).toLowerCase().compareTo(_cellText(f, b).toLowerCase());
  }

  List<Map<String, dynamic>> _sortedRows(List<DbFieldSpec> columns) {
    if (_sortField == null || !widget.enabled) return widget.rows;
    DbFieldSpec? field;
    for (final f in columns) {
      if (f.name == _sortField) {
        field = f;
        break;
      }
    }
    if (field == null) return widget.rows;
    final sorted = List<Map<String, dynamic>>.of(widget.rows);
    sorted.sort((a, b) {
      final cmp = _compare(field!, a, b);
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  void _toggleSort(String fieldName) {
    setState(() {
      if (_sortField == fieldName) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = fieldName;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columns(constraints.maxWidth);
        final available = (constraints.maxWidth - _checkboxWidth).clamp(
          _minColWidth,
          double.infinity,
        );
        final colWidth = columns.isEmpty
            ? _minColWidth
            : available / columns.length;
        final rows = _sortedRows(columns);
        final rowIds = [
          for (final r in rows)
            if (r['id'] != null) r['id'].toString(),
        ];
        final allSelected =
            widget.enabled &&
            rowIds.isNotEmpty &&
            rowIds.every(widget.selectedIds.contains);
        final someSelected =
            !allSelected && rowIds.any(widget.selectedIds.contains);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: PomgtColors.canvas,
            border: Border.all(
              color: PomgtColors.lineStrong.withValues(alpha: .55),
            ),
            borderRadius: PomgtRadii.borderMd,
          ),
          child: ClipRRect(
            borderRadius: PomgtRadii.borderMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: PomgtColors.surfaceAlt,
                    border: Border(bottom: BorderSide(color: PomgtColors.line)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _checkboxWidth,
                        child: Checkbox(
                          tristate: true,
                          value: allSelected
                              ? true
                              : (someSelected ? null : false),
                          onChanged: !widget.enabled || rowIds.isEmpty
                              ? null
                              : (_) => widget.onToggleAll(rowIds, !allSelected),
                        ),
                      ),
                      for (final f in columns)
                        SizedBox(
                          width: colWidth,
                          child: InkWell(
                            onTap: () => _toggleSort(f.name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      UiCopy.fieldLabel(f.name, f.label),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: PomgtColors.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    _sortField != f.name
                                        ? LucideIcons.chevronsUpDown
                                        : (_sortAscending
                                              ? LucideIcons.arrowUp
                                              : LucideIcons.arrowDown),
                                    size: 13,
                                    color: _sortField == f.name
                                        ? PomgtColors.blue
                                        : PomgtColors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ScrollToTopArea(
                    padding: const EdgeInsets.all(10),
                    builder: (context, controller) => PomgtListView.separated(
                      controller: controller,
                      padding: EdgeInsets.zero,
                      itemCount: rows.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: PomgtColors.line),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = row['id']?.toString();
                        final selected =
                            id != null && widget.selectedIds.contains(id);
                        return InkWell(
                          onTap: !widget.enabled || id == null
                              ? null
                              : () => widget.onToggleRow(id, !selected),
                          hoverColor: PomgtColors.surfaceAlt,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: selected
                                  ? PomgtColors.blue.withValues(alpha: .06)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: _checkboxWidth,
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: !widget.enabled || id == null
                                        ? null
                                        : (v) => widget.onToggleRow(
                                            id,
                                            v ?? false,
                                          ),
                                  ),
                                ),
                                for (final f in columns)
                                  SizedBox(
                                    width: colWidth,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 14,
                                      ),
                                      child:
                                          f.name == 'status' &&
                                              f.kind == DbFieldKind.enumValue
                                          ? Align(
                                              alignment: Alignment.centerLeft,
                                              child: StatusPill(
                                                row[f.name].toString(),
                                              ),
                                            )
                                          : Text(
                                              _cellText(f, row),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: PomgtColors.secondaryInk,
                                              ),
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
          ),
        );
      },
    );
  }
}

class EntityFormDialog extends StatefulWidget {
  const EntityFormDialog({
    super.key,
    required this.spec,
    required this.repository,
    required this.lookups,
    this.original,
    this.fixedValues = const {},
    this.title,
    this.description,
    this.icon,
    this.onSaved,
    this.afterSaved,
    this.extraContentBuilder,
    this.scrollToExtraWhenShown = false,
    this.hiddenFields = const {},
    this.referenceFilters = const {},
    this.referenceRows = const {},
  });

  final DbTableSpec spec;
  final GenericRepository repository;
  final LookupRepository lookups;
  final Map<String, dynamic>? original;
  final Map<String, dynamic> fixedValues;
  final String? title;
  final String? description;
  final IconData? icon;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  final FutureOr<void> Function(Map<String, dynamic>)? afterSaved;
  final Widget? Function(BuildContext, Map<String, dynamic>)?
  extraContentBuilder;
  final bool scrollToExtraWhenShown;
  final Set<String> hiddenFields;
  final Map<String, Map<String, dynamic>> referenceFilters;
  final Map<String, List<Map<String, dynamic>>> referenceRows;

  @override
  State<EntityFormDialog> createState() => _EntityFormDialogState();
}

class _EntityFormDialogState extends State<EntityFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;
  bool _extraShown = false;

  bool get editing => widget.original != null;

  @override
  void initState() {
    super.initState();
    _values.addAll(widget.original ?? const {});
    if (!editing) {
      for (final field in widget.spec.fields) {
        if (field.defaultValue != null && !_values.containsKey(field.name)) {
          _values[field.name] = field.defaultValue;
        }
      }
    }
    _values.addAll(widget.fixedValues);
    for (final field in widget.spec.fields) {
      if (field.hidden ||
          widget.hiddenFields.contains(field.name) ||
          field.readOnly ||
          (GenericRepository.autoGeneratedFields[widget.spec.table]?.contains(
                field.name,
              ) ??
              false) ||
          field.kind == DbFieldKind.booleanValue ||
          field.kind == DbFieldKind.enumValue ||
          field.kind == DbFieldKind.reference ||
          field.referenceTable != null ||
          _isCountryField(field.name)) {
        continue;
      }
      _controllers[field.name] = TextEditingController(
        text: _formatInitial(field, _values[field.name]),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatInitial(DbFieldSpec field, dynamic value) {
    if (value == null) return '';
    if (field.kind == DbFieldKind.jsonValue) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    }
    if (field.kind == DbFieldKind.numberValue ||
        field.kind == DbFieldKind.integerValue) {
      return formatNumberText(value);
    }
    return value.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      for (final field in widget.spec.fields) {
        final c = _controllers[field.name];
        if (c != null) _values[field.name] = _parse(field, c.text.trim());
      }
      final Map<String, dynamic> saved;
      if (editing) {
        saved = await widget.repository.updateAnyRow(
          widget.spec,
          widget.original!,
          _values,
        );
      } else {
        saved = await widget.repository.createRow(widget.spec, _values);
      }
      widget.onSaved?.call(saved);
      await widget.afterSaved?.call(saved);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  dynamic _parse(DbFieldSpec field, String value) {
    if (value.isEmpty) return null;
    switch (field.kind) {
      case DbFieldKind.numberValue:
        return double.parse(value.replaceAll(',', ''));
      case DbFieldKind.integerValue:
        return int.parse(value.replaceAll(',', ''));
      case DbFieldKind.jsonValue:
        return jsonDecode(value);
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.spec.fields
        .where(
          (f) =>
              !f.hidden &&
              !widget.hiddenFields.contains(f.name) &&
              !f.readOnly &&
              !(GenericRepository.autoGeneratedFields[widget.spec.table]
                      ?.contains(f.name) ??
                  false) &&
              !widget.fixedValues.containsKey(f.name),
        )
        .toList();
    final tableTitle = UiCopy.tableTitle(widget.spec.table, widget.spec.title);
    final title =
        widget.title ??
        (editing
            ? 'Editar $tableTitle'
            : _newTitle(widget.spec.table, tableTitle));
    final description =
        widget.description ??
        UiCopy.tableDescription(widget.spec.table, widget.spec.description);
    final media = MediaQuery.sizeOf(context);
    final compact = media.width < 640;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? media.width - 20 : 880,
          maxHeight: media.height * (compact ? .96 : .90),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 30,
            compact ? 16 : 24,
            compact ? 16 : 30,
            compact ? 14 : 22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      widget.icon ?? _iconForTable(widget.spec.table),
                      size: 25,
                      color: PomgtColors.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (description.isNotEmpty) ...[
                              InfoTip(description, size: 16),
                            ],
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            description,
                            style: const TextStyle(
                              color: PomgtColors.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const Divider(height: 30),
              Flexible(
                child: Form(
                  key: _formKey,
                  child: ScrollToTopArea(
                    padding: const EdgeInsets.all(12),
                    builder: (context, controller) => SingleChildScrollView(
                      controller: controller,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 680;
                            final extra = widget.extraContentBuilder?.call(
                              context,
                              Map.unmodifiable(_values),
                            );
                            final revealExtra = extra != null && !_extraShown;
                            _extraShown = extra != null;
                            if (widget.scrollToExtraWhenShown && revealExtra) {
                              WidgetsBinding.instance.addPostFrameCallback((
                                _,
                              ) async {
                                // Let cached material lookups finish their first
                                // layout before measuring the final scroll extent.
                                await WidgetsBinding.instance.endOfFrame;
                                if (!mounted ||
                                    !_extraShown ||
                                    !controller.hasClients) {
                                  return;
                                }
                                final duration = PomgtMotion.duration(
                                  this.context,
                                  const Duration(milliseconds: 420),
                                );
                                final target =
                                    controller.position.maxScrollExtent;
                                if (duration == Duration.zero) {
                                  controller.jumpTo(target);
                                } else {
                                  unawaited(
                                    controller.animateTo(
                                      target,
                                      duration: duration,
                                      curve: Curves.easeInOutCubic,
                                    ),
                                  );
                                }
                              });
                            }
                            return Wrap(
                              spacing: 26,
                              runSpacing: 14,
                              children: [
                                ...fields.map((field) {
                                  final full =
                                      field.kind == DbFieldKind.jsonValue ||
                                      field.name.contains('description') ||
                                      field.name.contains('notes') ||
                                      field.name.contains('instructions') ||
                                      field.name.contains('snapshot');
                                  return SizedBox(
                                    width: wide && !full
                                        ? (constraints.maxWidth - 26) / 2
                                        : constraints.maxWidth,
                                    child: _FieldInput(
                                      field: field,
                                      value: _values[field.name],
                                      controller: _controllers[field.name],
                                      lookups: widget.lookups,
                                      repository: widget.repository,
                                      referenceFilters: widget.referenceFilters,
                                      referenceRows: widget.referenceRows,
                                      onChanged: (v) => setState(
                                        () => _values[field.name] = v,
                                      ),
                                    ),
                                  );
                                }),
                                if (extra != null)
                                  SizedBox(
                                    width: constraints.maxWidth,
                                    child: extra,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      LucideIcons.circleAlert,
                      size: 18,
                      color: PomgtColors.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: PomgtColors.danger,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  PomgtButton(
                    label: 'Cancelar',
                    primary: false,
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                  PomgtButton(
                    label: editing ? 'Guardar cambios' : 'Crear',
                    icon: editing ? LucideIcons.save : LucideIcons.plus,
                    busy: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A field without a schema-authored hint still gets one by default, so
/// every generic form field shows internal placeholder guidance instead of
/// an empty box.
String _defaultFieldHint(DbFieldSpec f) {
  switch (f.kind) {
    case DbFieldKind.jsonValue:
      return '{ }';
    case DbFieldKind.dateValue:
    case DbFieldKind.dateTimeValue:
      return 'Selecciona una fecha';
    case DbFieldKind.numberValue:
    case DbFieldKind.integerValue:
      return 'Ej. 0';
    default:
      return 'Escribe ${UiCopy.fieldLabel(f.name, f.label).toLowerCase()}';
  }
}

class _FieldInput extends StatefulWidget {
  const _FieldInput({
    required this.field,
    required this.value,
    required this.controller,
    required this.lookups,
    required this.repository,
    required this.referenceFilters,
    required this.referenceRows,
    required this.onChanged,
  });
  final DbFieldSpec field;
  final dynamic value;
  final TextEditingController? controller;
  final LookupRepository lookups;
  final GenericRepository repository;
  final Map<String, Map<String, dynamic>> referenceFilters;
  final Map<String, List<Map<String, dynamic>>> referenceRows;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_FieldInput> createState() => _FieldInputState();
}

class _FieldInputState extends State<_FieldInput> {
  bool? _booleanValue;

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    if (_isCountryField(f.name)) return _countryInput(f);

    if (f.kind == DbFieldKind.booleanValue) {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Row(
          children: [
            Flexible(
              child: Text(
                UiCopy.fieldLabel(f.name, f.label),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (f.help != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: f.help!,
                child: const Icon(
                  LucideIcons.circleHelp,
                  size: 15,
                  color: PomgtColors.subtle,
                ),
              ),
            ],
          ],
        ),
        value: _booleanValue ?? (widget.value as bool?) ?? false,
        onChanged: (value) {
          setState(() => _booleanValue = value);
          widget.onChanged(value);
        },
      );
    }

    if (f.kind == DbFieldKind.enumValue) {
      final current = widget.value?.toString();
      return DropdownButtonFormField<String>(
        errorBuilder: pomgtValidationMessage,
        key: ValueKey('${f.name}-${current ?? ''}'),
        initialValue: current != null && f.enumValues.contains(current)
            ? current
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText:
              '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
          hintText: 'Selecciona una opción',
        ),
        items: f.enumValues
            .map(
              (v) =>
                  DropdownMenuItem(value: v, child: Text(UiCopy.enumLabel(v))),
            )
            .toList(),
        onChanged: widget.onChanged,
        validator: f.required
            ? (v) => v == null ? 'Selecciona una opción' : null
            : null,
      );
    }

    if (f.referenceTable != null) {
      return _ReferenceInput(
        field: f,
        value: widget.value,
        lookups: widget.lookups,
        repository: widget.repository,
        referenceFilters: widget.referenceFilters,
        referenceRows: widget.referenceRows,
        onChanged: widget.onChanged,
      );
    }

    final date =
        f.kind == DbFieldKind.dateValue || f.kind == DbFieldKind.dateTimeValue;
    final multiline =
        f.kind == DbFieldKind.jsonValue ||
        f.name.contains('description') ||
        f.name.contains('notes') ||
        f.name.contains('instructions') ||
        f.name.contains('snapshot');
    return TextFormField(
      errorBuilder: pomgtValidationMessage,
      controller: widget.controller,
      readOnly: date,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 7 : 1,
      keyboardType:
          (f.kind == DbFieldKind.numberValue ||
              f.kind == DbFieldKind.integerValue)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters:
          (f.kind == DbFieldKind.numberValue ||
              f.kind == DbFieldKind.integerValue)
          ? [
              ThousandsInputFormatter(
                allowDecimal: f.kind == DbFieldKind.numberValue,
                allowNegative: true,
              ),
            ]
          : null,
      decoration: InputDecoration(
        labelText:
            '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
        hintText: _defaultFieldHint(f),
        suffixIcon: date ? const Icon(LucideIcons.calendar, size: 17) : null,
        helperText: f.help,
      ),
      validator: (value) {
        if (f.required && (value == null || value.trim().isEmpty))
          return 'Campo requerido';
        if (value == null || value.trim().isEmpty) return null;
        try {
          if (f.kind == DbFieldKind.numberValue)
            double.parse(value.replaceAll(',', ''));
          if (f.kind == DbFieldKind.integerValue)
            int.parse(value.replaceAll(',', ''));
          if (f.kind == DbFieldKind.jsonValue) jsonDecode(value);
        } catch (_) {
          return f.kind == DbFieldKind.jsonValue
              ? 'Los datos estructurados no son válidos'
              : 'Valor numérico inválido';
        }
        return null;
      },
      onTap: date ? () => _pickDate(context) : null,
    );
  }

  Widget _countryInput(DbFieldSpec f) {
    final current = widget.value?.toString();
    const countries = <String, String>{'MX': 'México', 'US': 'Estados Unidos'};
    return DropdownButtonFormField<String>(
      errorBuilder: pomgtValidationMessage,
      key: ValueKey('${f.name}-${current ?? ''}'),
      initialValue: countries.containsKey(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText:
            '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
        hintText: 'Selecciona un país',
        helperText: 'Se guarda el código fiscal de 2 letras requerido por la base de datos.',
      ),
      items: countries.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: widget.onChanged,
      validator: f.required
          ? (v) => v == null ? 'Selecciona un país' : null
          : null,
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial =
        DateTime.tryParse(widget.controller?.text ?? '') ?? DateTime.now();
    final picked = await showPomgtDatePicker(
      context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    String value;
    if (widget.field.kind == DbFieldKind.dateTimeValue) {
      final time = await showPomgtTimePicker(
        context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (!mounted) return;
      final t = time ?? TimeOfDay.fromDateTime(initial);
      value = DateTime(
        picked.year,
        picked.month,
        picked.day,
        t.hour,
        t.minute,
      ).toIso8601String();
    } else {
      value = DateFormat('yyyy-MM-dd').format(picked);
    }
    widget.controller?.text = value;
    widget.onChanged(value);
  }
}

class _ReferenceInput extends StatefulWidget {
  const _ReferenceInput({
    required this.field,
    required this.value,
    required this.lookups,
    required this.repository,
    required this.referenceFilters,
    required this.referenceRows,
    required this.onChanged,
  });
  final DbFieldSpec field;
  final dynamic value;
  final LookupRepository lookups;
  final GenericRepository repository;
  final Map<String, Map<String, dynamic>> referenceFilters;
  final Map<String, List<Map<String, dynamic>>> referenceRows;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_ReferenceInput> createState() => _ReferenceInputState();
}

class _ReferenceInputState extends State<_ReferenceInput> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _selectedValue;
  late int _seenRuntimeRevision;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.value?.toString();
    _seenRuntimeRevision = context.read<RuntimeDataController>().revisionFor(
      widget.field.referenceTable!,
    );
    _future = _loadRows();
  }

  @override
  void didUpdateWidget(covariant _ReferenceInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.value?.toString();
    if (incoming != oldWidget.value?.toString()) _selectedValue = incoming;
    if (oldWidget.field.referenceTable != widget.field.referenceTable ||
        oldWidget.referenceFilters.toString() !=
            widget.referenceFilters.toString() ||
        oldWidget.referenceRows.toString() != widget.referenceRows.toString()) {
      _seenRuntimeRevision = context.read<RuntimeDataController>().revisionFor(
        widget.field.referenceTable!,
      );
      _future = _loadRows();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<RuntimeDataController>().revisionFor(
      widget.field.referenceTable!,
    );
    if (revision == _seenRuntimeRevision) return;
    _seenRuntimeRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    widget.lookups.invalidate(widget.field.referenceTable!);
    setState(() {
      _future = _loadRows(refresh: true);
    });
  }

  Future<List<Map<String, dynamic>>> _loadRows({bool refresh = false}) async {
    final table = widget.field.referenceTable!;
    final providedRows =
        widget.referenceRows[widget.field.name] ?? widget.referenceRows[table];
    if (providedRows != null) {
      return Future.value(providedRows);
    }
    final filters =
        widget.referenceFilters[widget.field.name] ??
        widget.referenceFilters[table];
    Future<List<Map<String, dynamic>>> rows;
    if (filters == null || filters.isEmpty) {
      rows = widget.lookups.rows(table, refresh: refresh);
    } else {
      final spec = Phase1Schema.tables[table];
      rows = spec == null
          ? widget.lookups.rows(table)
          : widget.repository.listRows(spec, filters: filters);
    }
    final loaded = await rows;
    return table == 'products' ? _productCatalogRows(loaded) : loaded;
  }

  bool get _canCreate {
    final hasProvidedRows =
        widget.referenceRows[widget.field.name] != null ||
        widget.referenceRows[widget.field.referenceTable] != null;
    if (widget.field.referenceTable == 'products' && hasProvidedRows) {
      return false;
    }
    const safe = <String>{
      'customers',
      'product_categories',
      'material_categories',
      'product_types',
      'material_types',
      'payment_terms',
      'units_of_measure',
      'products',
      'work_centers',
      'machines',
      'machine_categories',
      'machine_types',
      'labor_roles',
      'process_definitions',
      'checklist_templates',
      'quality_check_templates',
    };
    final spec = Phase1Schema.tables[widget.field.referenceTable!];
    return safe.contains(widget.field.referenceTable) &&
        spec != null &&
        !spec.readOnly;
  }

  Future<void> _createReference() async {
    final refTable = widget.field.referenceTable!;
    final refSpec = Phase1Schema.tables[refTable];
    if (refSpec == null) return;
    Map<String, dynamic>? created;
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: refSpec,
        repository: widget.repository,
        lookups: widget.lookups,
        fixedValues:
            widget.referenceFilters[widget.field.name] ??
            widget.referenceFilters[refTable] ??
            const {},
        onSaved: (row) => created = row,
        hiddenFields: _referenceHiddenFields(refTable),
      ),
    );
    if (changed != true || !mounted) return;
    _reload();
    final value = created?[widget.field.referenceColumn]?.toString();
    if (value != null) {
      setState(() => _selectedValue = value);
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final refSpec = Phase1Schema.tables[f.referenceTable!];
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final current = _selectedValue;
        final hasCurrent = rows.any(
          (r) => r[f.referenceColumn]?.toString() == current,
        );
        final categoryLabel = UiCopy.tableTitle(f.referenceTable!);
        final items = <PickerItem>[
          for (final r in rows)
            if ((r[f.referenceColumn]?.toString() ?? '').isNotEmpty)
              PickerItem(
                id: r[f.referenceColumn].toString(),
                label: refSpec == null
                    ? r[f.referenceColumn].toString()
                    : widget.lookups.display(refSpec, r),
                category: categoryLabel,
              ),
        ];
        final dropdown = CategorizedSearchPicker(
          key: ValueKey('${f.referenceTable}-${rows.length}'),
          items: items,
          value: hasCurrent ? current : null,
          label:
              '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
          helperText: rows.isEmpty
              ? _emptyReferenceMessage(f.referenceTable!, f.name)
              : f.help,
          onChanged: (value) {
            setState(() => _selectedValue = value);
            widget.onChanged(value);
          },
          validator: f.required
              ? (v) => v == null ? 'Selecciona una opción' : null
              : null,
        );

        if (!_canCreate) return dropdown;
        if (rows.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dropdown,
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _createReference,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text(UiCopy.createReferenceLabel(f.referenceTable!)),
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: dropdown),
            const SizedBox(width: 10),
            Tooltip(
              message: UiCopy.createReferenceLabel(f.referenceTable!),
              child: IconButton(
                onPressed: _createReference,
                icon: const Icon(LucideIcons.plus, size: 19),
              ),
            ),
          ],
        );
      },
    );
  }

  String _emptyReferenceMessage(String table, String field) {
    if (table == 'customer_products' &&
        widget.referenceFilters[field]?['customer_id'] != null) {
      return 'Este cliente todavía no tiene productos asociados.';
    }
    return 'Todavía no hay ${UiCopy.tableTitle(table).toLowerCase()} registrados.';
  }
}

Set<String> _referenceHiddenFields(String table) {
  if (table == 'products') {
    return const {'material_type_id', 'material_category_id', 'product_type'};
  }
  return const {};
}

/// Gives a hand-built reference picker (a [CategorizedSearchPicker] a
/// feature screen constructs itself, outside [EntityCrudPanel]/
/// [EntityFormDialog]) the same "+" quick-create affordance [EntityFormDialog]
/// already gives schema-driven reference fields. Without it, a user who
/// needs a category/type/unit that doesn't exist yet has no way to know it
/// can be created inline - they'd have to guess that Datos Maestros exists
/// and find the right tab on their own.
class QuickCreateField extends StatelessWidget {
  const QuickCreateField({
    super.key,
    required this.table,
    required this.repository,
    required this.lookups,
    required this.isEmpty,
    required this.child,
    this.fixedValues = const {},
    this.onCreated,
  });

  final String table;
  final GenericRepository repository;
  final LookupRepository lookups;
  final bool isEmpty;
  final Widget child;
  final Map<String, dynamic> fixedValues;
  final ValueChanged<Map<String, dynamic>>? onCreated;

  Future<void> _create(BuildContext context) async {
    final spec = Phase1Schema.tables[table];
    if (spec == null) return;
    Map<String, dynamic>? created;
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: spec,
        repository: repository,
        lookups: lookups,
        fixedValues: fixedValues,
        hiddenFields: _referenceHiddenFields(table),
        onSaved: (row) => created = row,
      ),
    );
    if (changed != true) return;
    lookups.invalidate(table);
    if (created != null) onCreated?.call(created!);
  }

  @override
  Widget build(BuildContext context) {
    final label = UiCopy.createReferenceLabel(table);
    if (isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(label),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: child),
        const SizedBox(width: 10),
        Tooltip(
          message: label,
          child: IconButton(
            onPressed: () => _create(context),
            icon: const Icon(LucideIcons.plus, size: 19),
          ),
        ),
      ],
    );
  }
}

bool _isCountryField(String name) =>
    name == 'tax_country_code' || name == 'country_code';

String _newTitle(String table, String fallback) {
  const overrides = <String, String>{
    'customers': 'Nuevo cliente',
    'customer_addresses': 'Nueva dirección',
    'customer_contacts': 'Nuevo contacto',
    'customer_contact_emails': 'Nuevo correo',
    'customer_contact_phones': 'Nuevo teléfono',
    'customer_orders': 'Nuevo pedido',
    'customer_order_lines': 'Nueva línea de pedido',
    'products': 'Nuevo producto',
    'product_categories': 'Nueva categoría',
    'material_categories': 'Nueva categoría de material',
    'product_types': 'Nuevo tipo de producto',
    'material_types': 'Nuevo tipo de material',
    'boms': 'Nueva estructura de fabricación',
    'bom_revisions': 'Nueva versión',
    'bom_items': 'Nuevo material / componente',
    'documents': 'Nuevo documento',
  };
  return overrides[table] ?? 'Nuevo registro · $fallback';
}

IconData _iconForTable(String table) {
  switch (table) {
    case 'customers':
      return LucideIcons.building2;
    case 'customer_addresses':
      return LucideIcons.mapPin;
    case 'customer_contacts':
      return LucideIcons.user;
    case 'customer_contact_emails':
      return LucideIcons.atSign;
    case 'customer_contact_phones':
      return LucideIcons.phone;
    case 'customer_orders':
      return LucideIcons.receiptText;
    case 'customer_order_lines':
      return LucideIcons.listOrdered;
    case 'products':
      return LucideIcons.package;
    case 'product_categories':
      return LucideIcons.shapes;
    case 'material_categories':
      return LucideIcons.layers;
    case 'product_types':
      return LucideIcons.tag;
    case 'material_types':
      return LucideIcons.layers;
    case 'boms':
      return LucideIcons.gitBranch;
    case 'bom_revisions':
      return LucideIcons.history;
    case 'bom_items':
      return LucideIcons.blocks;
    case 'documents':
      return LucideIcons.fileText;
    case 'payment_terms':
      return LucideIcons.banknote;
    case 'units_of_measure':
      return LucideIcons.ruler;
    default:
      return LucideIcons.slidersHorizontal;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: LucideIcons.circleAlert,
      title: 'No pudimos cargar la información',
      message: message,
      action: PomgtButton(
        label: 'Reintentar',
        primary: false,
        onPressed: onRetry,
      ),
    );
  }
}

String _friendlyError(Object error) => ErrorCopy.message(error);

List<Map<String, dynamic>> _productCatalogRows(
  List<Map<String, dynamic>> rows,
) {
  const materialTypes = {
    'raw_material',
    'consumable',
    'packaging',
    'tooling',
    'service',
  };
  return rows
      .where(
        (row) =>
            row['material_type_id'] == null &&
            !materialTypes.contains(row['product_type']?.toString()),
      )
      .toList();
}
