import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class DocumentStorageService {
  DocumentStorageService(this.client);
  final SupabaseClient client;

  Future<String> upload({
    required String organizationId,
    required String documentId,
    required int version,
    required String filename,
    required Uint8List bytes,
    String? contentType,
  }) async {
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$organizationId/$documentId/v$version/$safe';
    await client.storage
        .from(SupabaseConfig.documentBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<String> signedUrl(String objectPath, {int expiresIn = 900}) {
    return client.storage
        .from(SupabaseConfig.documentBucket)
        .createSignedUrl(objectPath, expiresIn);
  }

  Future<void> remove(String objectPath) async {
    await client.storage.from(SupabaseConfig.documentBucket).remove([
      objectPath,
    ]);
  }
}
