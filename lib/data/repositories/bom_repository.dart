import 'base_repository.dart';

class BomRepository extends BaseRepository {
  BomRepository(super.service, super.client);

  Future<String> createWithInitialRevision({
    required String productId,
    required String bomCode,
    required String name,
    String? description,
    bool isDefault = false,
    String revisionCode = 'Rev. 01',
    double outputQuantity = 1,
    String? outputUomId,
    String revisionStatus = 'draft',
  }) async {
    final params = {
      'p_product_id': productId,
      'p_bom_code': bomCode,
      'p_name': name,
      'p_description': description,
      'p_is_default': isDefault,
      'p_revision_code': revisionCode,
      'p_output_quantity': outputQuantity,
      'p_output_uom_id': outputUomId,
      'p_revision_status': revisionStatus,
    };
    dynamic result;
    try {
      result = await service.rpc(
        'create_bom_with_initial_revision',
        params: params,
      );
    } catch (error) {
      if (!_canFallbackCreate(error)) rethrow;
      result = await _createWithDirectInserts(
        productId: productId,
        bomCode: bomCode,
        name: name,
        description: description,
        isDefault: isDefault,
        revisionCode: revisionCode,
        outputQuantity: outputQuantity,
        outputUomId: outputUomId,
        revisionStatus: revisionStatus,
      );
    }
    if (result == null) {
      throw StateError('No fue posible crear la estructura de fabricación.');
    }
    return result.toString();
  }

  bool _canFallbackCreate(Object error) {
    final text = error.toString();
    final missingRpc =
        text.contains('create_bom_with_initial_revision') &&
        (text.contains('schema cache') ||
            text.contains('Could not find the function'));
    final staleRpc =
        text.contains('bom_status') &&
        text.contains('expression is of type text');
    return missingRpc || staleRpc;
  }

  Future<String> _createWithDirectInserts({
    required String productId,
    required String bomCode,
    required String name,
    String? description,
    required bool isDefault,
    required String revisionCode,
    required double outputQuantity,
    String? outputUomId,
    required String revisionStatus,
  }) async {
    final org = organizationId;
    if (org == null) throw StateError('No hay una organización seleccionada.');
    if (isDefault) {
      await service.db
          .from('boms')
          .update({
            'is_default': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('organization_id', org)
          .eq('product_id', productId)
          .eq('is_default', true);
    }
    final bom = await service.insert('boms', {
      'organization_id': org,
      'product_id': productId,
      'bom_code': bomCode.trim(),
      'name': name.trim(),
      'description': description?.trim(),
      'is_default': isDefault,
      'is_active': true,
    });
    final bomId = bom['id']?.toString();
    if (bomId == null) {
      throw StateError('No fue posible crear la estructura de fabricación.');
    }
    try {
      await service.insert('bom_revisions', {
        'organization_id': org,
        'bom_id': bomId,
        'revision_code': revisionCode.trim(),
        'status': revisionStatus.trim().isEmpty
            ? 'draft'
            : revisionStatus.trim(),
        'output_quantity': outputQuantity,
        'output_uom_id': outputUomId,
        'expected_scrap_pct': 0,
        'expected_yield_pct': 100,
      });
    } catch (_) {
      await service.delete('boms', bomId);
      rethrow;
    }
    return bomId;
  }

  Future<Map<String, dynamic>> detail(String bomId) async {
    final bom = await service.one('boms', bomId);
    if (bom == null) {
      throw StateError('Estructura de fabricación no encontrada.');
    }
    final revisions = await service.list(
      'bom_revisions',
      equals: {'bom_id': bomId},
      orderBy: 'created_at',
      ascending: false,
    );
    final items = <String, List<Map<String, dynamic>>>{};
    final substitutes = <String, List<Map<String, dynamic>>>{};
    for (final rev in revisions) {
      final revId = rev['id'] as String;
      final rows = await service.list(
        'bom_items',
        equals: {'bom_revision_id': revId},
        orderBy: 'line_no',
      );
      items[revId] = rows;
      for (final row in rows) {
        final id = row['id'] as String;
        substitutes[id] = await service.list(
          'bom_item_substitutes',
          equals: {'bom_item_id': id},
          orderBy: 'priority',
        );
      }
    }
    return {
      'bom': bom,
      'revisions': revisions,
      'items': items,
      'substitutes': substitutes,
    };
  }
}
