import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/runtime_data_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/info_tip.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> future;
  late int seenDataRevision;
  final searchController = TextEditingController();
  String query = '';

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
    reload();
  }

  Future<_DashboardData> _load() async {
    final repository = context.read<GenericRepository>();
    final result = await Future.wait([
      repository.listRows(Phase1Schema.tables['production_orders']!),
      repository.listRows(Phase1Schema.tables['customer_orders']!),
      repository.listRows(Phase1Schema.tables['deliveries']!),
      repository.listRows(Phase1Schema.tables['nonconformities']!),
      repository.listRows(Phase1Schema.tables['bom_items']!),
      repository.listRows(Phase1Schema.tables['quality_check_templates']!),
    ]);
    return _DashboardData(
      ops: result[0],
      orders: result[1],
      deliveries: result[2],
      nonconformities: result[3],
      bomItems: result[4],
      inspections: result[5],
    );
  }

  void reload() {
    setState(() {
      future = _load();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DashboardTopBar(
          controller: searchController,
          query: query,
          onChanged: (value) {
            setState(() {
              query = value;
            });
          },
          onClear: () {
            searchController.clear();
            setState(() {
              query = '';
            });
          },
        ),
        Expanded(
          child: FutureBuilder<_DashboardData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    ErrorCopy.message(
                      snapshot.error!,
                      fallback: 'No fue posible cargar el dashboard.',
                    ),
                    style: const TextStyle(color: PomgtColors.danger),
                  ),
                );
              }
              final data = (snapshot.data ?? _DashboardData.empty()).filter(
                query,
              );
              final compact = MediaQuery.sizeOf(context).width < 640;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 28,
                  compact ? 14 : 22,
                  compact ? 12 : 28,
                  compact ? 16 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DashboardTitle(date: data.todayDate),
                    const SizedBox(height: 16),
                    _KpiBoard(kpis: data.kpis),
                    const SizedBox(height: 16),
                    _ChartGrid(
                      left: _Panel(
                        title: 'Producción de la última semana',
                        action: 'Últimos 7 días',
                        child: _LineChart(
                          values: data.weekProduction,
                          labels: data.weekLabels,
                          maxLabel: '200',
                          legend: 'Unidades producidas',
                          color: PomgtColors.blue,
                        ),
                      ),
                      center: _Panel(
                        title: 'Utilización de capacidad',
                        action: 'Últimos 7 días',
                        child: _LineChart(
                          values: data.weekCapacity,
                          labels: data.weekLabels,
                          maxLabel: '100%',
                          legend: 'Capacidad utilizada',
                          color: PomgtColors.blue,
                          percent: true,
                        ),
                      ),
                      right: _Panel(
                        title: 'Estado de órdenes de producción',
                        child: _DonutStatus(items: data.productionStatus),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ChartGrid(
                      left: _Panel(
                        title: 'Actividad reciente',
                        link: 'Ver toda',
                        child: _ActivityList(items: data.activity),
                      ),
                      center: _Panel(
                        title: 'Próximos vencimientos',
                        link: 'Ver todos',
                        child: _DueList(items: data.timeline),
                      ),
                      right: _Panel(
                        title: 'Alertas',
                        link: 'Ver todas',
                        child: _AlertList(alerts: data.alerts),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Panel(
                      title: 'Órdenes de producción recientes',
                      link: 'Ver todas',
                      padding: EdgeInsets.zero,
                      child: _RecentOrdersTable(rows: data.recentOps),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Container(
      height: compact ? 64 : 72,
      padding: EdgeInsets.fromLTRB(compact ? 64 : 28, 0, compact ? 12 : 28, 0),
      decoration: const BoxDecoration(
        color: PomgtColors.canvas,
        border: Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SizedBox(
                  height: compact ? 46 : 56,
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(
                      color: PomgtColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar clientes, pedidos o productos',
                      prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: onClear,
                              icon: const Icon(
                                CupertinoIcons.xmark,
                                size: 15,
                                color: PomgtColors.muted,
                              ),
                            ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 46),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () =>
                showPomgtSnackBar(context, 'No hay notificaciones nuevas.'),
            icon: const Icon(CupertinoIcons.bell, color: PomgtColors.muted),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 26, color: PomgtColors.line),
            const SizedBox(width: 18),
            const Text(
              'BajaLabel',
              style: TextStyle(
                color: PomgtColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(CupertinoIcons.chevron_down, size: 14),
            const SizedBox(width: 18),
          ],
          SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Text(
                'D',
                style: TextStyle(
                  color: PomgtColors.blueHover,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTitle extends StatelessWidget {
  const _DashboardTitle({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Inicio',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 8),
                  const InfoTip(
                    'Centro de control de la operación de manufactura.',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Centro de control de la operación de manufactura.',
                style: TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Text(
          _longDate(date),
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _DashboardData {
  const _DashboardData({
    required this.ops,
    required this.orders,
    required this.deliveries,
    required this.nonconformities,
    required this.bomItems,
    required this.inspections,
  });

  final List<Map<String, dynamic>> ops;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> nonconformities;
  final List<Map<String, dynamic>> bomItems;
  final List<Map<String, dynamic>> inspections;

  factory _DashboardData.empty() => const _DashboardData(
    ops: [],
    orders: [],
    deliveries: [],
    nonconformities: [],
    bomItems: [],
    inspections: [],
  );

  _DashboardData filter(String value) {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return this;
    bool matches(Map<String, dynamic> row) {
      return row.values.any(
        (cell) => cell?.toString().toLowerCase().contains(needle) ?? false,
      );
    }

    return _DashboardData(
      ops: ops.where(matches).toList(),
      orders: orders.where(matches).toList(),
      deliveries: deliveries.where(matches).toList(),
      nonconformities: nonconformities.where(matches).toList(),
      bomItems: bomItems.where(matches).toList(),
      inspections: inspections.where(matches).toList(),
    );
  }

  DateTime get today => DateTime.now();
  DateTime get todayDate => DateTime(today.year, today.month, today.day);
  DateTime get horizon => todayDate.add(const Duration(days: 7));

  List<Map<String, dynamic>> get activeOps => ops.where((row) {
    final status = row['status']?.toString();
    return const {
      'planned',
      'ready',
      'in_progress',
      'on_hold',
    }.contains(status);
  }).toList();

  int get scheduledOps => ops.where((row) {
    final status = row['status']?.toString();
    return const {'planned', 'ready'}.contains(status);
  }).length;

  int get lateOps => activeOps.where((row) {
    final due = _date(row['required_at'] ?? row['planned_end_at']);
    return due != null && due.isBefore(todayDate);
  }).length;

  int get blockedOps =>
      ops.where((row) => row['status']?.toString() == 'on_hold').length;

  int get dueOrders => orders.where((row) {
    final due = _date(row['requested_delivery_date']);
    final status = row['status']?.toString();
    return due != null &&
        !due.isBefore(todayDate) &&
        !due.isAfter(horizon) &&
        !const {'completed', 'cancelled'}.contains(status);
  }).length;

  int get completedToday => ops.where((row) {
    final completed = _date(row['actual_end_at'] ?? row['updated_at']);
    return row['status']?.toString() == 'completed' &&
        completed != null &&
        _sameDay(completed, todayDate);
  }).length;

  double get capacityUsed {
    final planned = ops.fold<double>(
      0,
      (sum, row) => sum + ((row['planned_quantity'] as num?)?.toDouble() ?? 0),
    );
    final completed = ops.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['completed_quantity'] as num?)?.toDouble() ?? 0),
    );
    if (planned <= 0) return 0;
    return (completed / planned).clamp(0, 1);
  }

  int get missingMaterials => bomItems.where((row) {
    final type = row['component_type']?.toString();
    return type == 'material' && row['component_product_id'] == null;
  }).length;

  int get pendingPurchases => 0;

  int get pendingInspections =>
      inspections.length +
      nonconformities.where((row) {
        final status = row['status']?.toString();
        return !const {'resolved', 'closed'}.contains(status);
      }).length;

  int get upcomingDeliveries => deliveries.where((row) {
    final ship = _date(row['ship_date'] ?? row['delivered_date']);
    final status = row['status']?.toString();
    return ship != null &&
        !ship.isBefore(todayDate) &&
        !ship.isAfter(horizon) &&
        !const {'delivered', 'cancelled'}.contains(status);
  }).length;

  List<_Kpi> get kpis => [
    _Kpi(
      'Producción activa',
      activeOps.length,
      'OPs en proceso',
      Icons.play_circle_outline,
      PomgtColors.blue,
    ),
    _Kpi(
      'OPs programadas',
      scheduledOps,
      'Esta semana',
      Icons.event_available_outlined,
      PomgtColors.blue,
    ),
    _Kpi(
      'OPs atrasadas',
      lateOps,
      'Requieren atención',
      Icons.schedule_outlined,
      PomgtColors.danger,
    ),
    _Kpi(
      'OPs bloqueadas',
      blockedOps,
      'Sin materiales',
      Icons.block_outlined,
      PomgtColors.danger,
    ),
    _Kpi(
      'Órdenes por vencer',
      dueOrders,
      'Próximos 7 días',
      Icons.alarm_outlined,
      PomgtColors.amber,
    ),
    _Kpi(
      'Producción completada hoy',
      completedToday,
      'Unidades producidas',
      Icons.task_alt_outlined,
      PomgtColors.success,
    ),
    _Kpi(
      'Capacidad utilizada',
      (capacityUsed * 100).round(),
      'De la capacidad total',
      Icons.bar_chart_rounded,
      PomgtColors.blue,
      suffix: '%',
    ),
    _Kpi(
      'Materiales faltantes',
      missingMaterials,
      'Afectan OPs',
      Icons.inventory_2_outlined,
      PomgtColors.danger,
    ),
    _Kpi(
      'Compras pendientes',
      pendingPurchases,
      'En tránsito o por emitir',
      Icons.shopping_cart_outlined,
      PomgtColors.amber,
    ),
    _Kpi(
      'Inspecciones pendientes',
      pendingInspections,
      'Por liberar',
      Icons.fact_check_outlined,
      PomgtColors.blue,
    ),
    _Kpi(
      'Entregas próximas',
      upcomingDeliveries,
      'Próximos 7 días',
      Icons.local_shipping_outlined,
      PomgtColors.blue,
    ),
    _Kpi(
      'Alertas',
      alerts.length,
      'Requiere atención',
      Icons.notifications_none_rounded,
      PomgtColors.danger,
    ),
  ];

  List<double> get weekProduction {
    final values = List<double>.filled(7, 0);
    for (final row in ops) {
      final date = _date(row['actual_end_at'] ?? row['updated_at']);
      if (date == null) continue;
      final index = 6 - todayDate.difference(_dayOnly(date)).inDays;
      if (index >= 0 && index < 7) {
        values[index] += ((row['completed_quantity'] as num?)?.toDouble() ?? 1);
      }
    }
    return values;
  }

  List<double> get weekCapacity {
    final values = List<double>.filled(7, 0);
    for (final row in ops) {
      final date = _date(row['actual_end_at'] ?? row['updated_at']);
      if (date == null) continue;
      final index = 6 - todayDate.difference(_dayOnly(date)).inDays;
      if (index < 0 || index >= 7) continue;
      final planned = ((row['planned_quantity'] as num?)?.toDouble() ?? 0);
      final completed = ((row['completed_quantity'] as num?)?.toDouble() ?? 0);
      if (planned <= 0) continue;
      values[index] = math.max(
        values[index],
        (completed / planned).clamp(0, 1),
      );
    }
    return values;
  }

  List<String> get weekLabels {
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return List.generate(7, (index) {
      final day = todayDate.subtract(Duration(days: 6 - index));
      return '${days[day.weekday - 1]} ${day.day}';
    });
  }

  List<_StatusItem> get productionStatus {
    final values = <String, int>{};
    for (final row in ops) {
      final status = row['status']?.toString() ?? 'sin_estado';
      values[status] = (values[status] ?? 0) + 1;
    }
    if (values.isEmpty) {
      return const [];
    }
    return values.entries
        .map(
          (entry) => _StatusItem(
            UiCopy.enumLabel(entry.key),
            entry.value,
            _colorForStatus(entry.key),
          ),
        )
        .toList();
  }

  List<_TimelineItem> get timeline {
    final items = <_TimelineItem>[];
    for (final row in activeOps) {
      final due = _date(row['required_at'] ?? row['planned_end_at']);
      if (due == null) continue;
      items.add(
        _TimelineItem(
          title: row['op_number']?.toString() ?? 'Orden de producción',
          subtitle:
              row['product_name']?.toString() ??
              UiCopy.enumLabel(row['status']?.toString() ?? ''),
          date: due,
          quantity: '${_qty(row)} pzas',
          color: due.isBefore(todayDate)
              ? PomgtColors.danger
              : PomgtColors.amber,
        ),
      );
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items.take(7).toList();
  }

  List<_Alert> get alerts {
    final items = <_Alert>[];
    if (missingMaterials > 0) {
      items.add(
        _Alert(
          'Material faltante en producción',
          '$missingMaterials componentes requieren asignación.',
          PomgtColors.danger,
          today,
        ),
      );
    }
    if (dueOrders > 0) {
      items.add(
        _Alert(
          'Pedidos próximos a vencer',
          '$dueOrders pedidos vencen en los próximos 7 días.',
          PomgtColors.amber,
          today.add(const Duration(hours: 2)),
        ),
      );
    }
    if (capacityUsed >= .9) {
      items.add(
        _Alert(
          'Capacidad por encima del 90%',
          'Revisar carga de producción.',
          PomgtColors.amber,
          today.add(const Duration(hours: 3)),
        ),
      );
    }
    if (pendingInspections > 0) {
      items.add(
        _Alert(
          'Inspecciones pendientes',
          '$pendingInspections por liberar en control de calidad.',
          PomgtColors.blue,
          today.add(const Duration(hours: 4)),
        ),
      );
    }
    return items;
  }

  List<_Activity> get activity {
    final rows = <_Activity>[];
    for (final row in ops) {
      rows.add(
        _Activity(
          row['op_number']?.toString() ?? 'Orden de producción',
          'marcada como ${UiCopy.enumLabel(row['status']?.toString() ?? 'sin estado')}',
          row['product_name']?.toString() ?? 'Producción',
          _date(row['updated_at'] ?? row['created_at']) ?? today,
          _colorForStatus(row['status']?.toString() ?? ''),
        ),
      );
    }
    for (final row in orders) {
      rows.add(
        _Activity(
          row['order_number']?.toString() ?? 'Pedido',
          'actualizado a ${UiCopy.enumLabel(row['status']?.toString() ?? 'sin estado')}',
          row['customer_name']?.toString() ?? 'Pedido de cliente',
          _date(row['updated_at'] ?? row['created_at']) ?? today,
          PomgtColors.blue,
        ),
      );
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows.take(5).toList();
  }

  List<Map<String, dynamic>> get recentOps {
    final rows = [...ops];
    rows.sort((a, b) {
      final ad = _date(a['updated_at'] ?? a['created_at']) ?? DateTime(0);
      final bd = _date(b['updated_at'] ?? b['created_at']) ?? DateTime(0);
      return bd.compareTo(ad);
    });
    return rows.take(6).toList();
  }
}

class _Kpi {
  const _Kpi(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.color, {
    this.suffix = '',
  });

  final String label;
  final int value;
  final String caption;
  final IconData icon;
  final Color color;
  final String suffix;
}

class _KpiBoard extends StatelessWidget {
  const _KpiBoard({required this.kpis});
  final List<_Kpi> kpis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(
          color: PomgtColors.lineStrong.withValues(alpha: .55),
        ),
        boxShadow: PomgtShadows.card,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1320
              ? 6
              : constraints.maxWidth >= 920
              ? 4
              : 2;
          final compactTiles = constraints.maxWidth < 920;
          final spacing = compactTiles ? 10.0 : 0.0;
          final itemWidth =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: compactTiles ? 10 : 12,
            children: [
              for (var i = 0; i < kpis.length; i++)
                SizedBox(
                  width: itemWidth,
                  child: _KpiTile(
                    kpi: kpis[i],
                    compact: compactTiles,
                    showDivider:
                        !compactTiles &&
                        columns > 1 &&
                        i % columns != columns - 1,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.kpi,
    required this.showDivider,
    required this.compact,
  });
  final _Kpi kpi;
  final bool showDivider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 122 : 82,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 12 : 0,
      ),
      decoration: BoxDecoration(
        color: compact ? PomgtColors.surfaceAlt : null,
        borderRadius: compact ? PomgtRadii.borderSm : null,
        border: Border(
          top: compact
              ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .35))
              : BorderSide.none,
          left: compact
              ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .35))
              : BorderSide.none,
          right: showDivider
              ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .45))
              : compact
              ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .35))
              : BorderSide.none,
          bottom: compact
              ? BorderSide(color: PomgtColors.lineStrong.withValues(alpha: .35))
              : BorderSide.none,
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(kpi.icon, color: kpi.color, size: 22),
                    const SizedBox(width: 8),
                    Expanded(child: _KpiLabel(kpi.label)),
                  ],
                ),
                const Spacer(),
                Text(
                  '${kpi.value}${kpi.suffix}',
                  style: const TextStyle(
                    color: PomgtColors.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 7),
                _KpiCaption(kpi.caption),
              ],
            )
          : Row(
              children: [
                Icon(kpi.icon, color: kpi.color, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _KpiLabel(kpi.label),
                      const SizedBox(height: 4),
                      Text(
                        '${kpi.value}${kpi.suffix}',
                        style: const TextStyle(
                          color: PomgtColors.ink,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _KpiCaption(kpi.caption),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _KpiLabel extends StatelessWidget {
  const _KpiLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: PomgtColors.muted,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _KpiCaption extends StatelessWidget {
  const _KpiCaption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: PomgtColors.muted,
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
    ),
  );
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid({
    required this.left,
    required this.center,
    required this.right,
  });
  final Widget left;
  final Widget center;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            children: [
              left,
              const SizedBox(height: 16),
              center,
              const SizedBox(height: 16),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: center),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.action,
    this.link,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 18),
  });

  final String title;
  final Widget child;
  final String? action;
  final String? link;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(
          color: PomgtColors.lineStrong.withValues(alpha: .55),
        ),
        boxShadow: PomgtShadows.card,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PomgtColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      const InfoTip('Información del panel.', size: 15),
                    ],
                  ),
                ),
                if (action != null)
                  _FilterChipLike(label: action!)
                else if (link != null)
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
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _FilterChipLike extends StatelessWidget {
  const _FilterChipLike({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderSm,
        border: Border.all(color: PomgtColors.line),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            CupertinoIcons.chevron_down,
            size: 13,
            color: PomgtColors.muted,
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.values,
    required this.labels,
    required this.maxLabel,
    required this.legend,
    required this.color,
    this.percent = false,
  });

  final List<double> values;
  final List<String> labels;
  final String maxLabel;
  final String legend;
  final Color color;
  final bool percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _AreaChartPainter(
                values: values,
                labels: labels,
                color: color,
                percent: percent,
                maxLabel: maxLabel,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                legend,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AreaChartPainter extends CustomPainter {
  const _AreaChartPainter({
    required this.values,
    required this.labels,
    required this.color,
    required this.percent,
    required this.maxLabel,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final bool percent;
  final String maxLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const bottom = 28.0;
    const top = 8.0;
    final chartWidth = size.width - left - 4;
    final chartHeight = size.height - top - bottom;
    final maxValue = percent ? 1.0 : math.max(200.0, values.reduce(math.max));
    final gridPaint = Paint()
      ..color = PomgtColors.lineStrong.withValues(alpha: .42)
      ..strokeWidth = 1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < 5; i++) {
      final y = top + chartHeight * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      final label = percent ? '${(100 - i * 25)}%' : '${200 - i * 50}';
      _paintText(canvas, textPainter, label, Offset(0, y - 7), 11);
    }
    for (var i = 0; i < labels.length; i++) {
      final x = left + chartWidth * i / (labels.length - 1);
      canvas.drawLine(Offset(x, top), Offset(x, top + chartHeight), gridPaint);
      _paintText(
        canvas,
        textPainter,
        labels[i],
        Offset(x - 16, top + chartHeight + 9),
        10.5,
      );
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = left + chartWidth * i / (values.length - 1);
      final normalized = (values[i] / maxValue).clamp(0, 1);
      final y = top + chartHeight * (1 - normalized);
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = (previous.dx + current.dx) / 2;
      path.cubicTo(mid, previous.dy, mid, current.dy, current.dx, current.dy);
    }
    final area = Path.from(path)
      ..lineTo(points.last.dx, top + chartHeight)
      ..lineTo(points.first.dx, top + chartHeight)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .02)],
        ).createShader(Rect.fromLTWH(left, top, chartWidth, chartHeight)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 4.2, Paint()..color = PomgtColors.canvas);
      canvas.drawCircle(point, 3.2, Paint()..color = color);
    }
  }

  void _paintText(
    Canvas canvas,
    TextPainter painter,
    String text,
    Offset offset,
    double size,
  ) {
    painter.text = TextSpan(
      text: text,
      style: TextStyle(
        color: PomgtColors.muted,
        fontSize: size,
        fontWeight: FontWeight.w700,
      ),
    );
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AreaChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _StatusItem {
  const _StatusItem(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

class _DonutStatus extends StatelessWidget {
  const _DonutStatus({required this.items});
  final List<_StatusItem> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, item) => sum + item.value);
    if (total == 0) {
      return const SizedBox(
        height: 190,
        child: _EmptyDashboardMessage(text: 'Sin órdenes de producción.'),
      );
    }
    return SizedBox(
      height: 190,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 166,
            child: CustomPaint(
              painter: _DonutPainter(items: items),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      total.toString(),
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'OPs totales',
                      style: TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: items.map((item) {
                final percent = total == 0
                    ? 0
                    : (item.value / total * 100).round();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${item.value}',
                        style: const TextStyle(
                          color: PomgtColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '$percent%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.items});
  final List<_StatusItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    final total = items.fold<int>(0, (sum, item) => sum + item.value);
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = math.min(size.width, size.height) * .18;
    final rect = Rect.fromCircle(center: center, radius: (side - stroke) / 2);
    var start = -math.pi / 2;
    for (final item in items) {
      final sweep = total == 0 ? 0.0 : (item.value / total) * math.pi * 2;
      canvas.drawArc(
        rect.deflate(stroke),
        start,
        sweep,
        false,
        Paint()
          ..color = item.color
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _Activity {
  const _Activity(
    this.title,
    this.action,
    this.subtitle,
    this.date,
    this.color,
  );
  final String title;
  final String action;
  final String subtitle;
  final DateTime date;
  final Color color;
}

class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items});
  final List<_Activity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyDashboardMessage(text: 'Sin actividad reciente.');
    }
    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 74,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      _time(item.date),
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.title} ${item.action}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Hoy',
                style: TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TimelineItem {
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.quantity,
    required this.color,
  });
  final String title;
  final String subtitle;
  final DateTime date;
  final String quantity;
  final Color color;
}

class _DueList extends StatelessWidget {
  const _DueList({required this.items});
  final List<_TimelineItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyDashboardMessage(text: 'Sin vencimientos próximos.');
    }
    return Column(
      children: items.map((item) {
        return Container(
          height: 28,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: PomgtColors.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  _relativeDate(item.date),
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PomgtColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  item.subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                item.quantity,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Alert {
  const _Alert(this.title, this.message, this.color, this.date);
  final String title;
  final String message;
  final Color color;
  final DateTime date;
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.alerts});
  final List<_Alert> alerts;

  @override
  Widget build(BuildContext context) => Column(
    children: alerts.map((alert) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: alert.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PomgtColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Hoy ${_time(alert.date)}',
              style: const TextStyle(
                color: PomgtColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

class _RecentOrdersTable extends StatelessWidget {
  const _RecentOrdersTable({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: _EmptyDashboardMessage(text: 'Sin órdenes recientes.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 980 ? 980 : constraints.maxWidth,
          child: ClipRRect(
            borderRadius: PomgtRadii.borderSm,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(.75),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.25),
                3: FlexColumnWidth(.8),
                4: FlexColumnWidth(.95),
                5: FlexColumnWidth(.95),
                6: FlexColumnWidth(1.05),
                7: FlexColumnWidth(1.05),
                8: FlexColumnWidth(.45),
              },
              children: [
                _tableRow([
                  'OP',
                  'Producto',
                  'Cliente',
                  'Cantidad',
                  'Estado',
                  'Fecha inicio',
                  'Fecha compromiso',
                  'Avance',
                  'Acciones',
                ], header: true),
                for (final row in rows) _orderRow(row),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TableRow _orderRow(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final planned = ((row['planned_quantity'] as num?)?.toDouble() ?? 0);
    final completed = ((row['completed_quantity'] as num?)?.toDouble() ?? 0);
    final progress = planned <= 0
        ? 0.0
        : (completed / planned).clamp(0, 1).toDouble();
    return _tableRow(
      [
        row['op_number']?.toString() ?? '-',
        row['product_name']?.toString() ?? 'Producto',
        row['customer_name']?.toString() ?? '-',
        '${planned.round()} pzas',
        UiCopy.enumLabel(status),
        _shortDate(_date(row['planned_start_at']) ?? DateTime.now()),
        _shortDate(
          _date(row['required_at'] ?? row['planned_end_at']) ?? DateTime.now(),
        ),
        '${(progress * 100).round()}%',
        '•••',
      ],
      status: status,
      progress: progress,
    );
  }

  TableRow _tableRow(
    List<String> cells, {
    bool header = false,
    String status = '',
    double progress = 0,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        color: header ? PomgtColors.surfaceAlt : PomgtColors.canvas,
        border: const Border(bottom: BorderSide(color: PomgtColors.line)),
      ),
      children: [
        for (var i = 0; i < cells.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: i == 4 && !header
                ? _StatusText(status: status)
                : i == 7 && !header
                ? _ProgressCell(value: progress, label: cells[i])
                : Text(
                    cells[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: header ? PomgtColors.muted : PomgtColors.ink,
                      fontSize: header ? 11.5 : 12,
                      fontWeight: header ? FontWeight.w900 : FontWeight.w800,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus(status);
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

class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.value, required this.label});
  final double value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: PomgtRadii.borderSm,
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: PomgtColors.surfaceAlt,
              valueColor: const AlwaysStoppedAnimation(PomgtColors.blue),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
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
}

class _EmptyDashboardMessage extends StatelessWidget {
  const _EmptyDashboardMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          color: PomgtColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _qty(Map<String, dynamic> row) =>
    ((row['planned_quantity'] as num?) ?? (row['quantity'] as num?) ?? 0)
        .round();

String _shortDate(DateTime date) {
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

String _relativeDate(DateTime date) {
  final today = _dayOnly(DateTime.now());
  final target = _dayOnly(date);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  return '${date.day} ${_monthShort(date)}';
}

String _monthShort(DateTime date) {
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
  return months[date.month - 1];
}

String _longDate(DateTime date) {
  const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  return '${days[date.weekday - 1]}, ${date.day} de ${_monthShort(date)} de ${date.year}';
}

String _time(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

Color _colorForStatus(String status) {
  final value = status.toLowerCase();
  if (value.contains('completed') || value.contains('done')) {
    return PomgtColors.success;
  }
  if (value.contains('hold') || value.contains('blocked')) {
    return PomgtColors.danger;
  }
  if (value.contains('draft') ||
      value.contains('pending') ||
      value.contains('planned') ||
      value.contains('ready')) {
    return PomgtColors.amber;
  }
  if (value.contains('cancel')) {
    return PomgtColors.lineStrong;
  }
  return PomgtColors.blue;
}
