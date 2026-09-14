import 'base_repository.dart';

class CustomerRepository extends BaseRepository {
  CustomerRepository(super.service, super.client);

  Future<List<Map<String, dynamic>>> customers() =>
      listTenant('customers', orderBy: 'legal_name');

  Future<Map<String, dynamic>> detail(String customerId) async {
    final customer = await service.one('customers', customerId);
    if (customer == null) throw StateError('Cliente no encontrado.');
    final results = await Future.wait([
      service.list(
        'customer_addresses',
        equals: {'customer_id': customerId},
        orderBy: 'label',
      ),
      service.list(
        'customer_contacts',
        equals: {'customer_id': customerId},
        orderBy: 'full_name',
      ),
      service.list('customer_products', equals: {'customer_id': customerId}),
      service.list(
        'customer_requirements',
        equals: {'customer_id': customerId},
      ),
      service.list('design_approvals', equals: {'customer_id': customerId}),
      service.list(
        'customer_orders',
        equals: {'customer_id': customerId},
        orderBy: 'order_date',
        ascending: false,
      ),
      service.list(
        'deliveries',
        equals: {'customer_id': customerId},
        orderBy: 'created_at',
        ascending: false,
      ),
      service.list(
        'customer_claims',
        equals: {'customer_id': customerId},
        orderBy: 'opened_at',
        ascending: false,
      ),
      service.list(
        'nonconformities',
        equals: {'customer_id': customerId},
        orderBy: 'detected_at',
        ascending: false,
      ),
      service.list(
        'document_links',
        equals: {'customer_id': customerId},
        orderBy: 'created_at',
        ascending: false,
      ),
    ]);
    return {
      'customer': customer,
      'addresses': results[0],
      'contacts': results[1],
      'products': results[2],
      'requirements': results[3],
      'designs': results[4],
      'orders': results[5],
      'deliveries': results[6],
      'claims': results[7],
      'nonconformities': results[8],
      'documents': results[9],
    };
  }
}
