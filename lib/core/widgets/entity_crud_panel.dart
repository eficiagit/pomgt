import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
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
import 'empty_state.dart';
import 'info_tip.dart';
import 'pomgt_button.dart';
import 'section_header.dart';
import 'status_pill.dart';

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

  @override
  State<EntityCrudPanel> createState() => _EntityCrudPanelState();
}

class _EntityCrudPanelState extends State<EntityCrudPanel> {
  late Future<List<Map<String, dynamic>>> _future;
  late int _seenRuntimeRevision;
  String _search = '';

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
    _future = widget.repository
        .listRows(spec, filters: widget.fixedValues)
        .then(
          (rows) => widget.rowFilter == null
              ? rows
              : rows.where(widget.rowFilter!).toList(),
        );
    if (mounted) setState(() {});
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    if (spec.readOnly) return;
    final changed = await showDialog<bool>(
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: const Text(
          'Esta acción no se puede deshacer. Los registros relacionados pueden impedir la eliminación para proteger la trazabilidad.',
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
          trailing: spec.readOnly
              ? null
              : PomgtButton(
                  label: 'Nuevo',
                  icon: Icons.add_rounded,
                  onPressed: () => _edit(),
                ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  hintText: 'Buscar…',
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                  prefixIconConstraints: BoxConstraints(minWidth: 34),
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              tooltip: 'Actualizar información',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              if (snapshot.hasError) {
                return _ErrorState(
                  message: _friendlyError(snapshot.error!),
                  onRetry: _reload,
                );
              }
              final rows = _filter(snapshot.data ?? const []);
              if (!loading && rows.isEmpty) {
                return EmptyState(
                  title: _search.isEmpty
                      ? 'Todavía no hay registros'
                      : 'Sin resultados',
                  message: _search.isEmpty
                      ? 'Agrega el primer registro para comenzar a utilizar esta sección.'
                      : 'Prueba con otro término de búsqueda.',
                  action: spec.readOnly
                      ? null
                      : PomgtButton(
                          label: 'Crear registro',
                          icon: Icons.add_rounded,
                          onPressed: () => _edit(),
                        ),
                );
              }
              final displayRows = loading
                  ? List.generate(
                      5,
                      (_) => <String, dynamic>{
                        'id': 'loading',
                        for (final f in spec.displayFields)
                          f: 'Cargando información',
                      },
                    )
                  : rows;
              return Skeletonizer(
                enabled: loading,
                child: _RecordList(
                  spec: spec,
                  rows: displayRows,
                  onEdit: spec.readOnly ? null : _edit,
                  onDelete: spec.readOnly ? null : _remove,
                  flat: widget.flatList,
                ),
              );
            },
          ),
        ),
      ],
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
        border: flat ? null : Border.all(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderMd,
        boxShadow: flat ? null : PomgtShadows.card,
      ),
      child: ClipRRect(
        borderRadius: PomgtRadii.borderMd,
        child: ListView.separated(
          padding: const EdgeInsets.all(10),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final row = rows[index];
            final title = _display(spec, row);
            final status = row['status']?.toString();
            return InkWell(
              borderRadius: PomgtRadii.borderSm,
              onTap: onEdit == null ? null : () => onEdit!(row),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: index.isEven
                      ? PomgtColors.surfaceAlt.withValues(alpha: .55)
                      : Colors.white,
                  borderRadius: PomgtRadii.borderSm,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
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
                                      fontWeight: FontWeight.w800,
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
                            const SizedBox(height: 7),
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
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: value,
                                            style: const TextStyle(
                                              color: PomgtColors.secondaryInk,
                                              fontWeight: FontWeight.w600,
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
                          icon: const Icon(Icons.edit_outlined, size: 19),
                        ),
                      if (onDelete != null)
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () => onDelete!(row),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
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
        return int.parse(value);
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      widget.icon ?? _iconForTable(widget.spec.table),
                      size: 25,
                      color: PomgtColors.ink,
                    ),
                  ),
                  SizedBox(
                    width: compact ? media.width - 96 : 720,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? media.width - 122 : 650,
                              ),
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
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
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 30),
              Flexible(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 680;
                          final extra = widget.extraContentBuilder?.call(
                            context,
                            Map.unmodifiable(_values),
                          );
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
                                    onChanged: (v) =>
                                        setState(() => _values[field.name] = v),
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
              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
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
                    icon: editing ? Icons.save_outlined : Icons.add_rounded,
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
                  Icons.help_outline_rounded,
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
        key: ValueKey('${f.name}-${current ?? ''}'),
        initialValue: current != null && f.enumValues.contains(current)
            ? current
            : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText:
              '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
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
      controller: widget.controller,
      readOnly: date,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 7 : 1,
      keyboardType:
          (f.kind == DbFieldKind.numberValue ||
              f.kind == DbFieldKind.integerValue)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText:
            '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
        hintText: f.kind == DbFieldKind.jsonValue ? '{ }' : null,
        suffixIcon: date
            ? const Icon(Icons.calendar_today_outlined, size: 17)
            : null,
        helperText: f.help,
      ),
      validator: (value) {
        if (f.required && (value == null || value.trim().isEmpty))
          return 'Campo requerido';
        if (value == null || value.trim().isEmpty) return null;
        try {
          if (f.kind == DbFieldKind.numberValue)
            double.parse(value.replaceAll(',', ''));
          if (f.kind == DbFieldKind.integerValue) int.parse(value);
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
      key: ValueKey('${f.name}-${current ?? ''}'),
      initialValue: countries.containsKey(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText:
            '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
        helperText:
            'Se guarda el código fiscal de 2 letras requerido por la base de datos.',
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
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    String value;
    if (widget.field.kind == DbFieldKind.dateTimeValue) {
      final time = await showTimePicker(
        context: context,
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
    final changed = await showDialog<bool>(
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
        final dropdown = DropdownButtonFormField<String>(
          key: ValueKey('${f.referenceTable}-${current ?? ''}-${rows.length}'),
          initialValue: hasCurrent ? current : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText:
                '${UiCopy.fieldLabel(f.name, f.label)}${f.required ? ' *' : ''}',
            helperText: rows.isEmpty
                ? _emptyReferenceMessage(f.referenceTable!, f.name)
                : f.help,
          ),
          items: rows.map((r) {
            final value = r[f.referenceColumn]?.toString();
            return DropdownMenuItem<String>(
              value: value,
              child: Text(
                refSpec == null
                    ? (value ?? '—')
                    : widget.lookups.display(refSpec, r),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
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
                  icon: const Icon(CupertinoIcons.add, size: 16),
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
                icon: const Icon(CupertinoIcons.add, size: 19),
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
    'bom_revisions': 'Nueva revisión',
    'bom_items': 'Nuevo material / componente',
    'documents': 'Nuevo documento',
  };
  return overrides[table] ?? 'Nuevo registro · $fallback';
}

IconData _iconForTable(String table) {
  switch (table) {
    case 'customers':
      return Icons.business_outlined;
    case 'customer_addresses':
      return Icons.location_on_outlined;
    case 'customer_contacts':
      return Icons.person_outline_rounded;
    case 'customer_contact_emails':
      return Icons.alternate_email_rounded;
    case 'customer_contact_phones':
      return Icons.phone_outlined;
    case 'customer_orders':
      return Icons.receipt_long_outlined;
    case 'customer_order_lines':
      return Icons.format_list_numbered_rounded;
    case 'products':
      return Icons.inventory_2_outlined;
    case 'product_categories':
      return Icons.category_outlined;
    case 'material_categories':
      return Icons.layers_outlined;
    case 'product_types':
      return Icons.sell_outlined;
    case 'material_types':
      return Icons.layers_outlined;
    case 'boms':
      return Icons.account_tree_outlined;
    case 'bom_revisions':
      return Icons.history_rounded;
    case 'bom_items':
      return Icons.widgets_outlined;
    case 'documents':
      return Icons.description_outlined;
    case 'payment_terms':
      return Icons.payments_outlined;
    case 'units_of_measure':
      return Icons.straighten_rounded;
    default:
      return Icons.tune_rounded;
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
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
