import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/action_exception.dart';
import '../utils/operation_materials.dart';
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

  /// The floor uses paginated, tenant-scoped reads: no silent 500-row cutoff.
  Future<Map<String, dynamic>> floorSnapshot() async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    const tables = {
      'machines': 'machines',
      'work_centers': 'work_centers',
      'machine_types': 'machine_types',
      'machine_categories': 'machine_categories',
      'operations': 'production_order_operations',
      'orders': 'v_production_order_workspace',
      'products': 'products',
      'operators': 'operators',
      'order_operators': 'production_order_operators',
      'product_categories': 'product_categories',
      'material_categories': 'material_categories',
      'material_types': 'material_types',
      'product_types': 'product_types',
      'labor_roles': 'labor_roles',
    };
    final batches = await Future.wait<dynamic>([
      Future.wait(
        tables.entries.map(
          (entry) async => MapEntry(
            entry.key,
            await service.listAll(
              entry.value,
              equals: {'organization_id': org},
            ),
          ),
        ),
      ),
      service.listAll('units_of_measure'),
      _floorInventory(org),
    ]);
    final tableRows = Map<String, List<Map<String, dynamic>>>.fromEntries(
      batches[0] as List<MapEntry<String, List<Map<String, dynamic>>>>,
    );
    tableRows['operations'] = await _floorOperations(
      orders: tableRows['orders'] ?? const [],
      operations: tableRows['operations'] ?? const [],
    );
    return {
      ...tableRows,
      'units': batches[1],
      ...batches[2] as Map<String, dynamic>,
    };
  }

  Future<List<Map<String, dynamic>>> _floorOperations({
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> operations,
  }) async {
    final ordersWithSnapshot = operations
        .map((row) => row['production_order_id']?.toString())
        .whereType<String>()
        .toSet();
    final ordersNeedingRoute = orders.where((order) {
      final id = order['id']?.toString();
      final routeId = order['routing_revision_id']?.toString();
      return id != null &&
          !ordersWithSnapshot.contains(id) &&
          routeId != null &&
          routeId.isNotEmpty;
    }).toList();
    final routingIds = ordersNeedingRoute
        .map((order) => order['routing_revision_id'].toString())
        .toSet();
    // Orders are already tenant-scoped. Their routing revision IDs can point
    // to category-shared routings whose operation rows have no organization ID.
    final routeSteps = await service.listIn(
      'routing_operations',
      'routing_revision_id',
      routingIds,
      orderBy: 'sequence_no',
    );
    final stepsByRouting = <String, List<Map<String, dynamic>>>{};
    for (final step in routeSteps) {
      final id = step['routing_revision_id']?.toString();
      if (id != null) stepsByRouting.putIfAbsent(id, () => []).add(step);
    }

    final inferred = <Map<String, dynamic>>[];
    for (final order in ordersNeedingRoute) {
      final orderId = order['id'].toString();
      final steps =
          stepsByRouting[order['routing_revision_id'].toString()] ??
          const <Map<String, dynamic>>[];
      final orderStatus = order['status']?.toString();
      for (var index = 0; index < steps.length; index++) {
        final step = steps[index];
        final terminal = orderStatus == 'completed'
            ? 'completed'
            : orderStatus == 'cancelled'
            ? 'cancelled'
            : null;
        final stepStatus =
            terminal ??
            switch (orderStatus) {
              'on_hold' when index == 0 => 'on_hold',
              _ => 'ready',
            };
        inferred.add({
          'id': 'routing:${step['id']}:$orderId',
          'production_order_id': orderId,
          'routing_operation_id': step['id'],
          'source_routing_operation_id': step['id'],
          'operation_type': step['operation_type'],
          'operation_code': step['operation_code'],
          'sequence_no': step['sequence_no'],
          'name': step['name'],
          'description': step['description'],
          'work_center_id': step['work_center_id'],
          'machine_id': step['preferred_machine_id'],
          'setup_time_minutes': step['setup_time_minutes'],
          'planned_quantity': order['planned_quantity'],
          'completed_quantity': 0,
          'rejected_quantity': 0,
          'status': stepStatus,
          'snapshot_inferred': true,
        });
      }
    }
    return [...await _normalizeOperationRows(operations), ...inferred];
  }

  Future<Map<String, dynamic>> _floorInventory(String org) async {
    const tables = [
      'floor_zones',
      'warehouses',
      'inventory_stock',
      'inventory_movements',
    ];
    try {
      final entries = await Future.wait(
        tables.map(
          (table) async => MapEntry(
            table,
            await service.listAll(table, equals: {'organization_id': org}),
          ),
        ),
      );
      return {...Map.fromEntries(entries), 'inventory_available': true};
    } on PostgrestException catch (error) {
      if (!['42P01', 'PGRST205'].contains(error.code)) rethrow;
      return {
        'inventory_available': false,
        'inventory_error': 'Las áreas y el inventario requieren la actualización de la base de datos.',
      };
    }
  }

  String get _floorOrganization {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    return org;
  }

  Future<Map<String, dynamic>> floorProductDetail(String id) async {
    final product = await service.one('products', id);
    if (product == null || product['organization_id'] != _floorOrganization) {
      throw StateError('Producto no encontrado en esta organización.');
    }
    final tables = {
      'revisions': 'product_revisions',
      'boms': 'boms',
      'routings': 'routings',
      'customers': 'customer_products',
      'documents': 'document_links',
    };
    final entries = await Future.wait(
      tables.entries.map(
        (e) async => MapEntry(
          e.key,
          await service.listAll(
            e.value,
            equals: {'organization_id': _floorOrganization, 'product_id': id},
          ),
        ),
      ),
    );
    final result = <String, dynamic>{...Map.fromEntries(entries)};
    // Category routings are shared in this app; they need not have product_id.
    if (product['category_id'] != null) {
      final shared = await service.listAll(
        'routings',
        equals: {
          'organization_id': _floorOrganization,
          'category_id': product['category_id'],
        },
      );
      result['routings'] = {
        for (final route in result['routings'] as List<Map<String, dynamic>>)
          '${route['id']}': route,
        for (final route in shared)
          if (route['product_id'] == null || route['product_id'] == id)
            '${route['id']}': route,
      }.values.toList();
    }
    final revisions = (result['revisions'] as List<Map<String, dynamic>>)
        .map((r) => '${r['id']}')
        .toList();
    final bomIds = (result['boms'] as List<Map<String, dynamic>>)
        .map((r) => '${r['id']}')
        .toList();
    final routingIds = (result['routings'] as List<Map<String, dynamic>>)
        .map((r) => '${r['id']}')
        .toList();
    final related = await Future.wait([
      _floorRelated(
        'material_revision_attribute_values',
        'product_revision_id',
        revisions,
      ),
      _floorRelated('bom_revisions', 'bom_id', bomIds),
      _floorRelated('routing_revisions', 'routing_id', routingIds),
    ]);
    result['attributes'] = related[0];
    result['bom_revisions'] = related[1];
    result['routing_revisions'] = related[2];
    final lines = await Future.wait([
      _floorRelated(
        'bom_items',
        'bom_revision_id',
        related[1].map((r) => '${r['id']}').toList(),
      ),
      _floorRelated(
        'routing_operations',
        'routing_revision_id',
        related[2].map((r) => '${r['id']}').toList(),
      ),
      _floorRelated(
        'material_attribute_definitions',
        'id',
        related[0]
            .map((r) => '${r['attribute_definition_id']}')
            .toSet()
            .toList(),
      ),
    ]);
    result['bom_items'] = lines[0];
    result['routing_operations'] = lines[1];
    result['attribute_definitions'] = lines[2];
    return result;
  }

  Future<List<Map<String, dynamic>>> _floorRelated(
    String table,
    String column,
    List<String> ids,
  ) async {
    final batches = await Future.wait([
      for (var i = 0; i < ids.length; i += 100)
        service.listAll(
          table,
          within: {
            column: ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100),
          },
        ),
    ]);
    return batches.expand((rows) => rows).toList();
  }

  Future<void> updateMachinePosition(
    String machineId,
    double x,
    double y,
  ) async {
    if (!x.isFinite || !y.isFinite || x < 0 || y < 0) {
      throw ArgumentError('La posición debe estar dentro del plano.');
    }
    await service.updateWhere(
      'machines',
      {'id': machineId, 'organization_id': _floorOrganization},
      {'floor_pos_x': x, 'floor_pos_y': y},
    );
  }

  Future<void> saveFloorZone(Map<String, dynamic> values, {String? id}) async {
    if (id == null) {
      await service.insert('floor_zones', tenantValues(values));
    } else {
      await service.updateWhere('floor_zones', {
        'id': id,
        'organization_id': _floorOrganization,
      }, values);
    }
  }

  Future<void> deleteFloorZone(String id) => service.deleteWhere(
    'floor_zones',
    {'id': id, 'organization_id': _floorOrganization},
  );

  Future<void> saveFloorWarehouse(
    Map<String, dynamic> values, {
    String? id,
  }) async {
    if (id == null) {
      await service.insert('warehouses', tenantValues(values));
    } else {
      await service.updateWhere('warehouses', {
        'id': id,
        'organization_id': _floorOrganization,
      }, values);
    }
  }

  Future<void> recordFloorInventoryMovement({
    required String warehouseId,
    required String productId,
    required String movementType,
    required double quantity,
    required String requestId,
    String? notes,
    String? materialId,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('La cantidad debe ser mayor que cero.');
    }
    await service.rpc(
      'record_floor_inventory_movement',
      params: {
        'p_warehouse_id': warehouseId,
        'p_product_id': productId,
        'p_movement_type': movementType,
        'p_quantity': quantity,
        'p_request_id': requestId,
        'p_notes': notes,
        'p_material_id': materialId,
      },
    );
  }

  Future<Map<String, dynamic>> detail(String orderId) =>
      _loadOrderDetail(orderId);

  Future<Map<String, dynamic>> floorOrderDetail(String orderId) =>
      _loadOrderDetail(orderId, paginated: true);

  Future<Map<String, dynamic>> _loadOrderDetail(
    String orderId, {
    bool paginated = false,
  }) async {
    Future<List<Map<String, dynamic>>> readRows(
      String table, {
      Map<String, dynamic> equals = const {},
      String? orderBy,
      bool ascending = true,
      int limit = 500,
    }) async {
      if (!paginated) {
        return service.list(
          table,
          equals: equals,
          orderBy: orderBy,
          ascending: ascending,
          limit: limit,
        );
      }
      final rows = await service.listAll(table, equals: equals);
      if (orderBy != null) {
        rows.sort((a, b) {
          final av = a[orderBy], bv = b[orderBy];
          final comparison = av is num && bv is num
              ? av.compareTo(bv)
              : '${av ?? ''}'.compareTo('${bv ?? ''}');
          return ascending ? comparison : -comparison;
        });
      }
      return rows;
    }

    var order = await service.one('v_production_order_workspace', orderId);
    if (order == null) throw StateError('Orden de producción no encontrada.');
    order = await _resolveManufacturingRevisions(order);

    // Everything kicked off below only depends on orderId or a scalar
    // already on `order` - starting every request up front (instead of
    // awaiting one at a time) turns what used to be a long chain of
    // sequential round trips into a single parallel batch, which is most of
    // what made this screen slow to open.
    final operationsFuture = readRows(
      'production_order_operations',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final materialsFuture = readRows(
      'production_order_materials',
      equals: {'production_order_id': orderId},
      orderBy: 'line_no',
    );
    final checklistFuture = readRows(
      'production_order_checklist_items',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final qualityFuture = readRows(
      'production_order_quality_checks',
      equals: {'production_order_id': orderId},
      orderBy: 'sequence_no',
    );
    final parametersFuture = readRows(
      'production_order_machine_parameters',
      equals: {'production_order_id': orderId},
      orderBy: 'created_at',
    );
    final eventsFuture = readRows(
      'production_order_events',
      equals: {'production_order_id': orderId},
      orderBy: 'occurred_at',
      ascending: false,
    );
    final costsFuture = readRows(
      'production_order_costs',
      equals: {'production_order_id': orderId},
      limit: 1,
    );
    final allocationsFuture = readRows(
      'production_order_allocations',
      equals: {'production_order_id': orderId},
      orderBy: 'created_at',
    );
    final dependenciesFuture = readRows(
      'production_order_operation_dependencies',
      equals: {'production_order_id': orderId},
    );
    final movementsFuture = readRows(
      'production_order_material_movements',
      equals: {'production_order_id': orderId},
      orderBy: 'occurred_at',
      ascending: false,
    );
    final productFuture = service.one(
      'products',
      order['product_id'].toString(),
    );
    final uomFuture = service.one(
      'units_of_measure',
      order['uom_id'].toString(),
    );
    final customerOrderFuture = order['customer_order_id'] == null
        ? Future<Map<String, dynamic>?>.value(null)
        : service.one('customer_orders', order['customer_order_id'].toString());
    final customerFuture = order['customer_id'] == null
        ? Future<Map<String, dynamic>?>.value(null)
        : service.one('customers', order['customer_id'].toString());

    var operations = await operationsFuture;
    var materials = await materialsFuture;
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

    final checklist = await checklistFuture;
    final quality = await qualityFuture;
    final parameters = await parametersFuture;
    final events = await eventsFuture;
    final costs = await costsFuture;
    final allocations = await allocationsFuture;
    final dependencies = await dependenciesFuture;
    dependencies.sort((a, b) {
      final operation = (a['operation_id']?.toString() ?? '').compareTo(
        b['operation_id']?.toString() ?? '',
      );
      if (operation != 0) return operation;
      return (a['predecessor_operation_id']?.toString() ?? '').compareTo(
        b['predecessor_operation_id']?.toString() ?? '',
      );
    });
    final movements = await movementsFuture;
    final product = await productFuture;
    final uom = await uomFuture;
    final customerOrder = await customerOrderFuture;
    final customer = await customerFuture;

    // Resolve every reference row (work centers, machines, products, units)
    // with one batched "id in (...)" query per table, instead of one round
    // trip per distinct id referenced by the operations/materials/quality
    // checks above.
    final workCenterIds = operations
        .map((op) => op['work_center_id']?.toString())
        .whereType<String>()
        .toSet();
    final machineIds = operations
        .map((op) => op['machine_id']?.toString())
        .whereType<String>()
        .toSet();
    final materialProductIds = materials
        .map((m) => m['material_product_id']?.toString())
        .whereType<String>()
        .toSet();
    final uomIds = {
      ...materials.map((m) => m['uom_id']?.toString()).whereType<String>(),
      ...quality.map((q) => q['uom_id']?.toString()).whereType<String>(),
    };

    final workCentersFuture = service.listIn(
      'work_centers',
      'id',
      workCenterIds,
    );
    final machinesFuture = service.listIn('machines', 'id', machineIds);
    final materialProductsFuture = service.listIn(
      'products',
      'id',
      materialProductIds,
    );
    final materialUomsFuture = service.listIn('units_of_measure', 'id', uomIds);
    final materialRevisionsFuture = _materialRevisions(materials);

    final workCenters = {
      for (final row in await workCentersFuture) row['id'].toString(): row,
    };
    final machines = {
      for (final row in await machinesFuture) row['id'].toString(): row,
    };
    final products = <String, Map<String, dynamic>>{
      for (final row in await materialProductsFuture) row['id'].toString(): row,
    };
    if (product != null) products[product['id'].toString()] = product;
    final units = <String, Map<String, dynamic>>{
      for (final row in await materialUomsFuture) row['id'].toString(): row,
    };
    if (uom != null) units[uom['id'].toString()] = uom;

    for (final entry in routingOperationMaterials.entries.toList()) {
      routingOperationMaterials[entry.key] = resolveOperationMaterialTypes(
        entry.value,
        materials,
        products,
      );
    }
    final materialRevisions = await materialRevisionsFuture;
    final materialAttributeValues = await _materialAttributeValues(
      materialRevisions,
    );
    final materialAttributeDefinitions = await _materialAttributeDefinitions(
      materialAttributeValues,
    );

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
      // A type selects from the order's BOM; it is never a direct material.
      if (link['material_type_id'] != null) continue;
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
        'status': 'ready',
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
    final missingSourceIds = operations
        .where((row) => row['operation_type'] == null)
        .map(
          (row) =>
              row['source_routing_operation_id']?.toString() ??
              row['routing_operation_id']?.toString(),
        )
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final routingOperations = {
      for (final row in await service.listIn(
        'routing_operations',
        'id',
        missingSourceIds,
      ))
        row['id'].toString(): row,
    };
    return operations.map((row) {
      final copy = Map<String, dynamic>.from(row);
      copy['routing_operation_id'] ??= copy['source_routing_operation_id'];
      if (copy['operation_type'] == null) {
        final sourceId =
            copy['source_routing_operation_id']?.toString() ??
            copy['routing_operation_id']?.toString();
        copy['operation_type'] =
            routingOperations[sourceId]?['operation_type']?.toString() ??
            'activity';
      }
      return copy;
    }).toList();
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
    final routingOperationIds = operations
        .map((op) => op['routing_operation_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    // A single "in (...)" query, ordered by consumption_point, groups back
    // into per-operation lists that keep that same relative order.
    final rows = await service.listIn(
      'routing_operation_materials',
      'routing_operation_id',
      routingOperationIds,
      orderBy: 'consumption_point',
    );
    final byOperation = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final id = row['routing_operation_id']?.toString();
      if (id == null) continue;
      byOperation.putIfAbsent(id, () => []).add(row);
    }
    return byOperation;
  }

  Future<Map<String, Map<String, dynamic>>> _materialRevisions(
    List<Map<String, dynamic>> materials,
  ) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final materialIds = materials
        .map((row) => row['material_product_id']?.toString())
        .whereType<String>()
        .toSet();
    final rows = await service.listIn(
      'product_revisions',
      'product_id',
      materialIds,
      equals: {'organization_id': org},
      orderBy: 'revision_no',
    );
    final byMaterial = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final id = row['product_id']?.toString();
      if (id == null) continue;
      byMaterial.putIfAbsent(id, () => []).add(row);
    }
    final revisions = <String, Map<String, dynamic>>{};
    for (final entry in byMaterial.entries) {
      final active = entry.value.cast<Map<String, dynamic>?>().firstWhere(
        (row) => row?['status'] == 'active',
        orElse: () => entry.value.last,
      );
      if (active != null) {
        revisions[entry.key] = Map<String, dynamic>.from(active);
      }
    }
    return revisions;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _materialAttributeValues(
    Map<String, Map<String, dynamic>> materialRevisions,
  ) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final revisionIds = materialRevisions.values
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final rows = await service.listIn(
      'material_revision_attribute_values',
      'product_revision_id',
      revisionIds,
      equals: {'organization_id': org},
    );
    final byRevision = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final id = row['product_revision_id']?.toString();
      if (id == null) continue;
      byRevision.putIfAbsent(id, () => []).add(row);
    }
    return {
      for (final entry in materialRevisions.entries)
        if ((entry.value['id']?.toString() ?? '').isNotEmpty)
          entry.key: byRevision[entry.value['id'].toString()] ?? const [],
    };
  }

  Future<Map<String, Map<String, dynamic>>> _materialAttributeDefinitions(
    Map<String, List<Map<String, dynamic>>> valuesByMaterial,
  ) async {
    final definitionIds = valuesByMaterial.values
        .expand((rows) => rows)
        .map((row) => row['attribute_definition_id']?.toString())
        .whereType<String>()
        .toSet();
    final rows = await service.listIn(
      'material_attribute_definitions',
      'id',
      definitionIds,
    );
    final definitions = {for (final row in rows) row['id'].toString(): row};
    return definitions;
  }

  /// Orders created before linking a route/BOM can have no revision assigned.
  /// Preview their current active definitions without modifying the order.
  Future<Map<String, dynamic>> _resolveManufacturingRevisions(
    Map<String, dynamic> order,
  ) async {
    bool missing(String field) =>
        (order[field]?.toString().trim() ?? '').isEmpty;
    if (!missing('routing_revision_id') && !missing('bom_revision_id')) {
      return order;
    }
    final productId = order['product_id']?.toString();
    final organization = order['organization_id'] ?? organizationId;
    if (productId == null || organization == null) return order;
    final resolved = Map<String, dynamic>.from(order);
    if (missing('bom_revision_id')) {
      resolved['bom_revision_id'] = await _activeManufacturingRevision(
        'boms',
        'bom_revisions',
        'bom_id',
        {'organization_id': organization, 'product_id': productId},
      );
    }
    if (missing('routing_revision_id')) {
      var revisionId = await _activeManufacturingRevision(
        'routings',
        'routing_revisions',
        'routing_id',
        {'organization_id': organization, 'product_id': productId},
      );
      if (revisionId == null) {
        final product = await service.one('products', productId);
        final categoryId = product?['category_id']?.toString();
        if (categoryId != null && categoryId.isNotEmpty) {
          revisionId = await _activeManufacturingRevision(
            'routings',
            'routing_revisions',
            'routing_id',
            {'organization_id': organization, 'category_id': categoryId},
          );
        }
      }
      resolved['routing_revision_id'] = revisionId;
    }
    return resolved;
  }

  Future<String?> _activeManufacturingRevision(
    String table,
    String revisionTable,
    String parentField,
    Map<String, dynamic> filters,
  ) async {
    final heads = await service.list(
      table,
      equals: {...filters, 'is_active': true},
      orderBy: 'created_at',
      ascending: false,
    );
    heads.sort((a, b) {
      final preferred = (b['is_default'] == true ? 1 : 0).compareTo(
        a['is_default'] == true ? 1 : 0,
      );
      if (preferred != 0) return preferred;
      final newest = (b['created_at']?.toString() ?? '').compareTo(
        a['created_at']?.toString() ?? '',
      );
      return newest != 0
          ? newest
          : a['id'].toString().compareTo(b['id'].toString());
    });
    for (final head in heads) {
      final revisions = await service.list(
        revisionTable,
        equals: {parentField: head['id'], 'status': 'active'},
        orderBy: 'created_at',
        ascending: false,
      );
      if (revisions.isNotEmpty) return revisions.first['id']?.toString();
    }
    return null;
  }

  Future<Map<String, dynamic>> _assignMissingManufacturingRevisions(
    Map<String, dynamic> order,
  ) async {
    final resolved = await _resolveManufacturingRevisions(order);
    final changes = <String, dynamic>{
      for (final field in ['bom_revision_id', 'routing_revision_id'])
        if (resolved[field] != null && resolved[field] != order[field])
          field: resolved[field],
    };
    if (changes.isNotEmpty) {
      await service.update(
        'production_orders',
        order['id'].toString(),
        changes,
      );
    }
    return resolved;
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
        'status': 'ready',
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
        'status': 'ready',
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
    final order = await service.one('production_orders', orderId);
    if (order == null) throw StateError('Orden de producción no encontrada.');
    if (!['draft', 'planned', 'ready'].contains(order['status']?.toString())) {
      throw StateError('La OP no se puede preparar desde su estado actual.');
    }
    await _assignMissingManufacturingRevisions(order);
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

    order = await _assignMissingManufacturingRevisions(order);
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
        throw StateError('La OP no tiene estructura de fabricación asignada.');
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

  Future<void> deleteOrder(String orderId) async {
    await service.rpc(
      'delete_production_order',
      params: {'p_order_id': orderId},
    );
  }

  Future<Map<String, dynamic>> transitionOrder(
    String orderId,
    String newStatus, {
    String? note,
    double? completedQuantity,
  }) async {
    Map<String, dynamic>? operationalSnapshot;
    // Ensure route operations have persisted UUIDs before the order enters
    // production; detail() can otherwise synthesize temporary `routing:` IDs.
    if (newStatus == 'in_progress') {
      operationalSnapshot = await ensureOperationalSnapshot(orderId);
    }
    final current =
        await service.one('v_production_order_workspace', orderId) ??
        await service.one('production_orders', orderId);
    if (current?['status']?.toString() == newStatus) {
      return current ?? <String, dynamic>{'id': orderId, 'status': newStatus};
    }
    if (newStatus == 'in_progress') {
      final operations =
          (operationalSnapshot?['operations'] as List? ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort((a, b) => _compareOperationSequence(a, b));
      final firstPending = operations.cast<Map<String, dynamic>?>().firstWhere(
        (row) =>
            row != null &&
            !['completed', 'skipped', 'cancelled'].contains(row['status']),
        orElse: () => null,
      );
      final machineId = firstPending?['machine_id']?.toString();
      if (machineId != null && machineId.isNotEmpty) {
        await _assertMachineAvailable(machineId, orderId);
      }
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
    if (newStatus == 'in_progress') {
      final machineId = current?['machine_id']?.toString();
      final orderId = current?['production_order_id']?.toString();
      if (machineId != null && machineId.isNotEmpty && orderId != null) {
        await _assertMachineAvailable(machineId, orderId);
      }
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

  Future<void> _assertMachineAvailable(String machineId, String orderId) async {
    final assigned = await service.list(
      'production_order_operations',
      equals: {'machine_id': machineId},
      orderBy: 'sequence_no',
    );
    final candidates = assigned
        .where(
          (operation) =>
              operation['production_order_id']?.toString() != orderId,
        )
        .toList();
    final otherOrderIds = candidates
        .map((operation) => operation['production_order_id']?.toString())
        .whereType<String>()
        .toSet();
    if (otherOrderIds.isEmpty) return;

    final orders = await service.listIn(
      'production_orders',
      'id',
      otherOrderIds,
      select: 'id,op_number,status',
    );
    final ordersById = {for (final order in orders) '${order['id']}': order};
    final relevantOrderIds = orders
        .where(
          (order) =>
              ['ready', 'in_progress'].contains(order['status']?.toString()),
        )
        .map((order) => '${order['id']}')
        .toSet();
    final relevantOperations = await service.listIn(
      'production_order_operations',
      'production_order_id',
      relevantOrderIds,
      orderBy: 'sequence_no',
    );
    final operationsByOrder = <String, List<Map<String, dynamic>>>{};
    for (final operation in relevantOperations) {
      (operationsByOrder['${operation['production_order_id']}'] ??= []).add(
        operation,
      );
    }
    for (final operation in candidates) {
      final otherOrderId = operation['production_order_id']?.toString();
      final otherOrder = otherOrderId == null ? null : ordersById[otherOrderId];
      if (otherOrder == null ||
          ![
            'ready',
            'in_progress',
          ].contains(otherOrder['status']?.toString())) {
        continue;
      }
      final isExplicitlyRunning =
          operation['status']?.toString() == 'in_progress';
      final otherSteps = operationsByOrder[otherOrderId] ?? const [];
      final currentStep = otherSteps.cast<Map<String, dynamic>?>().firstWhere(
        (step) =>
            step != null &&
            !['completed', 'skipped', 'cancelled'].contains(step['status']),
        orElse: () => null,
      );
      final isOrderCurrentMachine =
          otherOrder['status']?.toString() == 'in_progress' &&
          currentStep?['id']?.toString() == operation['id']?.toString();
      if (!isExplicitlyRunning && !isOrderCurrentMachine) continue;

      final machine = await service.one('machines', machineId, select: 'name');
      final machineName = machine?['name']?.toString() ?? 'seleccionada';
      final orderNumber = otherOrder['op_number']?.toString() ?? 'en ejecución';
      throw ActionException(
        'No se puede iniciar esta operación: la máquina $machineName ya está asignada a la orden $orderNumber. Libera esa máquina antes de continuar.',
      );
    }
  }

  int _compareOperationSequence(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftSequence = _number(left['sequence_no']);
    final rightSequence = _number(right['sequence_no']);
    final bySequence = leftSequence.compareTo(rightSequence);
    return bySequence != 0
        ? bySequence
        : '${left['id']}'.compareTo('${right['id']}');
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
