import 'base_repository.dart';

class RoutingRepository extends BaseRepository {
  RoutingRepository(super.service, super.client, {super.runtimeData});

  /// Types actually used by BOM components of products in this category.
  Future<List<Map<String, dynamic>>> categoryMaterialTypes(
    String categoryId,
  ) async {
    final products = await listTenant(
      'products',
      filters: {'category_id': categoryId},
    );
    final typeIds = <String>{};
    final components = <String, Map<String, dynamic>?>{};
    for (final product in products) {
      final boms = await listTenant(
        'boms',
        filters: {'product_id': product['id'], 'is_active': true},
      );
      for (final bom in boms) {
        final revisions = await service.list(
          'bom_revisions',
          equals: {'bom_id': bom['id']},
          orderBy: 'created_at',
          ascending: false,
        );
        final active = revisions
            .where((row) => row['status'] == 'active')
            .toList();
        final selected = active.isNotEmpty
            ? active
            : revisions.where((row) => row['status'] == 'draft').take(1);
        for (final revision in selected) {
          final items = await service.list(
            'bom_items',
            equals: {'bom_revision_id': revision['id']},
          );
          for (final item in items) {
            final id = item['component_product_id']?.toString();
            if (id == null) continue;
            if (!components.containsKey(id)) {
              components[id] = await service.one('products', id);
            }
            final typeId = components[id]?['material_type_id']?.toString();
            if (typeId != null) typeIds.add(typeId);
          }
        }
      }
    }
    final types = await listTenant('material_types', orderBy: 'name');
    return types
        .where((row) => typeIds.contains(row['id']?.toString()))
        .toList();
  }

  Future<Map<String, dynamic>> detail(String routingId) async {
    final routing = await service.one('routings', routingId);
    if (routing == null) throw StateError('Ruta de fabricación no encontrada.');
    final revisions = await service.list(
      'routing_revisions',
      equals: {'routing_id': routingId},
      orderBy: 'created_at',
      ascending: false,
    );
    final operations = <String, List<Map<String, dynamic>>>{};
    for (final rev in revisions) {
      final revId = rev['id'] as String;
      operations[revId] = await service.list(
        'routing_operations',
        equals: {'routing_revision_id': revId},
        orderBy: 'sequence_no',
      );
    }
    return {
      'routing': routing,
      'revisions': revisions,
      'operations': operations,
    };
  }

  Future<Map<String, dynamic>> operationBundle(String operationId) async {
    final operation = await service.one('routing_operations', operationId);
    if (operation == null) throw StateError('Operación no encontrada.');
    final rows = await Future.wait([
      service.list(
        'routing_operation_dependencies',
        equals: {'operation_id': operationId},
      ),
      service.list(
        'routing_operation_materials',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'routing_operation_labor_requirements',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'routing_operation_machine_parameters',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'routing_operation_checklists',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'routing_operation_quality_checks',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'routing_operation_cost_components',
        equals: {'routing_operation_id': operationId},
      ),
      service.list(
        'document_links',
        equals: {'routing_operation_id': operationId},
      ),
    ]);
    return {
      'operation': operation,
      'dependencies': rows[0],
      'materials': rows[1],
      'labor': rows[2],
      'parameters': rows[3],
      'checklists': rows[4],
      'quality': rows[5],
      'costs': rows[6],
      'documents': rows[7],
    };
  }

  Future<void> deleteRouting(String routingId) async {
    await service.rpc('delete_routing', params: {'p_routing_id': routingId});
    runtimeData?.tablesChanged(['routings', 'routing_revisions']);
  }

  /// Creates a routing header scoped to either one product or a whole
  /// category (exactly one of [productId]/[categoryId] must be set, same
  /// mutual exclusivity the `routings` table itself enforces) plus an
  /// initial revision, defaulting to `active` so it's immediately
  /// releasable/preparable — mirrors `BomRepository._createWithDirectInserts`
  /// (same cleanup-on-failure, since `routings` has a partial unique index
  /// allowing only one `is_default && is_active` row per product/category).
  Future<String> createWithInitialRevision({
    String? productId,
    String? categoryId,
    required String routingCode,
    required String name,
    String? description,
    bool isDefault = true,
    String revisionCode = 'V.01',
    String revisionStatus = 'active',
  }) async {
    assert(
      (productId == null) != (categoryId == null),
      'Exactly one of productId or categoryId must be set.',
    );
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    if (isDefault) {
      if (productId != null) {
        await service.db
            .from('routings')
            .update({
              'is_default': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('organization_id', org)
            .eq('product_id', productId)
            .eq('is_default', true);
      } else {
        await service.db
            .from('routings')
            .update({
              'is_default': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('organization_id', org)
            .eq('category_id', categoryId!)
            .eq('is_default', true);
      }
    }
    final routing = await service.insert('routings', {
      'organization_id': org,
      'product_id': productId,
      'category_id': categoryId,
      'routing_code': routingCode.trim(),
      'name': name.trim(),
      'description': description?.trim(),
      'is_default': isDefault,
      'is_active': true,
    });
    final routingId = routing['id']?.toString();
    if (routingId == null) {
      throw StateError('No fue posible crear la ruta de fabricación.');
    }
    try {
      await service.insert('routing_revisions', {
        'organization_id': org,
        'routing_id': routingId,
        'revision_code': revisionCode.trim(),
        'status': revisionStatus.trim().isEmpty
            ? 'draft'
            : revisionStatus.trim(),
      });
    } catch (_) {
      await service.delete('routings', routingId);
      rethrow;
    }
    runtimeData?.tablesChanged(['routings', 'routing_revisions']);
    return routingId;
  }
}

/// Returns the subset of [productIds] that do not resolve to an active
/// manufacturing routing — neither one of their own nor their category's
/// default. Mirrors the category-fallback shape `prepare_production_order`
/// uses server-side, but strictly requires an `active`-status revision
/// (never just the newest one), matching `productIdsMissingActiveBom`'s own
/// strictness for a consistent UX between the two gates.
Set<String> productIdsMissingActiveRouting(
  Iterable<String> productIds, {
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> routings,
  required List<Map<String, dynamic>> routingRevisions,
}) {
  final revisionsByRouting = <String, List<Map<String, dynamic>>>{};
  for (final rev in routingRevisions) {
    final routingId = rev['routing_id']?.toString();
    if (routingId != null) {
      revisionsByRouting.putIfAbsent(routingId, () => []).add(rev);
    }
  }
  bool hasActiveRevision(String routingId) =>
      (revisionsByRouting[routingId] ?? const []).any(
        (rev) => rev['status']?.toString() == 'active',
      );

  final productsWithActiveRouting = <String>{};
  final categoriesWithActiveRouting = <String>{};
  for (final routing in routings) {
    if (routing['is_active'] != true) continue;
    final routingId = routing['id']?.toString();
    if (routingId == null || !hasActiveRevision(routingId)) continue;
    final productId = routing['product_id']?.toString();
    final categoryId = routing['category_id']?.toString();
    if (productId != null) productsWithActiveRouting.add(productId);
    if (categoryId != null) categoriesWithActiveRouting.add(categoryId);
  }

  final categoryByProduct = <String, String?>{
    for (final p in products)
      if (p['id'] != null) p['id'].toString(): p['category_id']?.toString(),
  };

  return {
    for (final id in productIds)
      if (!productsWithActiveRouting.contains(id) &&
          !(categoryByProduct[id] != null &&
              categoriesWithActiveRouting.contains(categoryByProduct[id])))
        id,
  };
}
