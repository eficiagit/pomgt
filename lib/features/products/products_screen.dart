import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/detail_sections.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Map<String, dynamic>>> future;
  late int seenRevision;
  late int seenDataRevision;
  String search = '';
  String? selectedId;

  @override
  void initState() {
    super.initState();
    seenRevision = context.read<ProductsController>().revision;
    seenDataRevision = context.read<RuntimeDataController>().revision;
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return context.read<GenericRepository>().listRows(
      Phase1Schema.tables['products']!,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<ProductsController>().revision;
    final dataRevision = context.watch<RuntimeDataController>().revision;
    if (revision != seenRevision || dataRevision != seenDataRevision) {
      if (revision != seenRevision) seenRevision = revision;
      if (dataRevision != seenDataRevision) seenDataRevision = dataRevision;
      _reload();
    }
  }

  void _reload() {
    setState(() {
      future = _load();
    });
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
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
        product,
      );
      if (!mounted) return;
      setState(() => selectedId = null);
      context.read<LookupRepository>().invalidate('products');
      context.read<ProductsController>().refresh();
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final repository = context.read<GenericRepository>();
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['products']!,
        repository: repository,
        lookups: context.read<LookupRepository>(),
        original: row,
        hiddenFields: const {
          'material_type_id',
          'material_category_id',
          'product_type',
        },
        fixedValues: row == null
            ? const {'product_type': 'finished_good'}
            : const {},
        referenceFilters: const {
          'product_type_catalog_id': {'system_class': 'finished_good'},
        },
        title: row == null ? 'Nuevo producto' : 'Editar producto',
        icon: Icons.inventory_2_outlined,
        afterSaved: (saved) async {
          if (saved['id'] == null || saved['product_type'] == 'finished_good') {
            return;
          }
          await repository.updateRow(
            Phase1Schema.tables['products']!,
            saved['id'].toString(),
            const {'product_type': 'finished_good', 'material_type_id': null},
          );
        },
      ),
    );
    if (changed == true && mounted) {
      context.read<LookupRepository>().invalidate('products');
      context.read<ProductsController>().refresh();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final rows = allRows
            .where((row) => !_isMaterialCatalogRow(row))
            .toList();

        final query = search.trim().toLowerCase();
        final filtered = rows.where((row) {
          if (query.isEmpty) return true;
          return row.values.any(
            (value) => value?.toString().toLowerCase().contains(query) ?? false,
          );
        }).toList();
        if (filtered.isNotEmpty &&
            (selectedId == null ||
                !filtered.any((row) => row['id']?.toString() == selectedId))) {
          selectedId = filtered.first['id']?.toString();
        }
        final selected = filtered.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == selectedId,
          orElse: () => filtered.isEmpty ? null : filtered.first,
        );
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'No fue posible cargar productos.',
              style: const TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProductsTitle(onCreate: () => _edit()),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width >= 1280
                          ? 270
                          : 300,
                      child: _ProductListPanel(
                        rows: filtered,
                        total: rows.length,
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
                          ? const _ProductEmptyDetail()
                          : _ProductOverview(
                              key: ValueKey(selected['id']),
                              product: selected,
                              onEdit: () => _edit(selected),
                              onDelete: () => _delete(selected),
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

class _ProductsTitle extends StatelessWidget {
  const _ProductsTitle({required this.onCreate});
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
                  'Productos',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                const InfoTip(
                  'Gestiona productos, revisiones, clientes, estructuras de fabricación, rutas y documentos.',
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Catálogo maestro de productos, revisiones, especificaciones, estructuras de fabricación y rutas de fabricación.',
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
        label: const Text('Nuevo producto'),
      ),
    ],
  );
}

class _ProductListPanel extends StatelessWidget {
  const _ProductListPanel({
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
  final Future<void> Function([Map<String, dynamic>?]) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
      boxShadow: PomgtShadows.card,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: TextField(
                        onChanged: onSearch,
                        decoration: const InputDecoration(
                          hintText: 'Buscar productos...',
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
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: onRefresh,
                    icon: const Icon(CupertinoIcons.refresh, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Expanded(child: _ProductSelectLike('Todos los productos')),
                  SizedBox(width: 10),
                  Expanded(child: _ProductSelectLike('Más recientes')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$total productos',
            style: const TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : rows.isEmpty
              ? const Center(
                  child: Text(
                    'Sin productos.',
                    style: TextStyle(color: PomgtColors.muted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final id = row['id']?.toString();
                    final selected = id == selectedId;
                    return InkWell(
                      borderRadius: PomgtRadii.borderSm,
                      onTap: () => onSelect(id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
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
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                size: 16,
                                color: selected
                                    ? PomgtColors.navy
                                    : PomgtColors.secondaryInk,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['sku'] ?? '—'} · ${row['name'] ?? 'Producto'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PomgtColors.ink,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${UiCopy.enumLabel(row['product_type']?.toString() ?? '')} · ${row['is_active'] == true ? 'Activo' : 'Inactivo'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PomgtColors.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
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

class _ProductSelectLike extends StatelessWidget {
  const _ProductSelectLike(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(border: Border.all(color: PomgtColors.line)),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PomgtColors.secondaryInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Icon(CupertinoIcons.chevron_down, size: 13),
      ],
    ),
  );
}

class _ProductOverview extends StatelessWidget {
  const _ProductOverview({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = product['id'].toString();
    return FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: _load(generic, id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'No fue posible cargar el expediente del producto.',
              style: TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final data = snapshot.data ?? const {};
        final revisions = data['revisions'] ?? const [];
        final customerProducts = data['customerProducts'] ?? const [];
        final boms = data['boms'] ?? const [];
        final routings = data['routings'] ?? const [];
        final documents = data['documents'] ?? const [];
        final productionOrders = data['productionOrders'] ?? const [];
        final orderLines = data['orderLines'] ?? const [];
        final nonconformities = data['nonconformities'] ?? const [];
        return SingleChildScrollView(
          child: Column(
            children: [
              _ProductHero(
                product: product,
                onEdit: onEdit,
                onDelete: onDelete,
              ),
              const SizedBox(height: 14),
              _ProductKpis(
                revisions: revisions.length,
                customers: customerProducts.length,
                boms: boms.length,
                routings: routings.length,
                documents: documents.length,
                productionOrders: productionOrders.length,
                requestedUnits: _sum(orderLines, 'quantity'),
                completedUnits: _sum(productionOrders, 'completed_quantity'),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _ProductInfoPanel(product: product, lookups: lookups),
                        const SizedBox(height: 14),
                        _ProductRowsPanel(
                          title: 'Estructura de fabricación vinculada',
                          link: boms.isEmpty ? null : 'Ver estructura completa',
                          rows: boms,
                          empty: 'Sin estructuras de fabricación.',
                          icon: CupertinoIcons.square_stack_3d_up,
                          titleField: 'name',
                          fallbackTitleField: 'bom_code',
                          subtitleFields: const ['bom_code', 'description'],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _ProductTechnicalPanel(rows: revisions),
                        const SizedBox(height: 14),
                        _ProductRevisionPanel(rows: revisions),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ProductRoutingPanel(rows: routings)),
                  const SizedBox(width: 14),
                  Expanded(child: _ProductUsagePanel(rows: productionOrders)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ProductRowsPanel(
                      title: 'Clientes que lo compran',
                      link: customerProducts.isEmpty
                          ? null
                          : 'Ver todos (${customerProducts.length})',
                      rows: customerProducts,
                      empty: 'Sin clientes vinculados.',
                      icon: CupertinoIcons.person_2,
                      titleField: 'customer_product_name',
                      fallbackTitleField: 'customer_sku',
                      subtitleFields: const ['customer_sku', 'revision'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ProductRowsPanel(
                      title: 'Documentos recientes',
                      link: documents.isEmpty ? null : 'Ver todos',
                      rows: documents,
                      empty: 'Sin documentos.',
                      icon: CupertinoIcons.doc_text,
                      titleField: 'document_title',
                      fallbackTitleField: 'document_id',
                      subtitleFields: const ['document_type', 'created_at'],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ProductActivityPanel(
                      productionOrders: productionOrders,
                      revisions: revisions,
                      nonconformities: nonconformities,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> _load(
    GenericRepository generic,
    String id,
  ) async {
    final results = await Future.wait([
      generic.listRows(
        Phase1Schema.tables['product_revisions']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['customer_products']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['boms']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['routings']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['document_links']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['production_orders']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['customer_order_lines']!,
        filters: {'product_id': id},
      ),
      generic.listRows(
        Phase1Schema.tables['nonconformities']!,
        filters: {'product_id': id},
      ),
    ]);
    return {
      'revisions': results[0],
      'customerProducts': results[1],
      'boms': results[2],
      'routings': results[3],
      'documents': results[4],
      'productionOrders': results[5],
      'orderLines': results[6],
      'nonconformities': results[7],
    };
  }
}

class _ProductHero extends StatelessWidget {
  const _ProductHero({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _ProductPanel(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
                      product['name']?.toString() ?? 'Producto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const InfoTip('Ficha maestra del producto.', size: 16),
                  const SizedBox(width: 10),
                  _PlainStatus(active: product['is_active'] == true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${product['sku'] ?? '—'} · ${UiCopy.enumLabel(product['product_type']?.toString() ?? '')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(CupertinoIcons.pencil, size: 17),
          label: const Text('Editar producto'),
        ),
        IconButton(
          onPressed: onDelete,
          tooltip: 'Eliminar producto',
          icon: const Icon(CupertinoIcons.trash, size: 18),
        ),
      ],
    ),
  );
}

class _ProductKpis extends StatelessWidget {
  const _ProductKpis({
    required this.revisions,
    required this.customers,
    required this.boms,
    required this.routings,
    required this.documents,
    required this.productionOrders,
    required this.requestedUnits,
    required this.completedUnits,
  });

  final int revisions;
  final int customers;
  final int boms;
  final int routings;
  final int documents;
  final int productionOrders;
  final int requestedUnits;
  final int completedUnits;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ProductKpi(
        'Revisiones',
        revisions,
        'Versiones técnicas',
        Icons.history_edu_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Clientes vinculados',
        customers,
        'SKUs comerciales',
        Icons.groups_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Estructuras de fabricación',
        boms,
        'Recetas disponibles',
        Icons.account_tree_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Rutas',
        routings,
        'Procesos definidos',
        Icons.route_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Documentos',
        documents,
        'Archivos vinculados',
        Icons.description_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'OPs generadas',
        productionOrders,
        'Producción vinculada',
        Icons.precision_manufacturing_outlined,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Unidades solicitadas',
        requestedUnits,
        'En líneas de pedido',
        Icons.bar_chart_rounded,
        PomgtColors.blue,
      ),
      _ProductKpi(
        'Unidades completadas',
        completedUnits,
        'Producción cerrada',
        Icons.task_alt_outlined,
        PomgtColors.mint,
      ),
    ];
    return _ProductPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1250 ? 4 : 2;
          final width = constraints.maxWidth / columns;
          return Wrap(
            runSpacing: 10,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: width,
                  child: _ProductKpiTile(
                    item: items[i],
                    divider: i % columns != columns - 1,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductKpi {
  const _ProductKpi(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.color,
  );
  final String label;
  final int value;
  final String caption;
  final IconData icon;
  final Color color;
}

class _ProductKpiTile extends StatelessWidget {
  const _ProductKpiTile({required this.item, required this.divider});
  final _ProductKpi item;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      border: Border(
        right: divider
            ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .45))
            : BorderSide.none,
      ),
    ),
    child: Row(
      children: [
        Icon(item.icon, color: item.color, size: 25),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value.toString(),
                style: const TextStyle(
                  color: PomgtColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                item.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductInfoPanel extends StatelessWidget {
  const _ProductInfoPanel({required this.product, required this.lookups});
  final Map<String, dynamic> product;
  final LookupRepository lookups;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<List<Map<String, dynamic>>>>(
    future: Future.wait([
      lookups.rows('units_of_measure'),
      lookups.rows('product_categories'),
      lookups.rows('product_types'),
      lookups.rows('customers'),
    ]),
    builder: (context, snapshot) {
      final data =
          snapshot.data ??
          const [
            <Map<String, dynamic>>[],
            <Map<String, dynamic>>[],
            <Map<String, dynamic>>[],
            <Map<String, dynamic>>[],
          ];
      String resolve(int index, dynamic id, String table) {
        if (id == null) return '—';
        final matches = data[index]
            .where((row) => row['id']?.toString() == id.toString())
            .toList();
        return matches.isEmpty
            ? '—'
            : lookups.display(Phase1Schema.tables[table]!, matches.first);
      }

      final rows = [
        MapEntry('SKU', product['sku']?.toString() ?? '—'),
        MapEntry('Nombre', product['name']?.toString() ?? '—'),
        MapEntry(
          'Tipo de producto',
          resolve(2, product['product_type_catalog_id'], 'product_types'),
        ),
        MapEntry(
          'Clasificación',
          UiCopy.enumLabel(product['product_type']?.toString() ?? ''),
        ),
        MapEntry(
          'Categoría',
          resolve(1, product['category_id'], 'product_categories'),
        ),
        MapEntry(
          'Unidad base',
          resolve(0, product['base_uom_id'], 'units_of_measure'),
        ),
        MapEntry(
          'Cliente propietario',
          resolve(3, product['owner_customer_id'], 'customers'),
        ),
        MapEntry(
          'Tiempo de entrega',
          '${product['default_lead_time_days'] ?? 0} días',
        ),
        MapEntry(
          'Se fabrica',
          product['is_manufacturable'] == true ? 'Sí' : 'No',
        ),
        MapEntry('Se compra', product['is_purchasable'] == true ? 'Sí' : 'No'),
        MapEntry('Se vende', product['is_sellable'] == true ? 'Sí' : 'No'),
        MapEntry('Trazabilidad', _tracking(product)),
      ];
      return _ProductTitledPanel(
        title: 'Resumen del producto',
        icon: Icons.inventory_2_outlined,
        link: null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child:
                      product['description'] != null &&
                          product['description'].toString().trim().isNotEmpty
                      ? Text(
                          product['description'].toString(),
                          style: const TextStyle(
                            color: PomgtColors.secondaryInk,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        )
                      : const Text(
                          'Ficha maestra del producto y sus vínculos operativos.',
                          style: TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 122,
                  height: 92,
                  decoration: BoxDecoration(
                    color: PomgtColors.surfaceAlt,
                    border: Border.all(color: PomgtColors.line),
                  ),
                  child: const Icon(
                    CupertinoIcons.cube_box,
                    size: 42,
                    color: PomgtColors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620 ? 2 : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 24) / columns;
                return Wrap(
                  spacing: 24,
                  runSpacing: 15,
                  children: rows
                      .map(
                        (row) => SizedBox(
                          width: width,
                          child: _ProductKV(label: row.key, value: row.value),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

class _ProductTechnicalPanel extends StatelessWidget {
  const _ProductTechnicalPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final revision = rows.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['status']?.toString() == 'active',
      orElse: () => rows.isEmpty ? null : rows.first,
    );
    if (revision == null) {
      return const _ProductTitledPanel(
        title: 'Especificaciones técnicas',
        icon: Icons.tune_outlined,
        child: Text(
          'Sin revisión técnica.',
          style: TextStyle(color: PomgtColors.muted),
        ),
      );
    }
    final values = <MapEntry<String, String>>[
      MapEntry('Ancho', _technicalValue(revision['width'], 'mm')),
      MapEntry('Alto', _technicalValue(revision['height'], 'mm')),
      MapEntry('Largo', _technicalValue(revision['length'], 'mm')),
      MapEntry('Espesor', _technicalValue(revision['thickness'], 'mm')),
      MapEntry('Peso', _technicalValue(revision['weight'], 'kg')),
      MapEntry('Material', revision['material_description']?.toString() ?? '—'),
      MapEntry('Color', revision['color_description']?.toString() ?? '—'),
      MapEntry(
        'Tolerancia',
        revision['general_tolerance_notes']?.toString() ?? '—',
      ),
    ];
    return _ProductTitledPanel(
      title: 'Especificaciones técnicas',
      icon: Icons.tune_outlined,
      link: 'Editar',
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
        children: [
          for (var index = 0; index < values.length; index += 2)
            TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PomgtColors.line)),
              ),
              children: [
                _TechnicalCell(values[index]),
                index + 1 < values.length
                    ? _TechnicalCell(values[index + 1])
                    : const SizedBox(),
              ],
            ),
        ],
      ),
    );
  }
}

class _TechnicalCell extends StatelessWidget {
  const _TechnicalCell(this.value);
  final MapEntry<String, String> value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            value.key,
            style: const TextStyle(color: PomgtColors.muted, fontSize: 11.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PomgtColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProductRoutingPanel extends StatelessWidget {
  const _ProductRoutingPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => _ProductTitledPanel(
    title: 'Ruta de fabricación',
    icon: Icons.route_outlined,
    link: rows.isEmpty ? null : 'Ver ruta completa',
    child: rows.isEmpty
        ? const Text(
            'Sin rutas de fabricación.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: rows.take(6).toList().asMap().entries.map((entry) {
                final row = entry.value;
                return Row(
                  children: [
                    if (entry.key > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          CupertinoIcons.arrow_right,
                          size: 15,
                          color: PomgtColors.subtle,
                        ),
                      ),
                    SizedBox(
                      width: 105,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: PomgtColors.blueSoft,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                color: PomgtColors.blue,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            row['name']?.toString() ??
                                row['routing_code']?.toString() ??
                                'Operación',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            row['description']?.toString() ?? 'Ruta activa',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PomgtColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
  );
}

class _ProductUsagePanel extends StatelessWidget {
  const _ProductUsagePanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final values = rows
        .take(6)
        .map((row) => ((row['planned_quantity'] as num?)?.toDouble() ?? 0))
        .toList();
    return _ProductTitledPanel(
      title: 'Uso reciente del producto',
      icon: Icons.show_chart_outlined,
      link: 'Últimas 6 semanas',
      child: SizedBox(
        height: 150,
        child: values.isEmpty
            ? const Center(
                child: Text(
                  'Sin órdenes recientes.',
                  style: TextStyle(color: PomgtColors.muted),
                ),
              )
            : CustomPaint(
                painter: _UsageChartPainter(values),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _UsageChartPainter extends CustomPainter {
  const _UsageChartPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = PomgtColors.line;
    final bar = Paint()..color = PomgtColors.blue;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final max = values.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );
    final gap = size.width / (values.length * 2 + 1);
    for (var index = 0; index < values.length; index++) {
      final height = (values[index] / max) * (size.height - 20);
      final left = gap * (index * 2 + 1);
      canvas.drawRect(
        Rect.fromLTWH(left, size.height - height, gap, height),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _UsageChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

String _technicalValue(dynamic value, String unit) {
  if (value == null || value.toString().trim().isEmpty) return '—';
  return '$value $unit';
}

class _ProductRevisionPanel extends StatelessWidget {
  const _ProductRevisionPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => _ProductTitledPanel(
    title: 'Revisiones',
    icon: Icons.history_edu_outlined,
    link: rows.isEmpty ? null : 'Ver todas',
    child: rows.isEmpty
        ? const Text(
            'Sin revisiones.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: rows.take(4).map((row) {
              return _ProductMiniRow(
                icon: Icons.history_edu_outlined,
                title: row['revision_code']?.toString() ?? 'Revisión',
                subtitle:
                    [
                          UiCopy.enumLabel(row['status']?.toString() ?? ''),
                          row['description'],
                        ]
                        .where(
                          (value) =>
                              value != null &&
                              value.toString().trim().isNotEmpty,
                        )
                        .join(' · '),
                trailing: row['effective_from']?.toString() ?? '',
              );
            }).toList(),
          ),
  );
}

class _ProductRowsPanel extends StatelessWidget {
  const _ProductRowsPanel({
    required this.title,
    required this.rows,
    required this.empty,
    required this.icon,
    required this.titleField,
    required this.subtitleFields,
    this.link,
    this.fallbackTitleField,
  });

  final String title;
  final String? link;
  final List<Map<String, dynamic>> rows;
  final String empty;
  final IconData icon;
  final String titleField;
  final String? fallbackTitleField;
  final List<String> subtitleFields;

  @override
  Widget build(BuildContext context) => _ProductTitledPanel(
    title: title,
    icon: icon,
    link: link,
    child: rows.isEmpty
        ? Text(empty, style: const TextStyle(color: PomgtColors.muted))
        : Column(
            children: rows.take(5).map((row) {
              final title = row[titleField]?.toString().trim();
              final fallback = fallbackTitleField == null
                  ? null
                  : row[fallbackTitleField]?.toString();
              final subtitle = subtitleFields
                  .map((field) => row[field]?.toString())
                  .where((value) => value != null && value.trim().isNotEmpty)
                  .join(' · ');
              return _ProductMiniRow(
                icon: icon,
                title: title?.isNotEmpty == true
                    ? title!
                    : (fallback ?? 'Registro'),
                subtitle: subtitle,
              );
            }).toList(),
          ),
  );
}

class _ProductActivityPanel extends StatelessWidget {
  const _ProductActivityPanel({
    required this.productionOrders,
    required this.revisions,
    required this.nonconformities,
  });

  final List<Map<String, dynamic>> productionOrders;
  final List<Map<String, dynamic>> revisions;
  final List<Map<String, dynamic>> nonconformities;

  @override
  Widget build(BuildContext context) {
    final rows = <_ProductActivity>[
      ...productionOrders.map(
        (row) => _ProductActivity(
          row['op_number']?.toString() ?? 'OP',
          UiCopy.enumLabel(row['status']?.toString() ?? ''),
          _date(row['updated_at'] ?? row['created_at']),
          _statusColor(row['status']?.toString() ?? ''),
        ),
      ),
      ...revisions.map(
        (row) => _ProductActivity(
          row['revision_code']?.toString() ?? 'Revisión',
          UiCopy.enumLabel(row['status']?.toString() ?? ''),
          _date(row['updated_at'] ?? row['created_at']),
          PomgtColors.blue,
        ),
      ),
      ...nonconformities.map(
        (row) => _ProductActivity(
          row['nc_number']?.toString() ?? 'No conformidad',
          row['title']?.toString() ??
              UiCopy.enumLabel(row['status']?.toString() ?? ''),
          _date(row['updated_at'] ?? row['detected_at']),
          PomgtColors.danger,
        ),
      ),
    ];
    rows.sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );
    return _ProductTitledPanel(
      title: 'Actividad reciente',
      icon: Icons.timeline_outlined,
      link: rows.isEmpty ? null : 'Ver toda',
      child: rows.isEmpty
          ? const Text(
              'Sin actividad reciente.',
              style: TextStyle(color: PomgtColors.muted),
            )
          : Column(
              children: rows.take(5).map((row) {
                return _ProductMiniRow(
                  icon: CupertinoIcons.circle_fill,
                  iconColor: row.color,
                  title: row.title,
                  subtitle: row.subtitle,
                  trailing: _shortProductDate(row.date),
                );
              }).toList(),
            ),
    );
  }
}

class _ProductActivity {
  const _ProductActivity(this.title, this.subtitle, this.date, this.color);
  final String title;
  final String subtitle;
  final DateTime? date;
  final Color color;
}

class _ProductTitledPanel extends StatelessWidget {
  const _ProductTitledPanel({
    required this.title,
    required this.child,
    this.link,
    this.icon,
  });
  final String title;
  final Widget child;
  final String? link;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => _ProductPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: PomgtColors.blue),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const InfoTip('Información de la sección.', size: 15),
                ],
              ),
            ),
            if (link != null)
              Text(
                link!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _ProductPanel extends StatelessWidget {
  const _ProductPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
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

class _ProductMiniRow extends StatelessWidget {
  const _ProductMiniRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.iconColor = PomgtColors.muted,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PomgtColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null && trailing!.trim().isNotEmpty) ...[
          const SizedBox(width: 12),
          Text(
            trailing!,
            style: const TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    ),
  );
}

class _ProductKV extends StatelessWidget {
  const _ProductKV({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: PomgtColors.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: PomgtColors.ink,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _PlainStatus extends StatelessWidget {
  const _PlainStatus({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? PomgtColors.mint : PomgtColors.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          active ? 'Activo' : 'Inactivo',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ProductStatusText extends StatelessWidget {
  const _ProductStatusText({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            UiCopy.enumLabel(status),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PomgtColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductProgress extends StatelessWidget {
  const _ProductProgress({required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LinearProgressIndicator(
          value: value,
          minHeight: 8,
          backgroundColor: PomgtColors.surfaceAlt,
          valueColor: const AlwaysStoppedAnimation(PomgtColors.blue),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 34,
        child: Text(
          label,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _ProductEmptyDetail extends StatelessWidget {
  const _ProductEmptyDetail();

  @override
  Widget build(BuildContext context) => const _ProductPanel(
    child: Center(
      child: Text(
        'Selecciona un producto para ver su expediente.',
        style: TextStyle(color: PomgtColors.muted),
      ),
    ),
  );
}

int _sum(List<Map<String, dynamic>> rows, String field) {
  return rows.fold<int>(
    0,
    (sum, row) => sum + ((row[field] as num?)?.round() ?? 0),
  );
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String _shortProductDate(DateTime? date) {
  if (date == null) return '—';
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _tracking(Map<String, dynamic> product) {
  if (product['track_lots'] == true) return 'Por lote';
  if (product['track_serials'] == true) return 'Por serie';
  return 'No requerida';
}

Color _statusColor(String status) {
  final value = status.toLowerCase();
  if (value.contains('completed') ||
      value.contains('done') ||
      value.contains('active')) {
    return PomgtColors.mint;
  }
  if (value.contains('hold') ||
      value.contains('blocked') ||
      value.contains('cancel')) {
    return PomgtColors.danger;
  }
  if (value.contains('draft') ||
      value.contains('pending') ||
      value.contains('planned')) {
    return PomgtColors.amber;
  }
  return PomgtColors.blue;
}

class _ProductDetail extends StatelessWidget {
  const _ProductDetail({required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = product['id'].toString();

    Future<void> edit() async {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EntityFormDialog(
          spec: Phase1Schema.tables['products']!,
          repository: generic,
          lookups: lookups,
          original: product,
          hiddenFields: const {
            'material_type_id',
            'material_category_id',
            'product_type',
          },
          referenceFilters: const {
            'product_type_catalog_id': {'system_class': 'finished_good'},
          },
          title: 'Editar producto',
          icon: Icons.inventory_2_outlined,
        ),
      );
      if (changed == true && context.mounted)
        context.read<ProductsController>().refresh();
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          DetailHeader(
            icon: Icons.inventory_2_outlined,
            title: product['name']?.toString() ?? 'Producto',
            subtitle:
                '${product['sku']} · ${UiCopy.enumLabel(product['product_type']?.toString() ?? '')}',
            help:
                'La definición estable vive en el producto; las especificaciones técnicas evolucionan mediante revisiones.',
            onEdit: edit,
          ),
          Expanded(
            child: DetailSections(
              sections: [
                DetailSection(
                  label: 'General',
                  help: 'Datos maestros, categoría y unidad.',
                  icon: Icons.dashboard_outlined,
                  child: _ProductSummary(product: product),
                ),
                DetailSection(
                  label: 'Revisiones',
                  help: 'Versiones técnicas del producto.',
                  icon: Icons.history_edu_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'product_revisions',
                      repository: generic,
                      lookups: lookups,
                      fixedValues: {'product_id': id},
                      title: 'Revisiones',
                      description:
                          'Versiona dimensiones, material, color, peso, tolerancias, calidad, empaque e imagen. Una revisión activa representa la especificación vigente.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Especificaciones',
                  help: 'Tolerancias y valores por revisión.',
                  icon: Icons.tune_outlined,
                  child: NestedRelationPanel(
                    title: 'Especificaciones por revisión',
                    help:
                        'Selecciona una revisión para administrar tolerancias y valores personalizados sin alterar revisiones anteriores.',
                    parentTable: 'product_revisions',
                    parentFilter: {'product_id': id},
                    repository: generic,
                    lookups: lookups,
                    childTabs: const [
                      ChildTabDefinition(
                        table: 'product_tolerances',
                        label: 'Tolerancias',
                        foreignKey: 'product_revision_id',
                        help:
                            'Valores nominales, límites, unidad y método de medición.',
                      ),
                      ChildTabDefinition(
                        table: 'product_revision_custom_values',
                        label: 'Valores personalizados',
                        foreignKey: 'product_revision_id',
                        help: 'Valores de propiedades creadas por la empresa.',
                      ),
                    ],
                  ),
                ),
                DetailSection(
                  label: 'Campos personalizados',
                  help: 'Propiedades configurables por industria.',
                  icon: Icons.dynamic_form_outlined,
                  child: _DynamicFieldsPanel(
                    product: product,
                    repository: generic,
                    lookups: lookups,
                  ),
                ),
                DetailSection(
                  label: 'Clientes',
                  help: 'Clientes, SKUs y revisiones comerciales.',
                  icon: Icons.groups_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'customer_products',
                      repository: generic,
                      lookups: lookups,
                      fixedValues: {'product_id': id},
                      title: 'Clientes que compran este producto',
                      description:
                          'Relaciona el producto con el SKU, nombre, revisión y dirección de envío utilizados por cada cliente.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Estructura de fabricación',
                  help: 'Recetas para fabricar el producto.',
                  icon: Icons.account_tree_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'boms',
                      repository: generic,
                      lookups: lookups,
                      fixedValues: {'product_id': id},
                      title: 'Estructuras de fabricación del producto',
                      description:
                          'Recetas de materiales disponibles para fabricar el producto.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Ruta de fabricación',
                  help: 'Secuencias de operación disponibles.',
                  icon: Icons.route_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'routings',
                      repository: generic,
                      lookups: lookups,
                      fixedValues: {'product_id': id},
                      title: 'Rutas de fabricación',
                      description:
                          'Secuencias de operaciones disponibles para fabricar el producto.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Documentos',
                  help: 'Planos, fichas, diseños y certificados.',
                  icon: Icons.folder_copy_outlined,
                  child: LinkedDocumentsPanel(
                    entityField: 'product_id',
                    entityId: id,
                    title: 'Documentos del producto',
                    help:
                        'Planos, fichas técnicas, diseños, especificaciones, fotografías y otros archivos relacionados con el producto.',
                    documentTypes: const [
                      'Ficha técnica',
                      'Plano',
                      'Diseño / arte',
                      'Especificación',
                      'Fotografía',
                      'Certificado',
                      'Otro',
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSummary extends StatelessWidget {
  const _ProductSummary({required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        lookups.rows('units_of_measure'),
        lookups.rows('product_categories'),
        lookups.rows('product_types'),
        lookups.rows('customers'),
      ]),
      builder: (context, snapshot) {
        final data =
            snapshot.data ??
            const [
              <Map<String, dynamic>>[],
              <Map<String, dynamic>>[],
              <Map<String, dynamic>>[],
              <Map<String, dynamic>>[],
            ];
        String resolve(int index, dynamic id, String table) {
          if (id == null) return '—';
          final matches = data[index]
              .where((r) => r['id']?.toString() == id.toString())
              .toList();
          return matches.isEmpty
              ? '—'
              : lookups.display(Phase1Schema.tables[table]!, matches.first);
        }

        final entries = <MapEntry<String, String>>[
          MapEntry('SKU', product['sku']?.toString() ?? '—'),
          MapEntry(
            'Tipo de producto',
            resolve(2, product['product_type_catalog_id'], 'product_types'),
          ),
          MapEntry(
            'Clasificación',
            UiCopy.enumLabel(product['product_type']?.toString() ?? ''),
          ),
          MapEntry(
            'Categoría',
            resolve(1, product['category_id'], 'product_categories'),
          ),
          MapEntry(
            'Unidad base',
            resolve(0, product['base_uom_id'], 'units_of_measure'),
          ),
          MapEntry(
            'Cliente propietario',
            resolve(3, product['owner_customer_id'], 'customers'),
          ),
          MapEntry(
            'Se fabrica',
            product['is_manufacturable'] == true ? 'Sí' : 'No',
          ),
          MapEntry(
            'Se compra',
            product['is_purchasable'] == true ? 'Sí' : 'No',
          ),
          MapEntry('Se vende', product['is_sellable'] == true ? 'Sí' : 'No'),
          MapEntry(
            'Tiempo de entrega',
            '${product['default_lead_time_days'] ?? 0} días',
          ),
          MapEntry(
            'Trazabilidad',
            product['track_lots'] == true
                ? 'Por lote'
                : (product['track_serials'] == true
                      ? 'Por serie'
                      : 'No requerida'),
          ),
          MapEntry(
            'Estado',
            product['is_active'] == true ? 'Activo' : 'Inactivo',
          ),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                product['description']?.toString() ?? 'Sin descripción.',
                style: const TextStyle(
                  color: PomgtColors.secondaryInk,
                  fontSize: 14.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 900 ? 4 : 2;
                  final w = (c.maxWidth - (cols - 1) * 26) / cols;
                  return Wrap(
                    spacing: 26,
                    runSpacing: 22,
                    children: entries
                        .map(
                          (e) => SizedBox(
                            width: w,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.key,
                                  style: const TextStyle(
                                    color: PomgtColors.muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  e.value,
                                  style: const TextStyle(
                                    color: PomgtColors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DynamicFieldsPanel extends StatelessWidget {
  const _DynamicFieldsPanel({
    required this.product,
    required this.repository,
    required this.lookups,
  });
  final Map<String, dynamic> product;
  final GenericRepository repository;
  final LookupRepository lookups;

  @override
  Widget build(BuildContext context) {
    final category = product['category_id'];
    final filter = category == null
        ? const <String, dynamic>{}
        : {'category_id': category};
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: PomgtColors.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              tabs: [
                HelpTab(
                  label: 'Definiciones',
                  help:
                      'Campos personalizados disponibles para la categoría o producto.',
                ),
                HelpTab(
                  label: 'Opciones',
                  help:
                      'Opciones permitidas para campos de selección o selección múltiple.',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: EntityCrudPanel(
                    table: 'product_custom_field_definitions',
                    repository: repository,
                    lookups: lookups,
                    fixedValues: filter,
                    title: 'Campos personalizados',
                    description:
                        'Crea propiedades específicas por industria sin modificar código, por ejemplo adhesivo, core, número de tintas, aleación, tratamiento o acabado.',
                  ),
                ),
                NestedRelationPanel(
                  title: 'Opciones de campos',
                  help:
                      'Para campos de selección define aquí sus opciones permitidas.',
                  parentTable: 'product_custom_field_definitions',
                  parentFilter: filter,
                  repository: repository,
                  lookups: lookups,
                  childTabs: const [
                    ChildTabDefinition(
                      table: 'product_custom_field_options',
                      label: 'Opciones',
                      foreignKey: 'field_definition_id',
                      help:
                          'Valor interno, etiqueta visible y orden de cada opción.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
