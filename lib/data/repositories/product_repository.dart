import 'base_repository.dart';

class ProductRepository extends BaseRepository {
  ProductRepository(super.service, super.client);

  Future<List<Map<String, dynamic>>> products() =>
      listTenant('products', orderBy: 'name');

  Future<Map<String, dynamic>> detail(String productId) async {
    final product = await service.one('products', productId);
    if (product == null) throw StateError('Producto no encontrado.');
    final results = await Future.wait([
      service.list(
        'product_revisions',
        equals: {'product_id': productId},
        orderBy: 'revision_no',
        ascending: false,
      ),
      service.list('customer_products', equals: {'product_id': productId}),
      service.list('boms', equals: {'product_id': productId}),
      service.list('routings', equals: {'product_id': productId}),
      service.list('document_links', equals: {'product_id': productId}),
    ]);
    return {
      'product': product,
      'revisions': results[0],
      'customers': results[1],
      'boms': results[2],
      'routings': results[3],
      'documents': results[4],
    };
  }
}
