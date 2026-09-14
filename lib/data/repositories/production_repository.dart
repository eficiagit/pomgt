import 'dart:convert';
import 'base_repository.dart';

class ProductionRepository extends BaseRepository {
  ProductionRepository(super.service, super.client);

  Future<List<Map<String, dynamic>>> orders() {
    return listTenant(
      'v_production_order_workspace',
      orderBy: 'created_at',
    ).then((rows) {
      rows.sort((a, b) {
        final ad =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(0);
        final bd =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(0);
        return bd.compareTo(ad);
      });
      return rows;
    });
  }

  Future<Map<String, dynamic>> detail(String orderId) async {
    final order = await service.one('v_production_order_workspace', orderId);
    if (order == null) throw StateError('Orden de producción no encontrada.');

    final operations = await service.list(
      'production_order_operations',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final materials = await service.list(
      'production_order_materials',
      equals: {'production_order_id': orderId},
      orderBy: 'line_no',
    );
    final checklist = await service.list(
      'production_order_checklist_items',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final quality = await service.list(
      'production_order_quality_checks',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final parameters = await service.list(
      'production_order_machine_parameters',
      equals: {'production_order_id': orderId},
      orderBy: 'created_at',
    );
    final events = await service.list(
      'production_order_events',
      equals: {'production_order_id': orderId},
      orderBy: 'occurred_at',
      ascending: false,
    );
    final costs = await service.list(
      'production_order_costs',
      equals: {'production_order_id': orderId},
      limit: 1,
    );
    final allocations = await service.list(
      'production_order_allocations',
      equals: {'production_order_id': orderId},
      orderBy: 'created_at',
    );
    final dependencies = await service.list(
      'production_order_operation_dependencies',
      equals: {'production_order_id': orderId},
    );
    dependencies.sort((a, b) {
      final operation = (a['operation_id']?.toString() ?? '').compareTo(
        b['operation_id']?.toString() ?? '',
      );
      if (operation != 0) return operation;
      return (a['predecessor_operation_id']?.toString() ?? '').compareTo(
        b['predecessor_operation_id']?.toString() ?? '',
      );
    });
    final movements = await service.list(
      'production_order_material_movements',
      equals: {'production_order_id': orderId},
      orderBy: 'occurred_at',
      ascending: false,
    );

    final product = await service.one(
      'products',
      order['product_id'].toString(),
    );
    final uom = await service.one(
      'units_of_measure',
      order['uom_id'].toString(),
    );

    final customerOrder = order['customer_order_id'] == null
        ? null
        : await service.one(
            'customer_orders',
            order['customer_order_id'].toString(),
          );
    final customer = order['customer_id'] == null
        ? null
        : await service.one('customers', order['customer_id'].toString());

    final workCenters = <String, Map<String, dynamic>>{};
    final machines = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    final units = <String, Map<String, dynamic>>{};

    if (product != null) products[product['id'].toString()] = product;
    if (uom != null) units[uom['id'].toString()] = uom;

    for (final op in operations) {
      final wc = op['work_center_id']?.toString();
      if (wc != null && !workCenters.containsKey(wc)) {
        final row = await service.one('work_centers', wc);
        if (row != null) workCenters[wc] = row;
      }
      final machine = op['machine_id']?.toString();
      if (machine != null && !machines.containsKey(machine)) {
        final row = await service.one('machines', machine);
        if (row != null) machines[machine] = row;
      }
    }

    for (final material in materials) {
      final pid = material['material_product_id']?.toString();
      if (pid != null && !products.containsKey(pid)) {
        final row = await service.one('products', pid);
        if (row != null) products[pid] = row;
      }
      final uid = material['uom_id']?.toString();
      if (uid != null && !units.containsKey(uid)) {
        final row = await service.one('units_of_measure', uid);
        if (row != null) units[uid] = row;
      }
    }

    for (final check in quality) {
      final uid = check['uom_id']?.toString();
      if (uid != null && !units.containsKey(uid)) {
        final row = await service.one('units_of_measure', uid);
        if (row != null) units[uid] = row;
      }
    }

    return {
      'order': order,
      'product': product,
      'uom': uom,
      'customer_order': customerOrder,
      'customer': customer,
      'operations': operations,
      'materials': materials,
      'checklist': checklist,
      'quality': quality,
      'parameters': parameters,
      'events': events,
      'costs': costs.isEmpty ? null : costs.first,
      'allocations': allocations,
      'dependencies': dependencies,
      'movements': movements,
      'work_centers': workCenters,
      'machines': machines,
      'products': products,
      'units': units,
    };
  }

  Future<Map<String, dynamic>> createManual({
    required String productId,
    required double quantity,
    String? uomId,
    DateTime? requiredAt,
    String priority = 'normal',
    DateTime? plannedStartAt,
    DateTime? plannedEndAt,
    String? notes,
    String sourceType = 'internal',
    String? bomRevisionId,
    String? routingRevisionId,
  }) async {
    final result = await service.rpc(
      'create_production_order',
      params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_uom_id': uomId,
        'p_required_at': requiredAt?.toIso8601String(),
        'p_priority': priority,
        'p_planned_start_at': plannedStartAt?.toIso8601String(),
        'p_planned_end_at': plannedEndAt?.toIso8601String(),
        'p_notes': notes,
        'p_source_type': sourceType,
        'p_bom_revision_id': bomRevisionId,
        'p_routing_revision_id': routingRevisionId,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> prepare(String orderId) async {
    await _alignOrderUomWithBom(orderId);
    try {
      final result = await service.rpc(
        'prepare_production_order',
        params: {'p_order_id': orderId},
      );
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      if (!_canFallbackPrepare(e)) rethrow;
      return _prepareWithDirectUpdate(orderId);
    }
  }

  bool _canFallbackPrepare(Object error) {
    final text = error.toString();
    return text.contains('prepare_production_order') &&
        (text.contains('schema cache') ||
            text.contains('Could not find the function'));
  }

  Future<Map<String, dynamic>> _prepareWithDirectUpdate(String orderId) async {
    final current = await service.one('production_orders', orderId);
    if (current == null) throw StateError('Orden de producción no encontrada.');
    final status = current['status']?.toString();
    if (status != 'draft' && status != 'planned' && status != 'ready') {
      throw StateError('La OP no se puede preparar desde su estado actual.');
    }
    await service.update('production_orders', orderId, {
      'status': 'ready',
      'updated_by': userId,
      'updated_at': DateTime.now().toIso8601String(),
    });
    return await service.one('v_production_order_workspace', orderId) ??
        await service.one('production_orders', orderId) ??
        <String, dynamic>{'id': orderId, 'status': 'ready'};
  }

  Future<void> _alignOrderUomWithBom(String orderId) async {
    final order = await service.one('production_orders', orderId);
    final bomRevisionId = order?['bom_revision_id']?.toString();
    if (bomRevisionId == null || bomRevisionId.isEmpty) return;

    final bomRevision = await service.one('bom_revisions', bomRevisionId);
    final bomUomId = bomRevision?['output_uom_id']?.toString();
    if (bomUomId == null || bomUomId.isEmpty) return;
    if (order?['uom_id']?.toString() == bomUomId) return;

    await service.update('production_orders', orderId, {
      'uom_id': bomUomId,
      'updated_by': userId,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> transitionOrder(
    String orderId,
    String newStatus, {
    String? note,
    double? completedQuantity,
  }) async {
    final current =
        await service.one('v_production_order_workspace', orderId) ??
        await service.one('production_orders', orderId);
    if (current?['status']?.toString() == newStatus) {
      return current ?? <String, dynamic>{'id': orderId, 'status': newStatus};
    }
    final result = await service.rpc(
      'transition_production_order',
      params: {
        'p_order_id': orderId,
        'p_new_status': newStatus,
        'p_note': note,
        'p_completed_quantity': completedQuantity,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return await service.one('v_production_order_workspace', orderId) ??
        await service.one('production_orders', orderId) ??
        <String, dynamic>{'id': orderId, 'status': newStatus};
  }

  Future<Map<String, dynamic>> updatePlanning(
    String orderId, {
    DateTime? plannedStartAt,
    DateTime? plannedEndAt,
    DateTime? requiredAt,
    String? priority,
    String? notes,
    String? responsibleUserId,
  }) {
    return service.update('production_orders', orderId, {
      'planned_start_at': plannedStartAt?.toIso8601String(),
      'planned_end_at': plannedEndAt?.toIso8601String(),
      'required_at': requiredAt?.toIso8601String(),
      if (priority != null) 'priority': priority,
      'notes': notes,
      'responsible_user_id': responsibleUserId,
      'updated_by': userId,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> transitionOperation(
    String operationId,
    String newStatus, {
    double? completedQuantity,
    double? rejectedQuantity,
    String? note,
  }) async {
    final current = await service.one(
      'production_order_operations',
      operationId,
    );
    if (current?['status']?.toString() == newStatus) {
      return current ??
          <String, dynamic>{'id': operationId, 'status': newStatus};
    }
    final result = await service.rpc(
      'transition_production_operation',
      params: {
        'p_operation_id': operationId,
        'p_new_status': newStatus,
        'p_completed_quantity': completedQuantity,
        'p_rejected_quantity': rejectedQuantity,
        'p_note': note,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return await service.one('production_order_operations', operationId) ??
        <String, dynamic>{'id': operationId, 'status': newStatus};
  }

  Future<Map<String, dynamic>> updateOperationResources(
    String operationId, {
    String? workCenterId,
    String? machineId,
    DateTime? plannedStartAt,
    DateTime? plannedEndAt,
    String? notes,
  }) {
    return service.update('production_order_operations', operationId, {
      'work_center_id': workCenterId,
      'machine_id': machineId,
      'planned_start_at': plannedStartAt?.toIso8601String(),
      'planned_end_at': plannedEndAt?.toIso8601String(),
      'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> materialMovement({
    required String materialId,
    required String movementType,
    required double quantity,
    String? lotNumber,
    String? warehouseReference,
    String? note,
  }) async {
    final result = await service.rpc(
      'register_production_material_movement',
      params: {
        'p_material_id': materialId,
        'p_movement_type': movementType,
        'p_quantity': quantity,
        'p_lot_number': lotNumber,
        'p_warehouse_reference': warehouseReference,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> answerChecklist({
    required String itemId,
    required dynamic response,
    String? note,
  }) async {
    final result = await service.rpc(
      'answer_production_checklist_item',
      params: {'p_item_id': itemId, 'p_response': response, 'p_note': note},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> recordQuality({
    required String checkId,
    required dynamic resultValue,
    String? note,
    String? forceStatus,
  }) async {
    final result = await service.rpc(
      'record_production_quality_result',
      params: {
        'p_check_id': checkId,
        'p_result': resultValue,
        'p_note': note,
        'p_force_status': forceStatus,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> updateMachineParameter({
    required String parameterId,
    required dynamic actualValue,
    String? note,
  }) {
    return service.update('production_order_machine_parameters', parameterId, {
      'actual_value': actualValue,
      'verified_by': userId,
      'verified_at': DateTime.now().toIso8601String(),
      'notes': note,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> updateCosts(
    String costId, {
    double? estimatedMaterial,
    double? estimatedLabor,
    double? estimatedMachine,
    double? estimatedSubcontract,
    double? estimatedOverhead,
    double? actualMaterial,
    double? actualLabor,
    double? actualMachine,
    double? actualSubcontract,
    double? actualOverhead,
  }) {
    return service.update('production_order_costs', costId, {
      if (estimatedMaterial != null) 'estimated_material': estimatedMaterial,
      if (estimatedLabor != null) 'estimated_labor': estimatedLabor,
      if (estimatedMachine != null) 'estimated_machine': estimatedMachine,
      if (estimatedSubcontract != null)
        'estimated_subcontract': estimatedSubcontract,
      if (estimatedOverhead != null) 'estimated_overhead': estimatedOverhead,
      if (actualMaterial != null) 'actual_material': actualMaterial,
      if (actualLabor != null) 'actual_labor': actualLabor,
      if (actualMachine != null) 'actual_machine': actualMachine,
      if (actualSubcontract != null) 'actual_subcontract': actualSubcontract,
      if (actualOverhead != null) 'actual_overhead': actualOverhead,
      'last_recalculated_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  String jsonText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return jsonEncode(value);
  }
}
