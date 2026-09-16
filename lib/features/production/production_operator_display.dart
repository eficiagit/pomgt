import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/orientation_lock.dart';
import '../../core/utils/ui_copy.dart';
import '../../data/repositories/production_repository.dart';

class ProductionOperatorDisplay extends StatefulWidget {
  const ProductionOperatorDisplay({
    super.key,
    required this.orderId,
    required this.repository,
  });

  final String orderId;
  final ProductionRepository repository;

  @override
  State<ProductionOperatorDisplay> createState() =>
      _ProductionOperatorDisplayState();
}

class _ProductionOperatorDisplayState extends State<ProductionOperatorDisplay> {
  late Future<Map<String, dynamic>> _future;
  int _index = 0;
  bool _busy = false;
  final Set<String> _autoStarted = <String>{};

  ProductionRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    unawaited(OrientationLock.operatorDisplayLandscapeOnly());
    _future = _load();
  }

  @override
  void dispose() {
    unawaited(OrientationLock.appPortraitOnly());
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final data = await _repository.detail(widget.orderId);
    final operations = _list(data['operations']);
    if (operations.isNotEmpty && _index == 0) {
      final next = operations.indexWhere((row) {
        final status = row['status']?.toString() ?? 'pending';
        return !['completed', 'skipped'].contains(status);
      });
      _index = next < 0 ? operations.length - 1 : next;
    }
    return data;
  }

  void _reload({int? nextIndex}) {
    if (!mounted) return;
    setState(() {
      if (nextIndex != null) _index = nextIndex;
      _future = _repository.detail(widget.orderId);
    });
  }

  Future<void> _finishStep(
    Map<String, dynamic> operation,
    List<Map<String, dynamic>> operations,
  ) async {
    if (_busy) return;
    var activeOperation = operation;
    var activeOperations = operations;
    var operationId = activeOperation['id']?.toString();
    if (operationId == null || operationId.startsWith('routing:')) {
      setState(() => _busy = true);
      try {
        final data = await _repository.ensureOperationalSnapshot(
          widget.orderId,
        );
        activeOperations = _list(data['operations']);
        final routingOperationId = operation['routing_operation_id']
            ?.toString();
        final sequenceNo = operation['sequence_no']?.toString();
        final match = activeOperations.indexWhere((row) {
          if (routingOperationId != null &&
              row['routing_operation_id']?.toString() == routingOperationId) {
            return true;
          }
          return sequenceNo != null &&
              row['sequence_no']?.toString() == sequenceNo;
        });
        if (match < 0) {
          throw StateError(
            'No fue posible ubicar la operación real para registrar la firma.',
          );
        }
        activeOperation = activeOperations[match];
        operationId = activeOperation['id']?.toString();
        if (!mounted) return;
        setState(() {
          _index = match;
          _future = Future.value(data);
        });
      } catch (e) {
        if (mounted) _showError(ErrorCopy.message(e));
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    final result = await showDialog<_OperatorSignature>(
      context: context,
      builder: (_) => _OperatorSignatureDialog(operation: activeOperation),
    );
    if (result == null) return;
    final realOperationId = operationId;
    if (realOperationId == null) {
      _showError('No fue posible identificar la operación para firmar.');
      return;
    }
    setState(() => _busy = true);
    try {
      final status = activeOperation['status']?.toString() ?? 'pending';
      final note = [
        'Firma operador: ${result.operatorName}',
        if (result.note != null) result.note!,
      ].join(' | ');
      if (status != 'in_progress') {
        await _repository.transitionOperation(
          realOperationId,
          'in_progress',
          note: 'Inicio en display operador: ${result.operatorName}',
        );
      }
      await _repository.transitionOperation(
        realOperationId,
        'completed',
        completedQuantity: result.completed,
        rejectedQuantity: result.rejected,
        note: note,
      );
      if (!mounted) return;
      var nextPending = -1;
      for (var i = _index + 1; i < activeOperations.length; i++) {
        final status = activeOperations[i]['status']?.toString() ?? 'pending';
        if (!['completed', 'skipped'].contains(status)) {
          nextPending = i;
          break;
        }
      }
      if (nextPending < 0) {
        _showSuccess('Secuencia finalizada.');
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted) Navigator.pop(context);
        return;
      }
      _reload(nextIndex: nextPending);
      _showSuccess('Paso firmado.');
    } catch (e) {
      if (mounted) _showError(ErrorCopy.message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    showPomgtSnackBar(context, message, isError: true);
  }

  void _showSuccess(String message) {
    showPomgtSnackBar(context, message);
  }

  void _maybeAutoStart(Map<String, dynamic> operation) {
    final operationId = operation['id']?.toString();
    if (operationId == null || operationId.startsWith('routing:')) return;
    final status = operation['status']?.toString() ?? 'pending';
    if (!['ready', 'pending'].contains(status)) return;
    if (!_autoStarted.add(operationId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _repository.transitionOperation(
          operationId,
          'in_progress',
          note: 'Inicio automatico en display operador.',
        );
        if (mounted) _reload(nextIndex: _index);
      } catch (e) {
        if (mounted) _showError(ErrorCopy.message(e));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PomgtColors.appBg,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _DisplayError(
                message: ErrorCopy.message(
                  snapshot.error!,
                  fallback: 'No fue posible abrir el display de operación.',
                ),
                onRetry: () => _reload(),
              );
            }
            final data = snapshot.data ?? const <String, dynamic>{};
            final operations = _list(data['operations']);
            final order = _map(data['order']);
            final product = _map(data['product']);
            if (operations.isEmpty) {
              return _DisplayError(
                message:
                    'La OP no tiene secuencia operativa. Prepara la orden para congelar la ruta de fabricación.',
                onRetry: () => _reload(),
              );
            }
            final safeIndex = _index.clamp(0, operations.length - 1);
            final operation = operations[safeIndex];
            _maybeAutoStart(operation);
            return Column(
              children: [
                _DisplayHeader(
                  order: order,
                  product: product,
                  index: safeIndex,
                  total: operations.length,
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 780;
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 28,
                          compact ? 14 : 22,
                          compact ? 14 : 28,
                          20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StepProgress(
                              operations: operations,
                              selectedIndex: safeIndex,
                              onSelect: (value) =>
                                  setState(() => _index = value),
                            ),
                            SizedBox(height: compact ? 14 : 20),
                            _CurrentStepPanel(
                              data: data,
                              operation: operation,
                              position: safeIndex + 1,
                              total: operations.length,
                              compact: compact,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                _DisplayActions(
                  busy: _busy,
                  canBack: safeIndex > 0,
                  canForward: safeIndex < operations.length - 1,
                  isCompleted: [
                    'completed',
                    'skipped',
                  ].contains(operation['status']?.toString() ?? 'pending'),
                  onClose: () => Navigator.pop(context),
                  onBack: () => setState(() => _index = safeIndex - 1),
                  onForward: () => setState(() => _index = safeIndex + 1),
                  onFinish: () => _finishStep(operation, operations),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DisplayHeader extends StatelessWidget {
  const _DisplayHeader({
    required this.order,
    required this.product,
    required this.index,
    required this.total,
    required this.onClose,
  });

  final Map<String, dynamic> order;
  final Map<String, dynamic> product;
  final int index;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      decoration: const BoxDecoration(
        color: PomgtColors.surface,
        border: Border(bottom: BorderSide(color: PomgtColors.lineStrong)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_display_outlined, color: PomgtColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Display operador · ${_show(order['op_number'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: PomgtColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_show(product['sku'])} - ${_show(product['name'])}  |  Paso ${index + 1} de $total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar display',
            onPressed: onClose,
            icon: const Icon(CupertinoIcons.xmark),
          ),
        ],
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.operations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> operations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < operations.length; i++) ...[
            _StepProgressItem(
              operation: operations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
            if (i < operations.length - 1)
              Container(
                width: 96,
                height: 1,
                margin: const EdgeInsets.only(top: 23),
                color: PomgtColors.lineStrong,
              ),
          ],
        ],
      ),
    );
  }
}

class _StepProgressItem extends StatelessWidget {
  const _StepProgressItem({
    required this.operation,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> operation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = operation['status']?.toString() ?? 'pending';
    final done = ['completed', 'skipped'].contains(status);
    final color = done
        ? PomgtColors.success
        : selected
        ? PomgtColors.blue
        : PomgtColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: PomgtRadii.borderSm,
      child: SizedBox(
        width: 112,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? PomgtColors.blue : PomgtColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: selected ? 2 : 1),
              ),
              child: done && !selected
                  ? const Icon(
                      CupertinoIcons.check_mark,
                      color: PomgtColors.success,
                      size: 17,
                    )
                  : Text(
                      _show(operation['sequence_no']),
                      style: TextStyle(
                        color: selected ? PomgtColors.canvas : color,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              _show(operation['name']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? PomgtColors.blue : PomgtColors.secondaryInk,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.text, {this.success = false});
  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final color = success ? PomgtColors.success : PomgtColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: PomgtColors.canvas,
        borderRadius: PomgtRadii.borderSm,
        border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .65)),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.icon, this.trailing});
  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        Icon(icon, color: PomgtColors.blue, size: 20),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class _CurrentStepPanel extends StatelessWidget {
  const _CurrentStepPanel({
    required this.data,
    required this.operation,
    required this.position,
    required this.total,
    required this.compact,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> operation;
  final int position;
  final int total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final workCenters = (data['work_centers'] as Map?) ?? const {};
    final machines = (data['machines'] as Map?) ?? const {};
    final workCenter = _map(
      workCenters[operation['work_center_id']?.toString()],
    )['name'];
    final machine = _map(machines[operation['machine_id']?.toString()])['name'];
    final materials = _linkedMaterials(data, operation);
    final firstMaterial = materials.isEmpty ? const <String, dynamic>{} : materials.first;
    final fields = <_DisplayField>[
      _DisplayField(
        'Tipo',
        UiCopy.enumLabel(_show(operation['operation_type'])),
        icon: CupertinoIcons.gear_alt,
      ),
      _DisplayField('Centro', _show(workCenter), icon: CupertinoIcons.building_2_fill),
      _DisplayField('Maquina', _show(machine), icon: Icons.precision_manufacturing_outlined),
      _DisplayField(
        'Cantidad / planificada',
        '${_fmt(operation['completed_quantity'])} / ${_fmt(operation['planned_quantity'])} ${_show(order['uom_symbol'])}',
        icon: CupertinoIcons.doc_text,
      ),
      _DisplayField(
        'Estado',
        UiCopy.enumLabel(_show(operation['status'])),
        icon: CupertinoIcons.check_mark_circled,
        success: ['completed', 'skipped'].contains(operation['status']?.toString()),
      ),
      _DisplayField('Inicio real', _dateTime(operation['actual_start_at']), icon: CupertinoIcons.calendar),
      _DisplayField('Fin real', _dateTime(operation['actual_end_at']), icon: CupertinoIcons.calendar),
      _DisplayField('Tiempo registrado', _elapsed(operation), icon: CupertinoIcons.clock),
      _DisplayField('Tiempo esperado', _operationTime(operation), icon: CupertinoIcons.clock),
      _DisplayField(
        'Metodo de consumo',
        UiCopy.enumLabel(_show(firstMaterial['issue_method'] ?? 'manual')),
        icon: Icons.storage_outlined,
      ),
      _DisplayField(
        'Revision',
        _show(order['bom_revision_code'] ?? order['routing_revision_code']),
        icon: CupertinoIcons.checkmark_square,
      ),
      _DisplayField(
        'Notas',
        _show(operation['notes']),
        icon: CupertinoIcons.doc_plaintext,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: PomgtColors.surface,
        border: Border.all(color: PomgtColors.lineStrong.withValues(alpha: .65)),
        borderRadius: PomgtRadii.borderSm,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LargeStepNumber(value: _show(operation['sequence_no'])),
                const SizedBox(width: 16),
                Expanded(
                  flex: compact ? 1 : 2,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _show(operation['name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          color: PomgtColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_show(operation['operation_code'])} · Paso $position de $total',
                        style: const TextStyle(
                          color: PomgtColors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((operation['description']?.toString() ?? operation['instructions']?.toString() ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          (operation['description'] ?? operation['instructions']).toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PomgtColors.secondaryInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 20),
                  Expanded(flex: 5, child: _ResponsiveFieldGrid(fields: fields, compact: compact)),
                ],
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 20),
              _ResponsiveFieldGrid(fields: fields, compact: compact),
            ],
            SizedBox(height: compact ? 16 : 20),
            _OperatorWorkspace(
              data: data,
              operation: operation,
              compact: compact,
            ),
            SizedBox(height: compact ? 14 : 18),
            _StepRecords(data: data, operation: operation),
          ],
        ),
      ),
    );
  }
}

class _LargeStepNumber extends StatelessWidget {
  const _LargeStepNumber({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 86,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PomgtColors.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(color: PomgtColors.lineStrong, width: 2),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: PomgtColors.secondaryInk,
          fontSize: 26,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ResponsiveFieldGrid extends StatelessWidget {
  const _ResponsiveFieldGrid({required this.fields, required this.compact});

  final List<_DisplayField> fields;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compact
            ? constraints.maxWidth < 420
                  ? 1
                  : 2
            : 5;
        final width = (constraints.maxWidth - ((columns - 1) * 16)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 18,
          children: fields
              .map((field) => SizedBox(width: width, child: _FieldCell(field)))
              .toList(),
        );
      },
    );
  }
}

class _FieldCell extends StatelessWidget {
  const _FieldCell(this.field);

  final _DisplayField field;

  @override
  Widget build(BuildContext context) {
    final value = field.success
        ? _StatusChip(field.value, success: true)
        : Text(
            field.value,
            overflow: TextOverflow.visible,
            style: const TextStyle(
              color: PomgtColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (field.icon != null) ...[
          Icon(field.icon, size: 19, color: PomgtColors.blue),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              value,
            ],
          ),
        ),
      ],
    );
  }
}

class _InstructionBlock extends StatelessWidget {
  const _InstructionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PomgtColors.surfaceAlt.withValues(alpha: .5),
        border: Border.all(color: PomgtColors.lineStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.engineering_outlined, color: PomgtColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: PomgtColors.secondaryInk,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationMaterials extends StatelessWidget {
  const _OperationMaterials({required this.data, required this.operation});

  final Map<String, dynamic> data;
  final Map<String, dynamic> operation;

  @override
  Widget build(BuildContext context) {
    final materials = _linkedMaterials(data, operation);
    final verified = materials.length;
    final trailing = materials.isEmpty
        ? null
        : _StatusChip('Materiales verificados ($verified/${materials.length})', success: true);
    if (materials.isEmpty) {
      return _OperatorCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _CardTitle('Materiales de este paso', icon: CupertinoIcons.cube_box),
            SizedBox(height: 14),
            Text(
              'Sin consumo de materiales asociado directamente a esta operacion.',
              style: TextStyle(
                color: PomgtColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return _OperatorCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(
            'Materiales de este paso',
            icon: CupertinoIcons.cube_box,
            trailing: trailing,
          ),
          const SizedBox(height: 14),
          _MaterialsTable(data: data, materials: materials),
          const SizedBox(height: 14),
          const _InfoStrip(
            text:
                'Verifica que todos los materiales esten cargados y configurados correctamente antes de continuar con la siguiente operacion.',
          ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: PomgtColors.blueSoft.withValues(alpha: .5),
      borderRadius: PomgtRadii.borderSm,
      border: Border.all(color: PomgtColors.blue.withValues(alpha: .25)),
    ),
    child: Row(
      children: [
        const Icon(CupertinoIcons.info_circle_fill, color: PomgtColors.blue, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: PomgtColors.blueHover,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MaterialsTable extends StatelessWidget {
  const _MaterialsTable({required this.data, required this.materials});
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> materials;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < materials.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _MaterialCompactRow(data: data, material: materials[i]),
              ],
            ],
          );
        }
        return Table(
          columnWidths: const {
            0: FlexColumnWidth(1.15),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1.8),
            5: FlexColumnWidth(.9),
          },
          border: TableBorder.all(color: PomgtColors.line, width: 1),
          children: [
            const TableRow(
              decoration: BoxDecoration(color: PomgtColors.surfaceAlt),
              children: [
                _MaterialHeader('Material'),
                _MaterialHeader('Descripcion'),
                _MaterialHeader('Cantidad requerida'),
                _MaterialHeader('Tipo'),
                _MaterialHeader('Detalles / Especificaciones'),
                _MaterialHeader('Estado'),
              ],
            ),
            for (final material in materials)
              TableRow(
                children: [
                  _MaterialTableCell(
                    child: _MaterialName(data: data, material: material),
                  ),
                  _MaterialTableCell(
                    child: Text(
                      _materialProduct(data, material)['description']?.toString() ??
                          _show(_materialProduct(data, material)['name']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _MaterialTableCell(
                    child: Text(
                      _materialQuantity(data, material),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _MaterialTableCell(
                    child: Text(UiCopy.enumLabel(_show(material['component_type']))),
                  ),
                  _MaterialTableCell(
                    child: _MaterialSpecs(data: data, material: material),
                  ),
                  const _MaterialTableCell(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusChip('Listo', success: true),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _MaterialHeader extends StatelessWidget {
  const _MaterialHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: PomgtColors.secondaryInk,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _MaterialTableCell extends StatelessWidget {
  const _MaterialTableCell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: DefaultTextStyle(
      style: const TextStyle(
        color: PomgtColors.secondaryInk,
        fontSize: 12.5,
        height: 1.45,
      ),
      child: child,
    ),
  );
}

class _MaterialCompactRow extends StatelessWidget {
  const _MaterialCompactRow({required this.data, required this.material});
  final Map<String, dynamic> data;
  final Map<String, dynamic> material;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: PomgtColors.line),
      borderRadius: PomgtRadii.borderSm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _MaterialName(data: data, material: material)),
            const _StatusChip('Listo', success: true),
          ],
        ),
        const SizedBox(height: 10),
        Text(_materialQuantity(data, material)),
        const SizedBox(height: 8),
        _MaterialSpecs(data: data, material: material),
      ],
    ),
  );
}

class _MaterialName extends StatelessWidget {
  const _MaterialName({required this.data, required this.material});
  final Map<String, dynamic> data;
  final Map<String, dynamic> material;

  @override
  Widget build(BuildContext context) {
    final product = _materialProduct(data, material);
    final revision = _materialRevision(data, material);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_show(product['sku'])} - ${_show(product['name'])}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PomgtColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _show(revision['revision_code'] ?? revision['revision']),
          style: const TextStyle(color: PomgtColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _MaterialSpecs extends StatelessWidget {
  const _MaterialSpecs({required this.data, required this.material});
  final Map<String, dynamic> data;
  final Map<String, dynamic> material;

  @override
  Widget build(BuildContext context) {
    final units = (data['units'] as Map?) ?? const {};
    final attributeValues =
        (data['material_attribute_values'] as Map?) ?? const {};
    final attributeDefinitions =
        (data['material_attribute_definitions'] as Map?) ?? const {};
    final materialProductId = material['material_product_id']?.toString();
    final revision = _materialRevision(data, material);
    final attributes = _list(attributeValues[materialProductId]);
    final specs = _materialSpecPairs(
      revision,
      attributes,
      attributeDefinitions,
      units,
    ).take(5).toList();
    if (specs.isEmpty) {
      return const Text('-', style: TextStyle(color: PomgtColors.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final spec in specs)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${spec.label}: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: spec.value),
              ],
            ),
          ),
      ],
    );
  }
}

class _OperatorWorkspace extends StatelessWidget {
  const _OperatorWorkspace({
    required this.data,
    required this.operation,
    required this.compact,
  });

  final Map<String, dynamic> data;
  final Map<String, dynamic> operation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final orderInfo = _OrderInfoPanel(data: data);
    final materials = _OperationMaterials(data: data, operation: operation);
    final product = _ProductPreviewPanel(data: data);
    if (compact) {
      return Column(
        children: [
          orderInfo,
          const SizedBox(height: 12),
          materials,
          const SizedBox(height: 12),
          product,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 12.0;
        final left = (constraints.maxWidth - gap * 2) * .20;
        final center = (constraints.maxWidth - gap * 2) * .60;
        final right = (constraints.maxWidth - gap * 2) * .20;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: left, child: orderInfo),
            SizedBox(width: gap),
            SizedBox(width: center, child: materials),
            SizedBox(width: gap),
            SizedBox(width: right, child: product),
          ],
        );
      },
    );
  }
}

class _OrderInfoPanel extends StatelessWidget {
  const _OrderInfoPanel({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final order = _map(data['order']);
    final product = _map(data['product']);
    final customer = _map(data['customer']);
    final customerOrder = _map(data['customer_order']);
    final route = [
      order['routing_code'],
      order['routing_revision_code'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' - ');
    return _OperatorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Informacion de la orden', icon: CupertinoIcons.doc_text),
          const SizedBox(height: 16),
          _OrderInfoLine('Producto', '${_show(product['sku'])} - ${_show(product['name'])}'),
          _OrderInfoLine(
            'Cliente',
            _show(customer['trade_name'] ?? customer['legal_name'] ?? order['customer_name']),
          ),
          _OrderInfoLine('Pedido', _show(customerOrder['order_number'] ?? order['order_number'])),
          _OrderInfoLine('OC del cliente', _show(customerOrder['customer_po_number'] ?? order['customer_po_number'])),
          _OrderInfoLine('Ruta de fabricacion', route.isEmpty ? '-' : route),
          _OrderInfoLine('Fecha requerida', _dateTime(order['required_at'])),
          const SizedBox(height: 4),
          const Text(
            'Prioridad',
            style: TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          _StatusChip(UiCopy.enumLabel(_show(order['priority']))),
        ],
      ),
    );
  }
}

class _OrderInfoLine extends StatelessWidget {
  const _OrderInfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PomgtColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: PomgtColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _ProductPreviewPanel extends StatelessWidget {
  const _ProductPreviewPanel({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final product = _map(data['product']);
    final materials = _list(data['materials']);
    final first = materials.isEmpty ? const <String, dynamic>{} : materials.first;
    final revision = _materialRevision(data, first);
    final specs = _productPreviewSpecs(data, first, revision);
    return _OperatorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Vista del producto', icon: CupertinoIcons.cube_box),
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 132,
              height: 116,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PomgtColors.surfaceAlt.withValues(alpha: .65),
                borderRadius: PomgtRadii.borderSm,
              ),
              child: const Icon(
                Icons.view_carousel_outlined,
                color: PomgtColors.muted,
                size: 58,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${_show(product['sku'])} - ${_show(product['name'])}',
            style: const TextStyle(
              color: PomgtColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _show(product['description'] ?? UiCopy.enumLabel(_show(product['product_type']))),
            style: const TextStyle(
              color: PomgtColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Divider(height: 24),
          for (final entry in specs)
            _OrderInfoLine(entry.key, entry.value),
        ],
      ),
    );
  }
}

class _StepRecords extends StatelessWidget {
  const _StepRecords({required this.data, required this.operation});
  final Map<String, dynamic> data;
  final Map<String, dynamic> operation;

  @override
  Widget build(BuildContext context) {
    final rows = _stepRecordRows(data, operation);
    return _OperatorCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardTitle('Registros del paso', icon: Icons.smart_display_outlined),
        const SizedBox(height: 12),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(.9),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(2.2),
          },
          border: TableBorder.all(color: PomgtColors.line),
          children: [
            const TableRow(
              decoration: BoxDecoration(color: PomgtColors.surfaceAlt),
              children: [
                _MaterialHeader('Fecha y hora'),
                _MaterialHeader('Usuario'),
                _MaterialHeader('Accion'),
                _MaterialHeader('Notas'),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  _MaterialTableCell(child: Text(row.date)),
                  _MaterialTableCell(child: Text(row.user)),
                  _MaterialTableCell(child: Text(row.action)),
                  _MaterialTableCell(child: Text(row.notes)),
                ],
              ),
          ],
        ),
      ],
      ),
    );
  }
}

class _StepRecord {
  const _StepRecord({
    required this.date,
    required this.user,
    required this.action,
    required this.notes,
  });

  final String date;
  final String user;
  final String action;
  final String notes;
}

class _DisplayActions extends StatelessWidget {
  const _DisplayActions({
    required this.busy,
    required this.canBack,
    required this.canForward,
    required this.isCompleted,
    required this.onClose,
    required this.onBack,
    required this.onForward,
    required this.onFinish,
  });

  final bool busy;
  final bool canBack;
  final bool canForward;
  final bool isCompleted;
  final VoidCallback onClose;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: const BoxDecoration(
        color: PomgtColors.surface,
        border: Border(top: BorderSide(color: PomgtColors.lineStrong)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final backToList = OutlinedButton.icon(
            onPressed: busy ? null : onClose,
            icon: const Icon(CupertinoIcons.chevron_left, size: 18),
            label: const Text('Volver al listado'),
          );
          final previous = OutlinedButton.icon(
            onPressed: !busy && canBack ? onBack : null,
            icon: const Icon(CupertinoIcons.chevron_left, size: 18),
            label: const Text('Paso anterior'),
          );
          final next = OutlinedButton.icon(
            onPressed: !busy && canForward ? onForward : null,
            icon: const Icon(CupertinoIcons.chevron_right, size: 18),
            label: const Text('Ver siguiente'),
          );
          final finish = FilledButton.icon(
            onPressed: !busy && !isCompleted ? onFinish : null,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.draw_outlined, size: 18),
            label: const Text('Firmar y continuar'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 48, child: backToList),
                const SizedBox(height: 8),
                SizedBox(height: 48, child: previous),
                const SizedBox(height: 8),
                SizedBox(height: 48, child: next),
                const SizedBox(height: 8),
                SizedBox(height: 48, child: finish),
              ],
            );
          }

          return Row(
            children: [
              backToList,
              const Spacer(),
              previous,
              const SizedBox(width: 10),
              next,
              const SizedBox(width: 10),
              SizedBox(height: 48, child: finish),
            ],
          );
        },
      ),
    );
  }
}

class _OperatorSignatureDialog extends StatefulWidget {
  const _OperatorSignatureDialog({required this.operation});

  final Map<String, dynamic> operation;

  @override
  State<_OperatorSignatureDialog> createState() =>
      _OperatorSignatureDialogState();
}

class _OperatorSignatureDialogState extends State<_OperatorSignatureDialog> {
  final operatorName = TextEditingController();
  final rejected = TextEditingController(text: '0');
  final note = TextEditingController();
  late final TextEditingController completed;

  @override
  void initState() {
    super.initState();
    completed = TextEditingController(
      text: _fmt(widget.operation['planned_quantity']),
    );
  }

  @override
  void dispose() {
    operatorName.dispose();
    completed.dispose();
    rejected.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 620;
    return AlertDialog(
      title: const Text('Firma de operación'),
      content: SizedBox(
        width: compact ? width - 56 : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _show(widget.operation['name']),
                style: const TextStyle(
                  color: PomgtColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: operatorName,
                decoration: const InputDecoration(
                  labelText: 'Operador responsable *',
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: compact ? double.infinity : 266,
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
                    width: compact ? double.infinity : 266,
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
              const SizedBox(height: 14),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observaciones de cierre',
                ),
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
        FilledButton.icon(
          onPressed: () {
            final name = operatorName.text.trim();
            final good = _n(completed.text);
            final bad = _n(rejected.text);
            if (name.isEmpty || good < 0 || bad < 0 || good + bad <= 0) {
              return;
            }
            Navigator.pop(
              context,
              _OperatorSignature(
                operatorName: name,
                completed: good,
                rejected: bad,
                note: note.text.trim().isEmpty ? null : note.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.draw_outlined, size: 17),
          label: const Text('Firmar paso'),
        ),
      ],
    );
  }
}

class _DisplayError extends StatelessWidget {
  const _DisplayError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: PomgtColors.danger,
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PomgtColors.secondaryInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(CupertinoIcons.refresh, size: 17),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayField {
  const _DisplayField(
    this.label,
    this.value, {
    this.icon,
    this.success = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool success;
}

class _OperatorSignature {
  const _OperatorSignature({
    required this.operatorName,
    required this.completed,
    required this.rejected,
    required this.note,
  });

  final String operatorName;
  final double completed;
  final double rejected;
  final String? note;
}

List<Map<String, dynamic>> _linkedMaterials(
  Map<String, dynamic> data,
  Map<String, dynamic> operation,
) {
  final operationMaterials =
      (data['operation_materials'] as Map?) ?? const <String, dynamic>{};
  final links = _list(
    operationMaterials[operation['routing_operation_id']?.toString()],
  );
  final materials = _list(data['materials']);
  if (links.isEmpty) {
    final operationId = operation['id']?.toString();
    final routingOperationId = operation['routing_operation_id']?.toString();
    final scoped = materials.where((material) {
      final materialOperationId =
          material['operation_id']?.toString() ??
          material['production_operation_id']?.toString();
      final materialRoutingOperationId =
          material['routing_operation_id']?.toString();
      if (operationId != null && materialOperationId == operationId) return true;
      if (routingOperationId != null &&
          materialRoutingOperationId == routingOperationId) {
        return true;
      }
      return false;
    }).toList();
    return scoped.isNotEmpty ? scoped : materials;
  }
  final byBomItem = {
    for (final material in materials)
      if (material['bom_item_id'] != null)
        material['bom_item_id'].toString(): material,
  };
  final byProduct = {
    for (final material in materials)
      if (material['material_product_id'] != null)
        material['material_product_id'].toString(): material,
  };
  return links.map((link) {
    final bomItemId = link['bom_item_id']?.toString();
    final productId = link['material_product_id']?.toString();
    return byBomItem[bomItemId] ??
        byProduct[productId] ??
        <String, dynamic>{
          'bom_item_id': bomItemId,
          'material_product_id': productId,
          'required_quantity': link['quantity_override'],
          'uom_id': link['uom_id'],
          'component_type': 'material',
          'issue_method': link['issue_method'],
        };
  }).toList();
}


Map<String, dynamic> _materialProduct(
  Map<String, dynamic> data,
  Map<String, dynamic> material,
) {
  final products = (data['products'] as Map?) ?? const {};
  final productId = material['material_product_id']?.toString();
  if (productId != null) {
    final product = _map(products[productId]);
    if (product.isNotEmpty) return product;
  }

  final embedded = _map(material['product']);
  if (embedded.isNotEmpty) return embedded;

  return <String, dynamic>{
    'sku':
        material['material_sku'] ??
        material['sku'] ??
        material['component_sku'],
    'name':
        material['material_name'] ??
        material['name'] ??
        material['component_name'] ??
        'Material',
    'description':
        material['material_description'] ??
        material['description'] ??
        material['component_description'],
  };
}

Map<String, dynamic> _materialRevision(
  Map<String, dynamic> data,
  Map<String, dynamic> material,
) {
  final embedded = _map(
    material['revision'] ??
        material['material_revision'] ??
        material['product_revision'],
  );
  if (embedded.isNotEmpty) return embedded;

  final revisionId =
      material['material_revision_id']?.toString() ??
      material['product_revision_id']?.toString() ??
      material['revision_id']?.toString();

  if (revisionId != null) {
    for (final key in const [
      'material_revisions',
      'product_revisions',
      'revisions',
    ]) {
      final revisions = (data[key] as Map?) ?? const {};
      final revision = _map(revisions[revisionId]);
      if (revision.isNotEmpty) return revision;
    }
  }

  return <String, dynamic>{
    if (material['revision_code'] != null)
      'revision_code': material['revision_code'],
    if (material['revision'] != null) 'revision': material['revision'],
    if (material['lot_number'] != null) 'lot_number': material['lot_number'],
    if (material['notes'] != null) 'notes': material['notes'],
    if (material['substrate_type'] != null)
      'substrate_type': material['substrate_type'],
    if (material['color'] != null) 'color': material['color'],
    if (material['finish'] != null) 'finish': material['finish'],
    if (material['grammage'] != null) 'grammage': material['grammage'],
    if (material['width'] != null) 'width': material['width'],
    if (material['ink_type'] != null) 'ink_type': material['ink_type'],
    if (material['color_code'] != null) 'color_code': material['color_code'],
    if (material['printing_technology'] != null)
      'printing_technology': material['printing_technology'],
  };
}

String _materialQuantity(
  Map<String, dynamic> data,
  Map<String, dynamic> material,
) {
  final units = (data['units'] as Map?) ?? const {};
  final unit = _map(units[material['uom_id']?.toString()]);
  final symbol =
      unit['symbol']?.toString().trim() ??
      material['uom_symbol']?.toString().trim() ??
      '';
  final quantity =
      material['required_quantity'] ??
      material['quantity_override'] ??
      material['planned_quantity'] ??
      0;
  return '${_fmt(quantity)}${symbol.isEmpty ? '' : ' $symbol'}';
}

List<MapEntry<String, String>> _productPreviewSpecs(
  Map<String, dynamic> data,
  Map<String, dynamic> material,
  Map<String, dynamic> revision,
) {
  final result = <MapEntry<String, String>>[];

  void add(String label, dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == '-') return;
    if (result.any((entry) => entry.key == label)) return;
    result.add(MapEntry(label, text));
  }

  final product = _materialProduct(data, material);

  add(
    'Tipo de sustrato',
    revision['substrate_type'] ??
        revision['substrate'] ??
        product['substrate_type'] ??
        material['substrate_type'],
  );
  add(
    'Color',
    revision['color'] ?? product['color'] ?? material['color'],
  );
  add(
    'Acabado',
    revision['finish'] ??
        revision['finish_type'] ??
        product['finish'] ??
        material['finish'],
  );
  add(
    'Gramaje',
    revision['grammage'] ??
        revision['basis_weight'] ??
        product['grammage'] ??
        material['grammage'],
  );
  add(
    'Ancho',
    revision['width'] ?? product['width'] ?? material['width'],
  );
  add(
    'Tipo de tinta',
    revision['ink_type'] ?? product['ink_type'] ?? material['ink_type'],
  );
  add(
    'Código de color',
    revision['color_code'] ??
        product['color_code'] ??
        material['color_code'],
  );
  add(
    'Tecnología de impresión',
    revision['printing_technology'] ??
        product['printing_technology'] ??
        material['printing_technology'],
  );

  if (result.isEmpty && material.isNotEmpty) {
    add('Cantidad requerida', _materialQuantity(data, material));
  }

  return result.take(5).toList();
}

List<_StepRecord> _stepRecordRows(
  Map<String, dynamic> data,
  Map<String, dynamic> operation,
) {
  final operationId = operation['id']?.toString();
  final routingOperationId = operation['routing_operation_id']?.toString();
  final operationCode = operation['operation_code']?.toString();
  final operationName = operation['name']?.toString();

  final events = _list(data['events']).where((event) {
    final eventOperationId =
        event['operation_id']?.toString() ??
        event['production_operation_id']?.toString();
    final eventRoutingOperationId =
        event['routing_operation_id']?.toString();

    if (operationId != null && eventOperationId == operationId) return true;
    if (routingOperationId != null &&
        eventRoutingOperationId == routingOperationId) {
      return true;
    }

    final description =
        '${event['title'] ?? ''} ${event['description'] ?? ''}'.toLowerCase();
    if (operationCode != null &&
        operationCode.trim().isNotEmpty &&
        description.contains(operationCode.toLowerCase())) {
      return true;
    }
    if (operationName != null &&
        operationName.trim().isNotEmpty &&
        description.contains(operationName.toLowerCase())) {
      return true;
    }

    return false;
  }).toList();

  if (events.isNotEmpty) {
    return events.map((event) {
      final action =
          event['title']?.toString().trim().isNotEmpty == true
          ? event['title'].toString()
          : UiCopy.enumLabel(
              event['new_status']?.toString() ??
                  event['event_type']?.toString() ??
                  'Actividad',
            );

      final user =
          event['user_name'] ??
          event['actor_name'] ??
          event['created_by_name'] ??
          event['operator_name'] ??
          '-';

      return _StepRecord(
        date: _dateTime(
          event['occurred_at'] ?? event['created_at'] ?? event['updated_at'],
        ),
        user: _show(user),
        action: action,
        notes: _show(event['description'] ?? event['notes']),
      );
    }).toList();
  }

  final status = operation['status']?.toString() ?? 'pending';
  final hasActivity =
      !['pending', 'ready'].contains(status) ||
      operation['actual_start_at'] != null ||
      operation['actual_end_at'] != null;

  if (!hasActivity) return const <_StepRecord>[];

  return [
    _StepRecord(
      date: _dateTime(
        operation['actual_end_at'] ??
            operation['actual_start_at'] ??
            operation['updated_at'],
      ),
      user: _show(
        operation['operator_name'] ??
            operation['completed_by_name'] ??
            operation['updated_by_name'],
      ),
      action: UiCopy.enumLabel(status),
      notes: _show(operation['notes']),
    ),
  ];
}

List<_DisplayField> _materialSpecPairs(
  Map<String, dynamic> revision,
  List<Map<String, dynamic>> attributes,
  Map<dynamic, dynamic> attributeDefinitions,
  Map<dynamic, dynamic> units,
) {
  final fields = <_DisplayField>[];
  void add(String label, dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return;
    fields.add(_DisplayField(label, text));
  }

  add('Revision', revision['revision_code'] ?? revision['revision']);
  add('Lote', revision['lot_number']);
  for (final attribute in attributes) {
    final definition = _map(
      attributeDefinitions[attribute['attribute_definition_id']?.toString()],
    );
    final label = definition['name']?.toString().trim();
    if (label == null || label.isEmpty) continue;
    final rawValue =
        attribute['value_text'] ??
        attribute['value_number'] ??
        attribute['value_boolean'] ??
        attribute['value_date'];
    final value = rawValue?.toString().trim();
    if (value == null || value.isEmpty) continue;
    final unit = _map(units[definition['uom_id']?.toString()]);
    final suffix = unit['symbol']?.toString();
    fields.add(
      _DisplayField(
        label,
        suffix == null || suffix.trim().isEmpty ? value : '$value $suffix',
      ),
    );
  }
  add('Notas tecnicas', revision['notes']);
  return fields;
}

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
    value == null || value.toString().trim().isEmpty ? '-' : value.toString();

DateTime? _dt(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String _dateTime(dynamic value) {
  final d = _dt(value);
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _operationTime(Map<String, dynamic> row) {
  final basis = row['run_time_basis']?.toString();
  if (basis == 'fixed') return '${_fmt(row['run_time_value'])} min';
  if (basis == 'per_unit') return '${_fmt(row['run_time_value'])} min / unidad';
  if (basis == 'formula') return row['run_time_formula']?.toString() ?? '-';
  return '-';
}

String _elapsed(Map<String, dynamic> row) {
  final start = _dt(row['actual_start_at']);
  if (start == null) return '-';
  final end = _dt(row['actual_end_at']) ?? DateTime.now();
  final minutes = end.difference(start).inMinutes;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '${hours}h ${rest}min';
}
