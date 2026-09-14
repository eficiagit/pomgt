import 'base_repository.dart';

class RoutingRepository extends BaseRepository {
  RoutingRepository(super.service, super.client);

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
}
