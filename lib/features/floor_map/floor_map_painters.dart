part of 'floor_map_screen.dart';

class _OrderFlowLinkPainter extends CustomPainter {
  const _OrderFlowLinkPainter({
    required this.data,
    required this.source,
    required this.animationProgress,
  });

  final FloorData data;
  final FloorRow source;
  final double animationProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final completed = data.operationIsComplete(source);
    final running = data.operationIsRunning(source);
    final color = completed
        ? PomgtColors.success
        : running
        ? PomgtColors.blue
        : PomgtColors.cyan;
    final path = Path()
      ..moveTo(2, size.height / 2)
      ..lineTo(size.width - 10, size.height / 2);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(
          alpha: running
              ? .28
              : completed
              ? .9
              : .35,
        )
        ..strokeWidth = completed ? 3 : 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    if (running) {
      const dash = 24.0;
      const gap = 15.0;
      final length = size.width - 12;
      final offset = animationProgress * (dash + gap);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var start = -dash + offset; start < length; start += dash + gap) {
        final from = math.max(0.0, start);
        final to = math.min(length, start + dash);
        if (to > from) {
          canvas.drawLine(
            Offset(from + 2, size.height / 2),
            Offset(to + 2, size.height / 2),
            paint,
          );
        }
      }
    }
    final arrow = Path()
      ..moveTo(size.width - 4, size.height / 2)
      ..lineTo(size.width - 13, size.height / 2 - 5)
      ..lineTo(size.width - 13, size.height / 2 + 5)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = color.withValues(alpha: completed || running ? 1 : .65)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _OrderFlowLinkPainter oldDelegate) =>
      oldDelegate.animationProgress != animationProgress ||
      oldDelegate.source != source ||
      oldDelegate.data != data;
}

/// Floor markings and routed arrows use the same world coordinates as nodes.
class _FactoryPainter extends CustomPainter {
  _FactoryPainter({
    required this.data,
    required this.positions,
    required this.flows,
    required this.visible,
    required this.selectedOrder,
    required this.animationProgress,
  });
  final FloorData data;
  final Map<String, Offset> positions;
  final bool flows;
  final Set<String> visible;
  final String? selectedOrder;
  final double animationProgress;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PomgtColors.appBg);
    final grid = Paint()
      ..color = PomgtColors.lineStrong.withValues(alpha: .4)
      ..strokeWidth = .6;
    for (var x = 0.0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final walls = Paint()
      ..color = PomgtColors.lineStrong
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(20, 20, size.width - 40, size.height - 40),
        const Radius.circular(20),
      ),
      walls,
    );
    // Dashed lanes between rows leave the machine footprints clear.
    final lane = Paint()
      ..color = PomgtColors.amber.withValues(alpha: .5)
      ..strokeWidth = 3;
    for (var y = 325.0; y < size.height - 100; y += 245) {
      for (var x = 50.0; x < size.width - 50; x += 35) {
        canvas.drawLine(Offset(x, y), Offset(x + 18, y), lane);
      }
    }
    if (!flows) return;
    final machinePositions = <String, Offset>{
      for (var i = 0; i < data.machines.length; i++)
        '${data.machines[i]['id']}':
            positions['machine:${data.machines[i]['id']}'] ??
            data.machinePosition(data.machines[i], i),
    };
    var count = 0;
    for (final entry in data.operationsByOrder.entries) {
      if (selectedOrder != null && entry.key != selectedOrder) continue;
      final order = data.row('orders', entry.key);
      if (selectedOrder == null &&
          ['completed', 'cancelled'].contains(order?['status'])) {
        continue;
      }
      final steps = entry.value.where((o) => o['machine_id'] != null).toList();
      for (var i = 1; i < steps.length; i++) {
        final from = '${steps[i - 1]['machine_id']}';
        final to = '${steps[i]['machine_id']}';
        if (from == to || !visible.contains(from) || !visible.contains(to)) {
          continue;
        }
        final start = machinePositions[from], end = machinePositions[to];
        if (start == null || end == null) continue;
        final a = start + const Offset(220, 105),
            b = end + const Offset(0, 105);
        final mid = (a.dx + b.dx) / 2 + (count % 5) * 7;
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
        final source = steps[i - 1];
        final completed = data.operationIsComplete(source);
        final running = data.operationIsRunning(source);
        final color = completed
            ? PomgtColors.success
            : running
            ? PomgtColors.blue
            : PomgtColors.cyan;
        final selected = selectedOrder == entry.key;
        final width = selected ? 3.2 : 2.2;
        final basePaint = Paint()
          ..color = color.withValues(
            alpha: completed
                ? .9
                : running
                ? .26
                : selected
                ? .48
                : .2,
          )
          ..strokeWidth = completed
              ? width
              : selected
              ? 2.2
              : 1.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(path, basePaint);
        if (running) {
          _drawSnake(canvas, path, color, width, animationProgress);
        }
        _drawArrow(canvas, b, color, alpha: completed ? .9 : .55);
        count++;
      }
    }
    _drawQueueFans(canvas, machinePositions);
  }

  /// When a single machine has several orders queued on it, one line per
  /// order fans out above the node instead of a single generic connector -
  /// so a busy shared machine reads as "3 orders waiting here", not "1
  /// anonymous order", at a glance.
  void _drawQueueFans(Canvas canvas, Map<String, Offset> machinePositions) {
    const maxBadges = 4;
    for (final machine in data.machines) {
      final machineId = '${machine['id']}';
      if (!visible.contains(machineId)) continue;
      final anchor = machinePositions[machineId];
      if (anchor == null) continue;
      final queue = data.queueOn(machineId);
      final seenOrders = <String>{};
      final queuedOps = <FloorRow>[];
      for (final operation in queue) {
        final orderId = '${operation['production_order_id']}';
        if (seenOrders.add(orderId)) queuedOps.add(operation);
      }
      if (queuedOps.length < 2) continue;
      if (selectedOrder != null && !seenOrders.contains(selectedOrder)) {
        continue;
      }
      final top = anchor + const Offset(110, 0);
      final shown = queuedOps.take(maxBadges).toList();
      final extra = queuedOps.length - shown.length;
      final spacing = 36.0;
      final startX =
          top.dx - (shown.length - (extra > 0 ? 0 : 1)) * spacing / 2;
      for (var j = 0; j < shown.length; j++) {
        _drawQueueBadge(
          canvas,
          top,
          Offset(startX + j * spacing, top.dy - 54),
          shown[j],
        );
      }
      if (extra > 0) {
        final badge = Offset(startX + shown.length * spacing, top.dy - 54);
        final paint = Paint()
          ..color = PomgtColors.muted.withValues(alpha: .4)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(
          Path()
            ..moveTo(top.dx, top.dy)
            ..quadraticBezierTo(
              (top.dx + badge.dx) / 2,
              top.dy - 24,
              badge.dx,
              badge.dy,
            ),
          paint,
        );
        _drawBadgeDot(canvas, badge, PomgtColors.muted, '+$extra');
      }
    }
  }

  void _drawQueueBadge(
    Canvas canvas,
    Offset anchor,
    Offset badge,
    FloorRow operation,
  ) {
    final running = data.operationIsRunning(operation);
    final completed = data.operationIsComplete(operation);
    final color = running
        ? PomgtColors.blue
        : completed
        ? PomgtColors.success
        : PomgtColors.cyan;
    final path = Path()
      ..moveTo(anchor.dx, anchor.dy)
      ..quadraticBezierTo(
        (anchor.dx + badge.dx) / 2,
        anchor.dy - 24,
        badge.dx,
        badge.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: running ? .4 : .5)
        ..strokeWidth = running ? 2.2 : 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (running) _drawSnake(canvas, path, color, 2.2, animationProgress);
    final order = data.row('orders', operation['production_order_id']);
    _drawBadgeDot(canvas, badge, color, _shortOpNumber(order?['op_number']));
  }

  void _drawBadgeDot(Canvas canvas, Offset center, Color color, String label) {
    canvas.drawCircle(center, 11, Paint()..color = color);
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = Colors.white.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  String _shortOpNumber(dynamic value) {
    final text = value?.toString() ?? '';
    final digits = RegExp(r'\d+').allMatches(text).map((m) => m.group(0)!);
    final last = digits.isEmpty ? text : digits.last;
    return last.length <= 4 ? last : last.substring(last.length - 4);
  }

  @override
  bool shouldRepaint(covariant _FactoryPainter oldDelegate) => true;

  void _drawSnake(
    Canvas canvas,
    Path path,
    Color color,
    double width,
    double progress,
  ) {
    const dashLength = 24.0;
    const gapLength = 15.0;
    const period = dashLength + gapLength;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final offset = progress * period;
    for (final metric in path.computeMetrics()) {
      for (
        var start = -period + offset;
        start < metric.length;
        start += period
      ) {
        final from = math.max(0.0, start);
        final to = math.min(metric.length, start + dashLength);
        if (to > from) canvas.drawPath(metric.extractPath(from, to), paint);
      }
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset tip,
    Color color, {
    required double alpha,
  }) {
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 9, tip.dy - 5)
        ..lineTo(tip.dx - 9, tip.dy + 5)
        ..close(),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  _MiniMapPainter(
    this.data,
    this.positions,
    this.transform,
    this.viewport,
    this.visibleMachines,
    this.includeStorage,
  );
  final FloorData data;
  final Map<String, Offset> positions;
  final TransformationController transform;
  final Size viewport;
  final Set<String> visibleMachines;
  final bool includeStorage;
  @override
  void paint(Canvas canvas, Size size) {
    final world = data.bounds(
      positions,
      visibleMachines: data.machines.where(
        (machine) => visibleMachines.contains('${machine['id']}'),
      ),
      includeStorage: includeStorage,
    );
    final scale = math.min(
      (size.width - 8) / world.width,
      (size.height - 8) / world.height,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(4, 4);
    canvas.scale(scale);
    canvas.drawRect(Offset.zero & world, Paint()..color = PomgtColors.appBg);
    for (final zone in includeStorage ? data.zones : const <FloorRow>[]) {
      final p =
          positions['zone:${zone['id']}'] ??
          Offset(floorNumber(zone['x']), floorNumber(zone['y']));
      canvas.drawRect(
        p & Size(floorNumber(zone['width']), floorNumber(zone['height'])),
        Paint()..color = _zoneColor('${zone['kind']}').withValues(alpha: .15),
      );
    }
    for (var i = 0; i < data.machines.length; i++) {
      final row = data.machines[i];
      if (!visibleMachines.contains('${row['id']}')) continue;
      final p = positions['machine:${row['id']}'] ?? floorPosition(row, i);
      canvas.drawRect(
        p & const Size(220, 180),
        Paint()..color = _statusColor(data.status(row)),
      );
    }
    for (var i = 0; includeStorage && i < data.warehouses.length; i++) {
      final row = data.warehouses[i];
      final p =
          positions['warehouse:${row['id']}'] ??
          floorPosition(row, i, warehouse: true);
      canvas.drawRect(
        p & const Size(220, 150),
        Paint()..color = PomgtColors.amber,
      );
    }
    final visible = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(viewport.bottomRight(Offset.zero)),
    );
    canvas.drawRect(
      visible,
      Paint()
        ..color = PomgtColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) => true;
}
