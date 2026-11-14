import 'dart:math' as math;

import 'package:flutter/material.dart';

// Snapshot indexes are shared by the map, catalog and detail panels.
typedef FloorRow = Map<String, dynamic>;
List<FloorRow> floorRows(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
String floorText(dynamic value) =>
    value == null || value.toString().trim().isEmpty ? '—' : value.toString();
double floorNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String floorQuantity(dynamic value) {
  final number = floorNumber(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2);
}

String floorMachineStatus(FloorRow machine, List<FloorRow> operations) {
  final recordedStatus = machine['status']?.toString().toLowerCase();
  if ([
    'setup',
    'preparing',
    'preparation',
    'in_preparation',
  ].contains(recordedStatus)) {
    return 'setup';
  }
  if ([
    'busy',
    'producing',
    'in_production',
    'in_progress',
  ].contains(recordedStatus)) {
    return 'busy';
  }
  if (operations.any((operation) => operation['operation_type'] == 'setup')) {
    return 'setup';
  }
  if (operations.isNotEmpty) return 'busy';
  if (machine['is_active'] == false) return 'inactive';
  return machine['status']?.toString() ?? 'available';
}

Offset floorPosition(FloorRow row, int index, {bool warehouse = false}) {
  final x = row['floor_pos_x'];
  final y = row['floor_pos_y'];
  if (x is num && y is num && x.isFinite && y.isFinite) {
    return Offset(math.max(0, x.toDouble()), math.max(0, y.toDouble()));
  }
  return warehouse
      ? Offset(80 + index * 260, 1000)
      : Offset(80 + index % 6 * 270, 100 + index ~/ 6 * 245);
}

class FloorData {
  FloorData(this.raw) {
    final machineIds = machines.map((machine) => '${machine['id']}').toSet();
    final machinesByWorkCenter = <String, List<FloorRow>>{};
    for (final machine in machines) {
      final workCenter = machine['work_center_id']?.toString();
      if (workCenter != null) {
        machinesByWorkCenter.putIfAbsent(workCenter, () => []).add(machine);
      }
    }
    for (final operation in operations) {
      var machine = operation['machine_id']?.toString();
      if (machine?.isEmpty == true) machine = null;
      if (machine != null && !machineIds.contains(machine)) {
        operation['machine_id_unresolved'] = machine;
        machine = null;
        operation['machine_id'] = null;
      }
      if (machine == null) {
        final workCenter = operation['work_center_id']?.toString();
        final candidates = (machinesByWorkCenter[workCenter] ?? [])
            .where(
              (row) =>
                  row['is_active'] != false &&
                  !['maintenance', 'down', 'inactive'].contains(row['status']),
            )
            .toList();
        if (candidates.length == 1) {
          machine = candidates.single['id']?.toString();
          operation['machine_id'] = machine;
          operation['machine_assignment_inferred'] = true;
        }
      }
      if (machine != null) (operationsByMachine[machine] ??= []).add(operation);
      (operationsByOrder['${operation['production_order_id']}'] ??= []).add(
        operation,
      );
    }
    for (final rows in [
      ...operationsByMachine.values,
      ...operationsByOrder.values,
    ]) {
      rows.sort(
        (a, b) =>
            floorNumber(a['sequence_no'])
                .compareTo(floorNumber(b['sequence_no'])),
      );
    }
  }
  final FloorRow raw;
  late final List<FloorRow> machines = floorRows(raw['machines']);
  late final List<FloorRow> orders = floorRows(raw['orders']);
  late final List<FloorRow> operations = floorRows(raw['operations']);
  late final List<FloorRow> products = floorRows(raw['products']);
  late final List<FloorRow> zones = floorRows(raw['floor_zones']);
  late final List<FloorRow> warehouses = floorRows(raw['warehouses']);
  late final List<FloorRow> stock = floorRows(raw['inventory_stock']);
  late final List<FloorRow> movements = floorRows(raw['inventory_movements']);
  late final Map<String, Offset> suggestedMachinePositions =
      _buildSuggestedMachinePositions();
  bool get inventoryAvailable => raw['inventory_available'] == true;
  final Map<String, List<FloorRow>> operationsByMachine = {};
  final Map<String, List<FloorRow>> operationsByOrder = {};
  final Map<String, Map<String, FloorRow>> _indexes = {};
  Map<String, FloorRow> index(String key) => _indexes.putIfAbsent(
    key,
    () => {for (final row in floorRows(raw[key])) '${row['id']}': row},
  );
  FloorRow? row(String key, dynamic id) => index(key)[id?.toString()];
  String name(String key, dynamic id) {
    final item = row(key, id);
    if (item == null) return floorText(id);
    return floorText(
      item['name'] ??
          item['full_name'] ??
          item['op_number'] ??
          item['symbol'] ??
          item['code'],
    );
  }

  Offset machinePosition(FloorRow machine, int index) {
    final x = machine['floor_pos_x'];
    final y = machine['floor_pos_y'];
    if (x is num && y is num && x.isFinite && y.isFinite) {
      return floorPosition(machine, index);
    }
    return suggestedMachinePositions['${machine['id']}'] ??
        floorPosition(machine, index);
  }

  Map<String, Offset> _buildSuggestedMachinePositions() {
    final ids = machines.map((machine) => '${machine['id']}').toList();
    final graph = {for (final id in ids) id: <String>{}};
    final directedEdges = <MapEntry<String, String>>[];
    final participating = <String>{};
    for (final order in orders) {
      if (!['ready', 'in_progress', 'on_hold'].contains(order['status'])) {
        continue;
      }
      final steps = (operationsByOrder['${order['id']}'] ?? const <FloorRow>[])
          .map((operation) => operation['machine_id']?.toString())
          .whereType<String>()
          .toList();
      participating.addAll(steps);
      for (var i = 1; i < steps.length; i++) {
        if (steps[i - 1] == steps[i]) continue;
        graph[steps[i - 1]]?.add(steps[i]);
        graph[steps[i]]?.add(steps[i - 1]);
        directedEdges.add(MapEntry(steps[i - 1], steps[i]));
      }
    }

    final result = <String, Offset>{};
    final visited = <String>{};
    var component = 0;
    for (final machine in machines) {
      final start = '${machine['id']}';
      if (visited.contains(start)) continue;
      final members = <String>[];
      final queue = <String>[start];
      visited.add(start);
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        members.add(current);
        for (final next in graph[current] ?? const <String>{}) {
          if (visited.add(next)) queue.add(next);
        }
      }
      final linked = members.any((id) => (graph[id]?.isNotEmpty ?? false));
      if (!linked) {
        // Keep unrelated machines in their own visual group below routed cells.
        result[start] = Offset(
          80 + (component % 4) * 280,
          80 + component * 520,
        );
        component++;
        continue;
      }
      final depths = <String, int>{for (final id in members) id: 0};
      for (var pass = 0; pass < members.length; pass++) {
        var changed = false;
        for (final edge in directedEdges) {
          if (!depths.containsKey(edge.key) ||
              !depths.containsKey(edge.value)) {
            continue;
          }
          final nextDepth = depths[edge.key]! + 1;
          if (depths[edge.value]! < nextDepth) {
            depths[edge.value] = nextDepth;
            changed = true;
          }
        }
        if (!changed) break;
      }
      final columns = <int, List<String>>{};
      for (final id in members) {
        final depth = depths[id] ?? 0;
        (columns[depth] ??= []).add(id);
      }
      for (final entry in columns.entries) {
        for (var row = 0; row < entry.value.length; row++) {
          result[entry.value[row]] = Offset(
            80 + entry.key * 290,
            80 + component * 520 + row * 260,
          );
        }
      }
      component++;
    }
    // Machines without active routes sit in a separate area of the floor.
    var unassignedIndex = 0;
    for (final id in ids) {
      if (participating.contains(id)) continue;
      result[id] = Offset(
        80 + (unassignedIndex % 4) * 280,
        80 + component * 520 + (unassignedIndex ~/ 4) * 260,
      );
      unassignedIndex++;
    }
    return result;
  }

  List<FloorRow> activeOn(String id) =>
      (operationsByMachine[id] ?? []).where((operation) {
        final order = row('orders', operation['production_order_id']);
        if (order?['status'] == 'on_hold' || operation['status'] == 'on_hold') {
          return false;
        }
        return operation['status'] == 'in_progress' &&
            !['completed', 'cancelled'].contains(order?['status']);
      }).toList();

  bool operationIsRunning(FloorRow operation) {
    final order = row('orders', operation['production_order_id']);
    if (order?['status'] == 'on_hold' ||
        order?['status'] == 'completed' ||
        order?['status'] == 'cancelled' ||
        operation['status'] == 'on_hold') {
      return false;
    }
    return operation['status'] == 'in_progress';
  }

  bool operationIsComplete(FloorRow operation) =>
      ['completed', 'skipped'].contains(operation['status']);

  bool get hasAnimatedFlow =>
      operations.any(operationIsRunning) ||
      machines.any(
        (machine) => [
          'busy',
          'producing',
          'in_production',
          'in_progress',
        ].contains(machine['status']?.toString().toLowerCase()),
      );
  bool machineIsRunning(FloorRow machine) {
    final id = '${machine['id']}';
    return [
          'busy',
          'setup',
          'preparing',
          'preparation',
          'in_preparation',
          'producing',
          'in_production',
          'in_progress',
        ].contains(machine['status']?.toString().toLowerCase()) ||
        activeOn(id).isNotEmpty ||
        preparingOn(id).isNotEmpty ||
        routedOn(id).isNotEmpty;
  }

  List<FloorRow> preparingOn(String id) =>
      (operationsByMachine[id] ?? []).where((operation) {
        if (!isCurrentOperation(operation)) return false;
        final order = row('orders', operation['production_order_id']);
        return order?['status'] == 'ready' ||
            (operation['operation_type'] == 'setup' &&
                order?['status'] == 'in_progress');
      }).toList();

  List<FloorRow> routedOn(String id) =>
      (operationsByMachine[id] ?? []).where((operation) {
        final order = row('orders', operation['production_order_id']);
        return ['ready', 'in_progress'].contains(order?['status']);
      }).toList();

  FloorRow? currentOperation(String orderId) {
    final steps = operationsByOrder[orderId] ?? const <FloorRow>[];
    for (final operation in steps) {
      if (operation['status'] == 'in_progress') return operation;
    }
    for (final operation in steps) {
      if (![
        'completed',
        'skipped',
        'cancelled',
      ].contains(operation['status'])) {
        return operation;
      }
    }
    return null;
  }

  bool isCurrentOperation(FloorRow operation) =>
      currentOperation('${operation['production_order_id']}')?['id'] ==
      operation['id'];

  String operationState(FloorRow operation) {
    final order = row('orders', operation['production_order_id']);
    if (operation['status'] == 'completed') return 'Completado';
    if (operation['status'] == 'skipped') return 'Omitido';
    if ((order?['status'] == 'on_hold' || operation['status'] == 'on_hold') &&
        isCurrentOperation(operation)) {
      return 'Necesita continuar';
    }
    if (operation['status'] == 'in_progress') {
      return 'En ejecución';
    }
    if (order?['status'] == 'in_progress' && isCurrentOperation(operation)) {
      return 'Lista para seguir';
    }
    if (operation['operation_type'] == 'setup' &&
        isCurrentOperation(operation)) {
      return 'Preparación';
    }
    if (isCurrentOperation(operation) &&
        ['ready', 'in_progress'].contains(order?['status'])) {
      return 'Lista para seguir';
    }
    return 'En espera';
  }

  int completedSteps(String orderId) => (operationsByOrder[orderId] ?? [])
      .where((o) => ['completed', 'skipped'].contains(o['status']))
      .length;

  int totalSteps(String orderId) => (operationsByOrder[orderId] ?? []).length;

  List<FloorRow> get unassignedRouteOperations => operations.where((operation) {
    final machineId = operation['machine_id']?.toString();
    if ((machineId != null && machineId.isNotEmpty) ||
        ['completed', 'skipped', 'cancelled'].contains(operation['status'])) {
      return false;
    }
    final order = row('orders', operation['production_order_id']);
    return ['ready', 'in_progress', 'on_hold'].contains(order?['status']);
  }).toList();

  int get activeOrdersWithoutMachine => unassignedRouteOperations
      .map((operation) => '${operation['production_order_id']}')
      .toSet()
      .length;

  List<FloorRow> queueOn(String id) => (operationsByMachine[id] ?? []).where((
    operation,
  ) {
    if (!['completed', 'skipped', 'cancelled'].contains(operation['status'])) {
      return true;
    }
    final order = row('orders', operation['production_order_id']);
    return ['ready', 'in_progress'].contains(order?['status']);
  }).toList();
  String status(FloorRow machine) {
    final id = '${machine['id']}';
    final recorded = machine['status']?.toString().toLowerCase();
    if ([
      'busy',
      'producing',
      'in_production',
      'in_progress',
    ].contains(recorded)) {
      return 'busy';
    }
    if ([
      'setup',
      'preparing',
      'preparation',
      'in_preparation',
    ].contains(recorded)) {
      return 'setup';
    }
    final active = activeOn(id);
    if (active.isNotEmpty) return floorMachineStatus(machine, active);
    if (preparingOn(id).isNotEmpty) return 'setup';
    if (['maintenance', 'down', 'inactive'].contains(recorded)) {
      return recorded!;
    }
    if (routedOn(id).any((operation) => !operationIsComplete(operation))) {
      return 'queued';
    }
    return floorMachineStatus(machine, const []);
  }

  Size bounds(
    Map<String, Offset> positions, {
    Iterable<FloorRow>? visibleMachines,
    bool includeStorage = true,
  }) {
    var right = 900.0;
    var bottom = 600.0;
    final shownMachines = visibleMachines ?? machines;
    for (final machine in shownMachines) {
      final point =
          positions['machine:${machine['id']}'] ??
          machinePosition(machine, machines.indexOf(machine));
      right = math.max(right, point.dx + 300);
      bottom = math.max(bottom, point.dy + 300);
    }
    if (includeStorage) {
      for (var index = 0; index < warehouses.length; index++) {
        final point =
            positions['warehouse:${warehouses[index]['id']}'] ??
            floorPosition(warehouses[index], index, warehouse: true);
        right = math.max(right, point.dx + 300);
        bottom = math.max(bottom, point.dy + 260);
      }
      for (final zone in zones) {
        final p =
            positions['zone:${zone['id']}'] ??
            Offset(floorNumber(zone['x']), floorNumber(zone['y']));
        right = math.max(right, p.dx + floorNumber(zone['width']) + 80);
        bottom = math.max(bottom, p.dy + floorNumber(zone['height']) + 80);
      }
    }
    return Size(right, bottom);
  }
}
