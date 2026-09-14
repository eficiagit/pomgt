import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/bom_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomTitle extends StatelessWidget {
  const _BomTitle({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Estructuras de fabricación',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                const InfoTip(
                  'Define materiales, subensambles, consumibles y empaques para fabricar cada producto.',
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Define materiales, subensambles, consumibles y empaques necesarios para fabricar cada producto.',
              style: TextStyle(
                color: PomgtColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(CupertinoIcons.add, size: 18),
        label: const Text('Nueva estructura de fabricación'),
      ),
    ],
  );
}

class _BomList extends StatelessWidget {
  const _BomList({
    required this.rows,
    required this.total,
    required this.selectedId,
    required this.search,
    required this.loading,
    required this.onSearch,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> rows;
  final int total;
  final String? selectedId;
  final String search;
  final bool loading;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onSelect;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;

  String _productName(
    List<Map<String, dynamic>> products,
    LookupRepository lookups,
    dynamic id,
  ) => _lookupDisplay(
    products,
    id,
    Phase1Schema.tables['products']!,
    lookups,
    fallback: 'Producto sin identificar',
  );

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('products'),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        return _BomPanel(
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
                          hintText: 'Buscar estructura o producto',
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
              Row(
                children: const [
                  Expanded(child: _BomFilter('Todos los productos')),
                  SizedBox(width: 8),
                  Expanded(child: _BomFilter('Más recientes')),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '$total resultados',
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : rows.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin estructuras de fabricación.',
                          style: TextStyle(color: PomgtColors.muted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final selected = row['id']?.toString() == selectedId;
                          final active = row['is_active'] == true;
                          return InkWell(
                            borderRadius: PomgtRadii.borderSm,
                            onTap: () => onSelect(row['id']?.toString()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${row['bom_code'] ?? 'LM'} · ${row['name'] ?? 'Estructura de fabricación'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          active ? 'Activa' : 'Inactiva',
                                          style: const TextStyle(
                                            color: PomgtColors.muted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Producto: ${_productName(products, lookups, row['product_id'])}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: PomgtColors.muted,
                                            fontSize: 10.5,
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
                                            Icon(
                                              CupertinoIcons.pencil,
                                              size: 17,
                                            ),
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
      },
    );
  }
}

class _BomFilter extends StatelessWidget {
  const _BomFilter(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    height: 35,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(border: Border.all(color: PomgtColors.line)),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: PomgtColors.secondaryInk,
            ),
          ),
        ),
        const Icon(CupertinoIcons.chevron_down, size: 12),
      ],
    ),
  );
}

class _BomOverview extends StatelessWidget {
  const _BomOverview({
    super.key,
    required this.bom,
    required this.onEdit,
    required this.onChanged,
  });
  final Map<String, dynamic> bom;
  final VoidCallback onEdit;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = bom['id'].toString();
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(generic, lookups, id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        final data = snapshot.data ?? const {};
        final revisions =
            data['revisions'] as List<Map<String, dynamic>>? ?? const [];
        final revision = revisions.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['status'] == 'active',
          orElse: () => revisions.isEmpty ? null : revisions.first,
        );
        final items = data['items'] as List<Map<String, dynamic>>? ?? const [];
        final documents =
            data['documents'] as List<Map<String, dynamic>>? ?? const [];
        final substitutes =
            data['substitutes'] as List<Map<String, dynamic>>? ?? const [];
        final products =
            data['products'] as List<Map<String, dynamic>>? ?? const [];
        final units = data['units'] as List<Map<String, dynamic>>? ?? const [];
        return SingleChildScrollView(
          child: Column(
            children: [
              _BomHero(
                bom: bom,
                onEdit: onEdit,
                onDuplicate: () => _duplicate(context, data),
                onCreateRevision: () => _createRevision(context),
              ),
              const SizedBox(height: 12),
              _BomKpis(
                bom: bom,
                revision: revision,
                items: items,
                revisions: revisions.length,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        _BomComponents(
                          rows: items,
                          revision: revision,
                          products: products,
                          units: units,
                          lookups: lookups,
                          onAdd: revision == null
                              ? null
                              : () => _createItem(context, revision, products),
                        ),
                        const SizedBox(height: 12),
                        _BomImpact(items: items),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _BomSubstitutes(
                          rows: substitutes,
                          products: products,
                          lookups: lookups,
                          onShowAll: substitutes.isEmpty
                              ? null
                              : () => _showSubstitutes(context, products),
                        ),
                        const SizedBox(height: 12),
                        _BomRevisions(
                          rows: revisions,
                          onShowHistory: revisions.isEmpty
                              ? null
                              : () => _showRevisions(context),
                        ),
                        const SizedBox(height: 12),
                        _BomDocuments(
                          rows: documents,
                          revision: revision,
                          onShowAll: documents.isEmpty || revision == null
                              ? null
                              : () => _showDocuments(context, revision),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BomActions(id: id, bom: bom),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createRevision(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['bom_revisions']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        fixedValues: {'bom_id': bom['id']},
        title: 'Nueva revisión',
        icon: CupertinoIcons.clock,
      ),
    );
    if (changed == true && context.mounted) onChanged();
  }

  Future<void> _createItem(
    BuildContext context,
    Map<String, dynamic> revision,
    List<Map<String, dynamic>> products,
  ) async {
    final materialRows = _materialComponentRows(products);
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['bom_items']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        fixedValues: {'bom_revision_id': revision['id']},
        referenceRows: {'component_product_id': materialRows},
        title: 'Nuevo material / componente',
        icon: CupertinoIcons.square_grid_2x2,
      ),
    );
    if (changed == true && context.mounted) onChanged();
  }

  Future<void> _showRevisions(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BomCrudDialog(
        title: 'Historial de revisiones',
        child: EntityCrudPanel(
          table: 'bom_revisions',
          repository: context.read<GenericRepository>(),
          lookups: context.read<LookupRepository>(),
          fixedValues: {'bom_id': bom['id']},
          title: 'Revisiones de la estructura',
          description: 'Versiones históricas o vigentes de esta estructura.',
          flatList: true,
          onChanged: onChanged,
        ),
      ),
    );
    if (context.mounted) onChanged();
  }

  Future<void> _showDocuments(
    BuildContext context,
    Map<String, dynamic> revision,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BomCrudDialog(
        title: 'Documentos vinculados',
        child: EntityCrudPanel(
          table: 'document_links',
          repository: context.read<GenericRepository>(),
          lookups: context.read<LookupRepository>(),
          fixedValues: {'bom_revision_id': revision['id']},
          title: 'Documentos',
          description: 'Documentos relacionados con esta revisión.',
          onChanged: onChanged,
        ),
      ),
    );
    if (context.mounted) onChanged();
  }

  Future<void> _showSubstitutes(
    BuildContext context,
    List<Map<String, dynamic>> products,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BomCrudDialog(
        title: 'Sustitutos',
        child: _BomSubstitutesPanel(
          bomId: bom['id'].toString(),
          repository: context.read<GenericRepository>(),
          lookups: context.read<LookupRepository>(),
          materialRows: _materialComponentRows(products),
        ),
      ),
    );
    if (context.mounted) onChanged();
  }

  Future<void> _duplicate(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final generic = context.read<GenericRepository>();
    final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(
      7,
    );
    final createdBom = await generic.createRow(Phase1Schema.tables['boms']!, {
      'product_id': bom['product_id'],
      'bom_code': '${bom['bom_code'] ?? 'LM'}-COPIA-$suffix',
      'name': 'Copia de ${bom['name'] ?? 'Estructura de fabricación'}',
      'description': bom['description'],
      'is_default': false,
      'is_active': true,
    });
    final revisions =
        data['revisions'] as List<Map<String, dynamic>>? ?? const [];
    final itemsByRevision =
        data['itemsByRevision'] as Map<String, List<Map<String, dynamic>>>? ??
        const {};
    for (final revision in revisions) {
      final newRevision = await generic
          .createRow(Phase1Schema.tables['bom_revisions']!, {
            'bom_id': createdBom['id'],
            'revision_code': revision['revision_code'],
            'status': revision['status'],
            'output_quantity': revision['output_quantity'],
            'output_uom_id': revision['output_uom_id'],
            'expected_scrap_pct': revision['expected_scrap_pct'],
            'expected_yield_pct': revision['expected_yield_pct'],
            'effective_from': revision['effective_from'],
            'effective_to': revision['effective_to'],
            'approval_status': revision['approval_status'],
            'notes': revision['notes'],
          });
      for (final item
          in itemsByRevision[revision['id']?.toString()] ??
              const <Map<String, dynamic>>[]) {
        await generic.createRow(Phase1Schema.tables['bom_items']!, {
          'bom_revision_id': newRevision['id'],
          'line_no': item['line_no'],
          'component_type': item['component_type'],
          'component_product_id': item['component_product_id'],
          'component_product_revision_id':
              item['component_product_revision_id'],
          'child_bom_revision_id': item['child_bom_revision_id'],
          'quantity_basis': item['quantity_basis'],
          'quantity': item['quantity'],
          'quantity_formula': item['quantity_formula'],
          'formula_language': item['formula_language'],
          'uom_id': item['uom_id'],
          'scrap_pct': item['scrap_pct'],
          'expected_yield_pct': item['expected_yield_pct'],
          'is_optional': item['is_optional'],
          'is_phantom': item['is_phantom'],
          'issue_method': item['issue_method'],
          'notes': item['notes'],
        });
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Estructura de fabricación duplicada.')),
    );
    onChanged();
  }

  Future<Map<String, dynamic>> _load(
    GenericRepository generic,
    LookupRepository lookups,
    String id,
  ) async {
    final revisions = await generic.listRows(
      Phase1Schema.tables['bom_revisions']!,
      filters: {'bom_id': id},
    );
    final active = revisions.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['status'] == 'active',
      orElse: () => revisions.isEmpty ? null : revisions.first,
    );
    final items = active == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['bom_items']!,
            filters: {'bom_revision_id': active['id']},
          );
    final itemsByRevision = <String, List<Map<String, dynamic>>>{};
    for (final revision in revisions) {
      final revisionId = revision['id']?.toString();
      if (revisionId == null) continue;
      itemsByRevision[revisionId] = await generic.listRows(
        Phase1Schema.tables['bom_items']!,
        filters: {'bom_revision_id': revisionId},
      );
    }
    final documents = active == null
        ? <Map<String, dynamic>>[]
        : await generic.listRows(
            Phase1Schema.tables['document_links']!,
            filters: {'bom_revision_id': active['id']},
          );
    final substitutes = <Map<String, dynamic>>[];
    for (final item in items) {
      substitutes.addAll(
        await generic.listRows(
          Phase1Schema.tables['bom_item_substitutes']!,
          filters: {'bom_item_id': item['id']},
        ),
      );
    }
    final products = await lookups.rows('products');
    final units = await lookups.rows('units_of_measure');
    return {
      'revisions': revisions,
      'items': items,
      'itemsByRevision': itemsByRevision,
      'documents': documents,
      'substitutes': substitutes,
      'products': products,
      'units': units,
    };
  }
}

class _BomHero extends StatelessWidget {
  const _BomHero({
    required this.bom,
    required this.onEdit,
    required this.onDuplicate,
    required this.onCreateRevision,
  });
  final Map<String, dynamic> bom;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onCreateRevision;
  @override
  Widget build(BuildContext context) => _BomPanel(
    padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
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
                      '${bom['bom_code'] ?? 'LM'} · ${bom['name'] ?? 'Estructura de fabricación'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: PomgtColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  _BomStatus(active: bom['is_active'] == true),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Producto asociado · Estructura ${bom['is_default'] == true ? 'predeterminada' : 'configurable'}',
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(CupertinoIcons.pencil, size: 16),
          label: const Text('Editar'),
        ),
        TextButton.icon(
          onPressed: onDuplicate,
          icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
          label: const Text('Duplicar'),
        ),
        TextButton.icon(
          onPressed: onCreateRevision,
          icon: const Icon(CupertinoIcons.add_circled, size: 16),
          label: const Text('Nueva revisión'),
        ),
      ],
    ),
  );
}

class _BomStatus extends StatelessWidget {
  const _BomStatus({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: active ? PomgtColors.mint : PomgtColors.amber,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        active ? 'Activa' : 'Inactiva',
        style: TextStyle(
          color: active ? PomgtColors.mint : PomgtColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _BomKpis extends StatelessWidget {
  const _BomKpis({
    required this.bom,
    required this.revision,
    required this.items,
    required this.revisions,
  });
  final Map<String, dynamic> bom;
  final Map<String, dynamic>? revision;
  final List<Map<String, dynamic>> items;
  final int revisions;
  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'Revisión activa',
        revision?['revision_code']?.toString() ?? '—',
        CupertinoIcons.checkmark_circle,
      ),
      (
        'Cantidad base',
        '${revision?['output_quantity'] ?? '—'}',
        CupertinoIcons.arrow_up_right,
      ),
      ('Componentes', '${items.length}', CupertinoIcons.square_stack_3d_up),
      ('Costo estimado', '—', CupertinoIcons.money_dollar_circle),
      (
        'Merma estimada',
        '${revision?['expected_scrap_pct'] ?? 0}%',
        CupertinoIcons.percent,
      ),
      ('Revisiones', '$revisions', CupertinoIcons.clock),
    ];
    return SizedBox(
      width: double.infinity,
      child: _BomPanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 5
                : constraints.maxWidth >= 820
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final rows = <Widget>[];
            for (var start = 0; start < values.length; start += columns) {
              final end = (start + columns).clamp(0, values.length);
              rows.add(
                Row(
                  children: [
                    for (var i = start; i < end; i++)
                      Expanded(
                        child: _BomKpi(
                          values[i].$1,
                          values[i].$2,
                          values[i].$3,
                          (i - start) != columns - 1,
                        ),
                      ),
                    for (var i = end; i < start + columns; i++) const Spacer(),
                  ],
                ),
              );
              if (end < values.length) rows.add(const SizedBox(height: 8));
            }
            return Column(children: rows);
          },
        ),
      ),
    );
  }
}

class _BomKpi extends StatelessWidget {
  const _BomKpi(this.label, this.value, this.icon, this.divider);
  final String label;
  final String value;
  final IconData icon;
  final bool divider;
  @override
  Widget build(BuildContext context) => Container(
    height: 55,
    padding: const EdgeInsets.symmetric(horizontal: 11),
    decoration: BoxDecoration(
      border: Border(
        right: divider
            ? const BorderSide(color: PomgtColors.line)
            : BorderSide.none,
      ),
    ),
    child: Row(
      children: [
        Icon(icon, color: PomgtColors.blue, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _lookupDisplay(
  List<Map<String, dynamic>> rows,
  dynamic id,
  DbTableSpec spec,
  LookupRepository lookups, {
  required String fallback,
}) {
  final key = id?.toString();
  if (key == null || key.trim().isEmpty) return fallback;
  final matches = rows.where((row) => row['id']?.toString() == key);
  if (matches.isEmpty) return fallback;
  return lookups.display(spec, matches.first);
}

List<Map<String, dynamic>> _materialComponentRows(
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
            row['material_type_id'] != null ||
            materialTypes.contains(row['product_type']?.toString()),
      )
      .toList();
}

class _BomComponents extends StatelessWidget {
  const _BomComponents({
    required this.rows,
    required this.revision,
    required this.products,
    required this.units,
    required this.lookups,
    required this.onAdd,
  });
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? revision;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> units;
  final LookupRepository lookups;
  final VoidCallback? onAdd;

  String _productName(dynamic id) => _lookupDisplay(
    products,
    id,
    Phase1Schema.tables['products']!,
    lookups,
    fallback: 'Componente',
  );

  String _unitName(dynamic id) => _lookupDisplay(
    units,
    id,
    Phase1Schema.tables['units_of_measure']!,
    lookups,
    fallback: '—',
  );

  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Materiales y componentes',
    icon: CupertinoIcons.square_grid_2x2,
    link: 'Agregar material',
    onLinkTap: onAdd,
    child: rows.isEmpty
        ? const SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Agrega materiales o subensambles a esta revisión.',
                style: TextStyle(color: PomgtColors.muted),
              ),
            ),
          )
        : Table(
            columnWidths: const {
              0: FlexColumnWidth(1.7),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(.7),
              3: FlexColumnWidth(.7),
              4: FlexColumnWidth(.7),
              5: FlexColumnWidth(1),
            },
            children: [
              _bomHeader([
                'Material',
                'Tipo',
                'Cantidad',
                'Unidad',
                'Merma',
                'Disponibilidad',
              ]),
              for (final row in rows.take(8))
                _bomRow([
                  _productName(row['component_product_id']),
                  UiCopy.enumLabel(row['component_type']?.toString() ?? ''),
                  row['quantity']?.toString() ?? '—',
                  _unitName(row['uom_id']),
                  '${row['scrap_pct'] ?? 0}%',
                  row['is_optional'] == true ? 'Opcional' : 'Disponible',
                ]),
            ],
          ),
  );
}

class _BomSubstitutes extends StatelessWidget {
  const _BomSubstitutes({
    required this.rows,
    required this.products,
    required this.lookups,
    required this.onShowAll,
  });
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> products;
  final LookupRepository lookups;
  final VoidCallback? onShowAll;

  String _productName(dynamic id) => _lookupDisplay(
    products,
    id,
    Phase1Schema.tables['products']!,
    lookups,
    fallback: 'Material sustituto',
  );

  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Sustitutos y cobertura',
    icon: CupertinoIcons.arrow_2_squarepath,
    link: rows.isEmpty ? null : 'Ver todos los sustitutos (${rows.length})',
    onLinkTap: onShowAll,
    child: rows.isEmpty
        ? const _BomLine(
            'Sustitutos',
            'Sin sustitutos configurados',
            color: PomgtColors.muted,
          )
        : Column(
            children: [
              for (final row in rows.take(5))
                _BomLine(
                  'Alternativa ${row['priority'] ?? '—'}',
                  _productName(row['substitute_product_id']),
                  color: PomgtColors.mint,
                ),
            ],
          ),
  );
}

class _BomRevisions extends StatelessWidget {
  const _BomRevisions({required this.rows, required this.onShowHistory});
  final List<Map<String, dynamic>> rows;
  final VoidCallback? onShowHistory;
  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Revisiones',
    icon: CupertinoIcons.clock,
    link: rows.isEmpty ? null : 'Ver historial',
    onLinkTap: onShowHistory,
    child: rows.isEmpty
        ? const Text(
            'Sin revisiones.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _BomLine(
                  row['revision_code']?.toString() ?? 'Revisión',
                  UiCopy.enumLabel(row['status']?.toString() ?? ''),
                  color: row['status'] == 'active'
                      ? PomgtColors.blue
                      : PomgtColors.muted,
                ),
            ],
          ),
  );
}

class _BomDocuments extends StatelessWidget {
  const _BomDocuments({
    required this.rows,
    required this.revision,
    required this.onShowAll,
  });
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? revision;
  final VoidCallback? onShowAll;
  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Documentos vinculados',
    icon: CupertinoIcons.doc_text,
    link: rows.isEmpty ? null : 'Ver todos',
    onLinkTap: onShowAll,
    child: rows.isEmpty
        ? const Text(
            'Sin documentos vinculados.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _BomLine(
                  row['purpose']?.toString() ?? 'Documento',
                  row['created_at']?.toString().split('T').first ?? '—',
                ),
            ],
          ),
  );
}

class _BomImpact extends StatelessWidget {
  const _BomImpact({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Impacto en producción',
    icon: CupertinoIcons.chart_bar,
    child: Row(
      children: [
        _BomImpactValue(
          CupertinoIcons.cube_box,
          '${items.length}',
          'Componentes ligados',
        ),
        _BomImpactValue(CupertinoIcons.cart, '—', 'Órdenes relacionadas'),
        _BomImpactValue(CupertinoIcons.calendar, '—', 'Última actualización'),
        _BomImpactValue(CupertinoIcons.person, '—', 'Responsable'),
      ],
    ),
  );
}

class _BomImpactValue extends StatelessWidget {
  const _BomImpactValue(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Row(
      children: [
        Icon(icon, color: PomgtColors.blue, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BomActions extends StatelessWidget {
  const _BomActions({required this.id, required this.bom});
  final String id;
  final Map<String, dynamic> bom;
  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('products'),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        final materialRows = _materialComponentRows(products);
        final productName = _lookupDisplay(
          products,
          bom['product_id'],
          Phase1Schema.tables['products']!,
          lookups,
          fallback: 'Producto sin identificar',
        );
        return _BomPanel(
          flat: true,
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'General'),
                    Tab(text: 'Revisiones'),
                    Tab(text: 'Materiales y componentes'),
                    Tab(text: 'Sustitutos'),
                  ],
                ),
                SizedBox(
                  height: 640,
                  child: TabBarView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: _BomSummary(bom: bom, productName: productName),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: EntityCrudPanel(
                          table: 'bom_revisions',
                          repository: generic,
                          lookups: lookups,
                          fixedValues: {'bom_id': id},
                          title: 'Revisiones de la estructura',
                          flatList: true,
                        ),
                      ),
                      NestedRelationPanel(
                        title: 'Materiales por revisión',
                        help:
                            'Administra materiales, subensambles, cantidades, merma y rendimiento.',
                        parentTable: 'bom_revisions',
                        parentFilter: {'bom_id': id},
                        repository: generic,
                        lookups: lookups,
                        childReferenceRows: {
                          'bom_items': {'component_product_id': materialRows},
                        },
                        flatList: true,
                        childTabs: const [
                          ChildTabDefinition(
                            table: 'bom_items',
                            label: 'Materiales y componentes',
                            foreignKey: 'bom_revision_id',
                            help: 'Componentes de la estructura.',
                          ),
                        ],
                      ),
                      _BomSubstitutesPanel(
                        bomId: id,
                        repository: generic,
                        lookups: lookups,
                        materialRows: materialRows,
                      ),
                    ],
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

class _BomSection extends StatelessWidget {
  const _BomSection({
    required this.title,
    required this.child,
    this.link,
    this.onLinkTap,
    this.icon,
  });
  final String title;
  final String? link;
  final VoidCallback? onLinkTap;
  final IconData? icon;
  final Widget child;
  @override
  Widget build(BuildContext context) => _BomPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: PomgtColors.blue),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: PomgtColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const InfoTip('Información de la sección.', size: 14),
                ],
              ),
            ),
            if (link != null && onLinkTap != null)
              TextButton(
                onPressed: onLinkTap,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  link!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 11),
        child,
      ],
    ),
  );
}

class _BomPanel extends StatelessWidget {
  const _BomPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.flat = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final bool flat;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: flat
        ? const BoxDecoration(color: PomgtColors.canvas)
        : BoxDecoration(
            color: PomgtColors.canvas,
            borderRadius: PomgtRadii.borderMd,
            border: Border.all(
              color: PomgtColors.lineStrong.withValues(alpha: .55),
            ),
            boxShadow: PomgtShadows.card,
          ),
    child: child,
  );
}

class _BomCrudDialog extends StatelessWidget {
  const _BomCrudDialog({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 26),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 980,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark, size: 20),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _BomLine extends StatelessWidget {
  const _BomLine(this.label, this.value, {this.color = PomgtColors.ink});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PomgtColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PomgtColors.muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

TableRow _bomHeader(List<String> values) => TableRow(
  decoration: const BoxDecoration(color: PomgtColors.surfaceAlt),
  children: [
    for (final value in values)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
  ],
);
TableRow _bomRow(List<String> values) => TableRow(
  decoration: const BoxDecoration(
    border: Border(bottom: BorderSide(color: PomgtColors.line)),
  ),
  children: [
    for (final value in values)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
  ],
);

class _BomScreenState extends State<BomScreen> {
  late Future<List<Map<String, dynamic>>> future;
  late int seenDataRevision;
  String search = '';
  String? selectedId;

  @override
  void initState() {
    super.initState();
    seenDataRevision = context.read<RuntimeDataController>().revision;
    future = _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dataRevision = context.watch<RuntimeDataController>().revision;
    if (dataRevision == seenDataRevision) return;
    seenDataRevision = dataRevision;
    _reload();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      context.read<GenericRepository>().listRows(Phase1Schema.tables['boms']!);

  void _reload() {
    if (!mounted) return;
    setState(() {
      future = _load();
    });
  }

  Future<void> _create() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BomCreateDialog(),
    );
    if (changed == true && mounted) {
      context.read<BomController>().refresh();
      _reload();
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['boms']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: row,
      ),
    );
    if (changed == true && mounted) {
      context.read<BomController>().refresh();
      _reload();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar estructura de fabricación'),
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
        Phase1Schema.tables['boms']!,
        row,
      );
      if (!mounted) return;
      setState(() => selectedId = null);
      context.read<BomController>().refresh();
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
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final query = search.trim().toLowerCase();
        final rows = allRows
            .where(
              (row) =>
                  query.isEmpty ||
                  row.values.any(
                    (value) =>
                        value?.toString().toLowerCase().contains(query) ??
                        false,
                  ),
            )
            .toList();
        if (rows.isNotEmpty &&
            (selectedId == null ||
                !rows.any((row) => row['id']?.toString() == selectedId)))
          selectedId = rows.first['id']?.toString();
        final selected = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == selectedId,
          orElse: () => rows.isEmpty ? null : rows.first,
        );
        if (snapshot.hasError)
          return const Center(
            child: Text(
              'No fue posible cargar estructuras de fabricación.',
              style: TextStyle(color: PomgtColors.danger),
            ),
          );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BomTitle(onCreate: _create),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width >= 1280
                          ? 270
                          : 300,
                      child: _BomList(
                        rows: rows,
                        total: allRows.length,
                        selectedId: selectedId,
                        search: search,
                        loading:
                            snapshot.connectionState == ConnectionState.waiting,
                        onSearch: (value) => setState(() => search = value),
                        onSelect: (id) => setState(() => selectedId = id),
                        onEdit: _edit,
                        onDelete: _delete,
                        onRefresh: _reload,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: selected == null
                          ? const _BomPanel(
                              child: Center(
                                child: Text(
                                  'Selecciona una estructura para ver su expediente.',
                                  style: TextStyle(color: PomgtColors.muted),
                                ),
                              ),
                            )
                          : _BomOverview(
                              key: ValueKey(selected['id']),
                              bom: selected,
                              onEdit: () => _edit(selected),
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
}

class _BomCreateDialog extends StatefulWidget {
  const _BomCreateDialog();

  @override
  State<_BomCreateDialog> createState() => _BomCreateDialogState();
}

class _BomCreateDialogState extends State<_BomCreateDialog> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  final name = TextEditingController();
  final description = TextEditingController();
  final revision = TextEditingController(text: 'Rev. 01');
  final quantity = TextEditingController(text: '1');
  String? productId;
  String? outputUomId;
  bool isDefault = true;
  bool saving = false;
  late Future<List<List<Map<String, dynamic>>>> future;

  LookupRepository get lookups => context.read<LookupRepository>();
  GenericRepository get generic => context.read<GenericRepository>();

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<List<Map<String, dynamic>>>> _load() =>
      Future.wait([lookups.rows('products'), lookups.rows('units_of_measure')]);

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    description.dispose();
    revision.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> _createProduct() async {
    Map<String, dynamic>? created;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['products']!,
        repository: generic,
        lookups: lookups,
        onSaved: (row) => created = row,
        hiddenFields: const {
          'material_type_id',
          'material_category_id',
          'product_type',
        },
        fixedValues: const {'product_type': 'finished_good'},
        referenceFilters: const {
          'product_type_catalog_id': {'system_class': 'finished_good'},
        },
        afterSaved: (saved) async {
          if (saved['id'] == null || saved['product_type'] == 'finished_good') {
            return;
          }
          await generic.updateRow(
            Phase1Schema.tables['products']!,
            saved['id'].toString(),
            const {'product_type': 'finished_good', 'material_type_id': null},
          );
        },
      ),
    );
    if (changed != true || !mounted) return;
    lookups.invalidate('products');
    setState(() {
      productId = created?['id']?.toString();
      outputUomId = created?['base_uom_id']?.toString();
      future = _load();
    });
  }

  void _selectProduct(String? value, List<Map<String, dynamic>> products) {
    if (value == null) return;
    final product = products
        .where((e) => e['id']?.toString() == value)
        .toList();
    setState(() {
      productId = value;
      if (product.isNotEmpty) {
        outputUomId = product.first['base_uom_id']?.toString();
        if (name.text.trim().isEmpty)
          name.text =
              'Estructura de fabricación · ${product.first['name'] ?? ''}';
      }
    });
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false) ||
        productId == null ||
        outputUomId == null)
      return;
    setState(() => saving = true);
    try {
      final createdId = await context
          .read<BomRepository>()
          .createWithInitialRevision(
            productId: productId!,
            bomCode: code.text.trim(),
            name: name.text.trim(),
            description: description.text.trim().isEmpty
                ? null
                : description.text.trim(),
            isDefault: isDefault,
            revisionCode: revision.text.trim(),
            outputQuantity: double.parse(quantity.text.replaceAll(',', '')),
            outputUomId: outputUomId,
          );
      if (!mounted) return;
      context.read<BomController>().select(createdId);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ErrorCopy.message(e))));
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 26, 30, 24),
          child: FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: future,
            builder: (context, snapshot) {
              final data =
                  snapshot.data ??
                  <List<Map<String, dynamic>>>[
                    <Map<String, dynamic>>[],
                    <Map<String, dynamic>>[],
                  ];
              final products = data[0]
                  .where((p) => p['is_manufacturable'] == true)
                  .toList();
              final units = data[1];
              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            CupertinoIcons.square_stack_3d_up,
                            size: 25,
                            color: PomgtColors.blue,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nueva estructura de fabricación',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  'Crea la estructura y su primera revisión. Después podrás agregar materiales, subensambles y sustitutos.',
                                  style: TextStyle(color: PomgtColors.muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(CupertinoIcons.xmark, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  products.any(
                                    (p) => p['id']?.toString() == productId,
                                  )
                                  ? productId
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Producto *',
                                helperText:
                                    'Solo se muestran productos marcados como fabricables.',
                              ),
                              items: products
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p['id'].toString(),
                                      child: Text(
                                        lookups.display(
                                          Phase1Schema.tables['products']!,
                                          p,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => _selectProduct(v, products),
                              validator: (v) =>
                                  v == null ? 'Selecciona un producto' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Tooltip(
                            message: 'Agregar producto',
                            child: IconButton(
                              onPressed: _createProduct,
                              icon: const Icon(CupertinoIcons.add, size: 19),
                            ),
                          ),
                        ],
                      ),
                      if (products.isEmpty &&
                          snapshot.connectionState !=
                              ConnectionState.waiting) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _createProduct,
                            icon: const Icon(CupertinoIcons.add, size: 16),
                            label: const Text('Agregar el primer producto'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final horizontal = constraints.maxWidth >= 620;
                          final codeField = TextFormField(
                            controller: code,
                            decoration: const InputDecoration(
                              labelText: 'Código de estructura *',
                              hintText: 'Ej. LM-ETQ-001',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Ingresa un código'
                                : null,
                          );
                          final nameField = TextFormField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'Nombre *',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Ingresa un nombre'
                                : null,
                          );
                          if (!horizontal)
                            return Column(
                              children: [
                                codeField,
                                const SizedBox(height: 14),
                                nameField,
                              ],
                            );
                          return Row(
                            children: [
                              Expanded(child: codeField),
                              const SizedBox(width: 28),
                              Expanded(child: nameField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final horizontal = constraints.maxWidth >= 620;
                          final revisionField = TextFormField(
                            controller: revision,
                            decoration: const InputDecoration(
                              labelText: 'Revisión inicial *',
                              hintText: 'Rev. 01',
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Ingresa una revisión'
                                : null,
                          );
                          final quantityField = TextFormField(
                            controller: quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad base *',
                            ),
                            validator: (v) {
                              final n = double.tryParse(
                                (v ?? '').replaceAll(',', ''),
                              );
                              return n == null || n <= 0
                                  ? 'Ingresa una cantidad válida'
                                  : null;
                            },
                          );
                          final unitField = DropdownButtonFormField<String>(
                            initialValue:
                                units.any(
                                  (u) => u['id']?.toString() == outputUomId,
                                )
                                ? outputUomId
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Unidad de salida *',
                            ),
                            items: units
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u['id'].toString(),
                                    child: Text(
                                      lookups.display(
                                        Phase1Schema
                                            .tables['units_of_measure']!,
                                        u,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => outputUomId = v),
                            validator: (v) =>
                                v == null ? 'Selecciona una unidad' : null,
                          );
                          if (!horizontal)
                            return Column(
                              children: [
                                revisionField,
                                const SizedBox(height: 14),
                                quantityField,
                                const SizedBox(height: 14),
                                unitField,
                              ],
                            );
                          return Row(
                            children: [
                              Expanded(child: revisionField),
                              const SizedBox(width: 24),
                              Expanded(child: quantityField),
                              const SizedBox(width: 24),
                              Expanded(child: unitField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Establecer como estructura predeterminada',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Será la estructura sugerida al planear la fabricación de este producto.',
                        ),
                        value: isDefault,
                        onChanged: (v) => setState(() => isDefault = v),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: saving ? null : _save,
                            icon: saving
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    CupertinoIcons.arrow_right,
                                    size: 16,
                                  ),
                            label: Text(
                              saving
                                  ? 'Creando…'
                                  : 'Crear y agregar materiales',
                            ),
                          ),
                        ],
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
}

class _BomDetail extends StatelessWidget {
  const _BomDetail({required this.bom});
  final Map<String, dynamic> bom;

  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = bom['id'].toString();

    Future<void> edit() async {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EntityFormDialog(
          spec: Phase1Schema.tables['boms']!,
          repository: generic,
          lookups: lookups,
          original: bom,
        ),
      );
      if (changed == true && context.mounted)
        context.read<BomController>().refresh();
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('products'),
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Map<String, dynamic>>[];
        final materialRows = _materialComponentRows(products);
        final matches = products
            .where((p) => p['id']?.toString() == bom['product_id']?.toString())
            .toList();
        final productName = matches.isEmpty
            ? 'Producto sin identificar'
            : lookups.display(Phase1Schema.tables['products']!, matches.first);
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              DetailHeader(
                icon: CupertinoIcons.square_stack_3d_up,
                title: bom['name']?.toString() ?? 'Estructura de fabricación',
                subtitle: '${bom['bom_code'] ?? 'Sin código'} · $productName',
                help:
                    'La cabecera identifica la estructura. Las cantidades y componentes se conservan por revisión para mantener la trazabilidad histórica.',
                onEdit: edit,
              ),
              const Divider(height: 1),
              Expanded(
                child: DefaultTabController(
                  length: 5,
                  initialIndex: 2,
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: const TabBar(
                          isScrollable: true,
                          tabAlignment: TabAlignment.start,
                          dividerColor: Colors.transparent,
                          indicatorColor: PomgtColors.blue,
                          labelColor: PomgtColors.ink,
                          unselectedLabelColor: PomgtColors.muted,
                          tabs: [
                            HelpTab(
                              label: 'General',
                              help:
                                  'Producto, código, nombre y configuración principal de la estructura de fabricación.',
                            ),
                            HelpTab(
                              label: 'Revisiones',
                              help:
                                  'Versiones de la estructura con cantidad base, unidad, merma, rendimiento, vigencia y aprobación.',
                            ),
                            HelpTab(
                              label: 'Materiales y componentes',
                              help:
                                  'Materiales, subensambles, consumibles y empaques necesarios para fabricar el producto.',
                            ),
                            HelpTab(
                              label: 'Sustitutos',
                              help:
                                  'Alternativas permitidas para componentes cuando el material principal no está disponible.',
                            ),
                            HelpTab(
                              label: 'Documentos',
                              help:
                                  'Especificaciones, planos y documentos vinculados a cada revisión de la estructura.',
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _BomSummary(bom: bom, productName: productName),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: EntityCrudPanel(
                                table: 'bom_revisions',
                                repository: generic,
                                lookups: lookups,
                                fixedValues: {'bom_id': id},
                                title: 'Revisiones de la estructura',
                                description:
                                    'Controla la cantidad base, unidad, merma esperada, rendimiento, vigencia, aprobación y estado. Solo una revisión puede estar activa al mismo tiempo.',
                                flatList: true,
                              ),
                            ),
                            NestedRelationPanel(
                              title: 'Materiales por revisión',
                              help:
                                  'Selecciona una revisión y agrega los materiales, subensambles, consumibles o empaques necesarios. Los selectores muestran SKU y nombre, nunca identificadores técnicos.',
                              parentTable: 'bom_revisions',
                              parentFilter: {'bom_id': id},
                              repository: generic,
                              lookups: lookups,
                              childReferenceRows: {
                                'bom_items': {
                                  'component_product_id': materialRows,
                                },
                              },
                              flatList: true,
                              childTabs: const [
                                ChildTabDefinition(
                                  table: 'bom_items',
                                  label: 'Materiales y componentes',
                                  foreignKey: 'bom_revision_id',
                                  help:
                                      'Define componente, cantidad o fórmula, unidad, merma, rendimiento, consumo y, cuando aplica, una estructura hija para subensambles.',
                                ),
                              ],
                            ),
                            _BomSubstitutesPanel(
                              bomId: id,
                              repository: generic,
                              lookups: lookups,
                              materialRows: materialRows,
                            ),
                            NestedRelationPanel(
                              title: 'Documentos por revisión',
                              help:
                                  'Relaciona especificaciones, planos u otros documentos con una revisión específica de la estructura de fabricación.',
                              parentTable: 'bom_revisions',
                              parentFilter: {'bom_id': id},
                              repository: generic,
                              lookups: lookups,
                              childTabs: const [
                                ChildTabDefinition(
                                  table: 'document_links',
                                  label: 'Documentos',
                                  foreignKey: 'bom_revision_id',
                                  help:
                                      'Vínculos documentales asociados a la revisión seleccionada.',
                                ),
                              ],
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
}

class _BomSummary extends StatelessWidget {
  const _BomSummary({required this.bom, required this.productName});
  final Map<String, dynamic> bom;
  final String productName;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Definición', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 7),
              const InfoTip(
                'La estructura define con qué se fabrica el producto. Las cantidades específicas se encuentran dentro de cada revisión.',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 36,
            runSpacing: 22,
            children: [
              _KV('Código', '${bom['bom_code'] ?? '—'}'),
              _KV('Producto', productName),
              _KV('Predeterminada', bom['is_default'] == true ? 'Sí' : 'No'),
              _KV('Activa', bom['is_active'] == true ? 'Sí' : 'No'),
            ],
          ),
          if (bom['description'] != null &&
              bom['description'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 30),
            Text(
              bom['description'].toString(),
              style: const TextStyle(
                color: PomgtColors.secondaryInk,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BomSubstitutesPanel extends StatefulWidget {
  const _BomSubstitutesPanel({
    required this.bomId,
    required this.repository,
    required this.lookups,
    required this.materialRows,
  });
  final String bomId;
  final GenericRepository repository;
  final LookupRepository lookups;
  final List<Map<String, dynamic>> materialRows;

  @override
  State<_BomSubstitutesPanel> createState() => _BomSubstitutesPanelState();
}

class _BomSubstitutesPanelState extends State<_BomSubstitutesPanel> {
  String? revisionId;
  String? itemId;
  late Future<List<Map<String, dynamic>>> revisions;
  late Future<List<Map<String, dynamic>>> products;

  @override
  void initState() {
    super.initState();
    revisions = widget.repository.listRows(
      Phase1Schema.tables['bom_revisions']!,
      filters: {'bom_id': widget.bomId},
    );
    products = widget.lookups.rows('products');
  }

  String _componentLabel(
    Map<String, dynamic> item,
    List<Map<String, dynamic>> productRows,
  ) {
    final id = item['component_product_id']?.toString();
    final match = productRows.where((p) => p['id']?.toString() == id).toList();
    final product = match.isEmpty
        ? 'Componente'
        : widget.lookups.display(Phase1Schema.tables['products']!, match.first);
    return 'Línea ${item['line_no'] ?? '—'} · $product';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Sustitutos', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 7),
              const InfoTip(
                'Selecciona una revisión y un material. Puedes definir alternativas, prioridad, relación de conversión, porcentaje máximo, vigencia y si requieren aprobación.',
              ),
            ],
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: Future.wait([revisions, products]),
            builder: (context, snap) {
              final data =
                  snap.data ??
                  <List<Map<String, dynamic>>>[
                    <Map<String, dynamic>>[],
                    <Map<String, dynamic>>[],
                  ];
              final rows = data[0];
              final productRows = data[1];
              if (snap.connectionState == ConnectionState.waiting)
                return const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              if (rows.isEmpty)
                return const Expanded(
                  child: Center(
                    child: Text(
                      'Crea primero una revisión de la estructura de fabricación.',
                      style: TextStyle(color: PomgtColors.muted),
                    ),
                  ),
                );
              revisionId ??= rows.first['id'].toString();
              return Expanded(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue:
                          rows.any((r) => r['id']?.toString() == revisionId)
                          ? revisionId
                          : null,
                      decoration: const InputDecoration(labelText: 'Revisión'),
                      items: rows
                          .map(
                            (r) => DropdownMenuItem(
                              value: r['id'].toString(),
                              child: Text(
                                '${r['revision_code']} · ${UiCopy.enumLabel(r['status']?.toString() ?? '')}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        revisionId = v;
                        itemId = null;
                      }),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.repository.listRows(
                          Phase1Schema.tables['bom_items']!,
                          filters: {'bom_revision_id': revisionId},
                        ),
                        builder: (context, itemSnap) {
                          final items =
                              itemSnap.data ?? const <Map<String, dynamic>>[];
                          if (itemSnap.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            );
                          if (items.isEmpty)
                            return const Center(
                              child: Text(
                                'Agrega materiales a esta revisión para configurar sustitutos.',
                                style: TextStyle(color: PomgtColors.muted),
                              ),
                            );
                          itemId ??= items.first['id'].toString();
                          return Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue:
                                    items.any(
                                      (r) => r['id']?.toString() == itemId,
                                    )
                                    ? itemId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Material o componente',
                                ),
                                items: items
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r['id'].toString(),
                                        child: Text(
                                          _componentLabel(r, productRows),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() => itemId = v),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: EntityCrudPanel(
                                  table: 'bom_item_substitutes',
                                  repository: widget.repository,
                                  lookups: widget.lookups,
                                  fixedValues: {'bom_item_id': itemId},
                                  referenceRows: {
                                    'substitute_product_id':
                                        widget.materialRows,
                                  },
                                  flatList: true,
                                  title: 'Alternativas permitidas',
                                  description:
                                      'Productos o materiales alternativos permitidos para el componente seleccionado.',
                                ),
                              ),
                            ],
                          );
                        },
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

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PomgtColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: PomgtColors.ink,
          ),
        ),
      ],
    ),
  );
}
