import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/detail_sections.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import 'customer_form_dialog.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late Future<List<Map<String, dynamic>>> future;
  late int seenRevision;
  late int seenDataRevision;
  String search = '';
  String? selectedId;

  @override
  void initState() {
    super.initState();
    seenRevision = context.read<CustomersController>().revision;
    seenDataRevision = context.read<RuntimeDataController>().revision;
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return context.read<GenericRepository>().listRows(
      Phase1Schema.tables['customers']!,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<CustomersController>().revision;
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

  Future<void> _delete(Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
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
        Phase1Schema.tables['customers']!,
        customer,
      );
      if (!mounted) return;
      setState(() => selectedId = null);
      context.read<LookupRepository>().invalidate('customers');
      context.read<CustomersController>().refresh();
      _reload();
    } catch (error) {
      if (!mounted) return;
      showPomgtSnackBar(context, error.toString(), isError: true);
    }
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(original: row),
    );
    if (changed == true && mounted) {
      context.read<CustomersController>().refresh();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              ErrorCopy.message(
                snapshot.error!,
                fallback: 'No fue posible cargar clientes.',
              ),
              style: const TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CustomersTitle(onCreate: () => _edit()),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 410,
                      child: _CustomerListPanel(
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: selected == null
                          ? const _CustomerEmptyDetail()
                          : _CustomerOverview(
                              key: ValueKey(selected['id']),
                              customer: selected,
                              onEdit: () => _edit(selected),
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

class _CustomersTitle extends StatelessWidget {
  const _CustomersTitle({required this.onCreate});
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
                  'Clientes',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                const InfoTip(
                  'Gestiona clientes, contactos, productos, documentos y trazabilidad.',
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Gestiona la información de tus clientes, contactos, productos y documentos.',
              style: TextStyle(
                color: PomgtColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 18),
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(CupertinoIcons.add, size: 18),
        label: const Text('Nuevo cliente'),
      ),
    ],
  );
}

class _CustomerListPanel extends StatelessWidget {
  const _CustomerListPanel({
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
                          hintText: 'Buscar clientes...',
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
                  Expanded(child: _SelectLike('Todos los clientes')),
                  SizedBox(width: 10),
                  Expanded(child: _SelectLike('Más recientes')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$total clientes',
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
                    'Sin clientes.',
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
                                Icons.business_outlined,
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
                                    _customerTitle(row),
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
                                    'RFC: ${row['tax_id'] ?? '—'} · ${_country(row)}',
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

class _SelectLike extends StatelessWidget {
  const _SelectLike(this.label);
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

class _CustomerOverview extends StatelessWidget {
  const _CustomerOverview({
    super.key,
    required this.customer,
    required this.onEdit,
  });
  final Map<String, dynamic> customer;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CustomerRepository>();
    final lookups = context.read<LookupRepository>();
    final id = customer['id'].toString();
    return FutureBuilder<Map<String, dynamic>>(
      future: repo.detail(id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              ErrorCopy.message(
                snapshot.error!,
                fallback: 'No fue posible cargar el expediente del cliente.',
              ),
              style: const TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final contacts = _list(data['contacts']);
        final addresses = _list(data['addresses']);
        final products = _list(data['products']);
        final requirements = _list(data['requirements']);
        final documents = _list(data['documents']);
        final orders = _list(data['orders']);
        final deliveries = _list(data['deliveries']);
        final claims = _list(data['claims']);
        final production = _productionTotal(orders);
        return SingleChildScrollView(
          child: Column(
            children: [
              _CustomerHero(customer: customer, onEdit: onEdit),
              const SizedBox(height: 14),
              _CustomerKpis(
                orders: orders.length,
                products: products.length,
                documents: documents.length,
                deliveries: deliveries.length,
                claims: claims.length,
                production: production,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _InfoPanel(customer: customer, lookups: lookups),
                        const SizedBox(height: 14),
                        _RequirementPanel(rows: requirements),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _SimpleRowsPanel(
                          title: 'Contactos',
                          link: 'Ver todos (${contacts.length})',
                          rows: contacts,
                          empty: 'Sin contactos.',
                          icon: CupertinoIcons.person,
                          titleField: 'full_name',
                          subtitleFields: const ['job_title', 'department'],
                        ),
                        const SizedBox(height: 14),
                        _AddressPanel(rows: addresses),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SimpleRowsPanel(
                      title: 'Productos vinculados',
                      link: 'Ver todos (${products.length})',
                      rows: products,
                      empty: 'Sin productos vinculados.',
                      icon: CupertinoIcons.cube_box,
                      titleField: 'customer_product_name',
                      fallbackTitleField: 'customer_sku',
                      subtitleFields: const ['customer_sku', 'revision'],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SimpleRowsPanel(
                      title: 'Documentos recientes',
                      link: 'Ver todos',
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
                    child: _ActivityPanel(
                      orders: orders,
                      deliveries: deliveries,
                      claims: claims,
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
}

class _CustomerHero extends StatelessWidget {
  const _CustomerHero({required this.customer, required this.onEdit});
  final Map<String, dynamic> customer;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => _CustomerPanel(
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
                      _customerName(customer),
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
                  const InfoTip('Ficha maestra del cliente.', size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${customer['customer_code'] ?? '—'} · ${customer['legal_name'] ?? '—'} · ${customer['tax_id'] ?? '—'}',
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
          label: const Text('Editar cliente'),
        ),
      ],
    ),
  );
}

class _CustomerKpis extends StatelessWidget {
  const _CustomerKpis({
    required this.orders,
    required this.products,
    required this.documents,
    required this.deliveries,
    required this.claims,
    required this.production,
  });

  final int orders;
  final int products;
  final int documents;
  final int deliveries;
  final int claims;
  final int production;

  @override
  Widget build(BuildContext context) {
    final items = [
      _CustomerKpi(
        'Pedidos activos',
        orders,
        CupertinoIcons.doc_plaintext,
        PomgtColors.blue,
      ),
      _CustomerKpi(
        'Productos vinculados',
        products,
        CupertinoIcons.cube_box,
        PomgtColors.blue,
      ),
      _CustomerKpi(
        'Documentos',
        documents,
        CupertinoIcons.doc_text,
        PomgtColors.blue,
      ),
      _CustomerKpi(
        'Entregas',
        deliveries,
        Icons.local_shipping_outlined,
        PomgtColors.blue,
      ),
      _CustomerKpi(
        'Reclamaciones',
        claims,
        CupertinoIcons.exclamationmark_triangle,
        PomgtColors.danger,
      ),
      _CustomerKpi(
        'Producción acumulada',
        production,
        CupertinoIcons.chart_bar,
        PomgtColors.blue,
      ),
    ];
    return _CustomerPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100 ? 6 : 3;
          final width = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: width,
                  child: _CustomerKpiTile(
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

class _CustomerKpi {
  const _CustomerKpi(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _CustomerKpiTile extends StatelessWidget {
  const _CustomerKpiTile({required this.item, required this.divider});
  final _CustomerKpi item;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
    height: 78,
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
        Icon(item.icon, color: item.color, size: 26),
        const SizedBox(width: 16),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.customer, required this.lookups});
  final Map<String, dynamic> customer;
  final LookupRepository lookups;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: lookups.rows('payment_terms'),
    builder: (context, snapshot) {
      final terms = snapshot.data ?? const <Map<String, dynamic>>[];
      final termId = customer['payment_term_id']?.toString();
      final term = terms.cast<Map<String, dynamic>?>().firstWhere(
        (row) => row?['id']?.toString() == termId,
        orElse: () => null,
      );
      final rows = [
        MapEntry('Razón social', customer['legal_name']?.toString() ?? '—'),
        MapEntry('Nombre comercial', customer['trade_name']?.toString() ?? '—'),
        MapEntry(
          'RFC / Identificación fiscal',
          customer['tax_id']?.toString() ?? '—',
        ),
        MapEntry('País fiscal', _country(customer)),
        MapEntry('Sitio web', customer['website']?.toString() ?? '—'),
        MapEntry(
          'Moneda',
          customer['default_currency_code']?.toString() ?? '—',
        ),
        MapEntry(
          'Condición de pago',
          term == null
              ? 'Sin definir'
              : lookups.display(Phase1Schema.tables['payment_terms']!, term),
        ),
        MapEntry(
          'Estado',
          customer['is_active'] == true ? 'Activo' : 'Inactivo',
        ),
        MapEntry('Notas', customer['notes']?.toString() ?? 'N/A'),
      ];
      return _TitledPanel(
        title: 'Información general',
        icon: Icons.badge_outlined,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680 ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 28) / columns;
            return Wrap(
              spacing: 28,
              runSpacing: 16,
              children: rows
                  .map(
                    (row) => SizedBox(
                      width: width,
                      child: _KeyValue(label: row.key, value: row.value),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
    },
  );
}

class _RequirementPanel extends StatelessWidget {
  const _RequirementPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => _TitledPanel(
    title: 'Requisitos del cliente',
    icon: Icons.fact_check_outlined,
    link: rows.isEmpty ? null : 'Ver todos',
    child: rows.isEmpty
        ? const Text(
            'Sin requisitos.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: rows.take(4).map((row) {
              return _MiniRow(
                icon: CupertinoIcons.doc_checkmark,
                title: row['title']?.toString() ?? 'Requisito',
                subtitle: row['requirement_type']?.toString() ?? '',
              );
            }).toList(),
          ),
  );
}

class _SimpleRowsPanel extends StatelessWidget {
  const _SimpleRowsPanel({
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
  Widget build(BuildContext context) => _TitledPanel(
    title: title,
    link: link,
    icon: icon,
    child: rows.isEmpty
        ? Text(empty, style: const TextStyle(color: PomgtColors.muted))
        : Column(
            children: rows.take(4).map((row) {
              final title = row[titleField]?.toString().trim();
              final fallback = fallbackTitleField == null
                  ? null
                  : row[fallbackTitleField]?.toString();
              final subtitles = subtitleFields
                  .map((field) => row[field]?.toString())
                  .where((value) => value != null && value.trim().isNotEmpty)
                  .join(' · ');
              return _MiniRow(
                icon: icon,
                title: title?.isNotEmpty == true
                    ? title!
                    : (fallback ?? 'Registro'),
                subtitle: subtitles,
              );
            }).toList(),
          ),
  );
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) => _TitledPanel(
    title: 'Direcciones',
    icon: Icons.location_on_outlined,
    link: rows.isEmpty ? null : 'Ver todas (${rows.length})',
    child: rows.isEmpty
        ? const Text(
            'Sin direcciones.',
            style: TextStyle(color: PomgtColors.muted),
          )
        : Column(
            children: rows.take(3).map((row) {
              final address =
                  [
                        row['line1'],
                        row['city'],
                        row['state_region'],
                        _country(row),
                      ]
                      .where(
                        (value) =>
                            value != null && value.toString().trim().isNotEmpty,
                      )
                      .join(', ');
              return _MiniRow(
                icon: CupertinoIcons.location,
                title: row['label']?.toString() ?? 'Dirección',
                subtitle: address,
                trailing: UiCopy.enumLabel(
                  row['address_type']?.toString() ?? '',
                ),
              );
            }).toList(),
          ),
  );
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.orders,
    required this.deliveries,
    required this.claims,
  });

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> claims;

  @override
  Widget build(BuildContext context) {
    final rows = <_CustomerActivity>[
      ...orders.map(
        (row) => _CustomerActivity(
          row['order_number']?.toString() ?? 'Pedido',
          UiCopy.enumLabel(row['status']?.toString() ?? ''),
          _date(row['updated_at'] ?? row['created_at']),
          PomgtColors.blue,
        ),
      ),
      ...deliveries.map(
        (row) => _CustomerActivity(
          row['delivery_number']?.toString() ?? 'Entrega',
          UiCopy.enumLabel(row['status']?.toString() ?? ''),
          _date(row['updated_at'] ?? row['created_at']),
          PomgtColors.mint,
        ),
      ),
      ...claims.map(
        (row) => _CustomerActivity(
          row['claim_number']?.toString() ?? 'Reclamación',
          row['subject']?.toString() ?? '',
          _date(row['updated_at'] ?? row['opened_at']),
          PomgtColors.danger,
        ),
      ),
    ];
    rows.sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );
    return _TitledPanel(
      title: 'Actividad reciente',
      icon: Icons.timeline_outlined,
      link: rows.isEmpty ? null : 'Ver todas',
      child: rows.isEmpty
          ? const Text(
              'Sin actividad reciente.',
              style: TextStyle(color: PomgtColors.muted),
            )
          : Column(
              children: rows.take(4).map((row) {
                return _MiniRow(
                  icon: CupertinoIcons.circle_fill,
                  iconColor: row.color,
                  title: row.title,
                  subtitle: row.subtitle,
                  trailing: row.date == null
                      ? ''
                      : _customerShortDate(row.date!),
                );
              }).toList(),
            ),
    );
  }
}

class _CustomerActivity {
  const _CustomerActivity(this.title, this.subtitle, this.date, this.color);
  final String title;
  final String subtitle;
  final DateTime? date;
  final Color color;
}

class _TitledPanel extends StatelessWidget {
  const _TitledPanel({
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
  Widget build(BuildContext context) => _CustomerPanel(
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
                style: const TextStyle(
                  color: PomgtColors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
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

class _CustomerPanel extends StatelessWidget {
  const _CustomerPanel({
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

class _MiniRow extends StatelessWidget {
  const _MiniRow({
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

class _CustomerEmptyDetail extends StatelessWidget {
  const _CustomerEmptyDetail();

  @override
  Widget build(BuildContext context) => const _CustomerPanel(
    child: Center(
      child: Text(
        'Selecciona un cliente para ver su expediente.',
        style: TextStyle(color: PomgtColors.muted),
      ),
    ),
  );
}

List<Map<String, dynamic>> _list(dynamic value) =>
    (value as List?)?.cast<Map<String, dynamic>>() ?? const [];

String _customerName(Map<String, dynamic> row) {
  final trade = row['trade_name']?.toString().trim();
  if (trade != null && trade.isNotEmpty) return trade;
  return row['legal_name']?.toString() ?? 'Cliente';
}

String _customerTitle(Map<String, dynamic> row) {
  final code = row['customer_code']?.toString();
  final name = _customerName(row);
  final legal = row['legal_name']?.toString();
  return [
    code,
    name,
    if (legal != null && legal != name) legal,
  ].where((value) => value != null && value.trim().isNotEmpty).join(' · ');
}

String _country(Map<String, dynamic> row) {
  final code = row['tax_country_code'] ?? row['country_code'];
  if (code == null) return '—';
  return UiCopy.countryLabel(code.toString());
}

int _productionTotal(List<Map<String, dynamic>> orders) {
  return orders.fold<int>(0, (sum, row) {
    final value =
        row['total_quantity'] ?? row['quantity'] ?? row['completed_quantity'];
    return sum + ((value as num?)?.round() ?? 0);
  });
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String _customerShortDate(DateTime date) {
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
  return '${date.day} ${months[date.month - 1]}';
}

class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({required this.customer});
  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = customer['id'].toString();

    Future<void> edit() async {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CustomerFormDialog(original: customer),
      );
      if (changed == true && context.mounted)
        context.read<CustomersController>().refresh();
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          DetailHeader(
            icon: Icons.business_outlined,
            title: customer['trade_name']?.toString().trim().isNotEmpty == true
                ? customer['trade_name'].toString()
                : customer['legal_name'].toString(),
            subtitle:
                '${customer['customer_code']} · ${customer['legal_name']}${customer['tax_id'] == null ? '' : ' · ${customer['tax_id']}'}',
            help:
                'Ficha maestra del cliente. Los pedidos históricos conservan copias de direcciones y requisitos para no cambiar retroactivamente.',
            onEdit: edit,
          ),
          Expanded(
            child: DetailSections(
              sections: [
                DetailSection(
                  label: 'Resumen',
                  help: 'Datos fiscales y comerciales principales.',
                  icon: Icons.dashboard_outlined,
                  child: _CustomerSummary(customer: customer),
                ),
                DetailSection(
                  label: 'Direcciones',
                  help: 'Facturación, envío, plantas y oficinas.',
                  icon: Icons.location_on_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'customer_addresses',
                      repository: repository,
                      lookups: lookups,
                      fixedValues: {'customer_id': id},
                      title: 'Direcciones',
                      description:
                          'Registra direcciones de facturación, envío, plantas y oficinas. El país se selecciona como México o Estados Unidos y se guarda internamente como MX o US.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Contactos',
                  help: 'Personas y medios de comunicación.',
                  icon: Icons.groups_outlined,
                  child: _CustomerContacts(
                    customerId: id,
                    repository: repository,
                    lookups: lookups,
                  ),
                ),
                DetailSection(
                  label: 'Productos',
                  help: 'SKUs y revisiones que compra el cliente.',
                  icon: Icons.inventory_2_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'customer_products',
                      repository: repository,
                      lookups: lookups,
                      fixedValues: {'customer_id': id},
                      title: 'Productos que compra',
                      description:
                          'Relaciona productos del catálogo con el SKU, nombre y revisión que utiliza este cliente.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Requisitos',
                  help: 'Especificaciones, empaque y calidad.',
                  icon: Icons.rule_folder_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'customer_requirements',
                      repository: repository,
                      lookups: lookups,
                      fixedValues: {'customer_id': id},
                      title: 'Requisitos productivos',
                      description:
                          'Especificaciones particulares, procesos especiales, instrucciones, tolerancias, requisitos de calidad y empaque.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Diseños',
                  help: 'Aprobaciones y evidencia documentada.',
                  icon: Icons.approval_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: EntityCrudPanel(
                      table: 'design_approvals',
                      repository: repository,
                      lookups: lookups,
                      fixedValues: {'customer_id': id},
                      title: 'Diseños aprobados',
                      description:
                          'Registra la aprobación de diseños y fija la versión documental correspondiente para conservar evidencia histórica.',
                    ),
                  ),
                ),
                DetailSection(
                  label: 'Documentos',
                  help: 'Contratos, constancias y archivos del cliente.',
                  icon: Icons.folder_copy_outlined,
                  child: LinkedDocumentsPanel(
                    entityField: 'customer_id',
                    entityId: id,
                    title: 'Documentos del cliente',
                    help:
                        'Carga y previsualiza constancia fiscal, contratos, especificaciones, diseños u otros archivos. Cada archivo queda versionado en el repositorio documental.',
                    documentTypes: const [
                      'Constancia fiscal',
                      'Contrato',
                      'Especificación',
                      'Diseño / arte',
                      'Identificación',
                      'Captura de mensaje',
                      'Otro',
                    ],
                  ),
                ),
                DetailSection(
                  label: 'Historial',
                  help: 'Pedidos, entregas y volumen producido.',
                  icon: Icons.timeline_outlined,
                  child: _CustomerHistory(customerId: id),
                ),
                DetailSection(
                  label: 'Calidad',
                  help: 'Reclamaciones y no conformidades.',
                  icon: Icons.verified_outlined,
                  child: _CustomerQuality(
                    customerId: id,
                    repository: repository,
                    lookups: lookups,
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

class _CustomerSummary extends StatelessWidget {
  const _CustomerSummary({required this.customer});
  final Map<String, dynamic> customer;

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('payment_terms'),
      builder: (context, snapshot) {
        final terms = snapshot.data ?? const <Map<String, dynamic>>[];
        final termId = customer['payment_term_id']?.toString();
        final term = terms
            .where((e) => e['id']?.toString() == termId)
            .cast<Map<String, dynamic>?>()
            .firstOrNull;
        final pairs = <MapEntry<String, String>>[
          MapEntry('Razón social', customer['legal_name']?.toString() ?? '—'),
          MapEntry(
            'Nombre comercial',
            customer['trade_name']?.toString() ?? '—',
          ),
          MapEntry(
            'RFC / identificación fiscal',
            customer['tax_id']?.toString() ?? '—',
          ),
          MapEntry(
            'País fiscal',
            customer['tax_country_code'] == null
                ? '—'
                : UiCopy.countryLabel(customer['tax_country_code'].toString()),
          ),
          MapEntry('Sitio web', customer['website']?.toString() ?? '—'),
          MapEntry(
            'Moneda',
            customer['default_currency_code']?.toString() ?? '—',
          ),
          MapEntry(
            'Condición de pago',
            term == null
                ? 'Sin definir'
                : lookups.display(Phase1Schema.tables['payment_terms']!, term),
          ),
          MapEntry(
            'Estado',
            customer['is_active'] == true ? 'Activo' : 'Inactivo',
          ),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Información general',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 7),
                  const InfoTip(
                    'Datos fiscales y comerciales usados como valores predeterminados al crear pedidos.',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 900
                      ? 4
                      : (c.maxWidth >= 560 ? 2 : 1);
                  final width = (c.maxWidth - (cols - 1) * 26) / cols;
                  return Wrap(
                    spacing: 26,
                    runSpacing: 20,
                    children: pairs
                        .map(
                          (p) => SizedBox(
                            width: width,
                            child: _KeyValue(label: p.key, value: p.value),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              if (customer['notes'] != null &&
                  customer['notes'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 34),
                Row(
                  children: [
                    Text(
                      'Notas',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 6),
                    const InfoTip(
                      'Contexto comercial o administrativo que no forma parte de una especificación productiva.',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  customer['notes'].toString(),
                  style: const TextStyle(
                    color: PomgtColors.secondaryInk,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CustomerContacts extends StatelessWidget {
  const _CustomerContacts({
    required this.customerId,
    required this.repository,
    required this.lookups,
  });
  final String customerId;
  final GenericRepository repository;
  final LookupRepository lookups;

  @override
  Widget build(BuildContext context) {
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
                  label: 'Personas',
                  help: 'Personas de contacto registradas para este cliente.',
                ),
                HelpTab(
                  label: 'Correos y teléfonos',
                  help:
                      'Medios de contacto asociados a cada persona, con datos principales y WhatsApp.',
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
                    table: 'customer_contacts',
                    repository: repository,
                    lookups: lookups,
                    fixedValues: {'customer_id': customerId},
                    title: 'Contactos',
                    description:
                        'Personas de contacto, puesto, departamento, idioma y preferencias de notificación.',
                  ),
                ),
                NestedRelationPanel(
                  title: 'Medios de contacto',
                  help:
                      'Selecciona una persona y administra sus correos y teléfonos. Puedes marcar un medio principal.',
                  parentTable: 'customer_contacts',
                  parentFilter: {'customer_id': customerId},
                  repository: repository,
                  lookups: lookups,
                  childTabs: const [
                    ChildTabDefinition(
                      table: 'customer_contact_emails',
                      label: 'Correos',
                      foreignKey: 'contact_id',
                      help: 'Correos del contacto y correo principal.',
                    ),
                    ChildTabDefinition(
                      table: 'customer_contact_phones',
                      label: 'Teléfonos',
                      foreignKey: 'contact_id',
                      help:
                          'Teléfonos, extensión, móvil, WhatsApp y teléfono principal.',
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

class _CustomerHistory extends StatelessWidget {
  const _CustomerHistory({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CustomerRepository>();
    return FutureBuilder<Map<String, dynamic>>(
      future: _load(repo),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        if (snapshot.hasError)
          return Center(
            child: Text(
              ErrorCopy.message(
                snapshot.error!,
                fallback: 'No fue posible cargar el historial.',
              ),
              style: const TextStyle(color: PomgtColors.danger),
            ),
          );
        final data = snapshot.data!;
        final summaryRows = data['summary'] as List<Map<String, dynamic>>;
        final summary = summaryRows.isEmpty
            ? <String, dynamic>{}
            : summaryRows.first;
        final volume = data['volume'] as List<Map<String, dynamic>>;
        final bundle = data['bundle'] as Map<String, dynamic>;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Historial',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 7),
                  const InfoTip(
                    'Concentra pedidos, OP, entregas, reclamaciones, no conformidades y volumen producido.',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(
                    label: 'Pedidos',
                    value: '${summary['total_orders'] ?? 0}',
                  ),
                  _Metric(
                    label: 'Órdenes de producción',
                    value: '${summary['total_production_orders'] ?? 0}',
                  ),
                  _Metric(
                    label: 'Entregas',
                    value: '${summary['total_deliveries'] ?? 0}',
                  ),
                  _Metric(
                    label: 'Reclamaciones',
                    value: '${summary['total_claims'] ?? 0}',
                  ),
                  _Metric(
                    label: 'No conformidades',
                    value: '${summary['total_nonconformities'] ?? 0}',
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _HistoryList(
                title: 'Pedidos recientes',
                rows: bundle['orders'] as List<Map<String, dynamic>>,
                primary: 'order_number',
                secondary: 'status',
              ),
              const SizedBox(height: 22),
              _HistoryList(
                title: 'Entregas',
                rows: bundle['deliveries'] as List<Map<String, dynamic>>,
                primary: 'delivery_number',
                secondary: 'status',
              ),
              const SizedBox(height: 22),
              Text(
                'Volumen producido',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Se mantiene separado por producto y unidad para no mezclar cantidades incompatibles.',
                style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              if (volume.isEmpty)
                const Text(
                  'Sin producción terminada todavía.',
                  style: TextStyle(color: PomgtColors.muted),
                )
              else
                ...volume.map(
                  (r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r['product_name']?.toString() ??
                                'Producto sin identificar',
                          ),
                        ),
                        Text(
                          '${r['completed_quantity']} · ${r['uom_symbol'] ?? 'unidad'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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

  Future<Map<String, dynamic>> _load(CustomerRepository repo) async {
    final bundle = await repo.detail(customerId);
    final summary = await repo.service.list(
      'v_customer_history_summary',
      equals: {'customer_id': customerId},
    );
    final volume = await repo.service.list(
      'v_customer_production_volume',
      equals: {'customer_id': customerId},
    );
    return {'bundle': bundle, 'summary': summary, 'volume': volume};
  }
}

class _CustomerQuality extends StatelessWidget {
  const _CustomerQuality({
    required this.customerId,
    required this.repository,
    required this.lookups,
  });
  final String customerId;
  final GenericRepository repository;
  final LookupRepository lookups;

  @override
  Widget build(BuildContext context) => DefaultTabController(
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
                label: 'Reclamaciones',
                help:
                    'Reclamaciones formales recibidas del cliente y su seguimiento.',
              ),
              HelpTab(
                label: 'No conformidades',
                help:
                    'Problemas de calidad, disposición, causa y acciones correctivas relacionadas con el cliente.',
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
                  table: 'customer_claims',
                  repository: repository,
                  lookups: lookups,
                  fixedValues: {'customer_id': customerId},
                  title: 'Reclamaciones',
                  description:
                      'Reclamaciones formales del cliente y seguimiento de su resolución.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: EntityCrudPanel(
                  table: 'nonconformities',
                  repository: repository,
                  lookups: lookups,
                  fixedValues: {'customer_id': customerId},
                  title: 'No conformidades',
                  description:
                      'Problemas de calidad, contención, causa raíz, acción correctiva y disposición.',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
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
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: PomgtColors.ink,
        ),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    color: PomgtColors.surfaceAlt,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: PomgtColors.muted),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: PomgtColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.title,
    required this.rows,
    required this.primary,
    required this.secondary,
  });
  final String title;
  final List<Map<String, dynamic>> rows;
  final String primary;
  final String secondary;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        const Text('Sin registros.', style: TextStyle(color: PomgtColors.muted))
      else
        ...rows
            .take(8)
            .map(
              (r) => Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: PomgtColors.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r[primary]?.toString() ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      UiCopy.enumLabel(r[secondary]?.toString() ?? ''),
                      style: const TextStyle(color: PomgtColors.muted),
                    ),
                  ],
                ),
              ),
            ),
    ],
  );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
