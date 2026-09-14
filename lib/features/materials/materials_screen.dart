import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/material_repository.dart';
import 'dynamic_material_attributes.dart';

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  late Future<_MaterialIndexData> _future;
  late int _seenDataRevision;
  String _search = '';
  String? _selectedId;
  String? _typeFilter;
  String? _categoryFilter;
  String? _classFilter;
  bool? _activeFilter;

  @override
  void initState() {
    super.initState();
    _seenDataRevision = context.read<RuntimeDataController>().revision;
    _future = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<RuntimeDataController>().revision;
    if (revision == _seenDataRevision) return;
    _seenDataRevision = revision;
    _reload();
  }

  Future<_MaterialIndexData> _load() async {
    final repo = context.read<MaterialRepository>();
    final lookups = context.read<LookupRepository>();
    final results = await Future.wait([
      repo.materials(),
      repo.materialTypes(),
      repo.categories(),
      lookups.rows('units_of_measure'),
      lookups.rows('currencies'),
    ]);
    return _MaterialIndexData(
      materials: results[0].where(_isMaterialCatalogRow).toList(),
      types: results[1],
      categories: results[2],
      units: results[3],
      currencies: results[4],
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _create(_MaterialIndexData data) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaterialFormDialog(data: data),
    );
    if (changed == true && mounted) {
      context.read<LookupRepository>().invalidate('products');
      context.read<RuntimeDataController>().tablesChanged({
        'products',
        'product_revisions',
        'material_revision_attribute_values',
      });
      context.read<MaterialsController>().refresh();
      _reload();
    }
  }

  Future<void> _edit(
    Map<String, dynamic> material,
    _MaterialIndexData data,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaterialFormDialog(data: data, material: material),
    );
    if (changed == true && mounted) {
      context.read<RuntimeDataController>().tablesChanged({'products'});
      _reload();
    }
  }

  Future<void> _delete(Map<String, dynamic> material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar material'),
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
    if (confirmed != true || !mounted) return;
    try {
      await context.read<GenericRepository>().deleteRow(
        Phase1Schema.tables['products']!,
        material,
      );
      if (!mounted) return;
      setState(() => _selectedId = null);
      context.read<RuntimeDataController>().tablesChanged({'products'});
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MaterialIndexData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'No fue posible cargar materiales.',
              style: TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final data = snapshot.data ?? _MaterialIndexData.empty();
        final rows = _filtered(data);
        if (rows.isNotEmpty &&
            (_selectedId == null ||
                !rows.any((row) => row['id']?.toString() == _selectedId))) {
          _selectedId = rows.first['id']?.toString();
        }
        final selected = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == _selectedId,
          orElse: () => rows.isEmpty ? null : rows.first,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onCreate: () => _create(data)),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width >= 1280
                          ? 320
                          : 300,
                      child: _MaterialList(
                        data: data,
                        rows: rows,
                        total: data.materials.length,
                        selectedId: _selectedId,
                        loading:
                            snapshot.connectionState == ConnectionState.waiting,
                        search: _search,
                        typeFilter: _typeFilter,
                        categoryFilter: _categoryFilter,
                        classFilter: _classFilter,
                        activeFilter: _activeFilter,
                        onSearch: (value) => setState(() => _search = value),
                        onType: (value) => setState(() => _typeFilter = value),
                        onCategory: (value) =>
                            setState(() => _categoryFilter = value),
                        onClass: (value) =>
                            setState(() => _classFilter = value),
                        onActive: (value) =>
                            setState(() => _activeFilter = value),
                        onSelect: (id) => setState(() => _selectedId = id),
                        onEdit: (material) => _edit(material, data),
                        onDelete: _delete,
                        onRefresh: _reload,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: selected == null
                          ? const _Panel(
                              child: Center(
                                child: Text(
                                  'Selecciona un material para ver su ficha.',
                                  style: TextStyle(color: PomgtColors.muted),
                                ),
                              ),
                            )
                          : _MaterialDetail(
                              key: ValueKey(selected['id']),
                              material: selected,
                              data: data,
                              onEdit: () => _edit(selected, data),
                              onDelete: () => _delete(selected),
                              onChanged: _reload,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _filtered(_MaterialIndexData data) {
    final query = _search.trim().toLowerCase();
    return data.materials.where((row) {
      if (query.isNotEmpty &&
          ![row['sku'], row['name'], row['description']].any(
            (value) => value?.toString().toLowerCase().contains(query) ?? false,
          )) {
        return false;
      }
      if (_typeFilter != null &&
          row['material_type_id']?.toString() != _typeFilter) {
        return false;
      }
      if (_categoryFilter != null &&
          row['material_category_id']?.toString() != _categoryFilter) {
        return false;
      }
      if (_classFilter != null &&
          row['product_type']?.toString() != _classFilter) {
        return false;
      }
      if (_activeFilter != null &&
          (row['is_active'] == true) != _activeFilter) {
        return false;
      }
      return true;
    }).toList();
  }
}

class _MaterialFormDialog extends StatefulWidget {
  const _MaterialFormDialog({required this.data, this.material});
  final _MaterialIndexData data;
  final Map<String, dynamic>? material;

  @override
  State<_MaterialFormDialog> createState() => _MaterialFormDialogState();
}

class _MaterialFormDialogState extends State<_MaterialFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _cost = TextEditingController();
  String? _typeId;
  String? _categoryId;
  String? _uomId;
  String? _currencyCode;
  bool _active = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _attributes = const [];
  Map<String, List<Map<String, dynamic>>> _options = const {};
  Map<String, dynamic> _values = {};
  String? _activeRevisionId;
  List<Map<String, dynamic>> _existingValues = const [];

  bool get editing => widget.material != null;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    if (material != null) {
      _sku.text = material['sku']?.toString() ?? '';
      _name.text = material['name']?.toString() ?? '';
      _description.text = material['description']?.toString() ?? '';
      _cost.text = material['standard_cost']?.toString() ?? '';
      _typeId = material['material_type_id']?.toString();
      _categoryId = material['material_category_id']?.toString();
      _uomId = material['base_uom_id']?.toString();
      _currencyCode = material['standard_cost_currency_code']?.toString();
      _active = material['is_active'] == true;
    } else {
      _typeId = widget.data.types
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (row) => row?['is_default'] == true,
            orElse: () =>
                widget.data.types.isEmpty ? null : widget.data.types.first,
          )?['id']
          ?.toString();
      _uomId = widget.data.units.isEmpty
          ? null
          : widget.data.units.first['id']?.toString();
      _currencyCode = widget.data.currencies.isEmpty
          ? null
          : widget.data.currencies.first['code']?.toString();
    }
    _loadAttributes();
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _description.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _loadAttributes() async {
    final typeId = _typeId;
    if (typeId == null) return;
    final repo = context.read<MaterialRepository>();
    final attrs = await repo.attributes(typeId);
    final options = await repo.optionsForAttributes(
      attrs.map((row) => row['id'].toString()),
    );
    Map<String, dynamic>? activeRevision;
    var existingValues = const <Map<String, dynamic>>[];
    if (editing) {
      final detail = await repo.detail(widget.material!['id'].toString());
      activeRevision = detail['activeRevision'] as Map<String, dynamic>?;
      existingValues =
          (detail['values'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
    }
    if (!mounted) return;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final option in options) {
      grouped
          .putIfAbsent(option['attribute_definition_id'].toString(), () => [])
          .add(option);
    }
    final existingFormValues = materialAttributeFormValues(
      attrs,
      existingValues,
    );
    setState(() {
      _attributes = attrs;
      _options = grouped;
      _activeRevisionId = activeRevision?['id']?.toString();
      _existingValues = existingValues;
      _values = {
        for (final attr in attrs)
          if (attr['default_value'] != null)
            attr['id'].toString(): attr['default_value'],
        ...existingFormValues,
      };
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final attributeError = materialAttributeValidationError(
      _attributes,
      _values,
    );
    if (attributeError != null) {
      setState(() => _error = attributeError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<MaterialRepository>();
      final generic = context.read<GenericRepository>();
      final type = widget.data.typeById[_typeId];
      if (editing) {
        await generic.updateRow(
          Phase1Schema.tables['products']!,
          widget.material!['id'].toString(),
          {
            'sku': _sku.text.trim(),
            'name': _name.text.trim(),
            'description': _description.text.trim(),
            'material_type_id': _typeId,
            'material_category_id': _categoryId,
            'base_uom_id': _uomId,
            'product_type': type?['system_class'] ?? 'raw_material',
            'is_active': _active,
            'standard_cost': _cost.text.trim().isEmpty
                ? null
                : num.parse(_cost.text.trim()),
            'standard_cost_currency_code': _currencyCode,
          },
        );
        if (_attributes.isNotEmpty) {
          final revisionId =
              _activeRevisionId ??
              await repo.createRevision(
                productId: widget.material!['id'].toString(),
                copyFromRevisionId: null,
              );
          await repo.upsertRevisionValues(
            revisionId: revisionId,
            values: materialAttributePayload(
              _attributes,
              _values,
              revisionId: revisionId,
              existing: _existingValues,
            ),
          );
        }
      } else {
        await repo.createMaterial(
          material: {
            'sku': _sku.text.trim(),
            'name': _name.text.trim(),
            'description': _description.text.trim(),
            'material_type_id': _typeId,
            'material_category_id': _categoryId,
            'base_uom_id': _uomId,
            'is_active': _active,
            'standard_cost': _cost.text.trim(),
            'standard_cost_currency_code': _currencyCode,
          },
          attributeValues: materialAttributePayload(
            _attributes,
            _values,
            includeNulls: false,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeName =
        widget.data.typeById[_typeId]?['name']?.toString() ?? 'material';
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 980,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    editing ? CupertinoIcons.pencil : CupertinoIcons.add,
                    color: PomgtColors.ink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      editing ? 'Editar material' : 'Nuevo material',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Divider(height: 28),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionTitle('INFORMACIÓN GENERAL'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 720;
                            final fieldWidth = wide
                                ? (constraints.maxWidth - 16) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 16,
                              runSpacing: 14,
                              children: [
                                SizedBox(
                                  width: fieldWidth,
                                  child: _text(_sku, 'Código / SKU *'),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _text(_name, 'Nombre *'),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth,
                                  child: _text(
                                    _description,
                                    'Descripción',
                                    lines: 3,
                                    required: false,
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _typeDropdown(),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _categoryDropdown(),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _uomDropdown(),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _currencyDropdown(),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: _text(
                                    _cost,
                                    'Costo estándar',
                                    required: false,
                                    number: true,
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Activo'),
                                    value: _active,
                                    onChanged: (value) =>
                                        setState(() => _active = value),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _SectionTitle('ESPECIFICACIONES · $typeName'),
                        if (_attributes.isEmpty) ...[
                          const Text(
                            'Este tipo de material todavía no tiene especificaciones configuradas.',
                            style: TextStyle(color: PomgtColors.muted),
                          ),
                        ] else
                          DynamicMaterialAttributeForm(
                            attributes: _attributes,
                            options: _options,
                            values: _values,
                            units: widget.data.unitById,
                            onChanged: (values) =>
                                setState(() => _values = values),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: PomgtColors.danger),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            editing ? Icons.save_outlined : Icons.add_rounded,
                            size: 17,
                          ),
                    label: Text(editing ? 'Guardar cambios' : 'Crear material'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    int lines = 1,
    bool required = true,
    bool number = false,
  }) {
    return TextFormField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Campo requerido';
        }
        if (number &&
            value != null &&
            value.trim().isNotEmpty &&
            num.tryParse(value.trim()) == null) {
          return 'Número inválido';
        }
        return null;
      },
    );
  }

  Widget _typeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _typeId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tipo de material *'),
      items: widget.data.types
          .map(
            (row) => DropdownMenuItem<String>(
              value: row['id']?.toString(),
              child: Text(row['name']?.toString() ?? 'Tipo'),
            ),
          )
          .toList(),
      onChanged: editing
          ? null
          : (value) {
              setState(() => _typeId = value);
              _loadAttributes();
            },
      validator: (value) => value == null ? 'Selecciona un tipo' : null,
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _categoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Categoría'),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Sin categoría'),
        ),
        ...widget.data.categories.map(
          (row) => DropdownMenuItem<String>(
            value: row['id']?.toString(),
            child: Text(row['name']?.toString() ?? 'Categoría'),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  Widget _uomDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _uomId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Unidad base *'),
      items: widget.data.units
          .map(
            (row) => DropdownMenuItem<String>(
              value: row['id']?.toString(),
              child: Text(
                '${row['name'] ?? 'Unidad'} (${row['symbol'] ?? ''})',
              ),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _uomId = value),
      validator: (value) => value == null ? 'Selecciona una unidad' : null,
    );
  }

  Widget _currencyDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _currencyCode,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Moneda'),
      items: widget.data.currencies
          .map(
            (row) => DropdownMenuItem<String>(
              value: row['code']?.toString(),
              child: Text('${row['code'] ?? ''} · ${row['name'] ?? ''}'),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _currencyCode = value),
    );
  }
}

class _MaterialDetail extends StatefulWidget {
  const _MaterialDetail({
    super.key,
    required this.material,
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onChanged,
  });

  final Map<String, dynamic> material;
  final _MaterialIndexData data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  State<_MaterialDetail> createState() => _MaterialDetailState();
}

class _MaterialDetailState extends State<_MaterialDetail> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<MaterialRepository>().detail(
      widget.material['id'].toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type =
        widget.data.typeById[widget.material['material_type_id']?.toString()];
    final category = widget
        .data
        .categoryById[widget.material['material_category_id']?.toString()];
    final unit =
        widget.data.unitById[widget.material['base_uom_id']?.toString()];
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final values =
            (snapshot.data?['values'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        final bomItems =
            (snapshot.data?['bomItems'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [];
        return _Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${widget.material['sku'] ?? 'MAT'} · ${widget.material['name'] ?? 'Material'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PomgtColors.ink,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _Status(
                                active: widget.material['is_active'] == true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${UiCopy.enumLabel(widget.material['product_type']?.toString() ?? '')} · ${type?['name'] ?? 'Tipo de material'}',
                            style: const TextStyle(
                              color: PomgtColors.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(CupertinoIcons.pencil, size: 17),
                      label: const Text('Editar'),
                    ),
                    IconButton(
                      onPressed: widget.onDelete,
                      tooltip: 'Eliminar material',
                      icon: const Icon(CupertinoIcons.trash, size: 18),
                    ),
                    TextButton.icon(
                      onPressed: null,
                      icon: const Icon(CupertinoIcons.doc_on_doc, size: 17),
                      label: const Text('Duplicar'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Expanded(
                  child: DefaultTabController(
                    length: 4,
                    child: Column(
                      children: [
                        const TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            Tab(text: 'Resumen'),
                            Tab(text: 'Especificaciones'),
                            Tab(text: 'Usado en BOM'),
                            Tab(text: 'Documentos'),
                          ],
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: TabBarView(
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Wrap(
                                  spacing: 28,
                                  runSpacing: 18,
                                  children: [
                                    _Kv(
                                      'Tipo',
                                      type?['name']?.toString() ?? '—',
                                    ),
                                    _Kv(
                                      'Categoría',
                                      category?['name']?.toString() ?? '—',
                                    ),
                                    _Kv(
                                      'Unidad',
                                      unit?['symbol']?.toString() ?? '—',
                                    ),
                                    _Kv(
                                      'Costo',
                                      widget.material['standard_cost']
                                              ?.toString() ??
                                          '—',
                                    ),
                                    _Kv(
                                      'BOMs relacionados',
                                      bomItems.length.toString(),
                                    ),
                                  ],
                                ),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: FutureBuilder<_SpecData>(
                                  future: _specData(type?['id']?.toString()),
                                  builder: (context, specSnapshot) {
                                    final spec =
                                        specSnapshot.data ?? _SpecData.empty();
                                    return DynamicMaterialAttributeViewer(
                                      attributes: spec.attributes,
                                      values: values,
                                      options: spec.options,
                                      units: widget.data.unitById,
                                    );
                                  },
                                ),
                              ),
                              _SimpleRows(
                                rows: bomItems,
                                empty: 'Sin consumos registrados.',
                                titleField: 'component_type',
                              ),
                              LinkedDocumentsPanel(
                                entityField: 'product_id',
                                entityId: widget.material['id'].toString(),
                                title: 'Documentos del material',
                                help:
                                    'Fichas técnicas, certificados, hojas de seguridad e imágenes.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<_SpecData> _specData(String? typeId) async {
    if (typeId == null) return _SpecData.empty();
    final repo = context.read<MaterialRepository>();
    final attrs = await repo.attributes(typeId);
    final options = await repo.optionsForAttributes(
      attrs.map((row) => row['id'].toString()),
    );
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final option in options) {
      grouped
          .putIfAbsent(option['attribute_definition_id'].toString(), () => [])
          .add(option);
    }
    return _SpecData(attributes: attrs, options: grouped);
  }
}

class _MaterialList extends StatelessWidget {
  const _MaterialList({
    required this.data,
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.loading,
    required this.search,
    required this.typeFilter,
    required this.categoryFilter,
    required this.classFilter,
    required this.activeFilter,
    required this.onSearch,
    required this.onType,
    required this.onCategory,
    required this.onClass,
    required this.onActive,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final _MaterialIndexData data;
  final List<Map<String, dynamic>> rows;
  final int total;
  final String? selectedId;
  final bool loading;
  final String search;
  final String? typeFilter;
  final String? categoryFilter;
  final String? classFilter;
  final bool? activeFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onType;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onClass;
  final ValueChanged<bool?> onActive;
  final ValueChanged<String?> onSelect;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: TextField(
                    onChanged: onSearch,
                    decoration: const InputDecoration(
                      hintText: 'Buscar materiales...',
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
          const SizedBox(height: 12),
          _filter('Tipo', typeFilter, [
            const DropdownMenuItem<String>(value: null, child: Text('Todos')),
            ...data.types.map(
              (row) => DropdownMenuItem<String>(
                value: row['id']?.toString(),
                child: Text(row['name']?.toString() ?? 'Tipo'),
              ),
            ),
          ], onType),
          const SizedBox(height: 8),
          _filter('Categoría', categoryFilter, [
            const DropdownMenuItem<String>(value: null, child: Text('Todas')),
            ...data.categories.map(
              (row) => DropdownMenuItem<String>(
                value: row['id']?.toString(),
                child: Text(row['name']?.toString() ?? 'Categoría'),
              ),
            ),
          ], onCategory),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _filter('Clasificación', classFilter, const [
                  DropdownMenuItem<String>(value: null, child: Text('Todas')),
                  DropdownMenuItem(
                    value: 'raw_material',
                    child: Text('Materia prima'),
                  ),
                  DropdownMenuItem(
                    value: 'consumable',
                    child: Text('Consumible'),
                  ),
                  DropdownMenuItem(value: 'packaging', child: Text('Empaque')),
                  DropdownMenuItem(
                    value: 'tooling',
                    child: Text('Herramienta'),
                  ),
                  DropdownMenuItem(value: 'service', child: Text('Servicio')),
                ], onClass),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<bool?>(
                  initialValue: activeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: true, child: Text('Activo')),
                    DropdownMenuItem(value: false, child: Text('Inactivo')),
                  ],
                  onChanged: onActive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$total materiales',
            style: const TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : rows.isEmpty
                ? const Center(
                    child: Text(
                      'Sin materiales.',
                      style: TextStyle(color: PomgtColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final id = row['id']?.toString();
                      final selected = id == selectedId;
                      final type =
                          data.typeById[row['material_type_id']?.toString()];
                      return InkWell(
                        borderRadius: PomgtRadii.borderSm,
                        onTap: () => onSelect(id),
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
                              Icon(
                                CupertinoIcons.cube_box,
                                size: 21,
                                color: selected
                                    ? PomgtColors.navy
                                    : PomgtColors.secondaryInk,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['sku']?.toString() ?? 'MAT',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      row['name']?.toString() ?? 'Material',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${type?['name'] ?? UiCopy.enumLabel(row['product_type']?.toString() ?? '')} · ${data.unitById[row['base_uom_id']?.toString()]?['symbol'] ?? '—'}',
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
                              PopupMenuButton<String>(
                                tooltip: 'Acciones',
                                padding: EdgeInsets.zero,
                                onSelected: (value) {
                                  if (value == 'edit') onEdit(row);
                                  if (value == 'delete') onDelete(row);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(CupertinoIcons.pencil, size: 17),
                                        SizedBox(width: 9),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filter(
    String label,
    String? value,
    List<DropdownMenuItem<String>> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Row(
          children: [
            Text(
              'Materiales',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(width: 8),
            const InfoTip(
              'Catálogo maestro de materiales basado en products con especificaciones por tipo de material.',
              size: 18,
            ),
          ],
        ),
      ),
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(CupertinoIcons.add, size: 18),
        label: const Text('Nuevo material'),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
      boxShadow: PomgtShadows.card,
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      label,
      style: const TextStyle(
        color: PomgtColors.muted,
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Dot(active: active),
      const SizedBox(width: 6),
      Text(
        active ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: active ? PomgtColors.mint : PomgtColors.danger,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
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
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _SimpleRows extends StatelessWidget {
  const _SimpleRows({
    required this.rows,
    required this.empty,
    required this.titleField,
  });
  final List<Map<String, dynamic>> rows;
  final String empty;
  final String titleField;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(empty, style: const TextStyle(color: PomgtColors.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        return ListTile(
          dense: true,
          leading: const Icon(CupertinoIcons.doc_text, color: PomgtColors.blue),
          title: Text(row[titleField]?.toString() ?? 'Registro'),
        );
      },
    );
  }
}

class _MaterialIndexData {
  const _MaterialIndexData({
    required this.materials,
    required this.types,
    required this.categories,
    required this.units,
    required this.currencies,
  });

  final List<Map<String, dynamic>> materials;
  final List<Map<String, dynamic>> types;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> currencies;

  factory _MaterialIndexData.empty() => const _MaterialIndexData(
    materials: [],
    types: [],
    categories: [],
    units: [],
    currencies: [],
  );

  Map<String, Map<String, dynamic>> get typeById => {
    for (final row in types) row['id']?.toString() ?? '': row,
  };
  Map<String, Map<String, dynamic>> get categoryById => {
    for (final row in categories) row['id']?.toString() ?? '': row,
  };
  Map<String, Map<String, dynamic>> get unitById => {
    for (final row in units) row['id']?.toString() ?? '': row,
  };
}

class _SpecData {
  const _SpecData({required this.attributes, required this.options});
  final List<Map<String, dynamic>> attributes;
  final Map<String, List<Map<String, dynamic>>> options;
  factory _SpecData.empty() => const _SpecData(attributes: [], options: {});
}

bool _isMaterialCatalogRow(Map<String, dynamic> row) {
  const materialTypes = {
    'raw_material',
    'consumable',
    'packaging',
    'tooling',
    'service',
  };
  return row['material_type_id'] != null ||
      materialTypes.contains(row['product_type']?.toString());
}
