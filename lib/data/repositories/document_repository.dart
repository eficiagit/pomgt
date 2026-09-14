import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../services/document_storage_service.dart';
import 'base_repository.dart';

class DocumentRepository extends BaseRepository {
  DocumentRepository(super.service, super.client, this.storage);
  final DocumentStorageService storage;

  Future<Map<String, dynamic>> createDocument({
    required String title,
    required String documentType,
    String? description,
    String confidentiality = 'internal',
  }) {
    return service.insert(
      'documents',
      tenantValues({
        'title': title,
        'document_type': documentType,
        'description': description,
        'confidentiality': confidentiality,
        'created_by': userId,
      }),
    );
  }

  Future<Map<String, dynamic>> uploadVersion({
    required String documentId,
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    String? versionLabel,
    String? changeNotes,
  }) async {
    final existing = await service.list(
      'document_versions',
      equals: {'document_id': documentId},
      orderBy: 'version_no',
      ascending: false,
    );
    final next = existing.isEmpty
        ? 1
        : ((existing.first['version_no'] as num).toInt() + 1);
    final org = organizationId!;
    final path = await storage.upload(
      organizationId: org,
      documentId: documentId,
      version: next,
      filename: filename,
      bytes: bytes,
      contentType: mimeType,
    );
    await client
        .schema('pomgt')
        .from('document_versions')
        .update({'is_current': false})
        .eq('document_id', documentId);
    return service.insert('document_versions', {
      'document_id': documentId,
      'version_no': next,
      'version_label': versionLabel ?? 'v$next',
      'original_filename': p.basename(filename),
      'bucket_name': 'pomgt-documents',
      'object_path': path,
      'mime_type': mimeType,
      'size_bytes': bytes.length,
      'checksum_sha256': sha256.convert(bytes).toString(),
      'change_notes': changeNotes,
      'uploaded_by': userId,
      'is_current': true,
    });
  }

  Future<Map<String, dynamic>> link({
    required String documentId,
    String? pinnedVersionId,
    String purpose = 'reference',
    String? customerId,
    String? customerProductId,
    String? productId,
    String? productRevisionId,
    String? customerOrderId,
    String? customerOrderLineId,
    String? bomRevisionId,
    String? routingRevisionId,
    String? routingOperationId,
    String? productionOrderId,
    String? deliveryId,
    String? customerClaimId,
    String? nonconformityId,
  }) {
    return service.insert(
      'document_links',
      tenantValues({
        'document_id': documentId,
        'pinned_version_id': pinnedVersionId,
        'purpose': purpose,
        'customer_id': customerId,
        'customer_product_id': customerProductId,
        'product_id': productId,
        'product_revision_id': productRevisionId,
        'customer_order_id': customerOrderId,
        'customer_order_line_id': customerOrderLineId,
        'bom_revision_id': bomRevisionId,
        'routing_revision_id': routingRevisionId,
        'routing_operation_id': routingOperationId,
        'production_order_id': productionOrderId,
        'delivery_id': deliveryId,
        'customer_claim_id': customerClaimId,
        'nonconformity_id': nonconformityId,
        'created_by': userId,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> linkedDocuments({
    required String entityField,
    required String entityId,
  }) async {
    final links = await service.list(
      'document_links',
      equals: {entityField: entityId},
      orderBy: 'created_at',
      ascending: false,
    );
    final result = <Map<String, dynamic>>[];
    for (final link in links) {
      final documentId = link['document_id']?.toString();
      if (documentId == null) continue;
      final document = await service.one('documents', documentId);
      if (document == null) continue;
      final versions = await service.list(
        'document_versions',
        equals: {'document_id': documentId},
        orderBy: 'version_no',
        ascending: false,
        limit: 1,
      );
      final version = versions.isEmpty ? <String, dynamic>{} : versions.first;
      result.add({
        ...document,
        ...version,
        'document_id': documentId,
        'link_id': link['id'],
        'link_purpose': link['purpose'],
      });
    }
    return result;
  }

  Future<Map<String, dynamic>> createUploadAndLink({
    required String entityField,
    required String entityId,
    required String title,
    required String documentType,
    String? description,
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    final document = await createDocument(
      title: title,
      documentType: documentType,
      description: description,
    );
    final version = await uploadVersion(
      documentId: document['id'].toString(),
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
    final linkValues = <String, String?>{
      'customer_id': null,
      'customer_product_id': null,
      'product_id': null,
      'product_revision_id': null,
      'customer_order_id': null,
      'customer_order_line_id': null,
      'bom_revision_id': null,
      'routing_revision_id': null,
      'routing_operation_id': null,
      'production_order_id': null,
      'delivery_id': null,
      'customer_claim_id': null,
      'nonconformity_id': null,
    };
    if (!linkValues.containsKey(entityField))
      throw ArgumentError('Entidad documental no soportada: $entityField');
    linkValues[entityField] = entityId;
    await link(
      documentId: document['id'].toString(),
      pinnedVersionId: version['id']?.toString(),
      customerId: linkValues['customer_id'],
      customerProductId: linkValues['customer_product_id'],
      productId: linkValues['product_id'],
      productRevisionId: linkValues['product_revision_id'],
      customerOrderId: linkValues['customer_order_id'],
      customerOrderLineId: linkValues['customer_order_line_id'],
      bomRevisionId: linkValues['bom_revision_id'],
      routingRevisionId: linkValues['routing_revision_id'],
      routingOperationId: linkValues['routing_operation_id'],
      productionOrderId: linkValues['production_order_id'],
      deliveryId: linkValues['delivery_id'],
      customerClaimId: linkValues['customer_claim_id'],
      nonconformityId: linkValues['nonconformity_id'],
    );
    return {...document, ...version};
  }

  Future<void> unlink(String linkId) =>
      service.delete('document_links', linkId);
}
