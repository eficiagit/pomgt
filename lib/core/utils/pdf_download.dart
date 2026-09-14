import 'dart:typed_data';

import 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart';

Future<void> downloadPdfFile({
  required Uint8List bytes,
  required String filename,
}) {
  return downloadPdfFileImpl(bytes: bytes, filename: filename);
}
