import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../controllers/feature_controllers.dart';
import '../../controllers/organization_controller.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/pdf_download.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/number_input.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/scroll_to_top.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../core/widgets/selected_product_row.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/bom_repository.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/production_repository.dart';
import '../../data/repositories/roles_repository.dart';
import '../../data/repositories/routing_repository.dart';
import '../bom/link_bom_dialog.dart';
import '../routings/link_routing_dialog.dart';
import '../../data/services/production_order_pdf_service.dart';
import 'production_operator_display.dart' show ProductionOperatorDisplay;
import '../../core/widgets/section_title.dart';
import '../../core/widgets/pomgt_date_picker.dart';

void _showProductionNotice(
  BuildContext context, {
  required String title,
  required String description,
  bool isError = false,
}) {
  // Delegates to the shared flat-style toast used across the app instead of
  // keeping a bespoke dark overlay implementation here.
  showPomgtNotice(
    context,
    title: title,
    description: description,
    isError: isError,
  );
}

void _showProductionSuccess(BuildContext context, String message) {
  _showProductionNotice(
    context,
    title: message,
    description: 'La información se actualizó correctamente.',
  );
}

void _showProductionError(BuildContext context, Object error) {
  _showProductionNotice(
    context,
    title: 'No fue posible completar la operación.',
    description: ErrorCopy.message(error),
    isError: true,
  );
}

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  late final ProductionRepository _repository;
  late final ProductionOrderPdfService _pdfService;
  late Future<List<Map<String, dynamic>>> _future;
  String _search = '';
  String _status = 'all';
  String? _customerFilter;
  String? _productFilter;
  String? _selectedId;
  bool _kanban = false;

  ProductionRepository get repository => _repository;

  @override
  void initState() {
    super.initState();
    final generic = context.read<GenericRepository>();
    _repository = ProductionRepository(generic.service, generic.client);
    final organizationId = context
        .read<OrganizationController>()
        .organizationId;
    if (organizationId != null) {
      _repository.setOrganization(organizationId);
    }
    _pdfService = ProductionOrderPdfService(
      _repository,
      context.read<DocumentRepository>(),
    );
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => repository.orders();

  void _reload({String? select}) {
    if (select != null) _selectedId = select;
    setState(() {
      _future = _load();
    });
    context.read<RuntimeDataController>().tableChanged('production_orders');
    context.read<ProductionController>().refresh();
  }

  Future<void> _create() async {
    final result = await showPomgtDialog<_CreateProductionRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateProductionOrderDialog(),
    );
    if (result == null || !mounted) return;
    try {
      var row = await repository.createManual(
        productId: result.productId,
        quantity: result.quantity,
        uomId: result.uomId,
        requiredAt: result.requiredAt,
        priority: result.priority,
        plannedStartAt: result.plannedStartAt,
        plannedEndAt: result.plannedEndAt,
        notes: result.notes,
        sourceType: result.sourceType,
        bomRevisionId: result.bomRevisionId,
        routingRevisionId: result.routingRevisionId,
      );
      if (result.prepareAutomatically) {
        row = await repository.prepare(row['id'].toString());
      }
      if (!mounted) return;
      _reload(select: row['id']?.toString());
      _showProductionSuccess(
        context,
        result.prepareAutomatically
            ? 'Orden creada y preparada.'
            : 'Orden creada en borrador.',
      );
    } catch (e) {
      if (!mounted) return;
      _showProductionError(context, e);
    }
  }

  Future<void> _createMultiple() async {
    final result = await showPomgtDialog<_CreateMultiProductionRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateMultiProductionOrderDialog(),
    );
    if (result == null || !mounted) return;
    final outcomes = <_MultiCreateOutcome>[];
    String? lastCreatedId;
    for (final item in result.items) {
      try {
        var row = await repository.createManual(
          productId: item.productId,
          quantity: item.quantity,
          uomId: item.uomId,
          requiredAt: result.requiredAt,
          priority: result.priority,
          plannedStartAt: result.plannedStartAt,
          plannedEndAt: result.plannedEndAt,
          notes: result.notes,
          sourceType: result.sourceType,
        );
        lastCreatedId = row['id']?.toString();
        if (result.prepareAutomatically) {
          try {
            row = await repository.prepare(row['id'].toString());
            outcomes.add(
              _MultiCreateOutcome(
                item.label,
                _MultiCreateStatus.prepared,
                opNumber: row['op_number']?.toString(),
              ),
            );
          } catch (e) {
            outcomes.add(
              _MultiCreateOutcome(
                item.label,
                _MultiCreateStatus.createdNotPrepared,
                opNumber: row['op_number']?.toString(),
                error: ErrorCopy.message(e),
              ),
            );
          }
        } else {
          outcomes.add(
            _MultiCreateOutcome(
              item.label,
              _MultiCreateStatus.createdDraft,
              opNumber: row['op_number']?.toString(),
            ),
          );
        }
      } catch (e) {
        outcomes.add(
          _MultiCreateOutcome(
            item.label,
            _MultiCreateStatus.failed,
            error: ErrorCopy.message(e),
          ),
        );
      }
    }
    if (!mounted) return;
    _reload(select: lastCreatedId);
    await showPomgtDialog<void>(
      context: context,
      builder: (_) => _MultiCreateResultsDialog(outcomes: outcomes),
    );
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EntityFormDialog(
        spec: Phase1Schema.tables['production_orders']!,
        repository: context.read<GenericRepository>(),
        lookups: context.read<LookupRepository>(),
        original: row,
        hiddenFields: const {
          'actual_start_at',
          'actual_end_at',
          'created_by',
          'updated_by',
        },
      ),
    );
    if (changed == true && mounted) {
      _reload(select: row['id']?.toString());
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showPomgtDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          'Eliminar orden de producción',
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'Se eliminará la orden con sus operaciones, materiales, eventos y asignación al pedido. Esta acción no se puede deshacer.',
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
    if (confirmed != true || !mounted) return;
    try {
      await repository.deleteOrder(row['id'].toString());
      if (!mounted) return;
      _selectedId = null;
      _reload();
      _showProductionSuccess(context, 'Orden de producción eliminada.');
    } catch (error) {
      if (!mounted) return;
      _showProductionError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ProductionRepository>.value(value: _repository),
        Provider<ProductionOrderPdfService>.value(value: _pdfService),
      ],
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                ErrorCopy.message(
                  snapshot.error!,
                  fallback: 'No fue posible cargar las órdenes de producción.',
                ),
                style: const TextStyle(color: PomgtColors.danger),
              ),
            );
          }
          final all = snapshot.data ?? const <Map<String, dynamic>>[];
          final customerItems = <PickerItem>[];
          final seenCustomers = <String>{};
          for (final row in all) {
            final id = row['customer_id']?.toString();
            final name = row['customer_name']?.toString();
            if (id == null || name == null || name.isEmpty) continue;
            if (!seenCustomers.add(id)) continue;
            customerItems.add(
              PickerItem(id: id, label: name, category: 'Clientes'),
            );
          }
          customerItems.sort((a, b) => a.label.compareTo(b.label));
          final productItems = <PickerItem>[];
          final seenProducts = <String>{};
          for (final row in all) {
            final id = row['product_id']?.toString();
            if (id == null || !seenProducts.add(id)) continue;
            final sku = row['product_sku']?.toString();
            final name = row['product_name']?.toString();
            productItems.add(
              PickerItem(
                id: id,
                label: '${sku ?? '—'} · ${name ?? 'Producto'}',
                category: 'Productos',
              ),
            );
          }
          productItems.sort((a, b) => a.label.compareTo(b.label));
          final scoped = all.where((row) {
            if (_customerFilter != null &&
                row['customer_id']?.toString() != _customerFilter) {
              return false;
            }
            if (_productFilter != null &&
                row['product_id']?.toString() != _productFilter) {
              return false;
            }
            return true;
          }).toList();
          final query = _search.trim().toLowerCase();
          final rows = scoped.where((row) {
            if (_status != 'all' && row['status']?.toString() != _status) {
              return false;
            }
            if (query.isEmpty) return true;
            final haystack = [
              row['op_number'],
              row['product_sku'],
              row['product_name'],
              row['customer_name'],
              row['order_number'],
              row['customer_po_number'],
              UiCopy.enumLabel(row['status']?.toString() ?? ''),
            ].whereType<Object>().join(' ').toLowerCase();
            return haystack.contains(query);
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

          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProductionTitle(
                  onCreate: _create,
                  onCreateMultiple: _createMultiple,
                  kanban: _kanban,
                  onViewChanged: (value) => setState(() => _kanban = value),
                ),
                const SizedBox(height: 14),
                _ProductionFilters(
                  customerItems: customerItems,
                  productItems: productItems,
                  customerId: _customerFilter,
                  productId: _productFilter,
                  onCustomerChanged: (value) =>
                      setState(() => _customerFilter = value),
                  onProductChanged: (value) =>
                      setState(() => _productFilter = value),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _kanban
                      ? ProductionKanbanBoard(
                          orders: scoped,
                          search: _search,
                          onSearch: (value) => setState(() => _search = value),
                          onOpen: (id) => setState(() {
                            _kanban = false;
                            _selectedId = id;
                          }),
                          onTransition: (id, status) async {
                            await repository.transitionOrder(id, status);
                            if (mounted) _reload();
                          },
                          onError: (e) => _showProductionError(context, e),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final compact = constraints.maxWidth < 1050;
                            if (compact) {
                              return Column(
                                children: [
                                  SizedBox(
                                    height: 300,
                                    child: _ProductionMasterList(
                                      rows: rows,
                                      loading:
                                          snapshot.connectionState ==
                                          ConnectionState.waiting,
                                      selectedId: _selectedId,
                                      search: _search,
                                      status: _status,
                                      onSearch: (value) =>
                                          setState(() => _search = value),
                                      onStatus: (value) =>
                                          setState(() => _status = value),
                                      onSelect: (id) =>
                                          setState(() => _selectedId = id),
                                      onEdit: _edit,
                                      onDelete: _delete,
                                      onRefresh: _reload,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Expanded(
                                    child: selected == null
                                        ? const _ProductionEmptyDetail()
                                        : _ProductionDetail(
                                            key: ValueKey(selected['id']),
                                            orderId: selected['id'].toString(),
                                            onChanged: () => _reload(
                                              select: selected['id'].toString(),
                                            ),
                                            onEdit: (order) => _edit(order),
                                            onDelete: (order) => _delete(order),
                                          ),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                SizedBox(
                                  width: constraints.maxWidth >= 1450
                                      ? 360
                                      : 320,
                                  child: _ProductionMasterList(
                                    rows: rows,
                                    loading:
                                        snapshot.connectionState ==
                                        ConnectionState.waiting,
                                    selectedId: _selectedId,
                                    search: _search,
                                    status: _status,
                                    onSearch: (value) =>
                                        setState(() => _search = value),
                                    onStatus: (value) =>
                                        setState(() => _status = value),
                                    onSelect: (id) =>
                                        setState(() => _selectedId = id),
                                    onEdit: _edit,
                                    onDelete: _delete,
                                    onRefresh: _reload,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: selected == null
                                      ? const _ProductionEmptyDetail()
                                      : _ProductionDetail(
                                          key: ValueKey(selected['id']),
                                          orderId: selected['id'].toString(),
                                          onChanged: () => _reload(
                                            select: selected['id'].toString(),
                                          ),
                                          onEdit: (order) => _edit(order),
                                          onDelete: (order) => _delete(order),
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
    );
  }
}

class _ProductionTitle extends StatelessWidget {
  const _ProductionTitle({
    required this.onCreate,
    required this.onCreateMultiple,
    required this.kanban,
    required this.onViewChanged,
  });
  final VoidCallback onCreate;
  final VoidCallback onCreateMultiple;
  final bool kanban;
  final ValueChanged<bool> onViewChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              SectionTitle('Producción', icon: LucideIcons.settings),
              SizedBox(width: 8),
              InfoTip(
                'Centro operativo de las órdenes de producción. Conecta pedido, producto, estructura de fabricación, ruta, ejecución, calidad, costos, documentos y trazabilidad.',
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'Planifica, prepara, ejecuta y cierra cada orden con trazabilidad completa.',
            style: TextStyle(
              color: PomgtColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ViewToggle(kanban: kanban, onChanged: onViewChanged),
          OutlinedButton.icon(
            onPressed: onCreateMultiple,
            icon: const Icon(LucideIcons.layers, size: 18),
            label: const Text('Nueva OP múltiple'),
          ),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Nueva Orden de Producción'),
          ),
        ],
      );
      if (constraints.maxWidth < 760) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 14), actions],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 14),
          actions,
        ],
      );
    },
  );
}

class _ProductionFilters extends StatelessWidget {
  const _ProductionFilters({
    required this.customerItems,
    required this.productItems,
    required this.customerId,
    required this.productId,
    required this.onCustomerChanged,
    required this.onProductChanged,
  });

  final List<PickerItem> customerItems;
  final List<PickerItem> productItems;
  final String? customerId;
  final String? productId;
  final ValueChanged<String?> onCustomerChanged;
  final ValueChanged<String?> onProductChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 620;
      final customer = CategorizedSearchPicker(
        label: 'Cliente',
        hint: 'Buscar cliente…',
        value: customerId,
        items: customerItems,
        emptyMessage: 'Sin clientes en estas órdenes',
        onChanged: onCustomerChanged,
      );
      final product = CategorizedSearchPicker(
        label: 'Producto',
        hint: 'Buscar producto…',
        value: productId,
        items: productItems,
        emptyMessage: 'Sin productos en estas órdenes',
        onChanged: onProductChanged,
      );
      final hasFilters = customerId != null || productId != null;
      final clear = TextButton.icon(
        onPressed: hasFilters
            ? () {
                onCustomerChanged(null);
                onProductChanged(null);
              }
            : null,
        icon: const Icon(LucideIcons.x, size: 16),
        label: const Text('Limpiar filtros'),
      );
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            customer,
            const SizedBox(height: 10),
            product,
            if (hasFilters) ...[
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: clear),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: customer),
          const SizedBox(width: 12),
          Expanded(child: product),
          const SizedBox(width: 8),
          clear,
        ],
      );
    },
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.kanban, required this.onChanged});
  final bool kanban;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: PomgtColors.surfaceAlt,
      borderRadius: PomgtRadii.borderPill,
      border: Border.all(color: PomgtColors.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewToggleButton(
          label: 'Lista',
          icon: LucideIcons.list,
          selected: !kanban,
          onTap: () => onChanged(false),
        ),
        _ViewToggleButton(
          label: 'Kanban',
          icon: LucideIcons.layoutGrid,
          selected: kanban,
          onTap: () => onChanged(true),
        ),
      ],
    ),
  );
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: PomgtRadii.borderPill,
    onTap: onTap,
    child: AnimatedContainer(
      duration: PomgtMotion.duration(context, PomgtMotion.fast),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? PomgtColors.canvas : Colors.transparent,
        borderRadius: PomgtRadii.borderPill,
        boxShadow: selected ? PomgtShadows.card : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: selected ? PomgtColors.blue : PomgtColors.muted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? PomgtColors.ink : PomgtColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

const _kanbanStatuses = [
  'draft',
  'planned',
  'ready',
  'in_progress',
  'on_hold',
  'completed',
  'cancelled',
];

Color _kanbanColumnColor(String status) => switch (status) {
  'draft' => PomgtColors.slate,
  'planned' => PomgtColors.violet,
  'ready' => PomgtColors.cyan,
  'in_progress' => PomgtColors.blue,
  'on_hold' => PomgtColors.amber,
  'completed' => PomgtColors.mint,
  'cancelled' => PomgtColors.rose,
  _ => PomgtColors.muted,
};

class _KanbanDragData {
  const _KanbanDragData(this.id, this.status);
  final String id;
  final String status;
}

/// Jira-style board for production orders: one column per OP status, cards
/// dragged between columns transition the order via [onTransition].
class ProductionKanbanBoard extends StatefulWidget {
  const ProductionKanbanBoard({
    super.key,
    required this.orders,
    required this.search,
    required this.onSearch,
    required this.onOpen,
    required this.onTransition,
    required this.onError,
  });

  final List<Map<String, dynamic>> orders;
  final String search;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onOpen;
  final Future<void> Function(String orderId, String newStatus) onTransition;
  final void Function(Object error) onError;

  @override
  State<ProductionKanbanBoard> createState() => _ProductionKanbanBoardState();
}

class _ProductionKanbanBoardState extends State<ProductionKanbanBoard> {
  final Map<String, String> _pending = {};
  Map<String, List<String>> _operatorNames = const {};
  String? _dragOverStatus;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.search);
    _loadOperators();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOperators() async {
    try {
      final generic = context.read<GenericRepository>();
      final assignments = await generic.listRows(
        Phase1Schema.tables['production_order_operators']!,
      );
      if (assignments.isEmpty || !mounted) return;
      final members = await context.read<LookupRepository>().rows(
        'organization_members',
      );
      final names = {
        for (final m in members)
          m['id'].toString(): m['full_name']?.toString() ?? 'Operador',
      };
      final grouped = <String, List<String>>{};
      for (final row in assignments) {
        final orderId = row['production_order_id']?.toString();
        final name = names[row['member_id']?.toString()];
        if (orderId == null || name == null) continue;
        grouped.putIfAbsent(orderId, () => []).add(name);
      }
      if (mounted) setState(() => _operatorNames = grouped);
    } catch (_) {
      // Operator chips are a nice-to-have; a failed fetch shouldn't break the board.
    }
  }

  Future<void> _handleDrop(
    String orderId,
    String currentStatus,
    String newStatus,
  ) async {
    setState(() {
      _pending[orderId] = newStatus;
      _dragOverStatus = null;
    });
    try {
      await widget.onTransition(orderId, newStatus);
    } catch (e) {
      widget.onError(e);
    } finally {
      if (mounted) setState(() => _pending.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.search.trim().toLowerCase();
    final filtered = widget.orders.where((row) {
      if (query.isEmpty) return true;
      final haystack = [
        row['op_number'],
        row['product_sku'],
        row['product_name'],
        row['customer_trade_name'],
        row['customer_name'],
        row['order_number'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    final byStatus = <String, List<Map<String, dynamic>>>{
      for (final s in _kanbanStatuses) s: [],
    };
    for (final row in filtered) {
      final id = row['id']?.toString();
      final effective = id != null && _pending.containsKey(id)
          ? _pending[id]!
          : (row['status']?.toString() ?? 'draft');
      (byStatus[effective] ??= []).add(row);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: TextField(
            controller: _searchController,
            onChanged: widget.onSearch,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Buscar OP, producto, cliente u OC...',
              prefixIcon: Icon(LucideIcons.search, size: 18),
              prefixIconConstraints: BoxConstraints(minWidth: 42),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final status in _kanbanStatuses) ...[
                  _KanbanColumn(
                    status: status,
                    rows: byStatus[status] ?? const [],
                    dragOver: _dragOverStatus == status,
                    operatorNames: _operatorNames,
                    onWillAccept: (data) => data.status != status,
                    onDragEnter: () => setState(() => _dragOverStatus = status),
                    onDragLeave: () => setState(() {
                      if (_dragOverStatus == status) _dragOverStatus = null;
                    }),
                    onAccept: (data) =>
                        _handleDrop(data.id, data.status, status),
                    onOpen: widget.onOpen,
                  ),
                  const SizedBox(width: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.rows,
    required this.dragOver,
    required this.operatorNames,
    required this.onWillAccept,
    required this.onDragEnter,
    required this.onDragLeave,
    required this.onAccept,
    required this.onOpen,
  });

  final String status;
  final List<Map<String, dynamic>> rows;
  final bool dragOver;
  final Map<String, List<String>> operatorNames;
  final bool Function(_KanbanDragData) onWillAccept;
  final VoidCallback onDragEnter;
  final VoidCallback onDragLeave;
  final ValueChanged<_KanbanDragData> onAccept;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _kanbanColumnColor(status);
    return DragTarget<_KanbanDragData>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onMove: (_) => onDragEnter(),
      onLeave: (_) => onDragLeave(),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        return Container(
          width: 300,
          decoration: BoxDecoration(
            color: dragOver
                ? color.withValues(alpha: .07)
                : PomgtColors.surface,
            borderRadius: PomgtRadii.borderMd,
            border: Border.all(
              color: dragOver ? color.withValues(alpha: .55) : PomgtColors.line,
              width: dragOver ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        UiCopy.enumLabel(status).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: PomgtRadii.borderPill,
                      ),
                      child: Text(
                        '${rows.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'Sin órdenes',
                          style: TextStyle(
                            color: PomgtColors.muted.withValues(alpha: .8),
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ScrollToTopArea(
                        padding: const EdgeInsets.all(10),
                        builder: (context, controller) => PomgtListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final id = row['id'].toString();
                            final card = _KanbanCard(
                              row: row,
                              color: color,
                              operators: operatorNames[id] ?? const [],
                              onTap: () => onOpen(id),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Draggable<_KanbanDragData>(
                                data: _KanbanDragData(id, status),
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(width: 276, child: card),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: .35,
                                  child: card,
                                ),
                                child: card,
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

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.row,
    required this.color,
    required this.operators,
    required this.onTap,
  });
  final Map<String, dynamic> row;
  final Color color;
  final List<String> operators;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priority = row['priority']?.toString() ?? 'normal';
    final progress = _n(row['progress_pct']) / 100;
    final customer = row['customer_trade_name'] ?? row['customer_name'];
    return InkWell(
      borderRadius: PomgtRadii.borderMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PomgtColors.canvas,
          borderRadius: PomgtRadii.borderMd,
          border: Border.all(
            color: PomgtColors.lineStrong.withValues(alpha: .55),
          ),
          boxShadow: PomgtShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row['op_number']?.toString() ?? 'OP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: PomgtColors.ink,
                    ),
                  ),
                ),
                _PriorityFlag(priority: priority),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${row['product_sku'] ?? '—'} · ${row['product_name'] ?? 'Producto'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: PomgtColors.secondaryInk,
                height: 1.3,
              ),
            ),
            if (row['batch_number'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    LucideIcons.layers,
                    size: 11,
                    color: PomgtColors.blue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Lote ${row['batch_number']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: PomgtColors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (customer != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    LucideIcons.building2,
                    size: 11,
                    color: PomgtColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      customer.toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: PomgtColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: PomgtProgressIndicator(
                value: progress.clamp(0, 1).toDouble(),
                minHeight: 4,
                backgroundColor: PomgtColors.line,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const Icon(
                  LucideIcons.calendar,
                  size: 12,
                  color: PomgtColors.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row['required_at'] == null
                        ? 'Sin fecha requerida'
                        : _date(row['required_at']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: PomgtColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${_fmt(row['planned_quantity'])} ${row['uom_symbol'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: PomgtColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (operators.isNotEmpty) ...[
              const SizedBox(height: 9),
              _OperatorAvatars(names: operators),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriorityFlag extends StatelessWidget {
  const _PriorityFlag({required this.priority});
  final String priority;

  Color get _color => switch (priority) {
    'urgent' => PomgtColors.rose,
    'high' => PomgtColors.amber,
    'low' => PomgtColors.muted,
    _ => PomgtColors.blue,
  };

  @override
  Widget build(BuildContext context) {
    if (priority.isEmpty || priority == 'normal') {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: UiCopy.enumLabel(priority),
      child: Icon(LucideIcons.flag, size: 13, color: _color),
    );
  }
}

class _OperatorAvatars extends StatelessWidget {
  const _OperatorAvatars({required this.names});
  final List<String> names;

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final shown = names.take(3).toList();
    final extra = names.length - shown.length;
    return Row(
      children: [
        for (final name in shown) ...[
          Tooltip(
            message: name,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: PomgtColors.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initials(name),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: PomgtColors.blue,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (extra > 0)
          Text(
            '+$extra',
            style: const TextStyle(
              fontSize: 10.5,
              color: PomgtColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ProductionMasterList extends StatelessWidget {
  const _ProductionMasterList({
    required this.rows,
    required this.loading,
    required this.selectedId,
    required this.search,
    required this.status,
    required this.onSearch,
    required this.onStatus,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> rows;
  final bool loading;
  final String? selectedId;
  final String search;
  final String status;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.surface,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(
          color: PomgtColors.lineStrong.withValues(alpha: .55),
        ),
        boxShadow: PomgtShadows.card,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: SizedBox(
              height: 56,
              child: TextField(
                onChanged: onSearch,
                decoration: InputDecoration(
                  hintText: 'Buscar OP, producto, cliente u OC...',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 46),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Actualizar',
                    onPressed: onRefresh,
                    icon: const Icon(LucideIcons.refreshCw, size: 17),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: DropdownButtonFormField<String>(
              errorBuilder: pomgtValidationMessage,
              initialValue: status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Estado'),
              items: const [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('Todas las órdenes'),
                ),
                DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                DropdownMenuItem(value: 'planned', child: Text('Planificadas')),
                DropdownMenuItem(value: 'ready', child: Text('Listas')),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('En proceso'),
                ),
                DropdownMenuItem(value: 'on_hold', child: Text('En pausa')),
                DropdownMenuItem(
                  value: 'completed',
                  child: Text('Completadas'),
                ),
                DropdownMenuItem(value: 'cancelled', child: Text('Canceladas')),
              ],
              onChanged: (value) => onStatus(value ?? 'all'),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              '${rows.length} ${rows.length == 1 ? 'orden' : 'órdenes'}',
              style: const TextStyle(
                color: PomgtColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: loading && rows.isEmpty
                ? const PomgtLoading()
                : rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay órdenes de producción con estos filtros.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PomgtColors.muted),
                      ),
                    ),
                  )
                : ScrollToTopArea(
                    padding: const EdgeInsets.all(10),
                    builder: (context, controller) => PomgtListView.builder(
                      controller: controller,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = row['id'].toString();
                        final selected = id == selectedId;
                        final progress = _n(row['progress_pct']);
                        return InkWell(
                          borderRadius: PomgtRadii.borderSm,
                          onTap: () => onSelect(id),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 30,
                                      height: 30,
                                      child: Icon(
                                        LucideIcons.settings,
                                        size: 17,
                                        color: PomgtColors.ink,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        row['op_number']?.toString() ?? 'OP',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: PomgtColors.ink,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                              Icon(
                                                LucideIcons.pencil,
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
                                const SizedBox(height: 6),
                                Text(
                                  '${row['product_sku'] ?? '—'} · ${row['product_name'] ?? 'Producto'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PomgtColors.secondaryInk,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  row['customer_name']?.toString() ??
                                      _sourceLabel(row['source_type']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PomgtColors.muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Expanded(
                                      child: PomgtProgressIndicator(
                                        value: (progress / 100).clamp(0, 1),
                                        minHeight: 3,
                                        backgroundColor: PomgtColors.line,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                              PomgtColors.blue,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${progress.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: PomgtColors.muted,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }
}

class _ProductionEmptyDetail extends StatelessWidget {
  const _ProductionEmptyDetail();
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: PomgtColors.surface,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
    ),
    child: const EmptyState(
      icon: LucideIcons.factory,
      title: 'Selecciona una orden de producción',
      message: 'El expediente operativo completo aparecerá aquí.',
    ),
  );
}

class _ProductionDetail extends StatefulWidget {
  const _ProductionDetail({
    super.key,
    required this.orderId,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });
  final String orderId;
  final VoidCallback onChanged;
  final void Function(Map<String, dynamic> order) onEdit;
  final void Function(Map<String, dynamic> order) onDelete;

  @override
  State<_ProductionDetail> createState() => _ProductionDetailState();
}

class _ProductionDetailState extends State<_ProductionDetail> {
  late Future<Map<String, dynamic>> _future;
  int _tab = 0;
  bool _busy = false;
  bool _startingProduction = false;
  late int _seenRevision;

  ProductionRepository get repository => context.read<ProductionRepository>();
  ProductionOrderPdfService get pdf =>
      context.read<ProductionOrderPdfService>();

  List<Map<String, dynamic>> _pendingOperations(Map<String, dynamic> data) {
    return _list(data['operations'])
        .map(_map)
        .where(
          (row) => ![
            'completed',
            'skipped',
          ].contains(row['status']?.toString() ?? 'pending'),
        )
        .toList();
  }

  void _showPendingOperationsNotice(Map<String, dynamic> data) {
    final pending = _pendingOperations(data);
    final first = pending
        .take(3)
        .map((row) {
          final code = row['operation_code']?.toString();
          final name = row['name']?.toString() ?? 'Operación';
          return code == null || code.trim().isEmpty ? name : '$code · $name';
        })
        .join(', ');
    final suffix = pending.length > 3 ? ' y ${pending.length - 3} más' : '';
    _showProductionNotice(
      context,
      title: 'Completa las operaciones pendientes.',
      description:
          'Faltan ${pending.length} operación(es): $first$suffix. Revisa la pestaña Operaciones.',
      isError: true,
    );
    setState(() {
      _tab = 1;
    });
  }

  @override
  void initState() {
    super.initState();
    _future = repository.detail(widget.orderId);
    _seenRevision = context.read<ProductionController>().revision;
  }

  // The panel used to be keyed by '$orderId-$revision', so every change -
  // including the ones this very panel triggers (complete/pause/start an
  // operation) - destroyed and recreated it, resetting `_tab` back to
  // Resumen. It's now keyed by orderId alone and stays mounted; this watches
  // the controller only to pick up changes made elsewhere (e.g. editing the
  // order via its dialog), refreshing `_future` in place without touching
  // `_tab`. `_reload()` already updates `_seenRevision` itself so this
  // doesn't re-fetch a second time for changes this panel caused.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<ProductionController>().revision;
    if (revision == _seenRevision) return;
    _seenRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _future = repository.detail(widget.orderId);
        });
      }
    });
  }

  void _reload() {
    if (!mounted) return;
    widget.onChanged();
    _seenRevision = context.read<ProductionController>().revision;
    setState(() {
      _future = repository.detail(widget.orderId);
    });
  }

  Future<void> _action(Future<dynamic> Function() work, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (!mounted) return;
      _showProductionError(context, e);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    _showProductionSuccess(context, success);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  /// Checks the order's product for an active BOM and an active routing
  /// before "Preparar OP"/"Display operador" proceed, opening the matching
  /// link dialog directly instead of letting the action fail with a raw
  /// Postgres error. Loops so one press can fix both gaps in sequence.
  Future<bool> _ensureBomAndRoutingReady(Map<String, dynamic> product) async {
    final productId = product['id']?.toString();
    if (productId == null) return true;
    final lookups = context.read<LookupRepository>();
    while (mounted) {
      final rows = await Future.wait([
        lookups.rows('boms'),
        lookups.rows('bom_revisions'),
        lookups.rows('routings'),
        lookups.rows('routing_revisions'),
      ]);
      final missingBom = productIdsMissingActiveBom(
        [productId],
        boms: rows[0],
        bomRevisions: rows[1],
      ).isNotEmpty;
      if (missingBom) {
        if (!mounted) return false;
        final created = await showPomgtDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              LinkBomDialog(product: product, activateRevision: true),
        );
        if (created != true) return false;
        lookups.invalidate('boms');
        lookups.invalidate('bom_revisions');
        continue;
      }
      final missingRouting = productIdsMissingActiveRouting(
        [productId],
        products: [product],
        routings: rows[2],
        routingRevisions: rows[3],
      ).isNotEmpty;
      if (missingRouting) {
        if (!mounted) return false;
        final created = await showPomgtDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LinkRoutingDialog(product: product),
        );
        if (created != true) return false;
        lookups.invalidate('routings');
        lookups.invalidate('routing_revisions');
        continue;
      }
      return true;
    }
    return false;
  }

  Future<void> _prepareOrder(Map<String, dynamic> product) async {
    final ready = await _ensureBomAndRoutingReady(product);
    if (!ready) {
      if (mounted) _reload();
      return;
    }
    await _action(
      () => repository.prepare(widget.orderId),
      'Orden preparada correctamente.',
    );
  }

  Future<void> _startProduction() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _startingProduction = true;
    });
    try {
      await repository.transitionOrder(widget.orderId, 'in_progress');
      if (!mounted) return;
      final data = await repository.detail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _future = Future.value(data);
      });
      widget.onChanged();
      _seenRevision = context.read<ProductionController>().revision;
      _showProductionSuccess(context, 'Producción iniciada.');
    } catch (e) {
      if (mounted) _showProductionError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _startingProduction = false;
        });
      }
    }
  }

  Future<void> _openOperatorDisplay(Map<String, dynamic> product) async {
    final ready = await _ensureBomAndRoutingReady(product);
    if (!ready) {
      if (mounted) _reload();
      return;
    }
    if (!mounted) return;
    final productionRepository = repository;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProductionOperatorDisplay(
          orderId: widget.orderId,
          repository: productionRepository,
        ),
      ),
    );
    if (!mounted) return;
    // _reload() already refreshes this panel and calls widget.onChanged(),
    // which is what tells the master list the operator display may have
    // transitioned the order's status (e.g. starting production on its
    // first step) without going through this screen's own _startProduction.
    _reload();
  }

  Future<void> _previewPdf() async {
    try {
      final data = await repository.detail(widget.orderId);
      final order = _map(data['order']);
      if (!mounted) return;
      final generatedBytes = await runWithPomgtLoadingDialog(
        context,
        'Generando PDF…',
        () => pdf.buildFromData(data),
      );
      if (generatedBytes.isEmpty) {
        throw StateError('El PDF se generó vacío. Intenta nuevamente.');
      }
      final sourceBytes = Uint8List.fromList(generatedBytes);
      final number = order['op_number']?.toString().trim();
      final filename =
          '${number == null || number.isEmpty ? 'OP' : number}.pdf';
      if (!mounted) return;
      await showPomgtDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: EdgeInsets.all(
            MediaQuery.sizeOf(dialogContext).width < 640 ? 10 : 28,
          ),
          child: SizedBox(
            width: _responsiveDialogWidth(dialogContext, 980),
            height: MediaQuery.sizeOf(dialogContext).height * .86,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 460;
                      Future<void> printAction() async {
                        await Printing.layoutPdf(
                          name: filename,
                          onLayout: (_) async =>
                              Uint8List.fromList(sourceBytes),
                        );
                      }

                      Future<void> downloadAction() async {
                        await downloadPdfFile(
                          bytes: Uint8List.fromList(sourceBytes),
                          filename: filename,
                        );
                      }

                      return Row(
                        children: [
                          const Icon(
                            LucideIcons.fileText,
                            color: PomgtColors.ink,
                            size: 20,
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'Vista previa de la orden de producción',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (narrow) ...[
                            IconButton(
                              tooltip: 'Imprimir',
                              onPressed: printAction,
                              icon: const Icon(LucideIcons.printer, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Descargar',
                              onPressed: downloadAction,
                              icon: const Icon(LucideIcons.fileDown, size: 18),
                            ),
                          ] else ...[
                            TextButton.icon(
                              onPressed: printAction,
                              icon: const Icon(LucideIcons.printer, size: 16),
                              label: const Text('Imprimir'),
                            ),
                            TextButton.icon(
                              onPressed: downloadAction,
                              icon: const Icon(LucideIcons.fileDown, size: 16),
                              label: const Text('Descargar'),
                            ),
                          ],
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(LucideIcons.x),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => Uint8List.fromList(sourceBytes),
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    allowPrinting: true,
                    allowSharing: true,
                    pdfFileName: filename,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showProductionError(context, e);
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final data = await repository.detail(widget.orderId);
      final order = _map(data['order']);
      if (!mounted) return;
      final generatedBytes = await runWithPomgtLoadingDialog(
        context,
        'Generando PDF…',
        () => pdf.buildFromData(data),
      );
      if (generatedBytes.isEmpty) {
        throw StateError('El PDF se generó vacío. Intenta nuevamente.');
      }
      final number = order['op_number']?.toString().trim();
      final filename =
          '${number == null || number.isEmpty ? 'OP' : number}.pdf';
      await downloadPdfFile(
        bytes: Uint8List.fromList(generatedBytes),
        filename: filename,
      );
      if (!mounted) return;
      _showProductionSuccess(context, 'PDF descargado.');
    } catch (e) {
      if (!mounted) return;
      _showProductionError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.surface,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(
          color: PomgtColors.lineStrong.withValues(alpha: .55),
        ),
        boxShadow: PomgtShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (_startingProduction) return const PomgtLoading();
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const PomgtLoading();
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                ErrorCopy.message(
                  snapshot.error!,
                  fallback: 'No fue posible cargar la orden de producción.',
                ),
                style: const TextStyle(color: PomgtColors.danger),
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final order = _map(data['order']);
          final product = _map(data['product']);
          return ScrollToTopArea(
            padding: const EdgeInsets.all(16),
            builder: (context, controller) => CustomScrollView(
              controller: controller,
              slivers: [
                SliverToBoxAdapter(
                  child: _ProductionHero(
                    data: data,
                    onPrepare:
                        !_busy &&
                            (order['status'] == 'draft' ||
                                order['status'] == 'planned')
                        ? () => _prepareOrder(product)
                        : null,
                    onStart: !_busy && order['status'] == 'ready'
                        ? _startProduction
                        : null,
                    onPause: !_busy && order['status'] == 'in_progress'
                        ? () => _action(
                            () => repository.transitionOrder(
                              widget.orderId,
                              'on_hold',
                            ),
                            'Orden pausada.',
                          )
                        : null,
                    onResume: !_busy && order['status'] == 'on_hold'
                        ? () => _action(
                            () => repository.transitionOrder(
                              widget.orderId,
                              'in_progress',
                            ),
                            'Producción reanudada.',
                          )
                        : null,
                    onComplete: !_busy && order['status'] == 'in_progress'
                        ? () async {
                            if (_pendingOperations(data).isNotEmpty) {
                              _showPendingOperationsNotice(data);
                              return;
                            }
                            final qty = await _quantityDialog(
                              context,
                              title: 'Completar orden de producción',
                              label: 'Cantidad completada',
                              initial: _n(order['planned_quantity']),
                            );
                            if (qty == null) return;
                            await _action(
                              () => repository.transitionOrder(
                                widget.orderId,
                                'completed',
                                completedQuantity: qty,
                              ),
                              'Orden de producción completada.',
                            );
                          }
                        : null,
                    onCancel:
                        !_busy &&
                            ![
                              'completed',
                              'cancelled',
                            ].contains(order['status'])
                        ? () async {
                            final ok = await _confirm(
                              context,
                              'Cancelar orden de producción',
                              'La orden quedará cancelada y conservará todo su historial. Esta acción no elimina registros.',
                              confirm: 'Cancelar OP',
                            );
                            if (!ok) return;
                            await _action(
                              () => repository.transitionOrder(
                                widget.orderId,
                                'cancelled',
                              ),
                              'Orden cancelada.',
                            );
                          }
                        : null,
                    onEdit: () => widget.onEdit(order),
                    onDelete: () => widget.onDelete(order),
                    onPlan: () async {
                      final changed = await showPomgtDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _PlanningDialog(order: order),
                      );
                      if (changed == true && mounted) _reload();
                    },
                    onOperatorDisplay: () => _openOperatorDisplay(product),
                    onPreviewPdf: _previewPdf,
                    onDownloadPdf: _downloadPdf,
                  ),
                ),
                SliverToBoxAdapter(child: _ProductionKpis(data: data)),
                SliverToBoxAdapter(
                  child: _ProductionTabs(
                    selected: _tab,
                    onChanged: (value) => setState(() => _tab = value),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: PomgtChangeMotion(
                    value: _tab,
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        _SummaryTab(data: data, orderId: widget.orderId),
                        _OperationsTab(data: data),
                        _MaterialsTab(data: data, onChanged: _reload),
                        _QualityTab(data: data, onChanged: _reload),
                        _CostsTab(data: data, onChanged: _reload),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: LinkedDocumentsPanel(
                            entityField: 'production_order_id',
                            entityId: widget.orderId,
                            title: 'Documentos de la orden de producción',
                            help: 'Instructivos, artes, especificaciones, evidencia fotográfica, certificados, reportes y PDFs generados por POMGT.',
                            documentTypes: const [
                              'Orden de producción',
                              'Instructivo',
                              'Diseño / arte',
                              'Especificación',
                              'Evidencia fotográfica',
                              'Certificado de calidad',
                              'Reporte',
                              'Otro',
                            ],
                          ),
                        ),
                        _ActivityTab(data: data),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductionHero extends StatelessWidget {
  const _ProductionHero({
    required this.data,
    required this.onPrepare,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onCancel,
    required this.onEdit,
    required this.onDelete,
    required this.onPlan,
    required this.onOperatorDisplay,
    required this.onPreviewPdf,
    required this.onDownloadPdf,
  });
  final Map<String, dynamic> data;
  final VoidCallback? onPrepare;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPlan;
  final VoidCallback onOperatorDisplay;
  final VoidCallback onPreviewPdf;
  final VoidCallback onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final product = _map(data['product']);
    final customer = _map(data['customer']);
    final clientName =
        customer['trade_name']?.toString().trim().isNotEmpty == true
        ? customer['trade_name'].toString()
        : customer['legal_name']?.toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 820;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isCompact
                          ? (constraints.maxWidth - 36).clamp(
                              0.0,
                              double.infinity,
                            )
                          : 520,
                    ),
                    child: Text(
                      order['op_number']?.toString() ?? 'Orden de producción',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _StatusText(status: order['status']?.toString() ?? 'draft'),
                  const InfoTip(
                    'Expediente operativo congelado de esta orden de producción.',
                    size: 15,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${product['sku'] ?? '—'} · ${product['name'] ?? 'Producto'}${clientName == null ? '' : ' · $clientName'}${order['order_number'] == null ? '' : ' · ${order['order_number']}'}',
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
            spacing: 4,
            runSpacing: 4,
            alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onPlan,
                icon: const Icon(LucideIcons.calendar, size: 16),
                label: const Text('Planeación'),
              ),
              FilledButton.icon(
                onPressed: onOperatorDisplay,
                icon: const Icon(LucideIcons.monitorPlay, size: 17),
                label: const Text('Display operador'),
              ),
              PopupMenuButton<String>(
                popUpAnimationStyle: PomgtMotion.style(context),
                tooltip: 'PDF y documentos',
                icon: const Icon(LucideIcons.fileText, size: 18),
                onSelected: (value) {
                  if (value == 'preview') onPreviewPdf();
                  if (value == 'download') onDownloadPdf();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'preview',
                    child: Text('Previsualizar / imprimir PDF'),
                  ),
                  PopupMenuItem(
                    value: 'download',
                    child: Text('Descargar PDF'),
                  ),
                ],
              ),
              if (onPrepare != null)
                FilledButton.icon(
                  onPressed: onPrepare,
                  icon: const Icon(LucideIcons.package, size: 17),
                  label: const Text('Preparar OP'),
                ),
              if (onStart != null)
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(LucideIcons.play, size: 17),
                  label: const Text('Iniciar producción'),
                ),
              if (onPause != null)
                OutlinedButton.icon(
                  onPressed: onPause,
                  icon: const Icon(LucideIcons.pause, size: 17),
                  label: const Text('Pausar'),
                ),
              if (onResume != null)
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(LucideIcons.play, size: 17),
                  label: const Text('Reanudar'),
                ),
              if (onComplete != null)
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(LucideIcons.check, size: 17),
                  label: const Text('Completar'),
                ),
              PopupMenuButton<String>(
                popUpAnimationStyle: PomgtMotion.style(context),
                tooltip: 'Más acciones',
                icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                  if (value == 'cancel' && onCancel != null) onCancel!();
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
                          style: TextStyle(color: PomgtColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 12), actionBlock],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .58,
                ),
                child: actionBlock,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductionKpis extends StatelessWidget {
  const _ProductionKpis({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final operations = _list(data['operations']);
    final materials = _list(data['materials']);
    final quality = _list(data['quality']);
    final checklist = _list(data['checklist']);
    final costs = _map(data['costs']);
    final completedOps = operations
        .where((e) => ['completed', 'skipped'].contains(e['status']))
        .length;
    final pendingQuality = quality
        .where(
          (e) => e['is_required'] == true && e['result_status'] == 'pending',
        )
        .length;
    final pendingChecklist = checklist
        .where((e) => e['is_required'] == true && e['is_completed'] != true)
        .length;
    final totalCost = _costTotal(costs, 'actual');
    final items = [
      _KpiData(
        'Cantidad',
        '${_fmt(order['planned_quantity'])} ${order['uom_symbol'] ?? ''}',
        LucideIcons.hash,
      ),
      _KpiData(
        'Avance',
        '${_fmt(order['progress_pct'])}%',
        LucideIcons.chartColumn,
      ),
      _KpiData(
        'Operaciones',
        '$completedOps / ${operations.length}',
        LucideIcons.gitBranch,
      ),
      _KpiData('Materiales', '${materials.length}', LucideIcons.layers),
      _KpiData(
        'Calidad pendiente',
        '$pendingQuality',
        LucideIcons.clipboardCheck,
      ),
      _KpiData('Verificaciones', '$pendingChecklist', LucideIcons.listChecks),
      _KpiData(
        'Fecha requerida',
        _date(order['required_at']),
        LucideIcons.calendar,
      ),
      _KpiData(
        'Costo real',
        '${costs['currency_code'] ?? 'MXN'} \$${totalCost.toStringAsFixed(2)}',
        LucideIcons.banknote,
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1250
              ? 8
              : constraints.maxWidth >= 850
              ? 4
              : 2;
          final width = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: width,
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      border: Border(
                        right: i % columns != columns - 1
                            ? const BorderSide(color: PomgtColors.line)
                            : BorderSide.none,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(items[i].icon, size: 18, color: PomgtColors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[i].value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                items[i].label,
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
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _ProductionTabs extends StatelessWidget {
  const _ProductionTabs({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    const labels = [
      'Resumen',
      'Operaciones',
      'Materiales',
      'Calidad',
      'Costos',
      'Documentos',
      'Actividad',
    ];
    return Container(
      height: 45,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                InkWell(
                  onTap: () => onChanged(i),
                  hoverColor: PomgtColors.blue.withValues(alpha: .06),
                  highlightColor: PomgtColors.blue.withValues(alpha: .10),
                  child: AnimatedContainer(
                    duration: PomgtMotion.duration(context, PomgtMotion.fast),
                    curve: PomgtMotion.curve,
                    height: 45,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == selected
                              ? PomgtColors.blue
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == selected
                            ? PomgtColors.ink
                            : PomgtColors.muted,
                        fontSize: 12,
                        fontWeight: i == selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.data, required this.orderId});
  final Map<String, dynamic> data;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final product = _map(data['product']);
    final customer = _map(data['customer']);
    final customerOrder = _map(data['customer_order']);
    final operations = _list(data['operations']);
    final materials = _list(data['materials']);
    final events = _list(data['events']);
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 980;
            final left = Column(
              children: [
                _Panel(
                  title: 'Información de la orden',
                  icon: LucideIcons.factory,
                  child: _InfoGrid(
                    items: [
                      _Info('Número de OP', order['op_number']),
                      if (order['batch_number'] != null)
                        _Info('Lote', order['batch_number']),
                      _Info('Origen', _sourceLabel(order['source_type'])),
                      _Info(
                        'Producto',
                        '${product['sku'] ?? '—'} · ${product['name'] ?? '—'}',
                      ),
                      _Info(
                        'Cantidad',
                        '${_fmt(order['planned_quantity'])} ${order['uom_symbol'] ?? ''}',
                      ),
                      _Info(
                        'Estado',
                        UiCopy.enumLabel(order['status']?.toString() ?? ''),
                      ),
                      _Info(
                        'Prioridad',
                        UiCopy.enumLabel(order['priority']?.toString() ?? ''),
                      ),
                      _Info(
                        'Inicio planificado',
                        _dateTime(order['planned_start_at']),
                      ),
                      _Info(
                        'Fin planificado',
                        _dateTime(order['planned_end_at']),
                      ),
                      _Info('Fecha requerida', _dateTime(order['required_at'])),
                      _Info('Inicio real', _dateTime(order['actual_start_at'])),
                      _Info('Fin real', _dateTime(order['actual_end_at'])),
                      _Info('Notas', order['notes']),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _OperatorsPanel(orderId: orderId),
                const SizedBox(height: 14),
                _Panel(
                  title: 'Estructura congelada de fabricación',
                  icon: LucideIcons.gitBranch,
                  child: _InfoGrid(
                    items: [
                      _Info(
                        'Estructura de fabricación',
                        '${order['bom_code'] ?? '—'} · ${order['bom_revision_code'] ?? '—'}',
                      ),
                      _Info(
                        'Ruta de fabricación',
                        '${order['routing_code'] ?? '—'} · ${order['routing_revision_code'] ?? '—'}',
                      ),
                      _Info('Operaciones', operations.length),
                      _Info('Materiales / componentes', materials.length),
                      _Info('Preparada el', _dateTime(order['prepared_at'])),
                      _Info(
                        'Versión de snapshot',
                        order['snapshot_version'] ?? 1,
                      ),
                    ],
                  ),
                ),
              ],
            );
            final right = Column(
              children: [
                _Panel(
                  title: 'Origen comercial',
                  icon: LucideIcons.fileText,
                  child: customerOrder.isEmpty
                      ? const _EmptyText(
                          'Esta OP corresponde a producción interna o no tiene un pedido vinculado.',
                        )
                      : _InfoGrid(
                          items: [
                            _Info(
                              'Cliente',
                              customer['trade_name'] ?? customer['legal_name'],
                            ),
                            _Info('Pedido', customerOrder['order_number']),
                            _Info(
                              'OC del cliente',
                              customerOrder['customer_po_number'],
                            ),
                            _Info(
                              'Referencia externa',
                              customerOrder['external_reference'],
                            ),
                            _Info(
                              'Entrega solicitada',
                              _date(customerOrder['requested_delivery_date']),
                            ),
                            _Info(
                              'Condición / moneda',
                              '${customerOrder['currency_code'] ?? '—'}',
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                _Panel(
                  title: 'Actividad reciente',
                  icon: LucideIcons.clock,
                  child: events.isEmpty
                      ? const _EmptyText('No hay actividad registrada todavía.')
                      : Column(
                          children: [
                            for (final event in events.take(6))
                              _TimelineRow(
                                title:
                                    event['title']?.toString() ?? 'Actividad',
                                subtitle:
                                    event['description']?.toString() ?? '',
                                date: _dateTime(event['occurred_at']),
                                color: PomgtColors.blue,
                              ),
                          ],
                        ),
                ),
              ],
            );
            if (!horizontal) {
              return Column(
                children: [left, const SizedBox(height: 14), right],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: right),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OperationsTab extends StatelessWidget {
  const _OperationsTab({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = _list(data['operations']);
    final order = _map(data['order']);
    final noOperationRunning =
        order['status'] == 'in_progress' &&
        !rows.any((row) => row['status'] == 'in_progress');
    final workCenters = (data['work_centers'] as Map?) ?? const {};
    final machines = (data['machines'] as Map?) ?? const {};
    final checklist = _list(data['checklist']);
    final quality = _list(data['quality']);
    if (rows.isEmpty) {
      return const Center(
        child: _EmptyText(
          'La OP no tiene operaciones. Prepara la orden para congelar su ruta de fabricación.',
        ),
      );
    }
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => PomgtListView.separated(
        controller: controller,
        padding: const EdgeInsets.all(16),
        itemCount: rows.length + (noOperationRunning ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (noOperationRunning && index == 0) {
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PomgtColors.blue.withValues(alpha: .07),
                borderRadius: PomgtRadii.borderMd,
                border: Border.all(
                  color: PomgtColors.blue.withValues(alpha: .2),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, color: PomgtColors.blue, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'La OP está abierta en producción, pero todavía no hay un paso activo. Abre el Display del operador para iniciar la primera operación y registrar su máquina.',
                    ),
                  ),
                ],
              ),
            );
          }
          final row = rows[index - (noOperationRunning ? 1 : 0)];
          final operationId = row['id'].toString();
          final wc =
              (workCenters[row['work_center_id']?.toString()] as Map?)?['name']
                  ?.toString() ??
              'Sin centro asignado';
          final machine =
              (machines[row['machine_id']?.toString()] as Map?)?['name']
                  ?.toString() ??
              'Sin máquina asignada';
          final checks = checklist
              .where((e) => e['operation_id']?.toString() == operationId)
              .toList();
          final q = quality
              .where((e) => e['operation_id']?.toString() == operationId)
              .toList();
          final status = row['status']?.toString() ?? 'pending';
          return _Panel(
            title:
                '${row['sequence_no'] ?? index + 1} · ${row['operation_code'] ?? ''} · ${row['name'] ?? 'Operación'}',
            icon: LucideIcons.route,
            trailing: _StatusText(status: status),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    _MiniMetric('Centro de trabajo', wc),
                    _MiniMetric('Máquina', machine),
                    _MiniMetric(
                      'Setup',
                      '${_fmt(row['setup_time_minutes'])} min',
                    ),
                    _MiniMetric('Tiempo', _operationTime(row)),
                    _MiniMetric(
                      'Cantidad',
                      '${_fmt(row['completed_quantity'])} / ${_fmt(row['planned_quantity'])}',
                    ),
                    _MiniMetric(
                      'Calidad',
                      q.isEmpty
                          ? 'No aplica'
                          : '${q.where((e) => e['result_status'] == 'passed').length}/${q.length} aprobados',
                    ),
                    _MiniMetric(
                      'Checklist',
                      checks.isEmpty
                          ? 'No aplica'
                          : '${checks.where((e) => e['is_completed'] == true).length}/${checks.length} completados',
                    ),
                  ],
                ),
                if ((row['instructions']?.toString() ?? '')
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 13),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  Text(
                    'Instrucciones: ${row['instructions']}',
                    style: const TextStyle(
                      color: PomgtColors.secondaryInk,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                if (status == 'ready' ||
                    status == 'in_progress' ||
                    status == 'on_hold') ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 11),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.monitorPlay,
                        size: 14,
                        color: PomgtColors.muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Para iniciar, pausar o completar esta operación usa el Display del operador — ahí se firma cada paso.',
                          style: TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MaterialsTab extends StatelessWidget {
  const _MaterialsTab({required this.data, required this.onChanged});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = _list(data['materials']);
    final products = (data['products'] as Map?) ?? const {};
    final units = (data['units'] as Map?) ?? const {};
    if (rows.isEmpty) {
      return const Center(
        child: _EmptyText(
          'No hay materiales congelados. Prepara la OP para calcular los requerimientos de la estructura de fabricación.',
        ),
      );
    }
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => PomgtListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _Panel(
            title: 'Materiales requeridos para la orden',
            icon: LucideIcons.layers,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = constraints.maxWidth < 860
                    ? 860.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        const _TableHeader(
                          columns: [
                            'Material',
                            'Tipo',
                            'Requerido',
                            'Surtido',
                            'Consumido',
                            'Devuelto',
                            'Merma',
                            'Acción',
                          ],
                        ),
                        for (final row in rows)
                          _MaterialRow(
                            row: row,
                            product: _map(
                              products[row['material_product_id']?.toString()],
                            ),
                            unit: _map(units[row['uom_id']?.toString()]),
                            onMove: () async {
                              final request =
                                  await showPomgtDialog<
                                    _MaterialMovementRequest
                                  >(
                                    context: context,
                                    builder: (_) => _MaterialMovementDialog(
                                      materialName:
                                          _map(
                                            products[row['material_product_id']
                                                ?.toString()],
                                          )['name']?.toString() ??
                                          'Material',
                                    ),
                                  );
                              if (request == null || !context.mounted) return;
                              try {
                                await context
                                    .read<ProductionRepository>()
                                    .materialMovement(
                                      materialId: row['id'].toString(),
                                      movementType: request.type,
                                      quantity: request.quantity,
                                      lotNumber: request.lot,
                                      warehouseReference: request.warehouse,
                                      note: request.note,
                                    );
                                if (!context.mounted) return;
                                onChanged();
                                _showProductionSuccess(
                                  context,
                                  'Movimiento de material registrado.',
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                _showProductionError(context, e);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Movimientos recientes',
            icon: LucideIcons.arrowRightLeft,
            child: _list(data['movements']).isEmpty
                ? const _EmptyText(
                    'Todavía no hay movimientos de material en esta OP.',
                  )
                : Column(
                    children: [
                      for (final move in _list(data['movements']).take(12))
                        _TimelineRow(
                          title: _movementLabel(move['movement_type']),
                          subtitle:
                              '${_fmt(move['quantity'])} · ${move['lot_number'] == null ? 'Sin lote' : 'Lote ${move['lot_number']}'}',
                          date: _dateTime(move['occurred_at']),
                          color: PomgtColors.blue,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QualityTab extends StatelessWidget {
  const _QualityTab({required this.data, required this.onChanged});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final quality = _list(data['quality']);
    final checklist = _list(data['checklist']);
    final operations = {
      for (final row in _list(data['operations'])) row['id'].toString(): row,
    };
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => PomgtListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _Panel(
            title: 'Controles de calidad',
            icon: LucideIcons.clipboardCheck,
            child: quality.isEmpty
                ? const _EmptyText(
                    'La ruta de esta OP no contiene controles de calidad.',
                  )
                : Column(
                    children: [
                      for (final row in quality)
                        _QualityRow(
                          row: row,
                          operation:
                              operations[row['operation_id']?.toString()],
                          onCapture: () async {
                            final result =
                                await showPomgtDialog<_QualityCapture>(
                                  context: context,
                                  builder: (_) => _QualityDialog(check: row),
                                );
                            if (result == null || !context.mounted) return;
                            try {
                              await context
                                  .read<ProductionRepository>()
                                  .recordQuality(
                                    checkId: row['id'].toString(),
                                    resultValue: result.value,
                                    note: result.note,
                                    forceStatus: result.forceStatus,
                                  );
                              if (!context.mounted) return;
                              onChanged();
                              _showProductionSuccess(
                                context,
                                'Resultado de calidad registrado.',
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              _showProductionError(context, e);
                            }
                          },
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Lista de verificación operativa',
            icon: LucideIcons.listChecks,
            child: checklist.isEmpty
                ? const _EmptyText(
                    'La ruta de esta OP no contiene listas de verificación.',
                  )
                : Column(
                    children: [
                      for (final row in checklist)
                        _ChecklistRow(
                          row: row,
                          operation:
                              operations[row['operation_id']?.toString()],
                          onCapture: () async {
                            final response =
                                await showPomgtDialog<_ChecklistCapture>(
                                  context: context,
                                  builder: (_) => _ChecklistDialog(item: row),
                                );
                            if (response == null || !context.mounted) return;
                            try {
                              await context
                                  .read<ProductionRepository>()
                                  .answerChecklist(
                                    itemId: row['id'].toString(),
                                    response: response.value,
                                    note: response.note,
                                  );
                              if (!context.mounted) return;
                              onChanged();
                              _showProductionSuccess(
                                context,
                                'Verificación registrada.',
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              _showProductionError(context, e);
                            }
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CostsTab extends StatelessWidget {
  const _CostsTab({required this.data, required this.onChanged});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final costs = _map(data['costs']);
    if (costs.isEmpty) {
      return const Center(
        child: _EmptyText('No existe una hoja de costos para esta OP.'),
      );
    }
    final currency = costs['currency_code']?.toString() ?? 'MXN';
    final estimated = _costTotal(costs, 'estimated');
    final actual = _costTotal(costs, 'actual');
    final variance = estimated == 0
        ? 0
        : ((actual - estimated) / estimated) * 100;
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => PomgtListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _Panel(
            title: 'Costo estimado vs. real',
            icon: LucideIcons.banknote,
            trailing: TextButton.icon(
              onPressed: () async {
                final changed = await showPomgtDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _CostDialog(costs: costs),
                );
                if (changed == true && context.mounted) onChanged();
              },
              icon: const Icon(LucideIcons.pencil, size: 15),
              label: const Text('Actualizar costos'),
            ),
            child: Column(
              children: [
                _CostLine(
                  'Materiales',
                  costs['estimated_material'],
                  costs['actual_material'],
                  currency,
                ),
                _CostLine(
                  'Mano de obra',
                  costs['estimated_labor'],
                  costs['actual_labor'],
                  currency,
                ),
                _CostLine(
                  'Máquina',
                  costs['estimated_machine'],
                  costs['actual_machine'],
                  currency,
                ),
                _CostLine(
                  'Subcontrato',
                  costs['estimated_subcontract'],
                  costs['actual_subcontract'],
                  currency,
                ),
                _CostLine(
                  'Indirectos',
                  costs['estimated_overhead'],
                  costs['actual_overhead'],
                  currency,
                ),
                const Divider(height: 24),
                _CostLine('TOTAL', estimated, actual, currency, strong: true),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricPanel(
                  title: 'Costo estimado',
                  value: '$currency \$${estimated.toStringAsFixed(2)}',
                  caption: 'Base de planeación',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricPanel(
                  title: 'Costo real',
                  value: '$currency \$${actual.toStringAsFixed(2)}',
                  caption: 'Acumulado registrado',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricPanel(
                  title: 'Variación',
                  value:
                      '${variance >= 0 ? '+' : ''}${variance.toStringAsFixed(2)}%',
                  caption: 'Real contra estimado',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final rows = _list(data['events']);
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => PomgtListView(
        controller: controller,
        padding: const EdgeInsets.all(16),
        children: [
          _Panel(
            title: 'Bitácora de la orden de producción',
            icon: LucideIcons.clock,
            child: rows.isEmpty
                ? const _EmptyText('Todavía no existe actividad registrada.')
                : Column(
                    children: [
                      for (final event in rows)
                        _TimelineRow(
                          title: event['title']?.toString() ?? 'Actividad',
                          subtitle:
                              event['description']?.toString() ??
                              _eventLabel(event['event_type']),
                          date: _dateTime(event['occurred_at']),
                          color: _statusColor(
                            event['new_status']?.toString() ?? '',
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

class _OperatorsPanel extends StatefulWidget {
  const _OperatorsPanel({required this.orderId});
  final String orderId;

  @override
  State<_OperatorsPanel> createState() => _OperatorsPanelState();
}

class _OperatorsPanelState extends State<_OperatorsPanel> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return context.read<GenericRepository>().listRows(
      Phase1Schema.tables['production_order_operators']!,
      filters: {'production_order_id': widget.orderId},
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _unassign(Map<String, dynamic> row) async {
    try {
      await context.read<GenericRepository>().deleteRow(
        Phase1Schema.tables['production_order_operators']!,
        row,
      );
      _reload();
    } catch (e) {
      if (mounted) _showProductionError(context, e);
    }
  }

  Future<void> _openAssignDialog(List<Map<String, dynamic>> assigned) async {
    final changed = await showPomgtDialog<bool>(
      context: context,
      builder: (_) =>
          _AssignOperatorsDialog(orderId: widget.orderId, assigned: assigned),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final assigned = snapshot.data ?? const <Map<String, dynamic>>[];
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: context.read<LookupRepository>().rows('organization_members'),
          builder: (context, memberSnap) {
            final members = {
              for (final m in memberSnap.data ?? const <Map<String, dynamic>>[])
                m['id'].toString(): m,
            };
            return _Panel(
              title: 'Operadores asignados',
              icon: LucideIcons.users,
              trailing: TextButton.icon(
                onPressed: () => _openAssignDialog(assigned),
                icon: const Icon(LucideIcons.pencil, size: 15),
                label: const Text('Asignar'),
              ),
              child: assigned.isEmpty
                  ? const _EmptyText(
                      'Sin operadores asignados. Puedes asignar uno o varios.',
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final row in assigned)
                          _OperatorChip(
                            name:
                                members[row['member_id']
                                        ?.toString()]?['full_name']
                                    ?.toString() ??
                                'Operador',
                            lead: row['role']?.toString() == 'lead',
                            onRemove: () => _unassign(row),
                          ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _OperatorChip extends StatelessWidget {
  const _OperatorChip({
    required this.name,
    required this.lead,
    required this.onRemove,
  });
  final String name;
  final bool lead;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
    decoration: BoxDecoration(
      color: lead ? PomgtColors.blueSoft : PomgtColors.surfaceAlt,
      borderRadius: PomgtRadii.borderPill,
      border: Border.all(
        color: lead ? PomgtColors.blue.withValues(alpha: .3) : PomgtColors.line,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          LucideIcons.circleUserRound,
          size: 15,
          color: lead ? PomgtColors.blue : PomgtColors.muted,
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: lead ? PomgtColors.blue : PomgtColors.ink,
          ),
        ),
        if (lead) ...[
          const SizedBox(width: 4),
          const Text(
            '· líder',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: PomgtColors.blue,
            ),
          ),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(LucideIcons.x, size: 12, color: PomgtColors.muted),
          ),
        ),
      ],
    ),
  );
}

class _AssignOperatorsDialog extends StatefulWidget {
  const _AssignOperatorsDialog({required this.orderId, required this.assigned});
  final String orderId;
  final List<Map<String, dynamic>> assigned;

  @override
  State<_AssignOperatorsDialog> createState() => _AssignOperatorsDialogState();
}

class _AssignOperatorsDialogState extends State<_AssignOperatorsDialog> {
  late Future<List<List<Map<String, dynamic>>>> _operatorsFuture;
  late final Set<String> _selected;
  String? _leadId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _operatorsFuture = Future.wait([
      context.read<GenericRepository>().listRows(
        Phase1Schema.tables['organization_members']!,
      ),
      context.read<RolesRepository>().roles(),
    ]);
    _selected = {
      for (final row in widget.assigned) row['member_id'].toString(),
    };
    final lead = widget.assigned
        .where((row) => row['role']?.toString() == 'lead')
        .toList();
    _leadId = lead.isEmpty ? null : lead.first['member_id']?.toString();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = context.read<GenericRepository>();
    final spec = Phase1Schema.tables['production_order_operators']!;
    try {
      final currentIds = {
        for (final row in widget.assigned) row['member_id'].toString(): row,
      };
      for (final id in _selected.difference(currentIds.keys.toSet())) {
        await repository.createRow(spec, {
          'production_order_id': widget.orderId,
          'member_id': id,
          'role': id == _leadId ? 'lead' : 'operator',
        });
      }
      for (final id in currentIds.keys.toSet().difference(_selected)) {
        await repository.deleteRow(spec, currentIds[id]!);
      }
      for (final id in _selected) {
        final current = currentIds[id];
        final shouldBeLead = id == _leadId;
        final isLead = current?['role']?.toString() == 'lead';
        if (current != null && shouldBeLead != isLead) {
          await repository.updateRow(spec, current['id'].toString(), {
            'role': shouldBeLead ? 'lead' : 'operator',
          });
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showProductionError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.users, color: PomgtColors.ink, size: 20),
          const SizedBox(width: 10),
          const Expanded(child: Text('Asignar operadores')),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 420),
        child: FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: _operatorsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 160, child: PomgtLoading());
            }
            final data = snapshot.data;
            final operators =
                (data == null ? const <Map<String, dynamic>>[] : data[0])
                    .where((o) => o['is_active'] != false)
                    .toList();
            final roleNames = {
              for (final r
                  in (data == null ? const <Map<String, dynamic>>[] : data[1]))
                r['id'].toString(): r['name']?.toString(),
            };
            if (operators.isEmpty) {
              return const _EmptyText(
                'No hay miembros activos. Invita miembros desde Roles y auditoría.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ScrollToTopArea(
                padding: const EdgeInsets.all(8),
                builder: (context, controller) => PomgtListView(
                  controller: controller,
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Marca uno o varios operadores. El botón de estrella señala al responsable de la orden.',
                        style: TextStyle(
                          color: PomgtColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    for (final operator in operators)
                      _OperatorSelectRow(
                        name: operator['full_name']?.toString() ?? 'Operador',
                        role:
                            roleNames[operator['role_id']?.toString()] ??
                            operator['email']?.toString(),
                        selected: _selected.contains(operator['id'].toString()),
                        isLead: _leadId == operator['id'].toString(),
                        onToggle: () => setState(() {
                          final id = operator['id'].toString();
                          if (_selected.contains(id)) {
                            _selected.remove(id);
                            if (_leadId == id) _leadId = null;
                          } else {
                            _selected.add(id);
                          }
                        }),
                        onSetLead: () => setState(() {
                          final id = operator['id'].toString();
                          if (!_selected.contains(id)) _selected.add(id);
                          _leadId = _leadId == id ? null : id;
                        }),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PomgtColors.canvas,
                  ),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _OperatorSelectRow extends StatelessWidget {
  const _OperatorSelectRow({
    required this.name,
    required this.role,
    required this.selected,
    required this.isLead,
    required this.onToggle,
    required this.onSetLead,
  });
  final String name;
  final String? role;
  final bool selected;
  final bool isLead;
  final VoidCallback onToggle;
  final VoidCallback onSetLead;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onToggle,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: (_) => onToggle()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PomgtColors.ink,
                  ),
                ),
                if (role != null && role!.trim().isNotEmpty)
                  Text(
                    role!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PomgtColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: isLead ? 'Responsable de la orden' : 'Marcar responsable',
            visualDensity: VisualDensity.compact,
            onPressed: selected ? onSetLead : null,
            icon: Icon(
              isLead ? LucideIcons.star : LucideIcons.star,
              size: 18,
              color: isLead ? PomgtColors.amber : PomgtColors.subtle,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 640 ? 12 : 16),
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      borderRadius: PomgtRadii.borderMd,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
      boxShadow: PomgtShadows.card,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: PomgtColors.blue),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width < 640 ? 260 : 520,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const InfoTip(
                    'Información operativa de esta sección.',
                    size: 14,
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});
  final List<_Info> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760
          ? 3
          : constraints.maxWidth >= 460
          ? 2
          : 1;
      final width = constraints.maxWidth / columns;
      return Wrap(
        runSpacing: 16,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _show(item.value),
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Info {
  const _Info(this.label, this.value);
  final String label;
  final dynamic value;
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => PomgtAnimatedValue(
    value: status,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: _statusColor(status),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          UiCopy.enumLabel(status),
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.color,
  });
  final String title;
  final String subtitle;
  final String date;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PomgtColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PomgtColors.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          date,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: PomgtColors.muted, fontSize: 12.5),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns});
  final List<String> columns;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    color: PomgtColors.surfaceAlt,
    child: Row(
      children: [
        for (var i = 0; i < columns.length; i++)
          Expanded(
            flex: i == 0
                ? 3
                : i == 1
                ? 2
                : 1,
            child: Text(
              columns[i],
              style: const TextStyle(
                color: PomgtColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    ),
  );
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.row,
    required this.product,
    required this.unit,
    required this.onMove,
  });
  final Map<String, dynamic> row;
  final Map<String, dynamic> product;
  final Map<String, dynamic> unit;
  final VoidCallback onMove;
  @override
  Widget build(BuildContext context) {
    final values = [
      '${product['sku'] ?? '—'} · ${product['name'] ?? 'Material'}',
      UiCopy.enumLabel(row['component_type']?.toString() ?? ''),
      '${_fmt(row['required_quantity'])} ${unit['symbol'] ?? ''}',
      '${_fmt(row['issued_quantity'])} ${unit['symbol'] ?? ''}',
      '${_fmt(row['consumed_quantity'])} ${unit['symbol'] ?? ''}',
      '${_fmt(row['returned_quantity'])} ${unit['symbol'] ?? ''}',
      '${_fmt(row['scrap_quantity'])} ${unit['symbol'] ?? ''}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              flex: i == 0
                  ? 3
                  : i == 1
                  ? 2
                  : 1,
              child: Text(
                values[i],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: i == 0 ? PomgtColors.ink : PomgtColors.secondaryInk,
                  fontSize: 11.5,
                  fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onMove,
                child: const Text('Registrar'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.row,
    required this.operation,
    required this.onCapture,
  });
  final Map<String, dynamic> row;
  final Map<String, dynamic>? operation;
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) {
    final status = row['result_status']?.toString() ?? 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 640
                ? double.infinity
                : 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['name']?.toString() ?? 'Control',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${operation?['operation_code'] ?? '—'} · ${operation?['name'] ?? 'Operación'}',
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 160,
            child: Text(
              _qualityLimits(row),
              style: const TextStyle(
                color: PomgtColors.secondaryInk,
                fontSize: 11.5,
              ),
            ),
          ),
          _StatusText(status: status),
          TextButton(
            onPressed: status == 'pending' || status == 'failed'
                ? onCapture
                : onCapture,
            child: Text(status == 'pending' ? 'Capturar' : 'Actualizar'),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.row,
    required this.operation,
    required this.onCapture,
  });
  final Map<String, dynamic> row;
  final Map<String, dynamic>? operation;
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: PomgtColors.line)),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          row['is_completed'] == true
              ? LucideIcons.circleCheck
              : LucideIcons.circle,
          size: 17,
          color: row['is_completed'] == true
              ? PomgtColors.success
              : PomgtColors.muted,
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 640 ? double.infinity : 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row['prompt']?.toString() ?? 'Verificación',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${operation?['operation_code'] ?? '—'} · ${operation?['name'] ?? 'Operación'}${row['is_required'] == true ? ' · Obligatoria' : ''}',
                style: const TextStyle(color: PomgtColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onCapture,
          child: Text(row['is_completed'] == true ? 'Actualizar' : 'Responder'),
        ),
      ],
    ),
  );
}

class _CostLine extends StatelessWidget {
  const _CostLine(
    this.label,
    this.estimated,
    this.actual,
    this.currency, {
    this.strong = false,
  });
  final String label;
  final dynamic estimated;
  final dynamic actual;
  final String currency;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'Est: $currency \$${_n(estimated).toStringAsFixed(2)}',
                style: TextStyle(
                  color: PomgtColors.secondaryInk,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              Text(
                'Real: $currency \$${_n(actual).toStringAsFixed(2)}',
                style: TextStyle(
                  color: PomgtColors.ink,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: Text(
                '$currency \$${_n(estimated).toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: PomgtColors.secondaryInk,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 34),
            SizedBox(
              width: 170,
              child: Text(
                '$currency \$${_n(actual).toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: PomgtColors.ink,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    required this.title,
    required this.value,
    required this.caption,
  });
  final String title;
  final String value;
  final String caption;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: PomgtColors.canvas,
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .55)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(color: PomgtColors.muted, fontSize: 10.5),
        ),
      ],
    ),
  );
}

class _CreateProductionOrderDialog extends StatefulWidget {
  const _CreateProductionOrderDialog();
  @override
  State<_CreateProductionOrderDialog> createState() =>
      _CreateProductionOrderDialogState();
}

class _CreateProductionOrderDialogState
    extends State<_CreateProductionOrderDialog> {
  final form = GlobalKey<FormState>();
  final quantity = TextEditingController();
  final notes = TextEditingController();
  String? productId;
  String? uomId;
  String priority = 'normal';
  String sourceType = 'internal';
  String? bomRevisionId;
  String? routingRevisionId;
  DateTime? requiredAt;
  DateTime? plannedStartAt;
  DateTime? plannedEndAt;
  bool prepareAutomatically = true;
  bool loadingRelations = false;
  List<Map<String, dynamic>> boms = const [];
  List<Map<String, dynamic>> routes = const [];
  String? relationsError;
  String? bomHint;
  String? routeHint;
  bool routeFromCategory = false;
  List<Map<String, dynamic>> availableUnits = const [];
  late Future<List<List<Map<String, dynamic>>>> future;

  @override
  void initState() {
    super.initState();
    final lookups = context.read<LookupRepository>();
    future = Future.wait([
      lookups.rows('products', refresh: true),
      lookups.rows('units_of_measure'),
      lookups.rows('product_categories'),
    ]);
  }

  @override
  void dispose() {
    quantity.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> selectProduct(
    String? id,
    List<Map<String, dynamic>> products,
  ) async {
    Map<String, dynamic>? selectedProduct;
    setState(() {
      productId = id;
      bomRevisionId = null;
      routingRevisionId = null;
      boms = const [];
      routes = const [];
      loadingRelations = id != null;
      relationsError = null;
      bomHint = null;
      routeHint = null;
      routeFromCategory = false;
      if (id != null) {
        final selected = products
            .where((e) => e['id']?.toString() == id)
            .toList();
        if (selected.isNotEmpty) {
          selectedProduct = selected.first;
          uomId = selected.first['base_uom_id']?.toString();
        }
      }
    });
    if (id == null) return;
    final generic = context.read<GenericRepository>();
    try {
      final bomHeads = await generic.listRows(
        Phase1Schema.tables['boms']!,
        filters: {'product_id': id},
      );
      var routeHeads = await generic.listRows(
        Phase1Schema.tables['routings']!,
        filters: {'product_id': id},
      );
      var routeHeadsFromCategory = false;
      final categoryId = selectedProduct?['category_id']?.toString();
      if (routeHeads.isEmpty && categoryId != null && categoryId.isNotEmpty) {
        routeHeads = await generic.listRows(
          Phase1Schema.tables['routings']!,
          filters: {'category_id': categoryId},
        );
        routeHeadsFromCategory = routeHeads.isNotEmpty;
      }
      final bomRows = <Map<String, dynamic>>[];
      final routeRows = <Map<String, dynamic>>[];
      final inactiveBoms = <String>[];
      final inactiveRoutes = <String>[];
      for (final head in bomHeads) {
        final revs = await generic.listRows(
          Phase1Schema.tables['bom_revisions']!,
          filters: {'bom_id': head['id']},
        );
        for (final rev in revs) {
          if (rev['status'] == 'active') {
            bomRows.add({...rev, '_head': head});
          } else {
            inactiveBoms.add(
              '${head['bom_code']} ${rev['revision_code']} (${UiCopy.enumLabel(rev['status']?.toString() ?? '')})',
            );
          }
        }
      }
      for (final head in routeHeads) {
        final revs = await generic.listRows(
          Phase1Schema.tables['routing_revisions']!,
          filters: {'routing_id': head['id']},
        );
        for (final rev in revs) {
          if (rev['status'] == 'active') {
            routeRows.add({...rev, '_head': head});
          } else {
            inactiveRoutes.add(
              '${head['routing_code']} ${rev['revision_code']} (${UiCopy.enumLabel(rev['status']?.toString() ?? '')})',
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        boms = bomRows;
        routes = routeRows;
        routeFromCategory = routeHeadsFromCategory && routeRows.isNotEmpty;
        bomHint = bomRows.isEmpty
            ? (inactiveBoms.isNotEmpty
                  ? 'La estructura existe, pero su versión no está Activa: ${inactiveBoms.join(', ')}. Activa la versión en Estructuras de fabricación → Versiones.'
                  : (bomHeads.isEmpty
                        ? 'Este producto no tiene ninguna estructura de fabricación.'
                        : 'La estructura no tiene versiones.'))
            : null;
        routeHint = routeRows.isEmpty
            ? (inactiveRoutes.isNotEmpty
                  ? 'La ruta existe, pero su versión no está Activa: ${inactiveRoutes.join(', ')}. Activa la versión en Rutas de fabricación → Versiones.'
                  : (routeHeads.isEmpty
                        ? 'Este producto no tiene ninguna ruta de fabricación.'
                        : 'La ruta no tiene versiones.'))
            : null;
        final defaultBom = bomRows
            .where((e) => _map(e['_head'])['is_default'] == true)
            .toList();
        final defaultRoute = routeRows
            .where((e) => _map(e['_head'])['is_default'] == true)
            .toList();
        final selectedBom = defaultBom.isNotEmpty
            ? defaultBom.first
            : bomRows.isNotEmpty
            ? bomRows.first
            : null;
        bomRevisionId = selectedBom?['id']?.toString();
        final bomUomId = selectedBom?['output_uom_id']?.toString();
        if (bomUomId != null && bomUomId.isNotEmpty) uomId = bomUomId;
        routingRevisionId =
            (defaultRoute.isNotEmpty
                    ? defaultRoute.first
                    : routeRows.isNotEmpty
                    ? routeRows.first
                    : null)?['id']
                ?.toString();
        loadingRelations = false;
      });
      await _syncBomWithRoute(routingRevisionId);
    } catch (e) {
      if (mounted) {
        setState(() {
          loadingRelations = false;
          relationsError = e.toString();
        });
      }
    }
  }

  Map<String, dynamic>? _selectedBomRevision() {
    if (bomRevisionId == null) return null;
    for (final row in boms) {
      if (row['id']?.toString() == bomRevisionId) return row;
    }
    return null;
  }

  String? _selectedBomUomId() =>
      _selectedBomRevision()?['output_uom_id']?.toString();

  /// The route's steps consume components of one BOM version; that version is
  /// the structure this production order must follow.
  Future<String?> _bomFromRoute(String? routeRevisionId) async {
    if (routeRevisionId == null) return null;
    final generic = context.read<GenericRepository>();
    final validIds = {for (final b in boms) b['id']?.toString()};
    try {
      final ops = await generic.listRows(
        Phase1Schema.tables['routing_operations']!,
        filters: {'routing_revision_id': routeRevisionId},
      );
      for (final op in ops) {
        final materials = await generic.listRows(
          Phase1Schema.tables['routing_operation_materials']!,
          filters: {'routing_operation_id': op['id']},
        );
        for (final material in materials) {
          final itemId = material['bom_item_id'];
          if (itemId == null) continue;
          final items = await generic.listRows(
            Phase1Schema.tables['bom_items']!,
            filters: {'id': itemId},
          );
          final bomRevision = items.isEmpty
              ? null
              : items.first['bom_revision_id']?.toString();
          if (bomRevision != null && validIds.contains(bomRevision)) {
            return bomRevision;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _syncBomWithRoute(String? routeRevisionId) async {
    final derived = await _bomFromRoute(routeRevisionId);
    if (!mounted || derived == null || routingRevisionId != routeRevisionId) {
      return;
    }
    _selectBomRevision(derived);
  }

  void _selectBomRevision(String? value) {
    setState(() {
      bomRevisionId = value;
      final bomUomId = _selectedBomUomId();
      if (bomUomId != null && bomUomId.isNotEmpty) uomId = bomUomId;
    });
  }

  String _unitName(List<Map<String, dynamic>> units, String? id) {
    final matches = units.where((u) => u['id']?.toString() == id).toList();
    if (matches.isEmpty) return id ?? 'sin unidad';
    final unit = matches.first;
    return '${unit['name'] ?? 'Unidad'} (${unit['symbol'] ?? 's/símbolo'})';
  }

  String? _preparationError(List<Map<String, dynamic>> units) {
    if (!prepareAutomatically) return null;
    if (boms.isEmpty) {
      return 'No hay una estructura de fabricación activa para preparar la OP. Crea o activa una estructura de fabricación, o guarda la OP como borrador.';
    }
    if (routes.isEmpty) {
      return 'No hay una ruta de fabricación activa para preparar la OP. Crea o activa una ruta, o guarda la OP como borrador.';
    }
    if (bomRevisionId == null)
      return 'Selecciona una estructura de fabricación.';
    if (routingRevisionId == null) return 'Selecciona una ruta de fabricación.';
    final bomUomId = _selectedBomUomId();
    if (bomUomId != null && uomId != bomUomId) {
      return 'La unidad de la OP debe coincidir con la unidad de salida de la estructura de fabricación seleccionada: ${_unitName(units, bomUomId)}.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(LucideIcons.factory, size: 22, color: PomgtColors.ink),
        const SizedBox(width: 10),
        const Expanded(child: Text('Nueva orden de producción')),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(LucideIcons.x, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 760),
      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(height: 300, child: PomgtLoading());
          }
          final products =
              (snapshot.data?.first ?? const <Map<String, dynamic>>[])
                  .where(
                    (e) =>
                        e['is_manufacturable'] == true &&
                        e['is_active'] != false,
                  )
                  .toList();
          final units = snapshot.data != null && snapshot.data!.length > 1
              ? snapshot.data![1]
              : <Map<String, dynamic>>[];
          availableUnits = units;
          final categoryNames = {
            for (final c
                in snapshot.data != null && snapshot.data!.length > 2
                    ? snapshot.data![2]
                    : const <Map<String, dynamic>>[])
              c['id'].toString(): (c['name'] ?? '').toString(),
          };
          final bomUomId = _selectedBomUomId();
          return Form(
            key: form,
            child: ScrollToTopArea(
              padding: const EdgeInsets.all(12),
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'La OP puede crearse manualmente para producción interna, inventario, muestras, retrabajos o pruebas. POMGT congelará la estructura de fabricación y la ruta al prepararla.',
                      style: TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    CategorizedSearchPicker(
                      label: 'Producto a fabricar *',
                      hint: 'Buscar por SKU, nombre o categoría…',
                      value: productId,
                      items: [
                        for (final p in products)
                          PickerItem(
                            id: p['id'].toString(),
                            label: '${p['sku']} · ${p['name']}',
                            category:
                                categoryNames[p['category_id']?.toString()] ??
                                'Sin categoría',
                          ),
                      ],
                      onChanged: (value) => selectProduct(value, products),
                      validator: (v) =>
                          v == null ? 'Selecciona un producto.' : null,
                    ),
                    if (products.isEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'No existen productos activos marcados como fabricables. Crea o edita un producto antes de generar la OP.',
                        style: TextStyle(
                          color: PomgtColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            errorBuilder: pomgtValidationMessage,
                            controller: quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              ThousandsInputFormatter(allowNegative: false),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Cantidad planificada *',
                              hintText: 'Ej. 100',
                            ),
                            validator: (value) => (_n(value) <= 0)
                                ? 'Captura una cantidad mayor a cero.'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: CategorizedSearchPicker(
                            key: ValueKey('op-uom-${uomId ?? ''}'),
                            label: 'Unidad de medida *',
                            hint: 'Buscar unidad…',
                            helperText: bomUomId == null ? null : 'Sincronizada con la unidad de salida de la estructura de fabricación.',
                            value: uomId,
                            enabled: bomUomId == null,
                            items: [
                              for (final u in units)
                                PickerItem(
                                  id: u['id'].toString(),
                                  label: '${u['name']} (${u['symbol']})',
                                  category: 'Unidades',
                                ),
                            ],
                            onChanged: bomUomId == null
                                ? (value) => setState(() => uomId = value)
                                : (_) {},
                            validator: (v) {
                              if (v == null) return 'Selecciona una unidad.';
                              if (prepareAutomatically &&
                                  bomUomId != null &&
                                  v != bomUomId) {
                                return 'Debe coincidir con la unidad de salida de la estructura de fabricación.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            errorBuilder: pomgtValidationMessage,
                            initialValue: sourceType,
                            decoration: const InputDecoration(
                              labelText: 'Origen de producción',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'internal',
                                child: Text('Orden interna'),
                              ),
                              DropdownMenuItem(
                                value: 'stock_replenishment',
                                child: Text('Reposición de inventario'),
                              ),
                              DropdownMenuItem(
                                value: 'make_to_stock',
                                child: Text('Producción para inventario'),
                              ),
                              DropdownMenuItem(
                                value: 'sample',
                                child: Text('Muestra'),
                              ),
                              DropdownMenuItem(
                                value: 'rework',
                                child: Text('Retrabajo'),
                              ),
                              DropdownMenuItem(
                                value: 'test',
                                child: Text('Prueba'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => sourceType = value ?? 'internal',
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: CategorizedSearchPicker(
                            label: 'Prioridad',
                            hint: 'Buscar prioridad…',
                            value: priority,
                            items: [
                              for (final v in [
                                'low',
                                'normal',
                                'high',
                                'urgent',
                              ])
                                PickerItem(
                                  id: v,
                                  label: UiCopy.enumLabel(v),
                                  category: 'Prioridades',
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => priority = value ?? 'normal'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (loadingRelations)
                      const PomgtProgressIndicator(minHeight: 2),
                    if (productId != null && !loadingRelations) ...[
                      Row(
                        children: [
                          Expanded(
                            child: CategorizedSearchPicker(
                              label: 'Ruta de fabricación activa',
                              hint: 'Buscar ruta…',
                              value: routingRevisionId,
                              items: [
                                for (final r in routes)
                                  PickerItem(
                                    id: r['id'].toString(),
                                    label:
                                        '${_map(r['_head'])['routing_code']} · ${r['revision_code']} · ${_map(r['_head'])['name']}',
                                    category: 'Rutas',
                                  ),
                              ],
                              onChanged: (value) {
                                setState(() => routingRevisionId = value);
                                _syncBomWithRoute(value);
                              },
                            ),
                          ),
                        ],
                      ),
                      if (routeFromCategory) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Este producto no tiene una ruta propia: se está usando la ruta predeterminada de su categoría.',
                          style: TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (relationsError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'No se pudieron cargar las estructuras de fabricación y rutas: $relationsError',
                          style: const TextStyle(
                            color: PomgtColors.danger,
                            fontSize: 11.5,
                          ),
                        ),
                      ] else if (boms.isEmpty || routes.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${[if (bomHint != null) bomHint, if (routeHint != null) routeHint].join(' ')} Puedes guardar la OP como borrador, pero no podrá prepararse hasta completar la configuración del producto.',
                          style: const TextStyle(
                            color: PomgtColors.warning,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Inicio planificado',
                            value: plannedStartAt,
                            onChanged: (d) =>
                                setState(() => plannedStartAt = d),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _DateField(
                            label: 'Fin planificado',
                            value: plannedEndAt,
                            onChanged: (d) => setState(() => plannedEndAt = d),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _DateField(
                            label: 'Fecha requerida',
                            value: requiredAt,
                            onChanged: (d) => setState(() => requiredAt = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notas de producción',
                        hintText: 'Indicaciones para el equipo de piso…',
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Preparar automáticamente al crear',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Congela estructura de fabricación, ruta, operaciones, calidad y checklists. Si falta configuración, la creación mostrará el motivo exacto.',
                      ),
                      value: prepareAutomatically,
                      onChanged: (value) =>
                          setState(() => prepareAutomatically = value),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton.icon(
        icon: const Icon(LucideIcons.plus, size: 16),
        onPressed: () {
          if (!(form.currentState?.validate() ?? false) ||
              productId == null ||
              uomId == null)
            return;
          final preparationError = _preparationError(availableUnits);
          if (preparationError != null) {
            _showProductionNotice(
              context,
              title: 'Revisa la orden antes de continuar.',
              description: preparationError,
              isError: true,
            );
            return;
          }
          if (plannedStartAt != null &&
              plannedEndAt != null &&
              plannedEndAt!.isBefore(plannedStartAt!)) {
            _showProductionNotice(
              context,
              title: 'Fechas de planeación inválidas.',
              description:
                  'El fin planificado no puede ser anterior al inicio.',
              isError: true,
            );
            return;
          }
          Navigator.pop(
            context,
            _CreateProductionRequest(
              productId: productId!,
              quantity: _n(quantity.text),
              uomId: uomId,
              priority: priority,
              sourceType: sourceType,
              bomRevisionId: bomRevisionId,
              routingRevisionId: routingRevisionId,
              requiredAt: requiredAt,
              plannedStartAt: plannedStartAt,
              plannedEndAt: plannedEndAt,
              notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
              prepareAutomatically: prepareAutomatically,
            ),
          );
        },
        label: Text(
          prepareAutomatically ? 'Crear y preparar OP' : 'Crear borrador',
        ),
      ),
    ],
  );
}

class _CreateProductionRequest {
  const _CreateProductionRequest({
    required this.productId,
    required this.quantity,
    required this.uomId,
    required this.priority,
    required this.sourceType,
    required this.bomRevisionId,
    required this.routingRevisionId,
    required this.requiredAt,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.notes,
    required this.prepareAutomatically,
  });
  final String productId;
  final double quantity;
  final String? uomId;
  final String priority;
  final String sourceType;
  final String? bomRevisionId;
  final String? routingRevisionId;
  final DateTime? requiredAt;
  final DateTime? plannedStartAt;
  final DateTime? plannedEndAt;
  final String? notes;
  final bool prepareAutomatically;
}

class _CreateMultiProductionItem {
  const _CreateMultiProductionItem({
    required this.productId,
    required this.label,
    required this.quantity,
    required this.uomId,
  });
  final String productId;
  final String label;
  final double quantity;
  final String? uomId;
}

class _CreateMultiProductionRequest {
  const _CreateMultiProductionRequest({
    required this.items,
    required this.priority,
    required this.sourceType,
    required this.requiredAt,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.notes,
    required this.prepareAutomatically,
  });
  final List<_CreateMultiProductionItem> items;
  final String priority;
  final String sourceType;
  final DateTime? requiredAt;
  final DateTime? plannedStartAt;
  final DateTime? plannedEndAt;
  final String? notes;
  final bool prepareAutomatically;
}

enum _MultiCreateStatus { prepared, createdNotPrepared, createdDraft, failed }

class _MultiCreateOutcome {
  const _MultiCreateOutcome(
    this.label,
    this.status, {
    this.opNumber,
    this.error,
  });
  final String label;
  final _MultiCreateStatus status;
  final String? opNumber;
  final String? error;
}

class _MultiCreateResultsDialog extends StatelessWidget {
  const _MultiCreateResultsDialog({required this.outcomes});
  final List<_MultiCreateOutcome> outcomes;

  @override
  Widget build(BuildContext context) {
    final preparedCount = outcomes
        .where((o) => o.status == _MultiCreateStatus.prepared)
        .length;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.layers, size: 21, color: PomgtColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$preparedCount de ${outcomes.length} órdenes preparadas',
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(12),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final outcome in outcomes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          switch (outcome.status) {
                            _MultiCreateStatus.prepared =>
                              LucideIcons.circleCheck,
                            _MultiCreateStatus.createdDraft => LucideIcons.file,
                            _MultiCreateStatus.createdNotPrepared =>
                              LucideIcons.triangleAlert,
                            _MultiCreateStatus.failed => LucideIcons.circleX,
                          },
                          size: 18,
                          color: switch (outcome.status) {
                            _MultiCreateStatus.prepared => PomgtColors.success,
                            _MultiCreateStatus.createdDraft =>
                              PomgtColors.muted,
                            _MultiCreateStatus.createdNotPrepared =>
                              PomgtColors.warning,
                            _MultiCreateStatus.failed => PomgtColors.danger,
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                outcome.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                switch (outcome.status) {
                                  _MultiCreateStatus.prepared =>
                                    'OP ${outcome.opNumber} preparada.',
                                  _MultiCreateStatus.createdDraft =>
                                    'OP ${outcome.opNumber} creada en borrador.',
                                  _MultiCreateStatus.createdNotPrepared =>
                                    'OP ${outcome.opNumber} creada, pero no se pudo preparar: ${outcome.error}',
                                  _MultiCreateStatus.failed =>
                                    'No se pudo crear: ${outcome.error}',
                                },
                                style: const TextStyle(
                                  color: PomgtColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _CreateMultiProductionOrderDialog extends StatefulWidget {
  const _CreateMultiProductionOrderDialog();
  @override
  State<_CreateMultiProductionOrderDialog> createState() =>
      _CreateMultiProductionOrderDialogState();
}

class _CreateMultiProductionOrderDialogState
    extends State<_CreateMultiProductionOrderDialog> {
  final form = GlobalKey<FormState>();
  final notes = TextEditingController();
  String priority = 'normal';
  String sourceType = 'internal';
  DateTime? requiredAt;
  DateTime? plannedStartAt;
  DateTime? plannedEndAt;
  bool prepareAutomatically = true;
  final List<String> _selectedProductOrder = [];
  final Set<String> _selectedProductIds = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  String? _lineError;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _boms = const [];
  List<Map<String, dynamic>> _bomRevisions = const [];
  late Future<List<List<Map<String, dynamic>>>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final lookups = context.read<LookupRepository>();
    final data = await Future.wait([
      lookups.rows('products', refresh: true),
      lookups.rows('units_of_measure'),
      lookups.rows('product_categories'),
      lookups.rows('boms'),
      lookups.rows('bom_revisions'),
    ]);
    _products = data[0]
        .where((e) => e['is_manufacturable'] == true && e['is_active'] != false)
        .toList();
    _boms = data[3];
    _bomRevisions = data[4];
    return data;
  }

  @override
  void dispose() {
    notes.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleProduct(String productId) {
    setState(() {
      if (_selectedProductIds.remove(productId)) {
        _selectedProductOrder.remove(productId);
        _qtyControllers.remove(productId)?.dispose();
      } else {
        _selectedProductIds.add(productId);
        _selectedProductOrder.add(productId);
        _qtyControllers[productId] = TextEditingController(text: '1');
      }
      _lineError = null;
    });
  }

  Future<void> _linkBom(Map<String, dynamic> product) async {
    final created = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LinkBomDialog(product: product, activateRevision: true),
    );
    if (created != true || !mounted) return;
    final lookups = context.read<LookupRepository>();
    _boms = await lookups.rows('boms', refresh: true);
    _bomRevisions = await lookups.rows('bom_revisions', refresh: true);
    if (mounted) setState(() {});
  }

  bool _validate() {
    if (!(form.currentState?.validate() ?? false)) return false;
    if (_selectedProductIds.isEmpty) {
      setState(
        () => _lineError = 'Agrega al menos un producto con su cantidad.',
      );
      return false;
    }
    for (final id in _selectedProductIds) {
      final qty = parseNumberText(_qtyControllers[id]?.text);
      if (qty == null || qty <= 0) {
        setState(
          () => _lineError = 'Captura una cantidad válida para cada producto.',
        );
        return false;
      }
    }
    setState(() => _lineError = null);
    return true;
  }

  List<_CreateMultiProductionItem> _buildItems() => [
    for (final id in _selectedProductOrder)
      () {
        final product = _products.firstWhere(
          (p) => p['id'].toString() == id,
          orElse: () => const {},
        );
        return _CreateMultiProductionItem(
          productId: id,
          label: '${product['sku'] ?? '—'} · ${product['name'] ?? 'Producto'}',
          quantity: (parseNumberText(_qtyControllers[id]?.text) ?? 0)
              .toDouble(),
          uomId: product['base_uom_id']?.toString(),
        );
      }(),
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.layers, size: 22, color: PomgtColors.ink),
          const SizedBox(width: 10),
          const Expanded(child: Text('Nueva orden de producción múltiple')),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 760),
        child: FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 300, child: PomgtLoading());
            }
            final products = _products;
            final categories =
                snapshot.data != null && snapshot.data!.length > 2
                ? snapshot.data![2]
                : const <Map<String, dynamic>>[];
            final categoryNames = {
              for (final c in categories)
                c['id'].toString(): (c['name'] ?? '').toString(),
            };
            final missingBomProductIds = productIdsMissingActiveBom(
              _selectedProductOrder,
              boms: _boms,
              bomRevisions: _bomRevisions,
            );
            return Form(
              key: form,
              child: ScrollToTopArea(
                padding: const EdgeInsets.all(12),
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Selecciona varios productos para generar una orden de producción por cada uno, con una fecha y prioridad compartidas. La estructura de fabricación y la ruta de cada producto se resuelven automáticamente al preparar la OP.',
                        style: TextStyle(
                          color: PomgtColors.muted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                      MultiCategorizedPicker(
                        label: 'Buscar producto',
                        hint: 'Escribe el SKU o el nombre…',
                        items: [
                          for (final p in products)
                            PickerItem(
                              id: p['id'].toString(),
                              label: '${p['sku']} · ${p['name']}',
                              category:
                                  categoryNames[p['category_id']?.toString()] ??
                                  'Sin categoría',
                            ),
                        ],
                        selectedIds: _selectedProductIds,
                        onToggle: _toggleProduct,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Productos seleccionados (${_selectedProductOrder.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (_selectedProductOrder.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'Todavía no has agregado productos.',
                            style: TextStyle(color: PomgtColors.muted),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (final id in _selectedProductOrder)
                              Builder(
                                builder: (context) {
                                  final product = products.firstWhere(
                                    (p) => p['id'].toString() == id,
                                    orElse: () => const {},
                                  );
                                  return SelectedProductRow(
                                    product: product,
                                    controller: _qtyControllers[id]!,
                                    onRemove: () => _toggleProduct(id),
                                    missingBom: missingBomProductIds.contains(
                                      id,
                                    ),
                                    onLinkBom: () => _linkBom(product),
                                  );
                                },
                              ),
                          ],
                        ),
                      if (_lineError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _lineError!,
                          style: const TextStyle(
                            color: PomgtColors.danger,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              errorBuilder: pomgtValidationMessage,
                              initialValue: sourceType,
                              decoration: const InputDecoration(
                                labelText: 'Origen de producción',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'internal',
                                  child: Text('Orden interna'),
                                ),
                                DropdownMenuItem(
                                  value: 'stock_replenishment',
                                  child: Text('Reposición de inventario'),
                                ),
                                DropdownMenuItem(
                                  value: 'make_to_stock',
                                  child: Text('Producción para inventario'),
                                ),
                                DropdownMenuItem(
                                  value: 'sample',
                                  child: Text('Muestra'),
                                ),
                                DropdownMenuItem(
                                  value: 'rework',
                                  child: Text('Retrabajo'),
                                ),
                                DropdownMenuItem(
                                  value: 'test',
                                  child: Text('Prueba'),
                                ),
                              ],
                              onChanged: (value) => setState(
                                () => sourceType = value ?? 'internal',
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: CategorizedSearchPicker(
                              label: 'Prioridad',
                              hint: 'Buscar prioridad…',
                              value: priority,
                              items: [
                                for (final v in [
                                  'low',
                                  'normal',
                                  'high',
                                  'urgent',
                                ])
                                  PickerItem(
                                    id: v,
                                    label: UiCopy.enumLabel(v),
                                    category: 'Prioridades',
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => priority = value ?? 'normal'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'Inicio planificado',
                              value: plannedStartAt,
                              onChanged: (d) =>
                                  setState(() => plannedStartAt = d),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _DateField(
                              label: 'Fin planificado',
                              value: plannedEndAt,
                              onChanged: (d) =>
                                  setState(() => plannedEndAt = d),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: _DateField(
                              label: 'Fecha requerida',
                              value: requiredAt,
                              onChanged: (d) => setState(() => requiredAt = d),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notas de producción',
                          hintText: 'Indicaciones para el equipo de piso…',
                        ),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Preparar automáticamente al crear',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Cada OP se prepara con la estructura de fabricación y ruta activas del producto (o la de su categoría, si no tiene una propia). Si a algún producto le falta configuración, el resumen mostrará el motivo exacto sin afectar a los demás.',
                        ),
                        value: prepareAutomatically,
                        onChanged: (value) =>
                            setState(() => prepareAutomatically = value),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_validate()) return;
            Navigator.pop(
              context,
              _CreateMultiProductionRequest(
                items: _buildItems(),
                priority: priority,
                sourceType: sourceType,
                requiredAt: requiredAt,
                plannedStartAt: plannedStartAt,
                plannedEndAt: plannedEndAt,
                notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                prepareAutomatically: prepareAutomatically,
              ),
            );
          },
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Crear órdenes'),
        ),
      ],
    );
  }
}

class _PlanningDialog extends StatefulWidget {
  const _PlanningDialog({required this.order});
  final Map<String, dynamic> order;
  @override
  State<_PlanningDialog> createState() => _PlanningDialogState();
}

class _PlanningDialogState extends State<_PlanningDialog> {
  DateTime? start;
  DateTime? end;
  DateTime? required;
  late String priority;
  late final TextEditingController notes;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    start = _dt(widget.order['planned_start_at']);
    end = _dt(widget.order['planned_end_at']);
    required = _dt(widget.order['required_at']);
    priority = widget.order['priority']?.toString() ?? 'normal';
    notes = TextEditingController(
      text: widget.order['notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(LucideIcons.calendar, color: PomgtColors.ink, size: 21),
        const SizedBox(width: 10),
        const Expanded(child: Text('Planeación de la OP')),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: saving ? null : () => Navigator.pop(context, false),
          icon: const Icon(LucideIcons.x, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 620),
      child: ScrollToTopArea(
        padding: const EdgeInsets.all(12),
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 600;
                  final fieldWidth = wide
                      ? (constraints.maxWidth - 36) / 3
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 18,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: fieldWidth,
                        child: _DateField(
                          label: 'Inicio planificado',
                          value: start,
                          onChanged: (d) => setState(() => start = d),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: _DateField(
                          label: 'Fin planificado',
                          value: end,
                          onChanged: (d) => setState(() => end = d),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: _DateField(
                          label: 'Fecha requerida',
                          value: required,
                          onChanged: (d) => setState(() => required = d),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 15),
              CategorizedSearchPicker(
                label: 'Prioridad',
                hint: 'Buscar prioridad…',
                value: priority,
                items: [
                  for (final v in ['low', 'normal', 'high', 'urgent'])
                    PickerItem(
                      id: v,
                      label: UiCopy.enumLabel(v),
                      category: 'Prioridades',
                    ),
                ],
                onChanged: (v) => setState(() => priority = v ?? 'normal'),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  hintText: 'Contexto administrativo…',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (start != null && end != null && end!.isBefore(start!)) {
                  _showProductionNotice(
                    context,
                    title: 'Fechas de planeación inválidas.',
                    description:
                        'El fin planificado no puede ser anterior al inicio.',
                    isError: true,
                  );
                  return;
                }
                setState(() => saving = true);
                try {
                  await context.read<ProductionRepository>().updatePlanning(
                    widget.order['id'].toString(),
                    plannedStartAt: start,
                    plannedEndAt: end,
                    requiredAt: required,
                    priority: priority,
                    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!context.mounted) return;
                  setState(() => saving = false);
                  _showProductionError(context, e);
                }
              },
        child: const Text('Guardar planeación'),
      ),
    ],
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final day = await showPomgtDatePicker(
        context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (day == null || !context.mounted) return;
      final time = await showPomgtTimePicker(
        context,
        initialTime: value == null
            ? TimeOfDay.now()
            : TimeOfDay.fromDateTime(value!),
      );
      if (time == null) {
        onChanged(DateTime(day.year, day.month, day.day));
      } else {
        onChanged(
          DateTime(day.year, day.month, day.day, time.hour, time.minute),
        );
      }
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(LucideIcons.calendar, size: 17),
      ),
      child: Text(
        value == null ? 'Sin definir' : _dateTime(value!.toIso8601String()),
        style: TextStyle(
          color: value == null ? PomgtColors.muted : PomgtColors.ink,
          fontSize: 12.5,
        ),
      ),
    ),
  );
}

class _MaterialMovementDialog extends StatefulWidget {
  const _MaterialMovementDialog({required this.materialName});
  final String materialName;
  @override
  State<_MaterialMovementDialog> createState() =>
      _MaterialMovementDialogState();
}

class _MaterialMovementDialogState extends State<_MaterialMovementDialog> {
  String type = 'issue';
  final quantity = TextEditingController();
  final lot = TextEditingController();
  final warehouse = TextEditingController();
  final note = TextEditingController();
  @override
  void dispose() {
    quantity.dispose();
    lot.dispose();
    warehouse.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(LucideIcons.layers, color: PomgtColors.ink, size: 21),
        const SizedBox(width: 10),
        const Expanded(child: Text('Registrar movimiento de material')),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(LucideIcons.x, size: 20),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 540),
      child: ScrollToTopArea(
        padding: const EdgeInsets.all(12),
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.materialName,
                style: const TextStyle(color: PomgtColors.muted),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                errorBuilder: pomgtValidationMessage,
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Movimiento'),
                items: const [
                  DropdownMenuItem(
                    value: 'issue',
                    child: Text('Surtido a producción'),
                  ),
                  DropdownMenuItem(value: 'consume', child: Text('Consumo')),
                  DropdownMenuItem(value: 'return', child: Text('Devolución')),
                  DropdownMenuItem(value: 'scrap', child: Text('Merma')),
                  DropdownMenuItem(value: 'adjustment', child: Text('Ajuste')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'issue'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [
                  ThousandsInputFormatter(allowNegative: false),
                ],
                decoration: const InputDecoration(
                  labelText: 'Cantidad *',
                  hintText: 'Ej. 1',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: _responsiveDialogWidth(context, 540) < 540
                        ? double.infinity
                        : 261,
                    child: TextField(
                      controller: lot,
                      decoration: const InputDecoration(
                        labelText: 'Lote / serie',
                        hintText: 'Ej. L-2026-001',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _responsiveDialogWidth(context, 540) < 540
                        ? double.infinity
                        : 261,
                    child: TextField(
                      controller: warehouse,
                      decoration: const InputDecoration(
                        labelText: 'Almacén / ubicación',
                        hintText: 'Ej. Almacén 1',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  hintText: 'Observaciones del movimiento…',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final q = _n(quantity.text);
          if (q <= 0) return;
          Navigator.pop(
            context,
            _MaterialMovementRequest(
              type,
              q,
              _nullable(lot.text),
              _nullable(warehouse.text),
              _nullable(note.text),
            ),
          );
        },
        child: const Text('Registrar movimiento'),
      ),
    ],
  );
}

class _MaterialMovementRequest {
  const _MaterialMovementRequest(
    this.type,
    this.quantity,
    this.lot,
    this.warehouse,
    this.note,
  );
  final String type;
  final double quantity;
  final String? lot;
  final String? warehouse;
  final String? note;
}

class _QualityDialog extends StatefulWidget {
  const _QualityDialog({required this.check});
  final Map<String, dynamic> check;
  @override
  State<_QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends State<_QualityDialog> {
  final value = TextEditingController();
  final note = TextEditingController();
  bool? booleanValue;
  String? selectValue;
  String? forceStatus;

  @override
  void initState() {
    super.initState();
    final current = widget.check['result_value'];
    if (current != null)
      value.text = current is String
          ? current
          : current.toString().replaceAll('"', '');
  }

  @override
  void dispose() {
    value.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.check['check_type']?.toString() ?? 'text';
    final allowed = _jsonList(widget.check['allowed_values']);
    Widget field;
    if (type == 'boolean') {
      field = DropdownButtonFormField<bool>(
        errorBuilder: pomgtValidationMessage,
        initialValue: booleanValue,
        decoration: const InputDecoration(
          labelText: 'Resultado *',
          hintText: 'Selecciona una opción',
        ),
        items: const [
          DropdownMenuItem(value: true, child: Text('Sí / Conforme')),
          DropdownMenuItem(value: false, child: Text('No / No conforme')),
        ],
        onChanged: (v) => setState(() => booleanValue = v),
      );
    } else if (type == 'select' && allowed.isNotEmpty) {
      field = CategorizedSearchPicker(
        label: 'Resultado *',
        hint: 'Buscar resultado…',
        value: selectValue,
        items: [
          for (final e in allowed)
            PickerItem(id: e, label: e, category: 'Opciones'),
        ],
        onChanged: (v) => setState(() => selectValue = v),
      );
    } else {
      field = TextField(
        controller: value,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: type == 'number'
            ? const [ThousandsInputFormatter(allowNegative: true)]
            : null,
        decoration: InputDecoration(
          labelText: type == 'number' ? 'Valor medido *' : 'Resultado *',
          hintText: type == 'number' ? 'Ej. 0' : 'Escribe el resultado',
        ),
      );
    }
    return AlertDialog(
      title: pomgtDialogTitle(context, 'Registrar control de calidad'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 540),
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(12),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.check['name']?.toString() ?? 'Control',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _qualityLimits(widget.check),
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                  ),
                ),
                if ((widget.check['instructions']?.toString() ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.check['instructions'].toString(),
                    style: const TextStyle(
                      color: PomgtColors.secondaryInk,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                field,
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  errorBuilder: pomgtValidationMessage,
                  initialValue: forceStatus,
                  decoration: const InputDecoration(
                    labelText: 'Resultado manual (opcional)',
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Evaluar automáticamente'),
                    ),
                    DropdownMenuItem(value: 'passed', child: Text('Aprobado')),
                    DropdownMenuItem(value: 'failed', child: Text('Rechazado')),
                    DropdownMenuItem(
                      value: 'not_applicable',
                      child: Text('No aplica'),
                    ),
                  ],
                  onChanged: (v) => setState(() => forceStatus = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    hintText: 'Detalles adicionales…',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            dynamic result;
            if (type == 'boolean')
              result = booleanValue;
            else if (type == 'select')
              result = selectValue;
            else if (type == 'number')
              result = parseNumberText(value.text)?.toDouble();
            else
              result = value.text.trim();
            if (result == null || (result is String && result.isEmpty)) return;
            Navigator.pop(
              context,
              _QualityCapture(result, _nullable(note.text), forceStatus),
            );
          },
          child: const Text('Guardar resultado'),
        ),
      ],
    );
  }
}

class _QualityCapture {
  const _QualityCapture(this.value, this.note, this.forceStatus);
  final dynamic value;
  final String? note;
  final String? forceStatus;
}

class _ChecklistDialog extends StatefulWidget {
  const _ChecklistDialog({required this.item});
  final Map<String, dynamic> item;
  @override
  State<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends State<_ChecklistDialog> {
  final value = TextEditingController();
  final note = TextEditingController();
  bool? boolValue;
  String? selectValue;
  @override
  void dispose() {
    value.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.item['response_type']?.toString() ?? 'text';
    final allowed = _jsonList(widget.item['allowed_values']);
    Widget field;
    if (type == 'boolean') {
      field = DropdownButtonFormField<bool>(
        errorBuilder: pomgtValidationMessage,
        initialValue: boolValue,
        decoration: const InputDecoration(
          labelText: 'Respuesta *',
          hintText: 'Selecciona una opción',
        ),
        items: const [
          DropdownMenuItem(value: true, child: Text('Sí')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: (v) => setState(() => boolValue = v),
      );
    } else if (type == 'select' && allowed.isNotEmpty) {
      field = CategorizedSearchPicker(
        label: 'Respuesta *',
        hint: 'Buscar respuesta…',
        value: selectValue,
        items: [
          for (final e in allowed)
            PickerItem(id: e, label: e, category: 'Opciones'),
        ],
        onChanged: (v) => setState(() => selectValue = v),
      );
    } else {
      field = TextField(
        controller: value,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: type == 'number'
            ? const [ThousandsInputFormatter(allowNegative: true)]
            : null,
        decoration: InputDecoration(
          labelText: 'Respuesta *',
          hintText: type == 'number' ? 'Ej. 0' : 'Escribe la respuesta',
        ),
      );
    }
    return AlertDialog(
      title: pomgtDialogTitle(context, 'Responder verificación'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 520),
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(12),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.item['prompt']?.toString() ?? 'Verificación',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if ((widget.item['instructions']?.toString() ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    widget.item['instructions'].toString(),
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 15),
                field,
                const SizedBox(height: 14),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    hintText: 'Observaciones adicionales…',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            dynamic response;
            if (type == 'boolean')
              response = boolValue;
            else if (type == 'select')
              response = selectValue;
            else if (type == 'number')
              response = parseNumberText(value.text)?.toDouble();
            else
              response = value.text.trim();
            if (response == null || (response is String && response.isEmpty))
              return;
            Navigator.pop(
              context,
              _ChecklistCapture(response, _nullable(note.text)),
            );
          },
          child: const Text('Guardar respuesta'),
        ),
      ],
    );
  }
}

class _ChecklistCapture {
  const _ChecklistCapture(this.value, this.note);
  final dynamic value;
  final String? note;
}

class _CostDialog extends StatefulWidget {
  const _CostDialog({required this.costs});
  final Map<String, dynamic> costs;
  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  final controllers = <String, TextEditingController>{};
  bool saving = false;
  static const fields = [
    ['estimated_material', 'Material estimado'],
    ['actual_material', 'Material real'],
    ['estimated_labor', 'Mano de obra estimada'],
    ['actual_labor', 'Mano de obra real'],
    ['estimated_machine', 'Máquina estimada'],
    ['actual_machine', 'Máquina real'],
    ['estimated_subcontract', 'Subcontrato estimado'],
    ['actual_subcontract', 'Subcontrato real'],
    ['estimated_overhead', 'Indirectos estimados'],
    ['actual_overhead', 'Indirectos reales'],
  ];
  @override
  void initState() {
    super.initState();
    for (final field in fields)
      controllers[field[0]] = TextEditingController(
        text: formatNumberText(_n(widget.costs[field[0]]).toStringAsFixed(2)),
      );
  }

  @override
  void dispose() {
    for (final c in controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: pomgtDialogTitle(context, 'Actualizar costos de la OP'),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 680),
      child: ScrollToTopArea(
        padding: const EdgeInsets.all(12),
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 660;
              return Wrap(
                spacing: 18,
                runSpacing: 14,
                children: [
                  for (final field in fields)
                    SizedBox(
                      width: wide
                          ? (constraints.maxWidth - 18) / 2
                          : constraints.maxWidth,
                      child: TextField(
                        controller: controllers[field[0]],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [
                          ThousandsInputFormatter(allowNegative: true),
                        ],
                        decoration: InputDecoration(labelText: field[1]),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() => saving = true);
                try {
                  await context.read<ProductionRepository>().updateCosts(
                    widget.costs['id'].toString(),
                    estimatedMaterial: _n(
                      controllers['estimated_material']!.text,
                    ),
                    actualMaterial: _n(controllers['actual_material']!.text),
                    estimatedLabor: _n(controllers['estimated_labor']!.text),
                    actualLabor: _n(controllers['actual_labor']!.text),
                    estimatedMachine: _n(
                      controllers['estimated_machine']!.text,
                    ),
                    actualMachine: _n(controllers['actual_machine']!.text),
                    estimatedSubcontract: _n(
                      controllers['estimated_subcontract']!.text,
                    ),
                    actualSubcontract: _n(
                      controllers['actual_subcontract']!.text,
                    ),
                    estimatedOverhead: _n(
                      controllers['estimated_overhead']!.text,
                    ),
                    actualOverhead: _n(controllers['actual_overhead']!.text),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                } catch (e) {
                  if (!context.mounted) return;
                  setState(() => saving = false);
                  _showProductionError(context, e);
                }
              },
        child: const Text('Guardar costos'),
      ),
    ],
  );
}

Future<double?> _quantityDialog(
  BuildContext context, {
  required String title,
  required String label,
  required double initial,
}) async {
  final controller = TextEditingController(text: _fmt(initial));
  final result = await showPomgtDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: pomgtDialogTitle(context, title),
      content: SizedBox(
        width: _responsiveDialogWidth(dialogContext, 420),
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [
            ThousandsInputFormatter(allowNegative: false),
          ],
          decoration: InputDecoration(labelText: label),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final q = _n(controller.text);
            if (q > 0) Navigator.pop(context, q);
          },
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body, {
  required String confirm,
}) async =>
    await showPomgtDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          title,
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Regresar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic value) => value is List
    ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
    : <Map<String, dynamic>>[];
double _n(dynamic value) {
  if (value is num) return value.toDouble();
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return 0;
  return double.tryParse(text.replaceAll(',', '')) ?? 0;
}

String _fmt(dynamic value) {
  final n = _n(value);
  if (n == n.roundToDouble()) return formatNumberText(n.toInt());
  return formatNumberText(
    n
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), ''),
  );
}

String _show(dynamic value) =>
    value == null || value.toString().trim().isEmpty ? '—' : value.toString();

double _responsiveDialogWidth(BuildContext context, double maxWidth) {
  final available = MediaQuery.sizeOf(context).width - 56;
  if (available <= 0) return maxWidth;
  return available < maxWidth ? available : maxWidth;
}

String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
DateTime? _dt(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
String _date(dynamic value) {
  final d = _dt(value);
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _dateTime(dynamic value) {
  final d = _dt(value);
  if (d == null) return '—';
  return '${_date(d.toIso8601String())} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _sourceLabel(dynamic value) {
  switch (value?.toString()) {
    case 'customer_order':
      return 'Pedido de cliente';
    case 'internal':
      return 'Orden interna';
    case 'stock_replenishment':
      return 'Reposición de inventario';
    case 'make_to_stock':
      return 'Producción para inventario';
    case 'sample':
      return 'Muestra';
    case 'rework':
      return 'Retrabajo';
    case 'test':
      return 'Prueba';
    default:
      return 'Producción interna';
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'completed':
    case 'passed':
    case 'active':
      return PomgtColors.success;
    case 'in_progress':
    case 'ready':
      return PomgtColors.blue;
    case 'on_hold':
    case 'failed':
    case 'urgent':
      return PomgtColors.danger;
    case 'planned':
    case 'draft':
    case 'pending':
    case 'high':
      return PomgtColors.warning;
    case 'cancelled':
    case 'skipped':
      return PomgtColors.subtle;
    default:
      return PomgtColors.muted;
  }
}

String _operationTime(Map<String, dynamic> row) {
  final basis = row['run_time_basis']?.toString();
  if (basis == 'fixed') return '${_fmt(row['run_time_value'])} min';
  if (basis == 'per_unit') return '${_fmt(row['run_time_value'])} min / unidad';
  if (basis == 'formula')
    return row['run_time_formula']?.toString() ?? 'Fórmula';
  return '—';
}

String _qualityLimits(Map<String, dynamic> row) {
  if (row['check_type'] == 'number') {
    final min = row['lower_limit'];
    final max = row['upper_limit'];
    final target = row['target_value'];
    if (min != null || max != null) return '${min ?? '—'} a ${max ?? '—'}';
    if (target != null) return 'Objetivo: $target';
  }
  return UiCopy.enumLabel(row['check_type']?.toString() ?? 'Control');
}

List<String> _jsonList(dynamic value) {
  if (value == null) return const [];
  if (value is List) return value.map((e) => e.toString()).toList();
  if (value is String) {
    try {
      final d = jsonDecode(value);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return const [];
}

String _movementLabel(dynamic type) {
  switch (type?.toString()) {
    case 'issue':
      return 'Surtido a producción';
    case 'consume':
      return 'Consumo';
    case 'return':
      return 'Devolución';
    case 'scrap':
      return 'Merma';
    case 'adjustment':
      return 'Ajuste';
    default:
      return 'Movimiento de material';
  }
}

String _eventLabel(dynamic type) =>
    type?.toString().replaceAll('_', ' ') ?? 'Actividad';
double _costTotal(Map<String, dynamic> row, String prefix) =>
    _n(row['${prefix}_material']) +
    _n(row['${prefix}_labor']) +
    _n(row['${prefix}_machine']) +
    _n(row['${prefix}_subcontract']) +
    _n(row['${prefix}_overhead']);
