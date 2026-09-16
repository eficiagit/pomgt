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

    var operations = await service.list(
      'production_order_operations',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    var materials = await service.list(
      'production_order_materials',
      equals: {'production_order_id': orderId},
      orderBy: 'line_no',
    );
    if (operations.isEmpty) {
      operations = await _operationsFromRouting(orderId, order);
    }
    if (materials.isEmpty) {
      materials = await _materialsFromBom(orderId, order);
    }
    operations = await _normalizeOperationRows(operations);
    materials = _normalizeMaterialRows(materials);
    final routingOperationMaterials = await _routingOperationMaterials(
      operations,
    );
    materials = _mergeDirectOperationMaterials(
      materials,
      routingOperationMaterials,
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
    final materialRevisions = await _materialRevisions(materials);
    final materialAttributeValues = await _materialAttributeValues(
      materialRevisions,
    );
    final materialAttributeDefinitions = await _materialAttributeDefinitions(
      materialAttributeValues,
    );

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
      'operation_materials': routingOperationMaterials,
      'material_revisions': materialRevisions,
      'material_attribute_values': materialAttributeValues,
      'material_attribute_definitions': materialAttributeDefinitions,
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

  List<Map<String, dynamic>> _mergeDirectOperationMaterials(
    List<Map<String, dynamic>> materials,
    Map<String, List<Map<String, dynamic>>> operationMaterials,
  ) {
    final merged = [...materials];
    final existingBomItems = materials
        .map((row) => row['bom_item_id']?.toString())
        .whereType<String>()
        .toSet();
    final existingProducts = materials
        .map((row) => row['material_product_id']?.toString())
        .whereType<String>()
        .toSet();
    for (final link in operationMaterials.values.expand((rows) => rows)) {
      final bomItemId = link['bom_item_id']?.toString();
      final productId = link['material_product_id']?.toString();
      final alreadyIncluded =
          (bomItemId != null && existingBomItems.contains(bomItemId)) ||
          (bomItemId == null &&
              productId != null &&
              existingProducts.contains(productId));
      if (alreadyIncluded) continue;
      merged.add({
        'id': 'routing-material:${link['id']}',
        'production_order_id': null,
        'routing_operation_material_id': link['id'],
        'bom_item_id': link['bom_item_id'],
        'line_no': merged.length + 1,
        'component_type': 'material',
        'material_product_id': link['material_product_id'],
        'uom_id': link['uom_id'],
        'required_quantity': link['quantity_override'],
        'issued_quantity': 0,
        'consumed_quantity': 0,
        'scrap_quantity': 0,
        'issue_method': link['consumption_point'],
        'status': 'planned',
        'notes': link['notes'],
      });
      if (bomItemId != null) existingBomItems.add(bomItemId);
      if (productId != null) existingProducts.add(productId);
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _normalizeOperationRows(
    List<Map<String, dynamic>> operations,
  ) async {
    final normalized = <Map<String, dynamic>>[];
    for (final row in operations) {
      final copy = Map<String, dynamic>.from(row);
      copy['routing_operation_id'] ??= copy['source_routing_operation_id'];
      if (copy['operation_type'] == null) {
        final sourceId = copy['source_routing_operation_id']?.toString();
        if (sourceId != null && sourceId.isNotEmpty) {
          final routingOperation = await service.one(
            'routing_operations',
            sourceId,
          );
          copy['operation_type'] =
              routingOperation?['operation_type']?.toString() ?? 'activity';
        } else {
          copy['operation_type'] = 'activity';
        }
      }
      normalized.add(copy);
    }
    return normalized;
  }

  List<Map<String, dynamic>> _normalizeMaterialRows(
    List<Map<String, dynamic>> materials,
  ) {
    return materials.map((row) {
      final copy = Map<String, dynamic>.from(row);
      copy['bom_item_id'] ??= copy['source_bom_item_id'];
      return copy;
    }).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _routingOperationMaterials(
    List<Map<String, dynamic>> operations,
  ) async {
    final byOperation = <String, List<Map<String, dynamic>>>{};
    for (final op in operations) {
      final routingOperationId = op['routing_operation_id']?.toString();
      if (routingOperationId == null || routingOperationId.isEmpty) continue;
      final rows = await service.list(
        'routing_operation_materials',
        equals: {'routing_operation_id': routingOperationId},
        orderBy: 'consumption_point',
      );
      if (rows.isNotEmpty) {
        byOperation[routingOperationId] = rows;
      }
    }
    return byOperation;
  }

  Future<Map<String, Map<String, dynamic>>> _materialRevisions(
    List<Map<String, dynamic>> materials,
  ) async {
    final revisions = <String, Map<String, dynamic>>{};
    final materialIds = materials
        .map((row) => row['material_product_id']?.toString())
        .whereType<String>()
        .toSet();
    for (final materialId in materialIds) {
      final rows = await listTenant(
        'product_revisions',
        filters: {'product_id': materialId},
        orderBy: 'revision_no',
      );
      if (rows.isEmpty) continue;
      final active = rows.cast<Map<String, dynamic>?>().firstWhere(
        (row) => row?['status'] == 'active',
        orElse: () => rows.last,
      );
      if (active != null) {
        revisions[materialId] = Map<String, dynamic>.from(active);
      }
    }
    return revisions;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _materialAttributeValues(
    Map<String, Map<String, dynamic>> materialRevisions,
  ) async {
    final values = <String, List<Map<String, dynamic>>>{};
    for (final entry in materialRevisions.entries) {
      final revisionId = entry.value['id']?.toString();
      if (revisionId == null || revisionId.isEmpty) continue;
      final rows = await listTenant(
        'material_revision_attribute_values',
        filters: {'product_revision_id': revisionId},
      );
      values[entry.key] = rows;
    }
    return values;
  }

  Future<Map<String, Map<String, dynamic>>> _materialAttributeDefinitions(
    Map<String, List<Map<String, dynamic>>> valuesByMaterial,
  ) async {
    final definitions = <String, Map<String, dynamic>>{};
    final definitionIds = valuesByMaterial.values
        .expand((rows) => rows)
        .map((row) => row['attribute_definition_id']?.toString())
        .whereType<String>()
        .toSet();
    for (final id in definitionIds) {
      final row = await service.one('material_attribute_definitions', id);
      if (row != null) definitions[id] = row;
    }
    return definitions;
  }

  Future<List<Map<String, dynamic>>> _operationsFromRouting(
    String orderId,
    Map<String, dynamic> order,
  ) async {
    final routingRevisionId = order['routing_revision_id']?.toString();
    if (routingRevisionId == null || routingRevisionId.isEmpty) return [];

    final rows = await service.list(
      'routing_operations',
      equals: {'routing_revision_id': routingRevisionId},
      orderBy: 'sequence_no',
    );
    final plannedQuantity = _number(order['planned_quantity']);
    return rows.map((row) {
      final setupMinutes = _number(row['setup_time_minutes']);
      final runMinutes = row['run_time_basis'] == 'per_unit'
          ? _number(row['run_time_value']) * plannedQuantity
          : _number(row['run_time_value']);
      return <String, dynamic>{
        'id': 'routing:${row['id']}',
        'production_order_id': orderId,
        'routing_operation_id': row['id'],
        'operation_code': row['operation_code'],
        'sequence_no': row['sequence_no'],
        'operation_type': row['operation_type'],
        'name': row['name'],
        'description': row['description'],
        'work_center_id': row['work_center_id'],
        'machine_id': row['preferred_machine_id'],
        'setup_time_minutes': setupMinutes,
        'run_time_minutes': runMinutes,
        'planned_quantity': plannedQuantity,
        'completed_quantity': 0,
        'rejected_quantity': 0,
        'status': 'planned',
        'instructions': row['instructions'],
        'notes': row['notes'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _materialsFromBom(
    String orderId,
    Map<String, dynamic> order,
  ) async {
    final bomRevisionId = order['bom_revision_id']?.toString();
    if (bomRevisionId == null || bomRevisionId.isEmpty) return [];

    final rows = await service.list(
      'bom_items',
      equals: {'bom_revision_id': bomRevisionId},
      orderBy: 'line_no',
    );
    final plannedQuantity = _number(order['planned_quantity']);
    return rows.map((row) {
      final quantity = _number(row['quantity']);
      final requiredQuantity = row['quantity_basis'] == 'fixed'
          ? quantity
          : quantity * plannedQuantity;
      final scrapPct = _number(row['scrap_pct']);
      return <String, dynamic>{
        'id': 'bom:${row['id']}',
        'production_order_id': orderId,
        'bom_item_id': row['id'],
        'line_no': row['line_no'],
        'component_type': row['component_type'],
        'material_product_id': row['component_product_id'],
        'material_product_revision_id': row['component_product_revision_id'],
        'uom_id': row['uom_id'],
        'required_quantity': requiredQuantity * (1 + scrapPct / 100),
        'issued_quantity': 0,
        'consumed_quantity': 0,
        'scrap_quantity': 0,
        'issue_method': row['issue_method'],
        'status': 'planned',
        'notes': row['notes'],
      };
    }).toList();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
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

  Future<Map<String, dynamic>> ensureOperationalSnapshot(String orderId) async {
    var order =
        await service.one('v_production_order_workspace', orderId) ??
        await service.one('production_orders', orderId);
    if (order == null) throw StateError('Orden de producción no encontrada.');
    final status = order['status']?.toString();
    if (status == 'draft' || status == 'planned' || status == 'ready') {
      await prepare(orderId);
      order =
          await service.one('v_production_order_workspace', orderId) ??
          await service.one('production_orders', orderId);
      if (order == null) throw StateError('Orden de producción no encontrada.');
    }

    var operations = await service.list(
      'production_order_operations',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    if (operations.isEmpty) {
      final routingRevisionId = order['routing_revision_id']?.toString();
      if (routingRevisionId == null || routingRevisionId.isEmpty) {
        throw StateError('La OP no tiene ruta de fabricación asignada.');
      }
      final routingOperations = await service.list(
        'routing_operations',
        equals: {'routing_revision_id': routingRevisionId},
        orderBy: 'sequence_no',
      );
      if (routingOperations.isEmpty) {
        throw StateError('La ruta de fabricación no tiene operaciones.');
      }
      final plannedQuantity = _number(order['planned_quantity']);
      final rows = routingOperations.map((row) {
        final setupMinutes = _number(row['setup_time_minutes']);
        return tenantValues({
          'production_order_id': orderId,
          'source_routing_operation_id': row['id'],
          'operation_code': row['operation_code'],
          'sequence_no': row['sequence_no'],
          'name': row['name'],
          'description': row['description'],
          'work_center_id': row['work_center_id'],
          'machine_id': row['preferred_machine_id'],
          'process_definition_id': row['process_definition_id'],
          'setup_time_minutes': setupMinutes,
          'run_time_basis': row['run_time_basis'],
          'run_time_value': row['run_time_value'],
          'run_time_formula': row['run_time_formula'],
          'queue_time_minutes': row['queue_time_minutes'] ?? 0,
          'move_time_minutes': row['move_time_minutes'] ?? 0,
          'expected_scrap_pct': row['expected_scrap_pct'] ?? 0,
          'expected_yield_pct': row['expected_yield_pct'] ?? 100,
          'requires_checklist': row['requires_checklist'] ?? false,
          'requires_quality': row['requires_quality'] ?? false,
          'external_service': row['external_service'] ?? false,
          'planned_quantity': plannedQuantity,
          'completed_quantity': 0,
          'rejected_quantity': 0,
          'status': 'ready',
          'instructions': row['instructions'],
          'notes': row['notes'],
        });
      }).toList();
      operations = await service.insertMany(
        'production_order_operations',
        rows,
      );
    }

    final materials = await service.list(
      'production_order_materials',
      equals: {'production_order_id': orderId},
      orderBy: 'line_no',
    );
    if (materials.isEmpty) {
      final bomRevisionId = order['bom_revision_id']?.toString();
      if (bomRevisionId == null || bomRevisionId.isEmpty) {
        throw StateError('La OP no tiene lista de materiales asignada.');
      }
      final bomItems = await service.list(
        'bom_items',
        equals: {'bom_revision_id': bomRevisionId},
        orderBy: 'line_no',
      );
      if (bomItems.isNotEmpty) {
        final plannedQuantity = _number(order['planned_quantity']);
        final rows = bomItems.map((row) {
          final quantity = _number(row['quantity']);
          final requiredQuantity = row['quantity_basis'] == 'fixed'
              ? quantity
              : quantity * plannedQuantity;
          final scrapPct = _number(row['scrap_pct']);
          return tenantValues({
            'production_order_id': orderId,
            'source_bom_item_id': row['id'],
            'line_no': row['line_no'],
            'component_type': row['component_type'],
            'material_product_id': row['component_product_id'],
            'material_product_revision_id':
                row['component_product_revision_id'],
            'uom_id': row['uom_id'],
            'quantity_basis': row['quantity_basis'],
            'quantity_per_basis': row['quantity'],
            'quantity_formula': row['quantity_formula'],
            'required_quantity': requiredQuantity * (1 + scrapPct / 100),
            'issued_quantity': 0,
            'consumed_quantity': 0,
            'returned_quantity': 0,
            'scrap_quantity': 0,
            'scrap_pct': scrapPct,
            'issue_method': row['issue_method'],
            'is_optional': row['is_optional'] ?? false,
            'is_phantom': row['is_phantom'] ?? false,
            'notes': row['notes'],
          });
        }).toList();
        await service.insertMany('production_order_materials', rows);
      }
    }

    return detail(orderId);
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
    try {
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
    } catch (e) {
      if (!_canFallbackTransitionOperation(e)) rethrow;
      return _transitionOperationWithDirectUpdate(
        operationId,
        newStatus,
        current: current,
        completedQuantity: completedQuantity,
        rejectedQuantity: rejectedQuantity,
        note: note,
      );
    }
    return await service.one('production_order_operations', operationId) ??
        <String, dynamic>{'id': operationId, 'status': newStatus};
  }

  bool _canFallbackTransitionOperation(Object error) {
    final text = error.toString();
    return text.contains('transition_production_operation') &&
        (text.contains('schema cache') ||
            text.contains('Could not find the function'));
  }

  Future<Map<String, dynamic>> _transitionOperationWithDirectUpdate(
    String operationId,
    String newStatus, {
    required Map<String, dynamic>? current,
    double? completedQuantity,
    double? rejectedQuantity,
    String? note,
  }) async {
    final row =
        current ??
        await service.one('production_order_operations', operationId);
    if (row == null) {
      throw StateError('Operación de producción no encontrada.');
    }
    final now = DateTime.now().toIso8601String();
    final values = <String, dynamic>{'status': newStatus, 'updated_at': now};
    if (newStatus == 'in_progress' && row['actual_start_at'] == null) {
      values['actual_start_at'] = now;
    }
    if (newStatus == 'completed') {
      values['actual_start_at'] = row['actual_start_at'] ?? now;
      values['actual_end_at'] = now;
      if (completedQuantity != null) {
        values['completed_quantity'] = completedQuantity;
      }
      if (rejectedQuantity != null) {
        values['rejected_quantity'] = rejectedQuantity;
      }
    }
    if (newStatus == 'ready') {
      values['actual_start_at'] = null;
      values['actual_end_at'] = null;
    }
    if (note != null && note.trim().isNotEmpty) {
      final existing = row['notes']?.toString().trim();
      values['notes'] = existing == null || existing.isEmpty
          ? note.trim()
          : '$existing\n${note.trim()}';
    }
    return service.update('production_order_operations', operationId, values);
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
