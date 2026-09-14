import 'base_repository.dart';

class OrderRepository extends BaseRepository {
  OrderRepository(super.service, super.client);

  Future<List<Map<String, dynamic>>> orders() =>
      listTenant('customer_orders', orderBy: 'order_date');

  Future<Map<String, dynamic>> detail(String orderId) async {
    final order = await service.one('customer_orders', orderId);
    if (order == null) throw StateError('Pedido no encontrado.');
    final lines = await service.list(
      'customer_order_lines',
      equals: {'customer_order_id': orderId},
      orderBy: 'line_no',
    );
    final lineIds = lines.map((e) => e['id']).whereType<String>().toList();
    final allocations = <Map<String, dynamic>>[];
    for (final id in lineIds) {
      allocations.addAll(
        await service.list(
          'production_order_allocations',
          equals: {'customer_order_line_id': id},
        ),
      );
    }
    return {'order': order, 'lines': lines, 'allocations': allocations};
  }

  Future<List<Map<String, dynamic>>> orderLineProductionStatus(
    String orderId,
  ) async {
    try {
      return await service.list(
        'v_order_line_production_status',
        equals: {'customer_order_id': orderId},
        orderBy: 'customer_order_line_id',
      );
    } catch (e) {
      if (!e.toString().contains('v_order_line_production_status')) rethrow;
    }

    final details = await detail(orderId);
    final lines = List<Map<String, dynamic>>.from(details['lines'] as List);
    final allocations = List<Map<String, dynamic>>.from(
      details['allocations'] as List,
    );
    final allocationByLine = <String, List<Map<String, dynamic>>>{};
    for (final allocation in allocations) {
      final lineId = allocation['customer_order_line_id']?.toString();
      if (lineId == null) continue;
      allocationByLine.putIfAbsent(lineId, () => []).add(allocation);
    }

    return lines.map((line) {
      final lineId = line['id']?.toString() ?? '';
      final lineAllocations =
          allocationByLine[lineId] ?? const <Map<String, dynamic>>[];
      final allocated = lineAllocations.fold<double>(
        0,
        (sum, allocation) =>
            sum + ((allocation['allocated_quantity'] as num?)?.toDouble() ?? 0),
      );
      final requested = (line['requested_quantity'] as num?)?.toDouble() ?? 0;
      return {
        'organization_id': line['organization_id'],
        'customer_order_id': line['customer_order_id'],
        'customer_order_line_id': line['id'],
        'line_no': line['line_no'],
        'product_id': line['product_id'],
        'product_description_snapshot': line['product_description_snapshot'],
        'requested_quantity': requested,
        'uom_id': line['uom_id'],
        'requested_delivery_date': line['requested_delivery_date'],
        'line_status': line['line_status'],
        'allocated_quantity': allocated,
        'quantity_pending_release': requested - allocated < 0
            ? 0
            : requested - allocated,
        'production_order_count': lineAllocations
            .map((allocation) => allocation['production_order_id']?.toString())
            .whereType<String>()
            .toSet()
            .length,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> releaseLineToProduction({
    required String orderLineId,
    required List<double> quantities,
    DateTime? requiredAt,
    String priority = 'normal',
  }) async {
    final params = {
      'p_order_line_id': orderLineId,
      'p_split_quantities': quantities,
      'p_required_at': requiredAt?.toIso8601String(),
      'p_priority': priority,
    };
    dynamic result;
    try {
      result = await service.rpc(
        'release_order_line_to_production',
        params: params,
      );
    } catch (error) {
      if (!_isMissingReleaseRpc(error)) rethrow;
      result = await _releaseLineWithDirectInserts(
        orderLineId: orderLineId,
        quantities: quantities,
        requiredAt: requiredAt,
        priority: priority,
      );
    }
    return List<Map<String, dynamic>>.from(result as List);
  }

  bool _isMissingReleaseRpc(Object error) {
    final text = error.toString();
    final missingRpc =
        text.contains('release_order_line_to_production') &&
        (text.contains('schema cache') ||
            text.contains('Could not find the function'));
    final staleRpc =
        text.contains('priority_level') &&
        text.contains('expression is of type text');
    return missingRpc || staleRpc;
  }

  Future<List<Map<String, dynamic>>> _releaseLineWithDirectInserts({
    required String orderLineId,
    required List<double> quantities,
    DateTime? requiredAt,
    required String priority,
  }) async {
    final line = await service.one('customer_order_lines', orderLineId);
    if (line == null) throw StateError('Línea de pedido no encontrada.');
    final org = line['organization_id']?.toString() ?? organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final requested = (line['requested_quantity'] as num?)?.toDouble() ?? 0;
    final existing = await service.list(
      'production_order_allocations',
      equals: {'customer_order_line_id': orderLineId},
    );
    final allocated = existing.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['allocated_quantity'] as num?)?.toDouble() ?? 0),
    );
    final total = quantities.fold<double>(0, (sum, value) => sum + value);
    if (quantities.isEmpty || quantities.any((value) => value <= 0)) {
      throw StateError('Captura al menos una cantidad mayor a cero.');
    }
    if (total > requested - allocated + 0.000001) {
      throw StateError('La cantidad liberada supera el pendiente de la línea.');
    }

    final created = <Map<String, dynamic>>[];
    final createdIds = <String>[];
    try {
      for (final quantity in quantities) {
        final opNumber = await service.rpc(
          'next_sequence_value',
          params: {'p_org': org, 'p_key': 'OP'},
        );
        final order = await service.insert('production_orders', {
          'organization_id': org,
          'op_number': opNumber.toString(),
          'product_id': line['product_id'],
          'planned_quantity': quantity,
          'completed_quantity': 0,
          'uom_id': line['uom_id'],
          'status': 'draft',
          'priority': priority,
          'required_at':
              requiredAt?.toIso8601String() ??
              line['requested_delivery_date']?.toString(),
          'notes': 'Creada desde línea de pedido',
          'created_by': userId,
          'updated_by': userId,
        });
        createdIds.add(order['id'].toString());
        await service.insert('production_order_allocations', {
          'organization_id': org,
          'production_order_id': order['id'],
          'customer_order_line_id': orderLineId,
          'allocated_quantity': quantity,
          'uom_id': line['uom_id'],
        });
        created.add(order);
      }
    } catch (_) {
      for (final id in createdIds.reversed) {
        await service.delete('production_orders', id);
      }
      rethrow;
    }
    return created;
  }
}
