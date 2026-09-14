import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> downloadPdfFileImpl({
  required Uint8List bytes,
  required String filename,
}) {
  return Printing.sharePdf(bytes: bytes, filename: filename);
}
