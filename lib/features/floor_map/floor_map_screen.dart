import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../controllers/organization_controller.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/pomgt_loading.dart';
import '../../core/widgets/number_input.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/production_repository.dart';
import '../production/production_operator_display.dart';
import 'floor_map_data.dart';

part 'floor_map_painters.dart';

const _statuses = [
  'busy',
  'queued',
  'available',
  'setup',
  'maintenance',
  'down',
  'inactive',
];
Color _statusColor(String status) => switch (status) {
  'busy' => PomgtColors.blue,
  'queued' => PomgtColors.cyan,
  'available' => PomgtColors.success,
  'setup' => PomgtColors.violet,
  'maintenance' => PomgtColors.warning,
  'down' => PomgtColors.danger,
  _ => PomgtColors.muted,
};
Color _zoneColor(String? kind) => switch (kind) {
  'storage' => PomgtColors.amber,
  'quality' => PomgtColors.violet,
  'shipping' => PomgtColors.cyan,
  _ => PomgtColors.blue,
};
const _movementLabels = {
  'receipt': 'Entrada',
  'issue': 'Salida',
  'adjustment_in': 'Ajuste de entrada',
  'adjustment_out': 'Ajuste de salida',
};

class FloorMapScreen extends StatefulWidget {
  const FloorMapScreen({
    super.key,
    this.repository,
    this.refreshInterval = const Duration(seconds: 9),
  });
  final ProductionRepository? repository;
  final Duration refreshInterval;
  @override
  State<FloorMapScreen> createState() => _FloorMapScreenState();
}

class _FloorMapScreenState extends State<FloorMapScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final ProductionRepository _repository;
  final _transform = TransformationController();
  final _searchController = TextEditingController();
  late final AnimationController _flowAnimation;
  Timer? _timer;
  FloorData? _data;
  Object? _error;
  DateTime? _lastUpdated;
  bool _loading = false,
      _editing = false,
      _onlyRunning = true,
      _flows = true,
      _orderRowsView = false,
      _expanded = true;
  String _search = '';
  bool _showFilters = false;
  String? _category,
      _workCenter,
      _status,
      _selectedMachine,
      _selectedWarehouse,
      _orderId;
  FloorRow? _detail;
  Object? _detailError;
  int _detailVersion = 0;
  bool _detailLoading = false;
  String? _loadingDetailOrder;
  bool _refreshQueued = false;
  bool _initialMapFocused = false;
  final Map<String, Offset> _positions = {};
  final Set<String> _saving = {}, _dragging = {};
  final Map<String, Offset> _dragOrigins = {};
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _flowAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
    );
    WidgetsBinding.instance.addObserver(this);
    if (widget.repository != null) {
      _repository = widget.repository!;
    } else {
      final generic = context.read<GenericRepository>();
      _repository = ProductionRepository(generic.service, generic.client);
      final org = context.read<OrganizationController>().organizationId;
      if (org != null) _repository.setOrganization(org);
    }
    unawaited(_refresh());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.refreshInterval, (_) {
      if (TickerMode.valuesOf(context).enabled) unawaited(_refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _transform.dispose();
    _searchController.dispose();
    _flowAnimation.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool afterMutation = false}) async {
    if (_loading) {
      if (afterMutation) _refreshQueued = true;
      return;
    }
    final settled = Map<String, Offset>.fromEntries(
      _positions.entries.where(
        (e) => !_saving.contains(e.key) && !_dragging.contains(e.key),
      ),
    );
    setState(() => _loading = true);
    try {
      final data = FloorData(await _repository.floorSnapshot());
      if (!mounted) return;
      setState(() {
        for (final entry in settled.entries) {
          if (_positions[entry.key] == entry.value &&
              !_saving.contains(entry.key) &&
              !_dragging.contains(entry.key)) {
            _positions.remove(entry.key);
          }
        }
        _data = data;
        _error = null;
        _lastUpdated = DateTime.now();
        if (_selectedMachine != null &&
            data.row('machines', _selectedMachine) == null) {
          _selectedMachine = null;
        }
        if (_selectedWarehouse != null &&
            data.row('warehouses', _selectedWarehouse) == null) {
          _selectedWarehouse = null;
        }
        if (_category != null &&
            data.row('machine_categories', _category) == null) {
          _category = null;
        }
        if (_workCenter != null &&
            data.row('work_centers', _workCenter) == null) {
          _workCenter = null;
        }
      });
      if (data.hasAnimatedFlow) {
        if (!_flowAnimation.isAnimating) _flowAnimation.repeat();
      } else {
        _flowAnimation.stop();
        _flowAnimation.value = 0;
      }
      // Details are refreshed too; never reuse another order's materials.
      if (_orderId != null) unawaited(_loadDetail(_orderId!));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(_refresh());
        }
      }
    }
  }

  Future<void> _loadDetail(String id) async {
    if (_detailLoading && _loadingDetailOrder == id) return;
    _loadingDetailOrder = id;
    final version = ++_detailVersion;
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final detail = await _repository.floorOrderDetail(id);
      if (!mounted || version != _detailVersion || id != _orderId) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (error) {
      if (mounted && version == _detailVersion) {
        setState(() {
          _detailError = error;
          _detailLoading = false;
        });
      }
    }
  }

  void _selectMachine(String id) {
    setState(() {
      _selectedMachine = id;
      _selectedWarehouse = null;
      _orderId = null;
      _detail = null;
      _detailError = null;
      _detailLoading = false;
      _detailVersion++;
      _expanded = true;
    });
  }

  void _selectOrder(String id) {
    if (id == _orderId) return;
    setState(() {
      _orderId = id;
      if (!_orderRowsView) _onlyRunning = false;
      _category = null;
      _workCenter = null;
      _status = null;
      _search = '';
      _searchController.clear();
      _detail = null;
      _expanded = true;
    });
    if (!_orderRowsView) _refitSoon();
    unawaited(_loadDetail(id));
  }

  void _closePanel() => setState(() {
    _selectedMachine = null;
    _selectedWarehouse = null;
    _orderId = null;
    _detail = null;
    _detailError = null;
    _detailLoading = false;
    _detailVersion++;
  });
  void _errorNotice(Object error) => showPomgtSnackBar(
    context,
    ErrorCopy.message(error, fallback: 'No fue posible guardar los cambios.'),
    isError: true,
  );
  Offset _position(String kind, FloorRow row, int index) =>
      _positions['$kind:${row['id']}'] ??
      (kind == 'zone'
          ? Offset(floorNumber(row['x']), floorNumber(row['y']))
          : kind == 'machine'
          ? _data!.machinePosition(row, index)
          : floorPosition(row, index, warehouse: true));
  void _move(String key, Offset delta) {
    final current = _positions[key]!;
    // Gesture deltas are already expressed in the transformed local space.
    setState(
      () => _positions[key] = Offset(
        math.max(0, current.dx + delta.dx),
        math.max(0, current.dy + delta.dy),
      ),
    );
  }

  Future<void> _savePosition(String kind, FloorRow row) async {
    final key = '$kind:${row['id']}';
    final point = _positions[key]!;
    setState(() {
      _dragging.remove(key);
      _saving.add(key);
    });
    try {
      if (kind == 'machine') {
        await _repository.updateMachinePosition(
          '${row['id']}',
          point.dx,
          point.dy,
        );
      } else if (kind == 'warehouse') {
        await _repository.saveFloorWarehouse({
          'floor_pos_x': point.dx,
          'floor_pos_y': point.dy,
        }, id: '${row['id']}');
      } else {
        await _repository.saveFloorZone({
          'x': point.dx,
          'y': point.dy,
        }, id: '${row['id']}');
      }
      if (!mounted) return;
      // Keep the successful position in the snapshot until the next server read.
      final table = kind == 'machine'
          ? 'machines'
          : kind == 'zone'
          ? 'floor_zones'
          : 'warehouses';
      for (final item in (_data!.raw[table] as List)) {
        if (item['id'] == row['id']) {
          item[kind == 'zone' ? 'x' : 'floor_pos_x'] = point.dx;
          item[kind == 'zone' ? 'y' : 'floor_pos_y'] = point.dy;
        }
      }
    } catch (error) {
      _positions.remove(key);
      if (mounted) _errorNotice(error);
    } finally {
      if (mounted) {
        setState(() {
          _saving.remove(key);
          _dragOrigins.remove(key);
        });
      }
    }
  }

  bool _matches(FloorRow machine) {
    final data = _data!;
    if (_onlyRunning && !data.machineIsRunning(machine)) return false;
    if (_category != null && machine['category_id'] != _category) return false;
    if (_workCenter != null && machine['work_center_id'] != _workCenter) {
      return false;
    }
    if (_status != null && data.status(machine) != _status) return false;
    if (_search.isEmpty) return true;
    final orders = data
        .queueOn('${machine['id']}')
        .map((o) => data.row('orders', o['production_order_id']));
    return '${machine.values.join(' ')} ${orders.map((o) => o?.values.join(' ')).join(' ')}'
        .toLowerCase()
        .contains(_search);
  }

  void _fit() {
    if (_data == null || _viewport.isEmpty) return;
    final visible = _data!.machines.where(_matches).toList();
    final size = _data!.bounds(
      _positions,
      visibleMachines: visible,
      includeStorage: false,
    );
    final scale = math
        .min(_viewport.width / size.width, _viewport.height / size.height)
        .clamp(.12, 2.5);
    _transform.value = Matrix4.identity()
      ..translateByDouble(16.0, 16.0, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  void _refitSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit();
    });
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.12, 3.0);
    final center = _viewport.center(Offset.zero);
    final scene = _transform.toScene(center);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        center.dx - scene.dx * next,
        center.dy - scene.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: PomgtColors.appBg,
      body: Column(
        children: [
          SizedBox(width: double.infinity, child: _toolbar()),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            _banner(
              ErrorCopy.message(
                _error!,
                fallback: 'No fue posible actualizar. Se conserva la última información.',
              ),
              error: true,
            ),
          Expanded(
            child: data == null
                ? (_error == null
                      ? const PomgtLoading()
                      : Center(
                          child: TextButton(
                            onPressed: _refresh,
                            child: const Text('Reintentar'),
                          ),
                        ))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final panel =
                          _selectedMachine != null ||
                          _selectedWarehouse != null ||
                          _orderId != null;
                      final compact = constraints.maxWidth < 1000;
                      final content = _map(data);
                      if (compact) {
                        return Stack(
                          children: [
                            Positioned.fill(child: content),
                            if (panel)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  height:
                                      constraints.maxHeight *
                                      (_expanded ? .82 : .28),
                                  width: constraints.maxWidth,
                                  child: _panel(data),
                                ),
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: content),
                          if (panel)
                            SizedBox(
                              width: _expanded ? 420 : 290,
                              child: _panel(data),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, {bool error = false}) => Container(
    width: double.infinity,
    color: (error ? PomgtColors.danger : PomgtColors.warning).withValues(
      alpha: .09,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Icon(
          error ? LucideIcons.wifiOff : LucideIcons.info,
          size: 16,
          color: error ? PomgtColors.danger : PomgtColors.ink,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        if (error)
          TextButton(onPressed: _refresh, child: const Text('Reintentar')),
      ],
    ),
  );
  Widget _toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 900;
      final search = TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Máquina, orden o paso…',
          prefixIcon: Icon(LucideIcons.search, size: 17),
        ),
      );
      final filters = <Widget>[
        if (_data != null) ...[
          _filter(
            'Categoría',
            _category,
            floorRows(_data!.raw['machine_categories']),
            (v) => setState(() => _category = v),
          ),
          _filter(
            'Centro de trabajo',
            _workCenter,
            floorRows(_data!.raw['work_centers']),
            (v) => setState(() => _workCenter = v),
          ),
        ],
      ];
      final timestamp = Text(
        _lastUpdated == null
            ? 'Sin sincronizar'
            : 'Actualizado ${_lastUpdated!.toLocal().toString().substring(11, 19)} · cada ${widget.refreshInterval.inSeconds}s',
        style: TextStyle(
          fontSize: 11,
          color: _error == null ? PomgtColors.muted : PomgtColors.danger,
        ),
      );
      final refresh = IconButton(
        tooltip: 'Actualizar',
        onPressed: _loading ? null : _refresh,
        icon: const Icon(LucideIcons.refreshCw, size: 18),
      );
      return Material(
        color: PomgtColors.canvas,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                Row(
                  children: [
                    const Icon(LucideIcons.factory, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Mapa de planta',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Filtros de máquinas',
                      onPressed: () =>
                          setState(() => _showFilters = !_showFilters),
                      icon: Icon(
                        LucideIcons.slidersHorizontal,
                        size: 18,
                        color: _showFilters
                            ? PomgtColors.blue
                            : PomgtColors.muted,
                      ),
                    ),
                    refresh,
                  ],
                ),
                search,
                if (_showFilters) ...[
                  Wrap(spacing: 8, runSpacing: 8, children: filters),
                  timestamp,
                ],
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(LucideIcons.factory, size: 22),
                    const Text(
                      'Mapa de planta',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 230, child: search),
                    ...filters,
                    refresh,
                    timestamp,
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  Widget _filter(
    String label,
    String? value,
    List<FloorRow> rows,
    ValueChanged<String?> onChange,
  ) => SizedBox(
    width: 165,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(isDense: true, labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('Todos')),
        for (final row in rows)
          DropdownMenuItem(
            value: '${row['id']}',
            child: Text(
              floorText(row['name']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChange,
    ),
  );

  Widget _mapControls(FloorData data) => Material(
    color: PomgtColors.canvas,
    elevation: 2,
    borderRadius: PomgtRadii.borderMd,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _mapChip(
                  label: 'Plano 2D',
                  selected: !_orderRowsView,
                  onSelected: () => setState(() => _orderRowsView = false),
                ),
                _mapChip(
                  label: 'Filas por orden',
                  selected: _orderRowsView,
                  onSelected: () => setState(() => _orderRowsView = true),
                ),
                _mapChip(
                  label: 'Solo máquinas en marcha',
                  selected: _onlyRunning,
                  key: const ValueKey('running-machines-filter'),
                  onSelected: () {
                    setState(() => _onlyRunning = !_onlyRunning);
                    _refitSoon();
                  },
                ),
                _mapChip(
                  label: 'Flujo de producción',
                  selected: _flows,
                  onSelected: () => setState(() => _flows = !_flows),
                ),
              ],
            ),
          ),
          if (data.activeOrdersWithoutMachine > 0) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip:
                  '${data.activeOrdersWithoutMachine} órdenes con pasos sin máquina',
              onPressed: () => _showFlowWarnings(data),
              icon: Badge(
                label: Text('${data.activeOrdersWithoutMachine}'),
                child: const Icon(
                  LucideIcons.triangleAlert,
                  color: PomgtColors.warning,
                  size: 20,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _mapChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    Key? key,
  }) => FilterChip(
    key: key,
    label: Text(label),
    selected: selected,
    selectedColor: PomgtColors.blue,
    backgroundColor: Colors.white,
    checkmarkColor: Colors.white,
    side: BorderSide(
      color: selected ? PomgtColors.blue : PomgtColors.lineStrong,
    ),
    labelStyle: TextStyle(
      color: selected ? Colors.white : PomgtColors.blue,
      fontWeight: FontWeight.w600,
    ),
    onSelected: (_) => onSelected(),
  );

  Future<void> _showFlowWarnings(FloorData data) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.triangleAlert, color: PomgtColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pasos sin máquina (${data.activeOrdersWithoutMachine})',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final operation in data.unassignedRouteOperations)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    LucideIcons.route,
                    color: PomgtColors.blue,
                  ),
                  title: Text(
                    '${data.name('orders', operation['production_order_id'])} · ${floorText(operation['name'])}',
                  ),
                  subtitle: Text(
                    'Paso ${floorText(operation['sequence_no'])} · Centro: ${data.name('work_centers', operation['work_center_id'])}',
                  ),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _selectOrder('${operation['production_order_id']}');
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );

  Widget _map(FloorData data) =>
      _orderRowsView ? _orderFlow(data) : _plantMap(data);

  Widget _plantMap(FloorData data) => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = Size(constraints.maxWidth, constraints.maxHeight);
      if (!_initialMapFocused && !_viewport.isEmpty) {
        _initialMapFocused = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusInitialMachine(data);
        });
      }
      final visible = data.machines.where(_matches).toList();
      final size = data.bounds(
        _positions,
        visibleMachines: visible,
        includeStorage: false,
      );
      final emptyMessage = data.activeOrdersWithoutMachine > 0
          ? '${data.activeOrdersWithoutMachine} órdenes en producción o listas tienen pasos sin máquina asignada.'
          : _onlyRunning
          ? 'No hay máquinas en marcha ni asociadas a rutas en producción o listas. Desactiva el filtro para revisar todas.'
          : 'No hay máquinas registradas para mostrar.';
      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              key: const ValueKey('factory-canvas'),
              transformationController: _transform,
              minScale: .12,
              maxScale: 3,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(500),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _flowAnimation,
                        builder: (context, _) => CustomPaint(
                          painter: _FactoryPainter(
                            data: data,
                            positions: _positions,
                            flows: _flows,
                            visible: visible.map((m) => '${m['id']}').toSet(),
                            selectedOrder: _orderId,
                            animationProgress: _flowAnimation.value,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < data.machines.length; i++)
                      if (_matches(data.machines[i]))
                        _machine(data, data.machines[i], i),
                    if (visible.isEmpty && data.machines.isNotEmpty)
                      Positioned(
                        left: 90,
                        top: 100,
                        child: Text(
                          emptyMessage,
                          style: const TextStyle(color: PomgtColors.muted),
                        ),
                      ),
                    if (data.machines.isEmpty)
                      const Positioned(
                        left: 80,
                        top: 100,
                        child: Text(
                          'Registra tu equipo en Datos maestros para visualizarlo aquí.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(top: 12, left: 12, right: 76, child: _mapControls(data)),
          Positioned(
            top: 12,
            right: 12,
            child: Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Acercar',
                    onPressed: () => _zoom(1.25),
                    icon: const Icon(LucideIcons.plus, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Alejar',
                    onPressed: () => _zoom(.8),
                    icon: const Icon(LucideIcons.minus, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Ver toda la planta',
                    onPressed: _fit,
                    icon: const Icon(LucideIcons.maximize, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Restablecer vista',
                    onPressed: () => _transform.value = Matrix4.identity(),
                    icon: const Icon(LucideIcons.rotateCcw, size: 18),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            right: constraints.maxWidth >= 650 && constraints.maxHeight >= 360
                ? 204
                : 70,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 6,
                children: [
                  for (final status in _statuses)
                    ActionChip(
                      avatar: Icon(
                        LucideIcons.circle,
                        size: 12,
                        color: _statusColor(status),
                      ),
                      backgroundColor: _status == status
                          ? _statusColor(status).withValues(alpha: .15)
                          : PomgtColors.canvas,
                      label: Text(
                        '${UiCopy.enumLabel(status)} ${data.machines.where((m) => data.status(m) == status).length}',
                      ),
                      onPressed: () => setState(() {
                        _status = _status == status ? null : status;
                        if (_status != null && status != 'busy') {
                          _onlyRunning = false;
                        }
                        _refitSoon();
                      }),
                    ),
                  if (_status != null)
                    ActionChip(
                      label: const Text('Ver todos'),
                      onPressed: () => setState(() => _status = null),
                    ),
                ],
              ),
            ),
          ),
          if (constraints.maxWidth >= 650 && constraints.maxHeight >= 360)
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(10),
                color: PomgtColors.canvas,
                child: GestureDetector(
                  onTapDown: (details) {
                    final factor = math.min(
                      172 / size.width,
                      102 / size.height,
                    );
                    final world = Offset(
                      (details.localPosition.dx - 4) / factor,
                      (details.localPosition.dy - 4) / factor,
                    );
                    final scale = _transform.value.getMaxScaleOnAxis();
                    final center = _viewport.center(Offset.zero);
                    _transform.value = Matrix4.identity()
                      ..translateByDouble(
                        center.dx - world.dx * scale,
                        center.dy - world.dy * scale,
                        0,
                        1,
                      )
                      ..scaleByDouble(scale, scale, 1, 1);
                  },
                  child: Tooltip(
                    message: 'Minimapa: toca para navegar',
                    child: SizedBox(
                      width: 180,
                      height: 110,
                      child: AnimatedBuilder(
                        animation: _transform,
                        builder: (context, _) => CustomPaint(
                          painter: _MiniMapPainter(
                            data,
                            _positions,
                            _transform,
                            _viewport,
                            visible
                                .map((machine) => '${machine['id']}')
                                .toSet(),
                            false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  void _focusInitialMachine(FloorData data) {
    if (_viewport.isEmpty) return;
    final running = data.operations.where(data.operationIsRunning);
    FloorRow? machine;
    for (final operation in running) {
      machine = data.row('machines', operation['machine_id']);
      if (machine != null) break;
    }
    if (machine == null) {
      for (final item in data.machines) {
        if (_matches(item)) {
          machine = item;
          break;
        }
      }
    }
    if (machine == null) {
      _fit();
      return;
    }
    final p = _position('machine', machine, data.machines.indexOf(machine));
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        _viewport.width / 2 - p.dx - 110,
        _viewport.height / 2 - p.dy - 75,
        0,
        1,
      )
      ..scaleByDouble(1, 1, 1, 1);
  }

  Widget _orderFlow(FloorData data) {
    final visibleStatuses = _onlyRunning
        ? {'ready', 'in_progress', 'on_hold'}
        : {'draft', 'planned', 'ready', 'in_progress', 'on_hold'};
    final orders =
        data.orders.where((order) {
          final steps = data.operationsByOrder['${order['id']}'] ?? const [];
          return visibleStatuses.contains(order['status']) && steps.isNotEmpty;
        }).toList()..sort((a, b) {
          final stateOrder = (order) => switch (order['status']) {
            'in_progress' => 0,
            'on_hold' => 1,
            'ready' => 2,
            _ => 3,
          };
          final byState = stateOrder(a).compareTo(stateOrder(b));
          if (byState != 0) return byState;
          return '${a['op_number']}'.compareTo('${b['op_number']}');
        });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: _mapControls(data),
        ),
        Expanded(
          child: orders.isEmpty
              ? const Center(
                  child: Text('No hay órdenes con rutas en este flujo.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  itemCount: orders.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                        child: Text(
                          '${orders.length} órdenes · rutas de fabricación por máquina',
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return _orderFlowLane(data, orders[index - 1]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _orderFlowLane(FloorData data, FloorRow order) {
    final id = '${order['id']}';
    final steps = data.operationsByOrder[id] ?? const <FloorRow>[];
    final progress = (floorNumber(order['progress_pct']) / 100).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _selectOrder(id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const Icon(LucideIcons.route, color: PomgtColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${floorText(order['op_number'])} · ${floorText(order['product_name'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${UiCopy.enumLabel('${order['status']}')} · ${floorQuantity(order['planned_quantity'])} ${floorText(order['uom_symbol'])}',
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: progress, minHeight: 4),
                        const SizedBox(height: 4),
                        Text(
                          '${(progress * 100).round()}% · ${steps.length} pasos',
                          style: const TextStyle(
                            fontSize: 10,
                            color: PomgtColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.chevronRight, size: 18),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  if (index > 0 && _flows)
                    _orderFlowLink(data, steps[index - 1]),
                  _orderFlowStep(data, steps[index]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderFlowStep(FloorData data, FloorRow operation) {
    final machineId = operation['machine_id']?.toString();
    final state = data.operationState(operation);
    final statusColor = ['completed', 'skipped'].contains(operation['status'])
        ? PomgtColors.success
        : state == 'En ejecución'
        ? PomgtColors.blue
        : state == 'Preparación'
        ? PomgtColors.violet
        : state == 'Necesita continuar'
        ? PomgtColors.warning
        : state == 'Lista para seguir'
        ? PomgtColors.cyan
        : PomgtColors.muted;
    return SizedBox(
      width: 218,
      child: _pulseGlow(
        active: data.operationIsRunning(operation),
        color: statusColor,
        child: Card(
          margin: EdgeInsets.zero,
          color: PomgtColors.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: PomgtRadii.borderMd,
            side: BorderSide(color: statusColor.withValues(alpha: .35)),
          ),
          child: InkWell(
            onTap: machineId == null ? null : () => _selectMachine(machineId),
            borderRadius: PomgtRadii.borderMd,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pulseActivity(
                        Icon(
                          Icons.precision_manufacturing,
                          size: 28,
                          color: statusColor,
                        ),
                        active: data.operationIsRunning(operation),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Paso ${floorText(operation['sequence_no'])}',
                          style: const TextStyle(
                            color: PomgtColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    floorText(operation['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    machineId == null
                        ? 'Máquina sin asignar · ${data.name('work_centers', operation['work_center_id'])}'
                        : data.name('machines', machineId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: machineId == null
                          ? PomgtColors.warning
                          : PomgtColors.secondaryInk,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pulseActivity(
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        active: data.operationIsRunning(operation),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          state,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderFlowLink(FloorData data, FloorRow source) => SizedBox(
    width: 70,
    height: 42,
    child: AnimatedBuilder(
      animation: _flowAnimation,
      builder: (context, _) => CustomPaint(
        painter: _OrderFlowLinkPainter(
          data: data,
          source: source,
          animationProgress: _flowAnimation.value,
        ),
      ),
    ),
  );

  Widget _draggable(
    String kind,
    FloorRow row,
    int index,
    Widget child, {
    double? width,
    double? height,
  }) {
    final key = '$kind:${row['id']}';
    final p = _position(kind, row, index);
    return Positioned(
      key: ValueKey(key),
      left: p.dx,
      top: p.dy,
      width: width,
      height: height,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.opaque,
        onPanStart: !_editing || _saving.contains(key)
            ? null
            : (_) => setState(() {
                _positions[key] = p;
                _dragOrigins[key] = p;
                _dragging.add(key);
              }),
        onPanUpdate: !_editing || _saving.contains(key)
            ? null
            : (d) => _move(key, d.delta),
        onPanEnd: !_editing || _saving.contains(key)
            ? null
            : (_) => unawaited(_savePosition(kind, row)),
        onPanCancel: !_editing
            ? null
            : () => setState(() {
                _positions.remove(key);
                _dragging.remove(key);
                _dragOrigins.remove(key);
              }),
        child: child,
      ),
    );
  }

  Widget _pulseActivity(Widget child, {required bool active}) {
    if (!active) return child;
    return AnimatedBuilder(
      animation: _flowAnimation,
      child: child,
      builder: (context, child) {
        final pulse = (math.sin(_flowAnimation.value * math.pi * 2) + 1) / 2;
        return Transform.scale(
          scale: .96 + pulse * .08,
          child: Opacity(opacity: .78 + pulse * .22, child: child),
        );
      },
    );
  }

  /// Soft pulsing glow around a whole card - makes "this is the machine
  /// running the order" readable at a glance, not just a tiny icon inside it.
  Widget _pulseGlow({
    required Widget child,
    required bool active,
    required Color color,
  }) {
    if (!active) return child;
    return AnimatedBuilder(
      animation: _flowAnimation,
      child: child,
      builder: (context, child) {
        final pulse = (math.sin(_flowAnimation.value * math.pi * 2) + 1) / 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: PomgtRadii.borderMd,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .16 + pulse * .22),
                blurRadius: 12 + pulse * 10,
                spreadRadius: pulse * 2,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }

  Widget _machine(FloorData data, FloorRow row, int index) {
    final id = '${row['id']}';
    final active = data.activeOn(id);
    final queue = data.queueOn(id);
    final queueOrderIds = queue
        .map((operation) => '${operation['production_order_id']}')
        .toSet();
    final shownOrders = <FloorRow>[];
    final shownOrderIds = <String>{};
    for (final operation in queue) {
      final orderId = '${operation['production_order_id']}';
      if (shownOrderIds.add(orderId)) shownOrders.add(operation);
      if (shownOrders.length == 2) break;
    }
    final color = _statusColor(data.status(row));
    final isProducing =
        data.status(row) == 'busy' || active.any(data.operationIsRunning);
    final category = data.name('machine_categories', row['category_id']);
    return _draggable(
      'machine',
      row,
      index,
      SizedBox(
        width: 220,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _selectMachine(id),
            borderRadius: PomgtRadii.borderMd,
            child: _pulseGlow(
              active: isProducing,
              color: color,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PomgtColors.canvas,
                  borderRadius: PomgtRadii.borderMd,
                  border: Border.all(
                    color: _selectedMachine == id
                        ? color
                        : PomgtColors.lineStrong,
                    width: _selectedMachine == id ? 2 : 1,
                  ),
                  boxShadow: PomgtShadows.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _pulseActivity(
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          active: isProducing,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            UiCopy.enumLabel(data.status(row)),
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (active.length > 1)
                          Tooltip(
                            message:
                                'Varias operaciones activas en este equipo',
                            child: Icon(
                              LucideIcons.triangleAlert,
                              size: 15,
                              color: PomgtColors.warning,
                            ),
                          ),
                        if (_saving.contains('machine:$id'))
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    Container(
                      height: 62,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _pulseActivity(
                            Icon(
                              Icons.precision_manufacturing,
                              size: 42,
                              color: color,
                            ),
                            active: isProducing,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.name(
                                    'machine_types',
                                    row['machine_type_id'],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: PomgtColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      floorText(row['name']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${floorText(row['machine_code'])} · ${data.name('work_centers', row['work_center_id'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: PomgtColors.muted,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (queue.isEmpty)
                      Text(
                        switch (data.status(row)) {
                          'maintenance' => 'Equipo en mantenimiento',
                          'setup' => 'Equipo en preparación',
                          'down' => 'Equipo detenido',
                          _ => 'Sin órdenes en esta máquina',
                        },
                        style: const TextStyle(
                          fontSize: 11,
                          color: PomgtColors.muted,
                        ),
                      )
                    else ...[
                      const Divider(height: 12),
                      for (final op in shownOrders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: InkWell(
                            onTap: () =>
                                _selectOrder('${op['production_order_id']}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${floorText(data.row('orders', op['production_order_id'])?['op_number'])} · Paso ${floorText(op['sequence_no'])}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: op['status'] == 'in_progress'
                                              ? PomgtColors.blue
                                              : PomgtColors.ink,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${data.completedSteps('${op['production_order_id']}')}/${data.totalSteps('${op['production_order_id']}')}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: PomgtColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${floorText(op['name'])} · ${data.operationState(op)}${op['machine_assignment_inferred'] == true ? ' · máquina inferida por centro' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (queueOrderIds.length > shownOrders.length)
                        Text(
                          '+${queueOrderIds.length - shownOrders.length} órdenes más en esta máquina',
                          style: const TextStyle(
                            fontSize: 10,
                            color: PomgtColors.muted,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderCard(FloorData data, FloorRow order) {
    final progress = (floorNumber(order['progress_pct']) / 100).clamp(0.0, 1.0);
    return Card(
      child: InkWell(
        onTap: () => _selectOrder('${order['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    floorText(order['op_number']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    UiCopy.enumLabel('${order['status']}'),
                    style: const TextStyle(
                      fontSize: 12,
                      color: PomgtColors.blue,
                    ),
                  ),
                  if (['high', 'urgent'].contains(order['priority']))
                    Icon(
                      LucideIcons.flag,
                      size: 15,
                      color: order['priority'] == 'urgent'
                          ? PomgtColors.danger
                          : PomgtColors.warning,
                    ),
                ],
              ),
              Text(
                '${floorText(order['product_sku'])} · ${floorText(order['product_name'])}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                floorText(
                  order['customer_trade_name'] ?? order['customer_name'],
                ),
                style: const TextStyle(color: PomgtColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress, minHeight: 4),
              const SizedBox(height: 6),
              Text(
                '${floorQuantity(order['planned_quantity'])} ${floorText(order['uom_symbol'])} · ${(progress * 100).round()}% · Entrega ${floorText(order['required_at'])}',
                style: const TextStyle(fontSize: 11, color: PomgtColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(FloorData data) {
    final machine = data.row('machines', _selectedMachine);
    final warehouse = data.row('warehouses', _selectedWarehouse);
    final order = data.row('orders', _orderId);
    final title =
        machine?['name'] ??
        warehouse?['name'] ??
        order?['op_number'] ??
        'Detalle';
    return Material(
      elevation: 5,
      color: PomgtColors.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    floorText(title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Minimizar' : 'Expandir',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? LucideIcons.chevronsDownUp
                        : LucideIcons.chevronsUpDown,
                    size: 18,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar detalle',
                  onPressed: _closePanel,
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (machine != null) ...[
                  Text(
                    '${UiCopy.enumLabel(data.status(machine))} · ${floorText(machine['machine_code'])}',
                    style: TextStyle(
                      color: _statusColor(data.status(machine)),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    data.activeOn('${machine['id']}').isEmpty
                        ? 'Estado registrado manualmente · sin operación en ejecución'
                        : 'Estado calculado a partir de operaciones en ejecución',
                    style: const TextStyle(
                      color: PomgtColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  if ((machine['is_active'] == false ||
                          [
                            'maintenance',
                            'down',
                            'inactive',
                          ].contains(machine['status'])) &&
                      data.activeOn('${machine['id']}').isNotEmpty)
                    _banner(
                      'Revisar el equipo: tiene operaciones en ejecución y un estado registrado de inactividad o mantenimiento.',
                    ),
                  if (_expanded) ...[
                    _section('Ficha completa de la máquina', [
                      _record('machines', machine, data),
                    ], initiallyExpanded: true),
                    _section('Centro de trabajo', [
                      if (data.row('work_centers', machine['work_center_id']) !=
                          null)
                        _record(
                          'work_centers',
                          data.row('work_centers', machine['work_center_id'])!,
                          data,
                        ),
                      if (data.row(
                            'machine_types',
                            machine['machine_type_id'],
                          ) !=
                          null)
                        _record(
                          'machine_types',
                          data.row(
                            'machine_types',
                            machine['machine_type_id'],
                          )!,
                          data,
                        ),
                      if (data.row(
                            'machine_categories',
                            machine['category_id'],
                          ) !=
                          null)
                        _record(
                          'machine_categories',
                          data.row(
                            'machine_categories',
                            machine['category_id'],
                          )!,
                          data,
                        ),
                    ]),
                  ],
                  _section(
                    'Operaciones y órdenes (${data.queueOn('${machine['id']}').length})',
                    [
                      if (data.queueOn('${machine['id']}').isEmpty)
                        const Text('Sin operaciones pendientes asignadas.'),
                      for (final op in data.queueOn('${machine['id']}')) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            LucideIcons.cog,
                            color: op['status'] == 'in_progress'
                                ? PomgtColors.blue
                                : PomgtColors.muted,
                          ),
                          title: Text(
                            '${floorText(op['sequence_no'])}. ${floorText(op['name'])}',
                          ),
                          subtitle: Text(UiCopy.enumLabel('${op['status']}')),
                          onTap: () =>
                              _selectOrder('${op['production_order_id']}'),
                        ),
                        if (_expanded &&
                            data.row('orders', op['production_order_id']) !=
                                null)
                          _orderCard(
                            data,
                            data.row('orders', op['production_order_id'])!,
                          ),
                      ],
                    ],
                    initiallyExpanded: true,
                  ),
                  if (_expanded)
                    _section('Historial del equipo', [
                      for (final op
                          in (data.operationsByMachine['${machine['id']}'] ??
                                  [])
                              .where(
                                (o) => [
                                  'completed',
                                  'skipped',
                                  'cancelled',
                                ].contains(o['status']),
                              ))
                        ListTile(
                          dense: true,
                          title: Text(floorText(op['name'])),
                          subtitle: Text(
                            '${UiCopy.enumLabel('${op['status']}')} · ${data.name('orders', op['production_order_id'])}',
                          ),
                          onTap: () =>
                              _selectOrder('${op['production_order_id']}'),
                        ),
                    ]),
                ],
                if (warehouse != null) ...[
                  if (_expanded) _record('warehouses', warehouse, data),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _inventoryDialog(warehouse: warehouse),
                        icon: const Icon(LucideIcons.arrowRightLeft, size: 16),
                        label: const Text('Movimiento'),
                      ),
                      TextButton(
                        onPressed: () => _editWarehouse(warehouse),
                        child: const Text('Editar'),
                      ),
                    ],
                  ),
                  _section('Existencias', [
                    if (!data.stock.any(
                      (s) => s['warehouse_id'] == warehouse['id'],
                    ))
                      const Text('Sin existencias registradas.'),
                    for (final stock in data.stock.where(
                      (s) => s['warehouse_id'] == warehouse['id'],
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(data.name('products', stock['product_id'])),
                        subtitle: Text(
                          '${floorQuantity(stock['quantity_on_hand'])} ${data.name('units', stock['uom_id'])}',
                        ),
                        onTap: () => _showRecord(
                          'products',
                          data.row('products', stock['product_id']) ?? stock,
                          data,
                        ),
                      ),
                  ], initiallyExpanded: true),
                  if (_expanded)
                    _section('Kardex de movimientos', [
                      for (final move
                          in (data.movements
                              .where(
                                (m) => m['warehouse_id'] == warehouse['id'],
                              )
                              .toList()
                            ..sort(
                              (a, b) => '${b['created_at']}'.compareTo(
                                '${a['created_at']}',
                              ),
                            )))
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            '${_movementLabels[move['movement_type']] ?? move['movement_type']} · ${floorQuantity(move['quantity'])} ${data.name('units', move['uom_id'])}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${data.name('products', move['product_id'])}\n${floorText(move['created_at'])}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          children: [
                            _record('inventory_movements', move, data),
                          ],
                        ),
                    ]),
                ],
                if (_orderId != null) ...[
                  const Divider(),
                  if (order != null) _orderCard(data, order),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProductionOperatorDisplay(
                            orderId: _orderId!,
                            repository: _repository,
                          ),
                        ),
                      );
                      if (mounted) unawaited(_refresh());
                    },
                    icon: const Icon(LucideIcons.externalLink, size: 16),
                    label: const Text('Abrir operación de producción'),
                  ),
                  if (_detailLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_detailError != null) ...[
                    Text(
                      ErrorCopy.message(
                        _detailError!,
                        fallback: 'No fue posible actualizar el detalle.',
                      ),
                      style: const TextStyle(color: PomgtColors.danger),
                    ),
                    TextButton(
                      onPressed: () => _loadDetail(_orderId!),
                      child: const Text('Reintentar detalle'),
                    ),
                  ],
                  if (_expanded && _detail != null)
                    ..._orderSections(data, _detail!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _orderSections(FloorData data, FloorRow detail) {
    final order = detail['order'] is Map
        ? Map<String, dynamic>.from(detail['order'])
        : <String, dynamic>{};
    return [
      _section('Datos completos de la orden', [
        _record('production_orders', order, data, detail: detail),
      ], initiallyExpanded: true),
      for (final entry in {
        'product': 'Producto',
        'customer': 'Cliente',
        'customer_order': 'Pedido del cliente',
        'costs': 'Costos',
      }.entries)
        if (detail[entry.key] is Map)
          _section(entry.value, [
            _record(
              {
                'product': 'products',
                'customer': 'customers',
                'customer_order': 'customer_orders',
                'costs': 'production_order_costs',
              }[entry.key]!,
              Map<String, dynamic>.from(detail[entry.key]),
              data,
              detail: detail,
            ),
          ]),
      _section('Operadores asignados', [
        for (final assignment in floorRows(
          data.raw['order_operators'],
        ).where((a) => a['production_order_id'] == order['id']))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(data.name('operators', assignment['operator_id'])),
            subtitle: Text(UiCopy.enumLabel('${assignment['role']}')),
            children: [
              _record('production_order_operators', assignment, data),
              if (data.row('operators', assignment['operator_id']) != null)
                _record(
                  'operators',
                  data.row('operators', assignment['operator_id'])!,
                  data,
                ),
            ],
          ),
      ]),
      _section('Materiales requeridos y consumidos', [
        for (final material in floorRows(detail['materials']))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              data.name('products', material['material_product_id']),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Requerido ${floorQuantity(material['required_quantity'])} · Surtido ${floorQuantity(material['issued_quantity'])}\nConsumido ${floorQuantity(material['consumed_quantity'])} · Merma ${floorQuantity(material['scrap_quantity'])}',
              style: const TextStyle(fontSize: 11),
            ),
            children: [
              _record(
                'production_order_materials',
                material,
                data,
                detail: detail,
              ),
              if (data.inventoryAvailable)
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => _inventoryDialog(
                        product: data.row(
                          'products',
                          material['material_product_id'],
                        ),
                        material: material,
                      ),
                      child: const Text('Surtir desde almacén'),
                    ),
                    TextButton(
                      onPressed: () => _inventoryDialog(
                        product: data.row(
                          'products',
                          material['material_product_id'],
                        ),
                        material: material,
                        returning: true,
                      ),
                      child: const Text('Devolver a almacén'),
                    ),
                  ],
                ),
            ],
          ),
        if (floorRows(detail['materials']).isEmpty)
          const Text('Sin materiales registrados.'),
      ], initiallyExpanded: true),
      for (final entry in {
        'operations': ('Operaciones', 'production_order_operations'),
        'allocations': (
          'Asignaciones de recursos',
          'production_order_allocations',
        ),
        'checklist': (
          'Lista de verificación',
          'production_order_checklist_items',
        ),
        'quality': ('Calidad', 'production_order_quality_checks'),
        'parameters': (
          'Parámetros de máquina',
          'production_order_machine_parameters',
        ),
        'movements': (
          'Movimientos de producción',
          'production_order_material_movements',
        ),
        'events': ('Historial de eventos', 'production_order_events'),
        'dependencies': (
          'Dependencias',
          'production_order_operation_dependencies',
        ),
      }.entries)
        _section('${entry.value.$1} (${floorRows(detail[entry.key]).length})', [
          for (final row in floorRows(detail[entry.key]))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                floorText(
                  row['name'] ??
                      row['label'] ??
                      row['event_type'] ??
                      row['movement_type'] ??
                      entry.value.$1,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              subtitle: row['status'] == null
                  ? null
                  : Text(
                      UiCopy.enumLabel('${row['status']}'),
                      style: const TextStyle(fontSize: 11),
                    ),
              children: [_record(entry.value.$2, row, data, detail: detail)],
            ),
        ]),
      for (final key in [
        'operation_materials',
        'material_revisions',
        'material_attribute_values',
        'material_attribute_definitions',
      ])
        if (detail[key] is Map && (detail[key] as Map).isNotEmpty)
          _section(
            {
              'operation_materials': 'Materiales por operación',
              'material_revisions': 'Revisiones de materiales',
              'material_attribute_values': 'Especificaciones de materiales',
              'material_attribute_definitions':
                  'Definiciones de especificaciones',
            }[key]!,
            [
              for (final value in (detail[key] as Map).values)
                for (final row
                    in (value is List
                        ? floorRows(value)
                        : value is Map
                        ? [Map<String, dynamic>.from(value)]
                        : <FloorRow>[]))
                  _record(
                    {
                      'operation_materials': 'routing_operation_materials',
                      'material_revisions': 'product_revisions',
                      'material_attribute_values': 'material_attribute_values',
                      'material_attribute_definitions':
                          'material_attribute_definitions',
                    }[key]!,
                    row,
                    data,
                    detail: detail,
                  ),
            ],
          ),
    ];
  }

  Widget _section(
    String title,
    List<Widget> children, {
    bool initiallyExpanded = false,
  }) => ExpansionTile(
    key: PageStorageKey(
      '$_selectedMachine:$_selectedWarehouse:$_orderId:$title',
    ),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 12),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    initiallyExpanded: initiallyExpanded,
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    children: children.isEmpty
        ? [
            const Text(
              'Sin registros.',
              style: TextStyle(color: PomgtColors.muted, fontSize: 12),
            ),
          ]
        : children,
  );
  Widget _record(
    String table,
    FloorRow row,
    FloorData data, {
    FloorRow? detail,
  }) {
    final fields = {
      for (final f in Phase1Schema.tables[table]?.fields ?? <DbFieldSpec>[])
        f.name: f,
    };
    const labels = {
      'operator_id': 'Operador',
      'production_material_id': 'Línea de material de producción',
      'full_name': 'Nombre completo',
      'employee_code': 'No. de empleado',
      'email': 'Correo',
      'phone': 'Teléfono',
      'role': 'Rol',
      'quantity_on_hand': 'Existencias',
      'warehouse_id': 'Almacén',
      'product_id': 'Producto',
      'uom_id': 'Unidad',
      'movement_type': 'Movimiento',
      'quantity': 'Cantidad',
      'notes': 'Notas',
      'created_at': 'Fecha de creación',
      'created_by': 'Registrado por',
      'updated_at': 'Actualizado',
      'reference_type': 'Origen',
      'reference_id': 'Referencia',
      'unit_cost': 'Costo unitario',
      'code': 'Código',
      'name': 'Nombre',
      'address': 'Dirección',
      'is_active': 'Activo',
      'is_default': 'Principal',
      'floor_pos_x': 'Posición horizontal',
      'floor_pos_y': 'Posición vertical',
    };
    final keys = row.keys
        .where((key) => !['organization_id', 'request_id', 'id'].contains(key))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: LayoutBuilder(
              builder: (context, c) {
                final label =
                    (table == 'machines' && key == 'status'
                        ? 'Estado registrado'
                        : fields[key]?.label) ??
                    labels[key] ??
                    key.replaceAll('_', ' ');
                dynamic value = row[key];
                final ref =
                    fields[key]?.referenceTable ??
                    {
                      'operator_id': 'operators',
                      'warehouse_id': 'warehouses',
                      'related_warehouse_id': 'warehouses',
                      'uom_id': 'units_of_measure',
                      'material_product_id': 'products',
                      'machine_id': 'machines',
                      'work_center_id': 'work_centers',
                    }[key];
                if (value is bool) {
                  value = value ? 'Sí' : 'No';
                } else if (fields[key]?.kind == DbFieldKind.enumValue) {
                  value = UiCopy.enumLabel('$value');
                } else if (ref != null && value != null) {
                  final mappedKey =
                      {
                        'units_of_measure': 'units',
                        'production_orders': 'orders',
                      }[ref] ??
                      ref;
                  final local = detail?[mappedKey];
                  final related = local is Map ? local['$value'] : null;
                  value = related is Map
                      ? related['name'] ??
                            related['op_number'] ??
                            related['symbol'] ??
                            value
                      : data.name(mappedKey, value);
                } else if (value is Map || value is List) {
                  value = const JsonEncoder.withIndent('  ').convert(value);
                }
                final content = SelectableText(
                  key: PageStorageKey('field:$table:${row['id']}:$key'),
                  floorText(value),
                  style: const TextStyle(fontSize: 12, color: PomgtColors.ink),
                );
                if (c.maxWidth < 310) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: PomgtColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      content,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: PomgtColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _showRecord(String table, FloorRow row, FloorData data) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(floorText(row['name'] ?? row['sku'])),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(child: _record(table, row, data)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );

  Future<void> _editWarehouse([FloorRow? row]) async {
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final code = TextEditingController(text: row?['code']?.toString() ?? '');
    final address = TextEditingController(
      text: row?['address']?.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    var active = row?['is_active'] != false;
    await _editDialog(
      row == null ? 'Nuevo almacén' : 'Editar almacén',
      (changed) => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Código'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Escribe un código' : null,
            ),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Escribe un nombre' : null,
            ),
            TextFormField(
              controller: address,
              decoration: const InputDecoration(
                labelText: 'Dirección / ubicación',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: active,
              onChanged: (v) => changed(() => active = v),
            ),
          ],
        ),
      ),
      () async {
        if (!form.currentState!.validate()) return false;
        await _repository.saveFloorWarehouse({
          'code': code.text.trim(),
          'name': name.text.trim(),
          'address': address.text.trim(),
          'is_active': active,
        }, id: row?['id']?.toString());
        return true;
      },
    );
    name.dispose();
    code.dispose();
    address.dispose();
  }

  Future<void> _editDialog(
    String title,
    Widget Function(StateSetter) fields,
    Future<bool> Function() save, {
    Future<void> Function()? remove,
  }) async {
    var busy = false;
    String? error;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, changed) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AbsorbPointer(absorbing: busy, child: fields(changed)),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(color: PomgtColors.danger),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (remove != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          changed(() => busy = true);
                          try {
                            await remove();
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            unawaited(_refresh(afterMutation: true));
                          } catch (e) {
                            if (dialogContext.mounted) {
                              changed(() {
                                busy = false;
                                error = ErrorCopy.message(
                                  e,
                                  fallback: 'No fue posible eliminar el área.',
                                );
                              });
                            }
                          }
                        },
                  child: const Text('Eliminar área'),
                ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        changed(() => busy = true);
                        try {
                          final saved = await save();
                          if (!dialogContext.mounted) return;
                          if (saved) {
                            Navigator.pop(dialogContext);
                            unawaited(_refresh(afterMutation: true));
                          } else {
                            changed(() => busy = false);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            changed(() {
                              busy = false;
                              error = ErrorCopy.message(
                                e,
                                fallback: 'No fue posible guardar.',
                              );
                            });
                          }
                        }
                      },
                child: Text(busy ? 'Guardando…' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    // Route completion follows the closing animation and removes its fields.
    await route.completed;
  }

  String _requestId() {
    final random = math.Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _inventoryDialog({
    FloorRow? warehouse,
    FloorRow? product,
    FloorRow? material,
    bool returning = false,
  }) async {
    final data = _data!;
    final warehouses = data.warehouses
        .where((w) => w['is_active'] != false)
        .toList();
    final products = data.products
        .where((p) => p['is_active'] != false && p['base_uom_id'] != null)
        .toList();
    if (warehouses.isEmpty || products.isEmpty) {
      showPomgtSnackBar(
        context,
        'Registra un almacén activo y un producto con unidad base antes de registrar movimientos.',
        isError: true,
      );
      return;
    }
    var warehouseId = warehouses.any((w) => w['id'] == warehouse?['id'])
        ? warehouse!['id'].toString()
        : warehouses.first['id'].toString();
    var productId = products.any((p) => p['id'] == product?['id'])
        ? product!['id'].toString()
        : products.first['id'].toString();
    if (material != null &&
        (product == null || productId != material['material_product_id'])) {
      showPomgtSnackBar(
        context,
        'El material requiere un producto activo con unidad base.',
        isError: true,
      );
      return;
    }
    var movement = material == null
        ? 'receipt'
        : returning
        ? 'receipt'
        : 'issue';
    var requestId = _requestId();
    final quantity = TextEditingController();
    final notes = TextEditingController();
    final form = GlobalKey<FormState>();
    await _editDialog(
      material == null
          ? 'Movimiento de inventario'
          : returning
          ? 'Devolver material'
          : 'Surtir material',
      (changed) => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Las existencias se calculan con las entradas y salidas registradas. No se importan saldos históricos automáticamente.',
              style: TextStyle(color: PomgtColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: warehouseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Almacén'),
              items: [
                for (final w in warehouses)
                  DropdownMenuItem(
                    value: '${w['id']}',
                    child: Text(
                      floorText(w['name']),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => changed(() {
                warehouseId = v!;
                requestId = _requestId();
              }),
            ),
            DropdownButtonFormField<String>(
              initialValue: productId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Producto / material',
              ),
              items: [
                for (final p in products)
                  DropdownMenuItem(
                    value: '${p['id']}',
                    child: Text(
                      '${floorText(p['sku'])} · ${floorText(p['name'])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: material != null
                  ? null
                  : (v) => changed(() {
                      productId = v!;
                      requestId = _requestId();
                    }),
            ),
            if (material == null)
              DropdownButtonFormField<String>(
                initialValue: movement,
                decoration: const InputDecoration(
                  labelText: 'Tipo de movimiento',
                ),
                items: [
                  for (final e in _movementLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => changed(() {
                  movement = v!;
                  requestId = _requestId();
                }),
              ),
            Text(
              'Unidad: ${data.name('units', data.row('products', productId)?['base_uom_id'])}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Saldo registrado: ${floorQuantity(data.stock.where((s) => s['warehouse_id'] == warehouseId && s['product_id'] == productId).fold<double>(0, (sum, s) => sum + floorNumber(s['quantity_on_hand'])))}',
              style: const TextStyle(fontSize: 12),
            ),
            TextFormField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: const InputDecoration(labelText: 'Cantidad'),
              onChanged: (_) => requestId = _requestId(),
              validator: (v) {
                final n = parseNumberText(v)?.toDouble();
                return n == null || !n.isFinite || n <= 0
                    ? 'Escribe una cantidad mayor que cero'
                    : null;
              },
            ),
            TextFormField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Notas / referencia',
              ),
              onChanged: (_) => requestId = _requestId(),
            ),
          ],
        ),
      ),
      () async {
        if (!form.currentState!.validate()) return false;
        await _repository.recordFloorInventoryMovement(
          warehouseId: warehouseId,
          productId: productId,
          movementType: movement,
          quantity: parseNumberText(quantity.text)!.toDouble(),
          requestId: requestId,
          notes: notes.text.trim(),
          materialId: material?['id']?.toString(),
        );
        return true;
      },
    );
    quantity.dispose();
    notes.dispose();
  }
}
