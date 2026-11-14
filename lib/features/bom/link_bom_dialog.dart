import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';
import '../../core/widgets/scroll_to_top.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/number_input.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/bom_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

bool isMaterialCatalogRow(Map<String, dynamic> row) {
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

/// Lets the user build a product's estructura de fabricación (BOM) by
/// linking already-existing materials/components, without a separate trip
/// to the BOM module. "Omitir por ahora" is always available — nothing here
/// is mandatory.
///
/// [activateRevision] controls whether the initial BOM revision is created
/// as `active` (immediately usable by `prepare_production_order`) or left
/// as the default `draft`, for callers that want this to go through the
/// BOM module's own deliberate review step instead.
class LinkBomDialog extends StatefulWidget {
  const LinkBomDialog({
    super.key,
    required this.product,
    this.activateRevision = false,
  });
  final Map<String, dynamic> product;
  final bool activateRevision;

  @override
  State<LinkBomDialog> createState() => LinkBomDialogState();
}

class LinkBomDialogState extends State<LinkBomDialog> {
  late final TextEditingController _bomCode;
  late final TextEditingController _name;
  final _outputQty = TextEditingController(text: '1');
  String? _outputUomId;
  final Set<String> _selectedIds = {};
  final List<String> _selectedOrder = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _saving = false;
  String? _error;
  String? _materialTypeFilter;

  late Future<List<List<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    final sku = widget.product['sku']?.toString() ?? '';
    _bomCode = TextEditingController(text: sku.isEmpty ? 'LM' : 'LM-$sku');
    _name = TextEditingController(
      text: 'Estructura de fabricación · ${widget.product['name'] ?? sku}',
    );
    _outputUomId = widget.product['base_uom_id']?.toString();
    final lookups = context.read<LookupRepository>();
    _future = Future.wait([
      lookups.rows('products'),
      lookups.rows('units_of_measure'),
      lookups.rows('material_types'),
    ]);
  }

  @override
  void dispose() {
    _bomCode.dispose();
    _name.dispose();
    _outputQty.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.remove(id)) {
        _selectedOrder.remove(id);
        _qtyControllers.remove(id)?.dispose();
      } else {
        _selectedIds.add(id);
        _selectedOrder.add(id);
        _qtyControllers[id] = TextEditingController(text: '1');
      }
    });
  }

  String _componentType(Map<String, dynamic> material) {
    switch (material['product_type']?.toString()) {
      case 'packaging':
        return 'packaging';
      case 'consumable':
        return 'consumable';
      case 'semi_finished':
      case 'subassembly':
        return 'subassembly';
      default:
        return 'material';
    }
  }

  Future<void> _create(List<Map<String, dynamic>> materials) async {
    if (_bomCode.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(
        () => _error = 'Captura el código y el nombre de la estructura.',
      );
      return;
    }
    if (_selectedOrder.isEmpty) {
      setState(
        () => _error = 'Vincula al menos un material o componente antes de crear la estructura de fabricación.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bom = context.read<BomRepository>();
      final generic = context.read<GenericRepository>();
      final bomId = await bom.createWithInitialRevision(
        productId: widget.product['id'].toString(),
        bomCode: _bomCode.text.trim(),
        name: _name.text.trim(),
        isDefault: true,
        outputQuantity: double.tryParse(_outputQty.text) ?? 1,
        outputUomId: _outputUomId,
        revisionStatus: widget.activateRevision ? 'active' : 'draft',
      );
      final revisions = await generic.listRows(
        Phase1Schema.tables['bom_revisions']!,
        filters: {'bom_id': bomId},
      );
      final revisionId = revisions.isEmpty
          ? null
          : revisions.first['id']?.toString();
      if (revisionId != null) {
        for (var i = 0; i < _selectedOrder.length; i++) {
          final id = _selectedOrder[i];
          final material = materials.firstWhere(
            (m) => m['id'].toString() == id,
            orElse: () => const {},
          );
          if (material.isEmpty) continue;
          final qty = double.tryParse(_qtyControllers[id]!.text) ?? 1;
          await generic.createRow(Phase1Schema.tables['bom_items']!, {
            'bom_revision_id': revisionId,
            'line_no': i + 1,
            'component_type': _componentType(material),
            'component_product_id': id,
            'quantity_basis': 'per_output_unit',
            'quantity': qty,
            'uom_id': material['base_uom_id'],
            'scrap_pct': 0,
            'expected_yield_pct': 100,
            'is_optional': false,
            'is_phantom': false,
            'issue_method': 'manual',
          });
        }
      }
      if (!mounted) return;
      // createWithInitialRevision/bom_items inserts don't all flow through
      // GenericRepository, so RuntimeDataController never bumps these
      // tables' revision automatically — invalidate explicitly so any
      // "does this product have an active BOM?" check elsewhere sees it.
      final lookups = context.read<LookupRepository>();
      lookups.invalidate('boms');
      lookups.invalidate('bom_revisions');
      showPomgtSnackBar(context, 'Estructura de fabricación creada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ErrorCopy.message(
          e,
          fallback: 'No fue posible crear la estructura de fabricación.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 720;
    final sku = widget.product['sku']?.toString() ?? '';
    final name = widget.product['name']?.toString() ?? '';
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? screen.width - 20 : 760,
          maxHeight: screen.height * (compact ? .96 : .88),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 28,
            compact ? 16 : 24,
            compact ? 16 : 28,
            compact ? 14 : 20,
          ),
          child: FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 300, child: PomgtLoading());
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 260,
                  child: Center(
                    child: Text(
                      ErrorCopy.message(snapshot.error!),
                      style: const TextStyle(color: PomgtColors.danger),
                    ),
                  ),
                );
              }
              final allProducts = snapshot.data![0];
              final units = snapshot.data![1];
              final materialTypes = snapshot.data![2];
              final materials = allProducts
                  .where(isMaterialCatalogRow)
                  .toList();
              final unitsById = {for (final u in units) u['id'].toString(): u};
              final materialTypesById = {
                for (final t in materialTypes) t['id'].toString(): t,
              };
              String materialTypeLabel(Map<String, dynamic> m) {
                final name =
                    materialTypesById[m['material_type_id']
                            ?.toString()]?['name']
                        ?.toString();
                return name ??
                    UiCopy.enumLabel(m['product_type']?.toString() ?? 'other');
              }

              final materialTypeLabels =
                  materials.map(materialTypeLabel).toSet().toList()..sort(
                    (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                  );
              final visibleMaterials = _materialTypeFilter == null
                  ? materials
                  : materials
                        .where(
                          (m) => materialTypeLabel(m) == _materialTypeFilter,
                        )
                        .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.layers,
                        color: PomgtColors.ink,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estructura de fabricación',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$sku · $name se creó correctamente. Vincula materiales existentes para dejarla lista, o hazlo después.',
                              style: const TextStyle(
                                color: PomgtColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        icon: const Icon(LucideIcons.x, size: 20),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Flexible(
                    child: ScrollToTopArea(
                      padding: const EdgeInsets.all(12),
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    errorBuilder: pomgtValidationMessage,
                                    controller: _bomCode,
                                    decoration: const InputDecoration(
                                      labelText: 'Código *',
                                      hintText: 'Ej. BOM-0001',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    errorBuilder: pomgtValidationMessage,
                                    controller: _name,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre *',
                                      hintText:
                                          'Escribe el nombre de la estructura',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    errorBuilder: pomgtValidationMessage,
                                    controller: _outputQty,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: const [
                                      ThousandsInputFormatter(
                                        allowNegative: false,
                                      ),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Cantidad de salida',
                                      hintText: 'Ej. 1',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: CategorizedSearchPicker(
                                    label: 'Unidad de salida',
                                    hint: 'Buscar unidad…',
                                    value: _outputUomId,
                                    items: [
                                      for (final u in units)
                                        PickerItem(
                                          id: u['id'].toString(),
                                          label:
                                              '${u['name']} (${u['symbol']})',
                                          category: 'Unidades',
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _outputUomId = v),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Materiales / componentes',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (materials.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Todavía no tienes materiales registrados. Una estructura de fabricación necesita al menos uno — créalos en Materiales y vuelve a intentarlo.',
                                  style: TextStyle(color: PomgtColors.muted),
                                ),
                              )
                            else ...[
                              DropdownButtonFormField<String?>(
                                initialValue: _materialTypeFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de material',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Todos los tipos'),
                                  ),
                                  for (final label in materialTypeLabels)
                                    DropdownMenuItem(
                                      value: label,
                                      child: Text(label),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _materialTypeFilter = v),
                              ),
                              const SizedBox(height: 12),
                              MultiCategorizedPicker(
                                key: ValueKey(
                                  'materials-${_materialTypeFilter ?? ''}',
                                ),
                                label: 'Buscar material o componente',
                                hint: 'Escribe el SKU o el nombre…',
                                items: [
                                  for (final m in visibleMaterials)
                                    PickerItem(
                                      id: m['id'].toString(),
                                      label: '${m['sku']} · ${m['name']}',
                                      category: materialTypeLabel(m),
                                    ),
                                ],
                                selectedIds: _selectedIds,
                                onToggle: _toggle,
                              ),
                              const SizedBox(height: 12),
                              if (_selectedOrder.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    'Sin materiales vinculados todavía.',
                                    style: TextStyle(color: PomgtColors.muted),
                                  ),
                                )
                              else
                                for (final id in _selectedOrder)
                                  Builder(
                                    builder: (context) {
                                      final material = materials.firstWhere(
                                        (m) => m['id'].toString() == id,
                                        orElse: () => const {},
                                      );
                                      final unitSymbol =
                                          unitsById[material['base_uom_id']
                                                  ?.toString()]?['symbol']
                                              ?.toString();
                                      return _SelectedMaterialRow(
                                        material: material,
                                        unitSymbol: unitSymbol,
                                        controller: _qtyControllers[id]!,
                                        onRemove: () => _toggle(id),
                                      );
                                    },
                                  ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: PomgtColors.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Omitir por ahora'),
                      ),
                      FilledButton.icon(
                        onPressed: (_saving || _selectedOrder.isEmpty)
                            ? null
                            : () => _create(materials),
                        icon: _saving
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.check, size: 18),
                        label: const Text('Crear estructura de fabricación'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SelectedMaterialRow extends StatelessWidget {
  const _SelectedMaterialRow({
    required this.material,
    required this.unitSymbol,
    required this.controller,
    required this.onRemove,
  });
  final Map<String, dynamic> material;
  final String? unitSymbol;
  final TextEditingController controller;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      border: Border.all(color: PomgtColors.line),
      borderRadius: PomgtRadii.borderSm,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${material['sku'] ?? '—'} · ${material['name'] ?? 'Material'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsInputFormatter()],
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Cantidad',
              hintText: 'Ej. 1',
              suffixText: unitSymbol,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Quitar',
          icon: const Icon(LucideIcons.x, size: 16),
          onPressed: onRemove,
        ),
      ],
    ),
  );
}
