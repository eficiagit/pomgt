import 'base_repository.dart';

class MaterialRepository extends BaseRepository {
  MaterialRepository(super.service, super.client);

  Future<List<Map<String, dynamic>>> materials() {
    return listTenant('products', orderBy: 'name');
  }

  Future<List<Map<String, dynamic>>> materialTypes() {
    return listTenant('material_types', orderBy: 'sort_order');
  }

  Future<List<Map<String, dynamic>>> categories() {
    return listTenant('material_categories', orderBy: 'name').catchError((_) {
      return <Map<String, dynamic>>[];
    });
  }

  Future<List<Map<String, dynamic>>> attributes(String materialTypeId) {
    return listTenant(
      'material_attribute_definitions',
      filters: {'material_type_id': materialTypeId},
      orderBy: 'sort_order',
    );
  }

  Future<List<Map<String, dynamic>>> optionsFor(String attributeId) {
    return listTenant(
      'material_attribute_options',
      filters: {'attribute_definition_id': attributeId},
      orderBy: 'sort_order',
    );
  }

  Future<List<Map<String, dynamic>>> optionsForAttributes(
    Iterable<String> attributeIds,
  ) async {
    final ids = attributeIds.toSet();
    if (ids.isEmpty) return const [];
    final rows = await listTenant(
      'material_attribute_options',
      orderBy: 'sort_order',
    );
    return rows
        .where(
          (row) => ids.contains(row['attribute_definition_id']?.toString()),
        )
        .toList();
  }

  Future<Map<String, dynamic>> createMaterial({
    required Map<String, dynamic> material,
    required List<Map<String, dynamic>> attributeValues,
  }) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    final payload = Map<String, dynamic>.from(material)
      ..['organization_id'] = org;
    final result = await service.rpc(
      'create_material_with_revision',
      params: {'p_material': payload, 'p_attribute_values': attributeValues},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<String> createRevision({
    required String productId,
    required String? copyFromRevisionId,
  }) async {
    final result = await service.rpc(
      'create_material_revision',
      params: {
        'p_product_id': productId,
        'p_copy_from_revision_id': copyFromRevisionId,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> detail(String productId) async {
    final product = await service.one('products', productId);
    if (product == null) throw StateError('Material no encontrado.');
    final revisionRows = await listTenant(
      'product_revisions',
      filters: {'product_id': productId},
      orderBy: 'revision_no',
    );
    final activeRevision = revisionRows
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (row) => row?['status'] == 'active',
          orElse: () => revisionRows.isEmpty ? null : revisionRows.last,
        );
    final values = activeRevision == null
        ? const <Map<String, dynamic>>[]
        : await listTenant(
            'material_revision_attribute_values',
            filters: {'product_revision_id': activeRevision['id']},
          );
    final boms = await listTenant(
      'bom_items',
      filters: {'component_product_id': productId},
    );
    final documents = await listTenant(
      'document_links',
      filters: {'product_id': productId},
    );
    return {
      'product': product,
      'revisions': revisionRows,
      'activeRevision': activeRevision,
      'values': values,
      'bomItems': boms,
      'documents': documents,
    };
  }

  Future<void> upsertRevisionValues({
    required String revisionId,
    required List<Map<String, dynamic>> values,
  }) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    for (final value in values) {
      final id = value['id']?.toString();
      final payload = Map<String, dynamic>.from(value)
        ..['organization_id'] = org
        ..['product_revision_id'] = revisionId;
      if (id == null || id.isEmpty) {
        payload.remove('id');
        await service.insert('material_revision_attribute_values', payload);
      } else {
        await service.update('material_revision_attribute_values', id, payload);
      }
    }
  }
}
