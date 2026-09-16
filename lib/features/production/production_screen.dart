import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/organization_controller.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/pdf_download.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/production_repository.dart';
import '../../data/services/production_order_pdf_service.dart';
import 'production_operator_display.dart' show ProductionOperatorDisplay;

void _showProductionNotice(
  BuildContext context, {
  required String title,
  required String description,
  bool isError = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  Timer? timer;
  void close() {
    timer?.cancel();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      final media = MediaQuery.of(context);
      final width = media.size.width < 480 ? media.size.width - 28 : 420.0;
      return Positioned(
        top: media.padding.top + 18,
        right: 14,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset((1 - value) * 18, 0),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: width),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PomgtColors.ink,
                  border: Border.all(
                    color: (isError ? PomgtColors.danger : PomgtColors.blue)
                        .withValues(alpha: .35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isError
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.bell_fill,
                        color: isError ? PomgtColors.rose : PomgtColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PomgtColors.subtle,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Cerrar',
                        child: IconButton(
                          onPressed: close,
                          icon: const Icon(CupertinoIcons.xmark, size: 16),
                          color: Colors.white,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  timer = Timer(const Duration(seconds: 4), close);
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
  String? _selectedId;

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
    final result = await showDialog<_CreateProductionRequest>(
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

  Future<void> _edit(Map<String, dynamic> row) async {
    final changed = await showDialog<bool>(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar orden de producción'),
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
        Phase1Schema.tables['production_orders']!,
        row,
      );
      if (!mounted) return;
      _selectedId = null;
      _reload();
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
          final query = _search.trim().toLowerCase();
          final rows = all.where((row) {
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
                _ProductionTitle(onCreate: _create),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
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
                                      key: ValueKey(
                                        '${selected['id']}-${context.watch<ProductionController>().revision}',
                                      ),
                                      orderId: selected['id'].toString(),
                                      onChanged: () => _reload(
                                        select: selected['id'].toString(),
                                      ),
                                    ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(
                            width: constraints.maxWidth >= 1450 ? 360 : 320,
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
                                    key: ValueKey(
                                      '${selected['id']}-${context.watch<ProductionController>().revision}',
                                    ),
                                    orderId: selected['id'].toString(),
                                    onChanged: () => _reload(
                                      select: selected['id'].toString(),
                                    ),
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
  const _ProductionTitle({required this.onCreate});
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
              children: const [
                Text(
                  'Producción',
                  style: TextStyle(
                    color: PomgtColors.ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.8,
                  ),
                ),
                SizedBox(width: 8),
                InfoTip(
                  'Centro operativo de las órdenes de producción. Conecta pedido, producto, lista de materiales, ruta, ejecución, calidad, costos, documentos y trazabilidad.',
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
        ),
      ),
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(CupertinoIcons.add, size: 18),
        label: const Text('Nueva Orden de Producción'),
      ),
    ],
  );
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
        border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .6)),
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
                  prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 46),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Actualizar',
                    onPressed: onRefresh,
                    icon: const Icon(CupertinoIcons.refresh, size: 17),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: DropdownButtonFormField<String>(
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
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: loading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
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
                : ListView.builder(
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
                                      CupertinoIcons.gear_alt,
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
                                        fontWeight: FontWeight.w900,
                                      ),
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
                              const SizedBox(height: 6),
                              Text(
                                '${row['product_sku'] ?? '—'} · ${row['product_name'] ?? 'Producto'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.secondaryInk,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
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
                                    child: LinearProgressIndicator(
                                      value: (progress / 100).clamp(0, 1),
                                      minHeight: 3,
                                      backgroundColor: PomgtColors.line,
                                      valueColor: const AlwaysStoppedAnimation(
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
                                      fontWeight: FontWeight.w800,
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
      border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .6)),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.precision_manufacturing_outlined,
            size: 28,
            color: PomgtColors.muted,
          ),
          SizedBox(height: 12),
          Text(
            'Selecciona una orden de producción',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 5),
          Text(
            'El expediente operativo completo aparecerá aquí.',
            style: TextStyle(color: PomgtColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _ProductionDetail extends StatefulWidget {
  const _ProductionDetail({
    super.key,
    required this.orderId,
    required this.onChanged,
  });
  final String orderId;
  final VoidCallback onChanged;

  @override
  State<_ProductionDetail> createState() => _ProductionDetailState();
}

class _ProductionDetailState extends State<_ProductionDetail> {
  late Future<Map<String, dynamic>> _future;
  int _tab = 0;
  bool _busy = false;

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
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = repository.detail(widget.orderId);
    });
    widget.onChanged();
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

  Future<void> _previewPdf() async {
    try {
      final data = await repository.detail(widget.orderId);
      final order = _map(data['order']);
      final generatedBytes = await pdf.buildFromData(data);
      if (generatedBytes.isEmpty) {
        throw StateError('El PDF se generó vacío. Intenta nuevamente.');
      }
      final sourceBytes = Uint8List.fromList(generatedBytes);
      final number = order['op_number']?.toString().trim();
      final filename =
          '${number == null || number.isEmpty ? 'OP' : number}.pdf';
      if (!mounted) return;
      await showDialog<void>(
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
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.doc_text,
                        color: PomgtColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text(
                          'Vista previa de la orden de producción',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Printing.layoutPdf(
                            name: filename,
                            onLayout: (_) async =>
                                Uint8List.fromList(sourceBytes),
                          );
                        },
                        icon: const Icon(CupertinoIcons.printer, size: 16),
                        label: const Text('Imprimir'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await downloadPdfFile(
                            bytes: Uint8List.fromList(sourceBytes),
                            filename: filename,
                          );
                        },
                        icon: const Icon(
                          CupertinoIcons.arrow_down_doc,
                          size: 16,
                        ),
                        label: const Text('Descargar'),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(CupertinoIcons.xmark),
                      ),
                    ],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.surface,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .6)),
        boxShadow: PomgtShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
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
          return Column(
            children: [
              _ProductionHero(
                data: data,
                onPrepare:
                    !_busy &&
                        (order['status'] == 'draft' ||
                            order['status'] == 'planned')
                    ? () => _action(
                        () => repository.prepare(widget.orderId),
                        'Orden preparada correctamente.',
                      )
                    : null,
                onStart: !_busy && order['status'] == 'ready'
                    ? () => _action(
                        () => repository.transitionOrder(
                          widget.orderId,
                          'in_progress',
                        ),
                        'Producción iniciada.',
                      )
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
                        !['completed', 'cancelled'].contains(order['status'])
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
                onPlan: () async {
                  final changed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _PlanningDialog(order: order),
                  );
                  if (changed == true && mounted) _reload();
                },
                onOperatorDisplay: () async {
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
                  if (mounted) _reload();
                },
                onPreviewPdf: _previewPdf,
                onSavePdf: () => _action(
                  () => pdf.saveAsDocument(widget.orderId),
                  'PDF guardado en Documentos y vinculado a la OP.',
                ),
              ),
              _ProductionKpis(data: data),
              _ProductionTabs(
                selected: _tab,
                onChanged: (value) => setState(() => _tab = value),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _SummaryTab(data: data),
                    _OperationsTab(data: data, onChanged: _reload),
                    _MaterialsTab(data: data, onChanged: _reload),
                    _QualityTab(data: data, onChanged: _reload),
                    _CostsTab(data: data, onChanged: _reload),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: LinkedDocumentsPanel(
                        entityField: 'production_order_id',
                        entityId: widget.orderId,
                        title: 'Documentos de la orden de producción',
                        help:
                            'Instructivos, artes, especificaciones, evidencia fotográfica, certificados, reportes y PDFs generados por POMGT.',
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
            ],
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
    required this.onPlan,
    required this.onOperatorDisplay,
    required this.onPreviewPdf,
    required this.onSavePdf,
  });
  final Map<String, dynamic> data;
  final VoidCallback? onPrepare;
  final VoidCallback? onStart;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback onPlan;
  final VoidCallback onOperatorDisplay;
  final VoidCallback onPreviewPdf;
  final VoidCallback onSavePdf;

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
                        fontWeight: FontWeight.w900,
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
                icon: const Icon(CupertinoIcons.calendar, size: 16),
                label: const Text('Planeación'),
              ),
              FilledButton.icon(
                onPressed: onOperatorDisplay,
                icon: const Icon(Icons.smart_display_outlined, size: 17),
                label: const Text('Display operador'),
              ),
              PopupMenuButton<String>(
                tooltip: 'PDF y documentos',
                icon: const Icon(CupertinoIcons.doc_text, size: 18),
                onSelected: (value) {
                  if (value == 'preview') onPreviewPdf();
                  if (value == 'save') onSavePdf();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'preview',
                    child: Text('Previsualizar / imprimir PDF'),
                  ),
                  PopupMenuItem(
                    value: 'save',
                    child: Text('Guardar PDF en Documentos'),
                  ),
                ],
              ),
              if (onPrepare != null)
                FilledButton.icon(
                  onPressed: onPrepare,
                  icon: const Icon(Icons.inventory_2_outlined, size: 17),
                  label: const Text('Preparar OP'),
                ),
              if (onStart != null)
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(CupertinoIcons.play, size: 17),
                  label: const Text('Iniciar producción'),
                ),
              if (onPause != null)
                OutlinedButton.icon(
                  onPressed: onPause,
                  icon: const Icon(CupertinoIcons.pause, size: 17),
                  label: const Text('Pausar'),
                ),
              if (onResume != null)
                FilledButton.icon(
                  onPressed: onResume,
                  icon: const Icon(CupertinoIcons.play, size: 17),
                  label: const Text('Reanudar'),
                ),
              if (onComplete != null)
                FilledButton.icon(
                  onPressed: onComplete,
                  icon: const Icon(CupertinoIcons.check_mark, size: 17),
                  label: const Text('Completar'),
                ),
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
                onSelected: (value) {
                  if (value == 'cancel' && onCancel != null) onCancel!();
                },
                itemBuilder: (_) => [
                  if (onCancel != null)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text(
                        'Cancelar orden',
                        style: TextStyle(color: PomgtColors.danger),
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
        Icons.numbers_outlined,
      ),
      _KpiData(
        'Avance',
        '${_fmt(order['progress_pct'])}%',
        CupertinoIcons.chart_bar,
      ),
      _KpiData(
        'Operaciones',
        '$completedOps / ${operations.length}',
        Icons.account_tree_outlined,
      ),
      _KpiData('Materiales', '${materials.length}', Icons.layers_outlined),
      _KpiData(
        'Calidad pendiente',
        '$pendingQuality',
        Icons.fact_check_outlined,
      ),
      _KpiData('Verificaciones', '$pendingChecklist', Icons.checklist_outlined),
      _KpiData(
        'Fecha requerida',
        _date(order['required_at']),
        CupertinoIcons.calendar,
      ),
      _KpiData(
        'Costo real',
        '${costs['currency_code'] ?? 'MXN'} \$${totalCost.toStringAsFixed(2)}',
        Icons.payments_outlined,
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
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.muted,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
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
                  child: Container(
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
                            ? FontWeight.w900
                            : FontWeight.w700,
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
  const _SummaryTab({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final product = _map(data['product']);
    final customer = _map(data['customer']);
    final customerOrder = _map(data['customer_order']);
    final operations = _list(data['operations']);
    final materials = _list(data['materials']);
    final events = _list(data['events']);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 980;
          final left = Column(
            children: [
              _Panel(
                title: 'Información de la orden',
                icon: Icons.precision_manufacturing_outlined,
                child: _InfoGrid(
                  items: [
                    _Info('Número de OP', order['op_number']),
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
              _Panel(
                title: 'Estructura congelada de fabricación',
                icon: Icons.account_tree_outlined,
                child: _InfoGrid(
                  items: [
                    _Info(
                      'BOM / Lista de materiales',
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
                icon: CupertinoIcons.doc_plaintext,
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
                icon: CupertinoIcons.clock,
                child: events.isEmpty
                    ? const _EmptyText('No hay actividad registrada todavía.')
                    : Column(
                        children: [
                          for (final event in events.take(6))
                            _TimelineRow(
                              title: event['title']?.toString() ?? 'Actividad',
                              subtitle: event['description']?.toString() ?? '',
                              date: _dateTime(event['occurred_at']),
                              color: PomgtColors.blue,
                            ),
                        ],
                      ),
              ),
            ],
          );
          if (!horizontal) {
            return Column(children: [left, const SizedBox(height: 14), right]);
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
    );
  }
}

class _OperationsTab extends StatelessWidget {
  const _OperationsTab({required this.data, required this.onChanged});
  final Map<String, dynamic> data;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rows = _list(data['operations']);
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
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final row = rows[index];
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
          icon: Icons.route_outlined,
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
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'ready')
                    FilledButton.icon(
                      onPressed: () => _operationAction(
                        context,
                        operationId,
                        'in_progress',
                        onChanged,
                      ),
                      icon: const Icon(CupertinoIcons.play, size: 16),
                      label: const Text('Iniciar operación'),
                    ),
                  if (status == 'in_progress') ...[
                    OutlinedButton.icon(
                      onPressed: () => _operationAction(
                        context,
                        operationId,
                        'on_hold',
                        onChanged,
                      ),
                      icon: const Icon(CupertinoIcons.pause, size: 16),
                      label: const Text('Pausar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final result = await showDialog<_OperationCompletion>(
                          context: context,
                          builder: (_) =>
                              _CompleteOperationDialog(operation: row),
                        );
                        if (result == null || !context.mounted) return;
                        await _operationAction(
                          context,
                          operationId,
                          'completed',
                          onChanged,
                          completed: result.completed,
                          rejected: result.rejected,
                          note: result.note,
                        );
                      },
                      icon: const Icon(CupertinoIcons.check_mark, size: 16),
                      label: const Text('Completar operación'),
                    ),
                  ],
                  if (status == 'on_hold')
                    FilledButton.icon(
                      onPressed: () => _operationAction(
                        context,
                        operationId,
                        'in_progress',
                        onChanged,
                      ),
                      icon: const Icon(CupertinoIcons.play, size: 16),
                      label: const Text('Reanudar'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _operationAction(
    BuildContext context,
    String operationId,
    String status,
    VoidCallback onChanged, {
    double? completed,
    double? rejected,
    String? note,
  }) async {
    try {
      await context.read<ProductionRepository>().transitionOperation(
        operationId,
        status,
        completedQuantity: completed,
        rejectedQuantity: rejected,
        note: note,
      );
      if (!context.mounted) return;
      onChanged();
      _showProductionSuccess(
        context,
        status == 'completed'
            ? 'Operación completada.'
            : 'Operación actualizada.',
      );
    } catch (e) {
      if (!context.mounted) return;
      _showProductionError(context, e);
    }
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
          'No hay materiales congelados. Prepara la OP para calcular los requerimientos del BOM.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Panel(
          title: 'Materiales requeridos para la orden',
          icon: Icons.layers_outlined,
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
                                await showDialog<_MaterialMovementRequest>(
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
          icon: CupertinoIcons.arrow_right_arrow_left,
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Panel(
          title: 'Controles de calidad',
          icon: Icons.fact_check_outlined,
          child: quality.isEmpty
              ? const _EmptyText(
                  'La ruta de esta OP no contiene controles de calidad.',
                )
              : Column(
                  children: [
                    for (final row in quality)
                      _QualityRow(
                        row: row,
                        operation: operations[row['operation_id']?.toString()],
                        onCapture: () async {
                          final result = await showDialog<_QualityCapture>(
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
          icon: Icons.checklist_outlined,
          child: checklist.isEmpty
              ? const _EmptyText(
                  'La ruta de esta OP no contiene listas de verificación.',
                )
              : Column(
                  children: [
                    for (final row in checklist)
                      _ChecklistRow(
                        row: row,
                        operation: operations[row['operation_id']?.toString()],
                        onCapture: () async {
                          final response = await showDialog<_ChecklistCapture>(
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Panel(
          title: 'Costo estimado vs. real',
          icon: Icons.payments_outlined,
          trailing: TextButton.icon(
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => _CostDialog(costs: costs),
              );
              if (changed == true && context.mounted) onChanged();
            },
            icon: const Icon(CupertinoIcons.pencil, size: 15),
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
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final rows = _list(data['events']);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Panel(
          title: 'Bitácora de la orden de producción',
          icon: CupertinoIcons.clock,
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
    );
  }
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
                        fontWeight: FontWeight.w900,
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
                        fontWeight: FontWeight.w800,
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
            fontWeight: FontWeight.w800,
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
  Widget build(BuildContext context) => Row(
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
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
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
                  fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w900,
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
                  fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
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
                    fontWeight: FontWeight.w800,
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
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.circle,
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
                  fontWeight: FontWeight.w800,
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
                    fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Est: $currency \$${_n(estimated).toStringAsFixed(2)}',
                style: TextStyle(
                  color: PomgtColors.secondaryInk,
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
              Text(
                'Real: $currency \$${_n(actual).toStringAsFixed(2)}',
                style: TextStyle(
                  color: PomgtColors.ink,
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
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
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
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
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
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
                  fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
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
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
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
  List<Map<String, dynamic>> availableUnits = const [];
  late Future<List<List<Map<String, dynamic>>>> future;

  @override
  void initState() {
    super.initState();
    final lookups = context.read<LookupRepository>();
    future = Future.wait([
      lookups.rows('products', refresh: true),
      lookups.rows('units_of_measure'),
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
    setState(() {
      productId = id;
      bomRevisionId = null;
      routingRevisionId = null;
      boms = const [];
      routes = const [];
      loadingRelations = id != null;
      if (id != null) {
        final selected = products
            .where((e) => e['id']?.toString() == id)
            .toList();
        if (selected.isNotEmpty)
          uomId = selected.first['base_uom_id']?.toString();
      }
    });
    if (id == null) return;
    final generic = context.read<GenericRepository>();
    try {
      final bomHeads = await generic.listRows(
        Phase1Schema.tables['boms']!,
        filters: {'product_id': id},
      );
      final routeHeads = await generic.listRows(
        Phase1Schema.tables['routings']!,
        filters: {'product_id': id},
      );
      final bomRows = <Map<String, dynamic>>[];
      final routeRows = <Map<String, dynamic>>[];
      for (final head in bomHeads) {
        final revs = await generic.listRows(
          Phase1Schema.tables['bom_revisions']!,
          filters: {'bom_id': head['id']},
        );
        for (final rev in revs.where((e) => e['status'] == 'active')) {
          bomRows.add({...rev, '_head': head});
        }
      }
      for (final head in routeHeads) {
        final revs = await generic.listRows(
          Phase1Schema.tables['routing_revisions']!,
          filters: {'routing_id': head['id']},
        );
        for (final rev in revs.where((e) => e['status'] == 'active')) {
          routeRows.add({...rev, '_head': head});
        }
      }
      if (!mounted) return;
      setState(() {
        boms = bomRows;
        routes = routeRows;
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
    } catch (_) {
      if (mounted) setState(() => loadingRelations = false);
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
      return 'No hay una lista de materiales activa para preparar la OP. Crea o activa una BOM, o guarda la OP como borrador.';
    }
    if (routes.isEmpty) {
      return 'No hay una ruta de fabricación activa para preparar la OP. Crea o activa una ruta, o guarda la OP como borrador.';
    }
    if (bomRevisionId == null) return 'Selecciona una lista de materiales.';
    if (routingRevisionId == null) return 'Selecciona una ruta de fabricación.';
    final bomUomId = _selectedBomUomId();
    if (bomUomId != null && uomId != bomUomId) {
      return 'La unidad de la OP debe coincidir con la unidad de salida de la BOM seleccionada: ${_unitName(units, bomUomId)}.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(
          Icons.precision_manufacturing_outlined,
          size: 22,
          color: PomgtColors.blue,
        ),
        SizedBox(width: 10),
        Expanded(child: Text('Nueva orden de producción')),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 760),
      child: FutureBuilder<List<List<Map<String, dynamic>>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
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
          final bomUomId = _selectedBomUomId();
          return Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'La OP puede crearse manualmente para producción interna, inventario, muestras, retrabajos o pruebas. POMGT congelará la BOM y la ruta al prepararla.',
                    style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Producto a fabricar *',
                    ),
                    items: products
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'].toString(),
                            child: Text('${p['sku']} · ${p['name']}'),
                          ),
                        )
                        .toList(),
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
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad planificada *',
                          ),
                          validator: (value) => (_n(value) <= 0)
                              ? 'Captura una cantidad mayor a cero.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('op-uom-${uomId ?? ''}'),
                          initialValue: uomId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Unidad de medida *',
                            helperText: bomUomId == null
                                ? null
                                : 'Sincronizada con la unidad de salida de la BOM.',
                          ),
                          items: units
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u['id'].toString(),
                                  child: Text('${u['name']} (${u['symbol']})'),
                                ),
                              )
                              .toList(),
                          onChanged: bomUomId == null
                              ? (value) => setState(() => uomId = value)
                              : null,
                          validator: (v) {
                            if (v == null) return 'Selecciona una unidad.';
                            if (prepareAutomatically &&
                                bomUomId != null &&
                                v != bomUomId) {
                              return 'Debe coincidir con la unidad de salida de la BOM.';
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
                          onChanged: (value) =>
                              setState(() => sourceType = value ?? 'internal'),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Prioridad',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Baja')),
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('Alta'),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('Urgente'),
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
                    const LinearProgressIndicator(minHeight: 2),
                  if (productId != null && !loadingRelations) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('op-bom-${bomRevisionId ?? ''}'),
                            initialValue: bomRevisionId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Lista de materiales activa',
                            ),
                            items: boms.map((r) {
                              final head = _map(r['_head']);
                              return DropdownMenuItem(
                                value: r['id'].toString(),
                                child: Text(
                                  '${head['bom_code']} · ${r['revision_code']} · ${head['name']}',
                                ),
                              );
                            }).toList(),
                            onChanged: _selectBomRevision,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: routingRevisionId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Ruta de fabricación activa',
                            ),
                            items: routes.map((r) {
                              final head = _map(r['_head']);
                              return DropdownMenuItem(
                                value: r['id'].toString(),
                                child: Text(
                                  '${head['routing_code']} · ${r['revision_code']} · ${head['name']}',
                                ),
                              );
                            }).toList(),
                            onChanged: (value) =>
                                setState(() => routingRevisionId = value),
                          ),
                        ),
                      ],
                    ),
                    if (boms.isEmpty || routes.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${boms.isEmpty ? 'Falta una lista de materiales activa. ' : ''}${routes.isEmpty ? 'Falta una ruta de fabricación activa.' : ''} Puedes guardar la OP como borrador, pero no podrá prepararse hasta completar la configuración del producto.',
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
                          onChanged: (d) => setState(() => plannedStartAt = d),
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
                    ),
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Preparar automáticamente al crear',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: const Text(
                      'Congela lista de materiales, ruta, operaciones, calidad y checklists. Si falta configuración, la creación mostrará el motivo exacto.',
                    ),
                    value: prepareAutomatically,
                    onChanged: (value) =>
                        setState(() => prepareAutomatically = value),
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
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
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
        child: Text(
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
    title: const Row(
      children: [
        Icon(CupertinoIcons.calendar, color: PomgtColors.blue, size: 21),
        SizedBox(width: 10),
        Text('Planeación de la OP'),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 620),
      child: SingleChildScrollView(
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
            DropdownButtonFormField<String>(
              initialValue: priority,
              decoration: const InputDecoration(labelText: 'Prioridad'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Baja')),
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'high', child: Text('Alta')),
                DropdownMenuItem(value: 'urgent', child: Text('Urgente')),
              ],
              onChanged: (v) => setState(() => priority = v ?? 'normal'),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
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
      final day = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        helpText: 'Selecciona una fecha',
        cancelText: 'Cancelar',
        confirmText: 'Aceptar',
      );
      if (day == null || !context.mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: value == null
            ? TimeOfDay.now()
            : TimeOfDay.fromDateTime(value!),
        helpText: 'Selecciona una hora',
        cancelText: 'Cancelar',
        confirmText: 'Aceptar',
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
        suffixIcon: const Icon(CupertinoIcons.calendar, size: 17),
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

class _CompleteOperationDialog extends StatefulWidget {
  const _CompleteOperationDialog({required this.operation});
  final Map<String, dynamic> operation;
  @override
  State<_CompleteOperationDialog> createState() =>
      _CompleteOperationDialogState();
}

class _CompleteOperationDialogState extends State<_CompleteOperationDialog> {
  late final TextEditingController completed;
  final rejected = TextEditingController(text: '0');
  final note = TextEditingController();
  @override
  void initState() {
    super.initState();
    completed = TextEditingController(
      text: _fmt(widget.operation['planned_quantity']),
    );
  }

  @override
  void dispose() {
    completed.dispose();
    rejected.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Completar operación'),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.operation['name']?.toString() ?? 'Operación',
              style: const TextStyle(color: PomgtColors.muted),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: _responsiveDialogWidth(context, 520) < 520
                      ? double.infinity
                      : 251,
                  child: TextField(
                    controller: completed,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad buena *',
                    ),
                  ),
                ),
                SizedBox(
                  width: _responsiveDialogWidth(context, 520) < 520
                      ? double.infinity
                      : 251,
                  child: TextField(
                    controller: rejected,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad rechazada',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notas de cierre'),
            ),
          ],
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
          final good = _n(completed.text);
          final bad = _n(rejected.text);
          if (good < 0 || bad < 0 || good + bad <= 0) return;
          Navigator.pop(
            context,
            _OperationCompletion(
              good,
              bad,
              note.text.trim().isEmpty ? null : note.text.trim(),
            ),
          );
        },
        child: const Text('Completar operación'),
      ),
    ],
  );
}

class _OperationCompletion {
  const _OperationCompletion(this.completed, this.rejected, this.note);
  final double completed;
  final double rejected;
  final String? note;
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
    title: const Row(
      children: [
        Icon(Icons.layers_outlined, color: PomgtColors.blue, size: 21),
        SizedBox(width: 10),
        Text('Registrar movimiento de material'),
      ],
    ),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 540),
      child: SingleChildScrollView(
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
              decoration: const InputDecoration(labelText: 'Cantidad *'),
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
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
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
        initialValue: booleanValue,
        decoration: const InputDecoration(labelText: 'Resultado *'),
        items: const [
          DropdownMenuItem(value: true, child: Text('Sí / Conforme')),
          DropdownMenuItem(value: false, child: Text('No / No conforme')),
        ],
        onChanged: (v) => setState(() => booleanValue = v),
      );
    } else if (type == 'select' && allowed.isNotEmpty) {
      field = DropdownButtonFormField<String>(
        initialValue: selectValue,
        decoration: const InputDecoration(labelText: 'Resultado *'),
        items: allowed
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) => setState(() => selectValue = v),
      );
    } else {
      field = TextField(
        controller: value,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: type == 'number' ? 'Valor medido *' : 'Resultado *',
        ),
      );
    }
    return AlertDialog(
      title: const Text('Registrar control de calidad'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 540),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.check['name']?.toString() ?? 'Control',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _qualityLimits(widget.check),
                style: const TextStyle(color: PomgtColors.muted, fontSize: 12),
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
                decoration: const InputDecoration(labelText: 'Observaciones'),
              ),
            ],
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
              result = double.tryParse(value.text.trim());
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
        initialValue: boolValue,
        decoration: const InputDecoration(labelText: 'Respuesta *'),
        items: const [
          DropdownMenuItem(value: true, child: Text('Sí')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: (v) => setState(() => boolValue = v),
      );
    } else if (type == 'select' && allowed.isNotEmpty) {
      field = DropdownButtonFormField<String>(
        initialValue: selectValue,
        decoration: const InputDecoration(labelText: 'Respuesta *'),
        items: allowed
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) => setState(() => selectValue = v),
      );
    } else {
      field = TextField(
        controller: value,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: const InputDecoration(labelText: 'Respuesta *'),
      );
    }
    return AlertDialog(
      title: const Text('Responder verificación'),
      content: SizedBox(
        width: _responsiveDialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.item['prompt']?.toString() ?? 'Verificación',
                style: const TextStyle(fontWeight: FontWeight.w800),
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
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
            ],
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
              response = double.tryParse(value.text.trim());
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
        text: _n(widget.costs[field[0]]).toStringAsFixed(2),
      );
  }

  @override
  void dispose() {
    for (final c in controllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Actualizar costos de la OP'),
    content: SizedBox(
      width: _responsiveDialogWidth(context, 680),
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
                    decoration: InputDecoration(labelText: field[1]),
                  ),
                ),
            ],
          );
        },
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
  final result = await showDialog<double>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
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
