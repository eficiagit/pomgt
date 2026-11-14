import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/number_input.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/scroll_to_top.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/bom_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../core/widgets/section_title.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomTitle extends StatelessWidget {
  const _BomTitle({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SectionTitle(
                'Estructuras de fabricación',
                icon: LucideIcons.layers,
              ),
              const InfoTip(
                'Define materiales, subensambles, consumibles y empaques para fabricar cada producto.',
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Define materiales, subensambles, consumibles y empaques necesarios para fabricar cada producto.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: PomgtColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
      final button = FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Nueva estructura de fabricación'),
      );

      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 10), button],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 18),
          button,
        ],
      );
    },
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
                          prefixIcon: Icon(LucideIcons.search, size: 20),
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
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: loading
                    ? const PomgtLoading()
                    : rows.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin estructuras de fabricación.',
                          style: TextStyle(color: PomgtColors.muted),
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
                            final selected =
                                row['id']?.toString() == selectedId;
                            final active = row['is_active'] == true;
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              onTap: () => onSelect(row['id']?.toString()),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: Icon(
                                      LucideIcons.layers,
                                      size: 17,
                                      color: PomgtColors.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
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
                                            fontWeight: FontWeight.w600,
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
                                    popUpAnimationStyle: PomgtMotion.style(
                                      context,
                                    ),
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
                                            Icon(LucideIcons.pencil, size: 17),
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
                                    ],
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(
                                        LucideIcons.ellipsisVertical,
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
              fontWeight: FontWeight.w600,
              color: PomgtColors.secondaryInk,
            ),
          ),
        ),
        const Icon(LucideIcons.chevronDown, size: 12),
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
          return const PomgtLoading();
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
        final products =
            data['products'] as List<Map<String, dynamic>>? ?? const [];
        final units = data['units'] as List<Map<String, dynamic>>? ?? const [];
        return ScrollToTopArea(
          padding: const EdgeInsets.all(16),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final left = Column(
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
                    );
                    final right = Column(
                      children: [
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
                    );
                    if (constraints.maxWidth < 860) {
                      return Column(
                        children: [left, const SizedBox(height: 12), right],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: left),
                        const SizedBox(width: 12),
                        Expanded(flex: 4, child: right),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _BomActions(id: id, bom: bom),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createRevision(BuildContext context) async {
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['bom_revisions']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        fixedValues: {'bom_id': bom['id']},
        title: 'Nueva versión',
        icon: LucideIcons.clock,
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
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['bom_items']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        fixedValues: {'bom_revision_id': revision['id']},
        referenceRows: {'component_product_id': materialRows},
        title: 'Nuevo material / componente',
        icon: LucideIcons.layoutGrid,
      ),
    );
    if (changed == true && context.mounted) onChanged();
  }

  Future<void> _showRevisions(BuildContext context) async {
    await showPomgtDialog<void>(
      context: context,
      builder: (_) => _BomCrudDialog(
        title: 'Historial de versiones',
        child: EntityCrudPanel(
          table: 'bom_revisions',
          repository: context.read<GenericRepository>(),
          lookups: context.read<LookupRepository>(),
          fixedValues: {'bom_id': bom['id']},
          title: 'Versiones de la estructura',
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
    await showPomgtDialog<void>(
      context: context,
      builder: (_) => _BomCrudDialog(
        title: 'Documentos vinculados',
        child: EntityCrudPanel(
          table: 'document_links',
          repository: context.read<GenericRepository>(),
          lookups: context.read<LookupRepository>(),
          fixedValues: {'bom_revision_id': revision['id']},
          title: 'Documentos',
          description: 'Documentos relacionados con esta versión.',
          onChanged: onChanged,
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
      final newRevision = await generic.createRow(
        Phase1Schema.tables['bom_revisions']!,
        {
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
        },
      );
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
    showPomgtSnackBar(context, 'Estructura de fabricación duplicada.');
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
    final products = await lookups.rows('products');
    final units = await lookups.rows('units_of_measure');
    return {
      'revisions': revisions,
      'items': items,
      'itemsByRevision': itemsByRevision,
      'documents': documents,
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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 9,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact
                        ? (constraints.maxWidth - 36).clamp(
                            0.0,
                            double.infinity,
                          )
                        : constraints.maxWidth * .68,
                  ),
                  child: Text(
                    '${bom['bom_code'] ?? 'LM'} · ${bom['name'] ?? 'Estructura de fabricación'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: PomgtColors.ink,
                    ),
                  ),
                ),
                _BomStatus(active: bom['is_active'] == true),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Producto asociado · Estructura ${bom['is_default'] == true ? 'predeterminada' : 'configurable'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PomgtColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        final actionBlock = Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(LucideIcons.pencil, size: 16),
              label: const Text('Editar'),
            ),
            TextButton.icon(
              onPressed: onDuplicate,
              icon: const Icon(LucideIcons.files, size: 16),
              label: const Text('Duplicar'),
            ),
            TextButton.icon(
              onPressed: onCreateRevision,
              icon: const Icon(LucideIcons.circlePlus, size: 16),
              label: const Text('Nueva versión'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titleBlock, const SizedBox(height: 10), actionBlock],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .46),
              child: actionBlock,
            ),
          ],
        );
      },
    ),
  );
}

class _BomStatus extends StatelessWidget {
  const _BomStatus({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => PomgtAnimatedValue(
    value: active,
    child: Row(
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
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
        'Versión activa',
        revision?['revision_code']?.toString() ?? '—',
        LucideIcons.circleCheck,
      ),
      (
        'Cantidad base',
        '${revision?['output_quantity'] ?? '—'}',
        LucideIcons.arrowUpRight,
      ),
      ('Componentes', '${items.length}', LucideIcons.layers),
      ('Costo estimado', '—', LucideIcons.circleDollarSign),
      (
        'Merma estimada',
        '${revision?['expected_scrap_pct'] ?? 0}%',
        LucideIcons.percent,
      ),
      ('Versiones', '$revisions', LucideIcons.clock),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
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
    icon: LucideIcons.layoutGrid,
    link: 'Agregar material',
    onLinkTap: onAdd,
    child: rows.isEmpty
        ? const SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Agrega materiales o subensambles a esta versión.',
                style: TextStyle(color: PomgtColors.muted),
              ),
            ),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 760,
              child: Table(
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
            ),
          ),
  );
}

class _BomRevisions extends StatelessWidget {
  const _BomRevisions({required this.rows, required this.onShowHistory});
  final List<Map<String, dynamic>> rows;
  final VoidCallback? onShowHistory;
  @override
  Widget build(BuildContext context) => _BomSection(
    title: 'Versiones',
    icon: LucideIcons.clock,
    link: rows.isEmpty ? null : 'Ver historial',
    onLinkTap: onShowHistory,
    child: rows.isEmpty
        ? const Text(
            'Sin versiones.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: [
              for (final row in rows.take(4))
                _BomLine(
                  row['revision_code']?.toString() ?? 'Versión',
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
    icon: LucideIcons.fileText,
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
    icon: LucideIcons.chartColumn,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 620
            ? (constraints.maxWidth - 24) / 4
            : constraints.maxWidth >= 360
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemWidth,
              child: _BomImpactValue(
                LucideIcons.box,
                '${items.length}',
                'Componentes ligados',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _BomImpactValue(
                LucideIcons.shoppingCart,
                '—',
                'Órdenes relacionadas',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _BomImpactValue(
                LucideIcons.calendar,
                '—',
                'Última actualización',
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _BomImpactValue(LucideIcons.user, '—', 'Responsable'),
            ),
          ],
        );
      },
    ),
  );
}

class _BomImpactValue extends StatelessWidget {
  const _BomImpactValue(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: PomgtColors.blue, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PomgtColors.muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    ],
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
          child: PomgtTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'General'),
                    Tab(text: 'Versiones'),
                    Tab(text: 'Materiales y componentes'),
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
                          title: 'Versiones de la estructura',
                          flatList: true,
                        ),
                      ),
                      NestedRelationPanel(
                        title: 'Materiales por versión',
                        help: 'Administra materiales, subensambles, cantidades, merma y rendimiento.',
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
                        fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
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
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
    ),
    child: child,
  );
}

class _BomCrudDialog extends StatelessWidget {
  const _BomCrudDialog({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 26,
        vertical: compact ? 10 : 26,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? size.width - 20 : 980,
          maxHeight: size.height * .9,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 22,
            compact ? 14 : 18,
            compact ? 14 : 22,
            compact ? 14 : 22,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
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
              fontWeight: FontWeight.w600,
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
            fontWeight: FontWeight.w600,
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
    final changed = await showPomgtDialog<bool>(
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
    final changed = await showPomgtDialog<bool>(
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
    final confirmed = await showPomgtDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          'Eliminar estructura de fabricación',
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'Se eliminarán también sus versiones, componentes y documentos ligados. Esta acción no se puede deshacer.\n\n'
            'Si ya se usó para preparar una orden de producción, no podrá eliminarse.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: PomgtColors.danger),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<BomRepository>().deleteBom(row['id'].toString());
      if (!mounted) return;
      setState(() => selectedId = null);
      context.read<BomController>().refresh();
      _reload();
      showPomgtSnackBar(context, 'Estructura de fabricación eliminada.');
    } catch (error) {
      if (!mounted) return;
      showPomgtSnackBar(
        context,
        ErrorCopy.message(
          error,
          fallback: 'No fue posible eliminar la estructura de fabricación.',
        ),
        isError: true,
      );
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
        final width = MediaQuery.sizeOf(context).width;
        final compact = width < 980;
        final sideWidth = width >= 1280 ? 270.0 : 300.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            compact ? 14 : 18,
            compact ? 12 : 16,
            compact ? 18 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BomTitle(onCreate: _create),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = _BomList(
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
                    );
                    final detail = selected == null
                        ? const _BomPanel(
                            child: EmptyState(
                              icon: LucideIcons.layers,
                              title: 'Selecciona una estructura',
                              message:
                                  'Su expediente y relaciones aparecerán aquí.',
                            ),
                          )
                        : _BomOverview(
                            key: ValueKey(selected['id']),
                            bom: selected,
                            onEdit: () => _edit(selected),
                            onChanged: _reload,
                          );
                    if (constraints.maxWidth < 980) {
                      final listHeight = (constraints.maxHeight * .36).clamp(
                        240.0,
                        360.0,
                      );
                      return Column(
                        children: [
                          SizedBox(height: listHeight, child: list),
                          const SizedBox(height: 12),
                          Expanded(child: detail),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        SizedBox(width: sideWidth, child: list),
                        const SizedBox(width: 14),
                        Expanded(child: detail),
                      ],
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
  final revision = TextEditingController(text: 'V.01');
  final quantity = TextEditingController(text: '1');
  String? productId;
  String? outputUomId;
  bool isDefault = true;
  bool saving = false;
  late Future<List<List<Map<String, dynamic>>>> future;
  final List<Map<String, dynamic>> extraUnits = [];

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
    final changed = await showPomgtDialog<bool>(
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
      showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 24,
        vertical: compact ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? size.width - 20 : 820,
          maxHeight: size.height * .9,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 30,
            compact ? 16 : 26,
            compact ? 16 : 30,
            compact ? 16 : 24,
          ),
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
              final units = [...data[1], ...extraUnits];
              return Form(
                key: formKey,
                child: ScrollToTopArea(
                  padding: const EdgeInsets.all(12),
                  builder: (context, controller) => SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              LucideIcons.layers,
                              size: 25,
                              color: PomgtColors.ink,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nueva estructura de fabricación',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Crea la estructura y su primera versión. Después podrás agregar materiales, subensambles y sustitutos.',
                                    style: TextStyle(color: PomgtColors.muted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(LucideIcons.x, size: 20),
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
                              child: CategorizedSearchPicker(
                                label: 'Producto *',
                                hint: 'Buscar producto…',
                                helperText: 'Solo se muestran productos marcados como fabricables.',
                                value:
                                    products.any(
                                      (p) => p['id']?.toString() == productId,
                                    )
                                    ? productId
                                    : null,
                                items: [
                                  for (final p in products)
                                    PickerItem(
                                      id: p['id'].toString(),
                                      label: lookups.display(
                                        Phase1Schema.tables['products']!,
                                        p,
                                      ),
                                      category: 'Productos',
                                    ),
                                ],
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
                                icon: const Icon(LucideIcons.plus, size: 19),
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
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: const Text('Agregar el primer producto'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final horizontal = constraints.maxWidth >= 620;
                            final codeField = TextFormField(
                              errorBuilder: pomgtValidationMessage,
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
                              errorBuilder: pomgtValidationMessage,
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'Nombre *',
                                hintText: 'Escribe el nombre de la estructura',
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
                          errorBuilder: pomgtValidationMessage,
                          controller: description,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Descripción',
                            hintText: 'Notas sobre esta estructura…',
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final horizontal = constraints.maxWidth >= 620;
                            final revisionField = TextFormField(
                              errorBuilder: pomgtValidationMessage,
                              controller: revision,
                              decoration: const InputDecoration(
                                labelText: 'Versión inicial *',
                                hintText: 'V.01',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Ingresa una versión'
                                  : null,
                            );
                            final quantityField = TextFormField(
                              errorBuilder: pomgtValidationMessage,
                              controller: quantity,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: const [
                                ThousandsInputFormatter(),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Cantidad base *',
                                hintText: 'Ej. 1',
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
                            final unitField = QuickCreateField(
                              table: 'units_of_measure',
                              repository: generic,
                              lookups: lookups,
                              isEmpty: units.isEmpty,
                              onCreated: (row) => setState(() {
                                extraUnits.add(row);
                                outputUomId = row['id']?.toString();
                              }),
                              child: CategorizedSearchPicker(
                                label: 'Unidad de salida *',
                                hint: 'Buscar unidad…',
                                value:
                                    units.any(
                                      (u) => u['id']?.toString() == outputUomId,
                                    )
                                    ? outputUomId
                                    : null,
                                items: [
                                  for (final u in units)
                                    PickerItem(
                                      id: u['id'].toString(),
                                      label: lookups.display(
                                        Phase1Schema
                                            .tables['units_of_measure']!,
                                        u,
                                      ),
                                      category: 'Unidades',
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => outputUomId = v),
                                validator: (v) =>
                                    v == null ? 'Selecciona una unidad' : null,
                              ),
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
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
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
                                      LucideIcons.arrowRight,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BomSummary extends StatelessWidget {
  const _BomSummary({required this.bom, required this.productName});
  final Map<String, dynamic> bom;
  final String productName;

  @override
  Widget build(BuildContext context) {
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Definición',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 7),
                const InfoTip(
                  'La estructura define con qué se fabrica el producto. Las cantidades específicas se encuentran dentro de cada versión.',
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
