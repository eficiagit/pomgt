import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../repositories/document_repository.dart';
import '../repositories/production_repository.dart';

class ProductionOrderPdfService {
  ProductionOrderPdfService(this.production, this.documents);

  final ProductionRepository production;
  final DocumentRepository documents;

  Future<Uint8List> build(String orderId) async {
    final data = await production.detail(orderId);
    return buildFromData(data);
  }

  Future<Uint8List> buildFromData(Map<String, dynamic> data) async {
    final order = _map(data['order']);
    final product = _map(data['product']);
    final customer = _map(data['customer']);
    final customerOrder = _map(data['customer_order']);
    final operations = _list(data['operations']);
    final materials = _list(data['materials']);
    final quality = _list(data['quality']);
    final checklist = _list(data['checklist']);
    final operationMaterials = _listMap(data['operation_materials']);
    final materialRevisions = _mapMap(data['material_revisions']);
    final materialAttributeValues = _listMap(data['material_attribute_values']);
    final materialAttributeDefinitions = _mapMap(
      data['material_attribute_definitions'],
    );
    final units =
        (data['units'] as Map?)?.cast<String, Map<String, dynamic>>() ??
        const {};
    final products =
        (data['products'] as Map?)?.cast<String, Map<String, dynamic>>() ??
        const {};
    final workCenters =
        (data['work_centers'] as Map?)?.cast<String, Map<String, dynamic>>() ??
        const {};
    final machines =
        (data['machines'] as Map?)?.cast<String, Map<String, dynamic>>() ??
        const {};
    final logoBytes = (await rootBundle.load(
      'assets/POMGT-LOGO.png',
    )).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final iconFont = pw.Font.ttf(
      await rootBundle.load(
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      ),
    );

    final pdf = pw.Document(
      title: 'Orden de producción ${order['op_number'] ?? ''}',
      author: 'POMGT',
      subject: 'Orden de producción',
      creator: 'POMGT - Production Order Management',
    );

    const blue = PdfColor.fromInt(0xFF1B78D8);
    const blueSoft = PdfColor.fromInt(0xFFEAF3FF);
    const ink = PdfColor.fromInt(0xFF111111);
    const muted = PdfColor.fromInt(0xFF666666);
    const line = PdfColor.fromInt(0xFFD6D6D6);
    const green = PdfColor.fromInt(0xFF0F9F60);
    const greenSoft = PdfColor.fromInt(0xFFE7F8EE);

    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    pw.Widget labelValue(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 5.8, color: muted)),
        pw.SizedBox(height: 1.2),
        pw.Text(
          _dash(value),
          style: pw.TextStyle(
            fontSize: 6.7,
            color: ink,
            fontWeight: pw.FontWeight.bold,
            height: 1.05,
          ),
        ),
      ],
    );

    pw.Widget sectionTitle(String title, int iconCodePoint) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 5),
      padding: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: line, width: .7)),
      ),
      child: pw.Row(
        children: [
          _sectionIcon(iconCodePoint, iconFont, blue),
          pw.SizedBox(width: 7),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
        ],
      ),
    );

    pw.Widget statusBadge(String status) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: greenSoft,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 9,
            height: 9,
            decoration: const pw.BoxDecoration(
              color: green,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.InkList(
                points: [
                  [
                    const PdfPoint(1.5, 5),
                    const PdfPoint(3.5, 7),
                    const PdfPoint(7.5, 2),
                  ],
                ],
                strokeColor: PdfColors.white,
                strokeWidth: 1.2,
              ),
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Text(
            status,
            style: pw.TextStyle(
              fontSize: 8,
              color: green,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    pw.Widget infoColumns(List<List<pw.Widget>> columns) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0)
            pw.Container(
              width: .6,
              height: 48,
              margin: const pw.EdgeInsets.symmetric(horizontal: 14),
              color: line,
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final item in columns[i]) ...[
                  item,
                  pw.SizedBox(height: 9),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    final generatedAt = _dateTime(DateTime.now().toIso8601String());

    pw.Widget header(pw.Context context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Image(logo, width: 82, fit: pw.BoxFit.contain),
            pw.Spacer(),
            pw.SizedBox(
              width: 150,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    order['op_number']?.toString() ?? 'OP',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  statusBadge(_status(order['status'])),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Generado: $generatedAt',
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 6.8, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 9),
        pw.Text(
          'ORDEN DE PRODUCCIÓN',
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Centro de control de la operación de manufactura.',
          style: const pw.TextStyle(fontSize: 6.5, color: muted),
        ),
        pw.SizedBox(height: 4),
      ],
    );

    final customerName =
        customer['trade_name']?.toString().trim().isNotEmpty == true
        ? customer['trade_name'].toString()
        : customer['legal_name']?.toString() ?? '-';
    final materialsByBomItem = {
      for (final material in materials)
        if (material['bom_item_id'] != null)
          material['bom_item_id'].toString(): material,
    };
    final materialsByProduct = {
      for (final material in materials)
        if (material['material_product_id'] != null)
          material['material_product_id'].toString(): material,
    };

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(36, 18, 36, 18),
          theme: theme,
        ),
        header: header,
        footer: (_) => pw.SizedBox(),
        build: (context) => [
          sectionTitle(
            'Resumen de la orden',
            CupertinoIcons.doc_text.codePoint,
          ),
          infoColumns([
            [
              labelValue(
                'Producto',
                '${product['sku'] ?? '-'} - ${product['name'] ?? '-'}',
              ),
              labelValue(
                'Cantidad planificada',
                '${_qty(order['planned_quantity'])} ${order['uom_symbol'] ?? ''}',
              ),
              labelValue('Prioridad', _status(order['priority'])),
            ],
            [
              labelValue('Cliente', customerName),
              labelValue(
                'Pedido',
                customerOrder['order_number']?.toString() ??
                    order['order_number']?.toString() ??
                    'Producción interna',
              ),
              labelValue(
                'OC del cliente',
                customerOrder['customer_po_number']?.toString() ??
                    order['customer_po_number']?.toString() ??
                    '-',
              ),
            ],
            [
              labelValue(
                'Lista de materiales',
                '${order['bom_code'] ?? '-'} - ${order['bom_revision_code'] ?? '-'}',
              ),
              labelValue(
                'Ruta de fabricación',
                '${order['routing_code'] ?? '-'} - ${order['routing_revision_code'] ?? '-'}',
              ),
              labelValue('Fecha requerida', _dateTime(order['required_at'])),
            ],
          ]),

          sectionTitle(
            'Planeación y ejecución',
            CupertinoIcons.calendar.codePoint,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: labelValue(
                  'Inicio planificado',
                  _dateTime(order['planned_start_at']),
                ),
              ),
              pw.Container(
                width: .8,
                height: 20,
                color: line,
                margin: const pw.EdgeInsets.symmetric(horizontal: 12),
              ),
              pw.Expanded(
                child: labelValue(
                  'Fin planificado',
                  _dateTime(order['planned_end_at']),
                ),
              ),
              pw.Container(
                width: .8,
                height: 20,
                color: line,
                margin: const pw.EdgeInsets.symmetric(horizontal: 12),
              ),
              pw.Expanded(
                child: labelValue(
                  'Inicio real',
                  _dateTime(order['actual_start_at']),
                ),
              ),
              pw.Container(
                width: .8,
                height: 20,
                color: line,
                margin: const pw.EdgeInsets.symmetric(horizontal: 12),
              ),
              pw.Expanded(
                child: labelValue(
                  'Fin real',
                  _dateTime(order['actual_end_at']),
                ),
              ),
            ],
          ),
          if ((order['notes']?.toString() ?? '').trim().isNotEmpty)
            labelValue('Notas de la orden', order['notes'].toString()),

          sectionTitle(
            'Secuencia de fabricación',
            CupertinoIcons.gear_alt.codePoint,
          ),
          if (operations.isEmpty)
            _empty('La orden todavía no tiene operaciones preparadas.', muted)
          else
            ...operations.map((op) {
              final wc =
                  workCenters[op['work_center_id']?.toString()]?['name']
                      ?.toString() ??
                  '-';
              final machine =
                  machines[op['machine_id']?.toString()]?['name']?.toString() ??
                  '';
              final linked =
                  operationMaterials[op['routing_operation_id']?.toString()] ??
                  const <Map<String, dynamic>>[];
              return _operationBlock(
                op: op,
                workCenter: wc,
                machine: machine,
                linkedMaterials: linked,
                materialsByBomItem: materialsByBomItem,
                materialsByProduct: materialsByProduct,
                products: products,
                units: units,
                materialRevisions: materialRevisions,
                materialAttributeValues: materialAttributeValues,
                materialAttributeDefinitions: materialAttributeDefinitions,
                line: line,
                blue: blue,
                blueSoft: blueSoft,
                ink: ink,
                muted: muted,
              );
            }),

          sectionTitle(
            'Materiales requeridos y consumo',
            CupertinoIcons.cube_box.codePoint,
          ),
          if (materials.isEmpty)
            _empty('No hay materiales congelados para esta orden.', muted)
          else
            _table(
              headers: const [
                'Material',
                'Descripcion',
                'Tipo',
                'Requerido',
                'Surtido',
                'Consumido',
                'Merma',
                'Especificaciones clave',
              ],
              widths: const [13, 17, 11, 10, 9, 10, 8, 22],
              rows: materials.map((m) {
                final material =
                    products[m['material_product_id']?.toString()] ?? const {};
                final unit = units[m['uom_id']?.toString()] ?? const {};
                final symbol = unit['symbol']?.toString() ?? '';
                final revision =
                    materialRevisions[m['material_product_id']?.toString()] ??
                    const {};
                final attrs =
                    materialAttributeValues[m['material_product_id']
                        ?.toString()] ??
                    const <Map<String, dynamic>>[];
                return [
                  material['sku']?.toString() ?? '-',
                  material['name']?.toString() ?? 'Material',
                  _status(m['component_type']),
                  '${_qty(m['required_quantity'])} $symbol',
                  '${_qty(m['issued_quantity'])} $symbol',
                  '${_qty(m['consumed_quantity'])} $symbol',
                  '${_qty(m['scrap_quantity'])} $symbol',
                  _materialSpecsSummary(
                    revision,
                    attrs,
                    materialAttributeDefinitions,
                    units,
                  ),
                ];
              }).toList(),
              line: line,
              ink: ink,
              muted: muted,
            ),

          sectionTitle(
            'Calidad y verificaciones',
            CupertinoIcons.checkmark_circle.codePoint,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Controles de calidad',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    if (quality.isEmpty)
                      _empty('Sin controles liberados.', muted)
                    else
                      ...quality
                          .take(12)
                          .map(
                            (q) => _resultLine(
                              q['name']?.toString() ?? 'Control',
                              _status(q['result_status']),
                              q['result_status'] == 'failed'
                                  ? PdfColors.red700
                                  : q['result_status'] == 'passed'
                                  ? PdfColors.green700
                                  : muted,
                              ink,
                              muted,
                            ),
                          ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Lista de verificación',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: ink,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    if (checklist.isEmpty)
                      _empty('Sin verificaciones operativas.', muted)
                    else
                      ...checklist
                          .take(12)
                          .map(
                            (c) => _resultLine(
                              c['prompt']?.toString() ?? 'Verificación',
                              c['is_completed'] == true
                                  ? 'Completada'
                                  : 'Pendiente',
                              c['is_completed'] == true
                                  ? PdfColors.green700
                                  : muted,
                              ink,
                              muted,
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
          sectionTitle('Firmas / liberación', CupertinoIcons.pencil.codePoint),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _signatureBox('Produccion', line, ink, muted),
              pw.SizedBox(width: 18),
              _signatureBox('Calidad', line, ink, muted),
              pw.SizedBox(width: 18),
              _signatureBox('Supervision', line, ink, muted),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> printOrder(String orderId) async {
    final bytes = await build(orderId);
    await Printing.layoutPdf(
      name: 'OP-$orderId.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<Map<String, dynamic>> saveAsDocument(String orderId) async {
    final data = await production.detail(orderId);
    final order = _map(data['order']);
    final bytes = await buildFromData(data);
    final number = order['op_number']?.toString() ?? 'OP';
    return documents.createUploadAndLink(
      entityField: 'production_order_id',
      entityId: orderId,
      title: 'Orden de producción $number',
      documentType: 'Orden de producción',
      description:
          'PDF generado por POMGT con el estado de la orden al momento de su generación.',
      bytes: bytes,
      filename: '$number.pdf',
      mimeType: 'application/pdf',
    );
  }

  static pw.Widget _empty(String text, PdfColor muted) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: muted)),
  );

  static pw.Widget _sectionIcon(
    int iconCodePoint,
    pw.Font iconFont,
    PdfColor blue,
  ) => pw.SizedBox(
    width: 13,
    child: pw.Text(
      String.fromCharCode(iconCodePoint),
      style: pw.TextStyle(font: iconFont, fontSize: 11.5, color: blue),
    ),
  );

  static pw.Widget _resultLine(
    String title,
    String status,
    PdfColor color,
    PdfColor ink,
    PdfColor muted,
  ) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Container(
          width: 5,
          height: 5,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(title, style: pw.TextStyle(fontSize: 7.8, color: ink)),
        ),
        pw.Text(status, style: pw.TextStyle(fontSize: 7.4, color: muted)),
      ],
    ),
  );

  static pw.Widget _operationBlock({
    required Map<String, dynamic> op,
    required String workCenter,
    required String machine,
    required List<Map<String, dynamic>> linkedMaterials,
    required Map<String, Map<String, dynamic>> materialsByBomItem,
    required Map<String, Map<String, dynamic>> materialsByProduct,
    required Map<String, Map<String, dynamic>> products,
    required Map<String, Map<String, dynamic>> units,
    required Map<String, Map<String, dynamic>> materialRevisions,
    required Map<String, List<Map<String, dynamic>>> materialAttributeValues,
    required Map<String, Map<String, dynamic>> materialAttributeDefinitions,
    required PdfColor line,
    required PdfColor blue,
    required PdfColor blueSoft,
    required PdfColor ink,
    required PdfColor muted,
  }) {
    final materials = linkedMaterials.map((link) {
      final bomItemId = link['bom_item_id']?.toString();
      final productId = link['material_product_id']?.toString();
      return materialsByBomItem[bomItemId] ??
          materialsByProduct[productId] ??
          <String, dynamic>{
            'material_product_id': productId,
            'bom_item_id': bomItemId,
            'required_quantity': link['quantity_override'],
            'uom_id': link['uom_id'],
            'component_type': 'material',
            'notes': link['notes'],
          };
    }).toList();

    pw.Widget pair(String label, String value) => pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label\n',
            style: pw.TextStyle(fontSize: 6.6, color: muted),
          ),
          pw.TextSpan(
            text: _dash(value),
            style: pw.TextStyle(
              fontSize: 6.6,
              color: ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            children: [
              pw.Container(
                width: 19,
                height: 19,
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFE5E7EB),
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFF9CA3AF),
                    width: .7,
                  ),
                ),
                child: pw.Center(
                  child: pw.Text(
                    '${op['sequence_no'] ?? '-'}',
                    style: pw.TextStyle(
                      fontSize: 6.6,
                      color: const PdfColor.fromInt(0xFF4B5563),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
              pw.Container(
                width: .7,
                height: materials.isEmpty ? 22 : 32,
                color: line,
              ),
            ],
          ),
          pw.SizedBox(width: 7),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: PdfColor.fromInt(0xFFE5E7EB),
                    width: .5,
                  ),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 135,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              _dash(op['name']),
                              style: pw.TextStyle(
                                fontSize: 8.2,
                                fontWeight: pw.FontWeight.bold,
                                color: ink,
                              ),
                            ),
                            pw.Text(
                              '${_dash(op['operation_code'])} - ${_dash(op['name'])}',
                              style: pw.TextStyle(
                                fontSize: 5.5,
                                color: ink,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            if ((op['description']?.toString() ?? '')
                                .trim()
                                .isNotEmpty)
                              pw.Text(
                                op['description'].toString(),
                                style: pw.TextStyle(
                                  fontSize: 5.2,
                                  color: muted,
                                  height: 1.05,
                                ),
                              ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 10),
                      pw.Container(width: .7, height: 33, color: line),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pair(
                                    'Tipo',
                                    _status(op['operation_type']),
                                  ),
                                ),
                                pw.Expanded(child: pair('Centro', workCenter)),
                                pw.Expanded(child: pair('Maquina', machine)),
                                pw.Expanded(
                                  child: pair(
                                    'Cantidad',
                                    '${_qty(op['completed_quantity'])} / ${_qty(op['planned_quantity'])}',
                                  ),
                                ),
                                pw.Expanded(
                                  child: pair(
                                    'Inicio',
                                    _shortDate(
                                      op['actual_start_at'] ??
                                          op['planned_start_at'],
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  child: pair(
                                    'Fin',
                                    _shortDate(
                                      op['actual_end_at'] ??
                                          op['planned_end_at'],
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  flex: 3,
                                  child: pair('Firma', '____________________'),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 5),
                            if (materials.isEmpty)
                              _linkedMaterialEmpty(line, muted)
                            else
                              _materialsBox(
                                materials: materials,
                                products: products,
                                units: units,
                                materialRevisions: materialRevisions,
                                materialAttributeValues:
                                    materialAttributeValues,
                                materialAttributeDefinitions:
                                    materialAttributeDefinitions,
                                line: line,
                                ink: ink,
                                blue: blue,
                                muted: muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if ((op['instructions']?.toString() ?? '')
                      .trim()
                      .isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pair(
                      'Instruccion industrial',
                      op['instructions'].toString(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _linkedMaterialEmpty(PdfColor line, PdfColor muted) =>
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: line, width: .45),
        ),
        child: pw.Text(
          'Sin consumo de materiales asociado directamente a esta operacion.',
          style: pw.TextStyle(fontSize: 6.6, color: muted),
        ),
      );

  static pw.Widget _materialsBox({
    required List<Map<String, dynamic>> materials,
    required Map<String, Map<String, dynamic>> products,
    required Map<String, Map<String, dynamic>> units,
    required Map<String, Map<String, dynamic>> materialRevisions,
    required Map<String, List<Map<String, dynamic>>> materialAttributeValues,
    required Map<String, Map<String, dynamic>> materialAttributeDefinitions,
    required PdfColor line,
    required PdfColor ink,
    required PdfColor blue,
    required PdfColor muted,
  }) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: line, width: .45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < materials.length; index++) ...[
          if (index > 0) ...[
            pw.SizedBox(height: 4),
            pw.Container(height: .4, color: line),
            pw.SizedBox(height: 4),
          ],
          _materialDataGrid(
            material: materials[index],
            product:
                products[materials[index]['material_product_id']?.toString()] ??
                const {},
            unit: units[materials[index]['uom_id']?.toString()] ?? const {},
            revision:
                materialRevisions[materials[index]['material_product_id']
                    ?.toString()] ??
                const {},
            attributes:
                materialAttributeValues[materials[index]['material_product_id']
                    ?.toString()] ??
                const <Map<String, dynamic>>[],
            attributeDefinitions: materialAttributeDefinitions,
            units: units,
            line: line,
            ink: ink,
            blue: blue,
            muted: muted,
          ),
        ],
      ],
    ),
  );

  static pw.Widget _signatureBox(
    String title,
    PdfColor line,
    PdfColor ink,
    PdfColor muted,
  ) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 6.6,
              color: ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(height: .6, color: const PdfColor.fromInt(0xFF9AA8B5)),
          pw.SizedBox(height: 3),
          pw.Text(
            'Nombre y firma',
            style: pw.TextStyle(fontSize: 5.2, color: muted),
          ),
        ],
      ),
    ),
  );

  static pw.Widget _materialDataGrid({
    required Map<String, dynamic> material,
    required Map<String, dynamic> product,
    required Map<String, dynamic> unit,
    required Map<String, dynamic> revision,
    required List<Map<String, dynamic>> attributes,
    required Map<String, Map<String, dynamic>> attributeDefinitions,
    required Map<String, Map<String, dynamic>> units,
    required PdfColor line,
    required PdfColor ink,
    required PdfColor blue,
    required PdfColor muted,
  }) {
    final symbol = unit['symbol']?.toString() ?? '';
    final fields = <MapEntry<String, String>>[
      MapEntry(
        'Material',
        '${_dash(product['sku'])} - ${_dash(product['name'])}',
      ),
      MapEntry(
        'Cantidad requerida',
        '${_qty(material['required_quantity'])} $symbol'.trim(),
      ),
      MapEntry('Tipo', _status(material['component_type'])),
      MapEntry('Metodo de consumo', _status(material['issue_method'])),
      ..._materialSpecPairs(revision, attributes, attributeDefinitions, units),
    ];
    final rows = <pw.Widget>[];
    for (var i = 0; i < fields.length; i += 4) {
      rows.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(top: i == 0 ? 0 : 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < 4; j++) ...[
                if (j > 0) pw.SizedBox(width: 10),
                pw.Expanded(
                  child: i + j < fields.length
                      ? _materialDataCell(fields[i + j], ink, blue, muted)
                      : pw.SizedBox(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return pw.Container(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  static pw.Widget _materialDataCell(
    MapEntry<String, String> field,
    PdfColor ink,
    PdfColor blue,
    PdfColor muted,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        field.key,
        style: pw.TextStyle(
          fontSize: 6.4,
          color: field.key == 'Material' ? blue : muted,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 1.2),
      pw.Text(
        _dash(field.value),
        style: pw.TextStyle(
          fontSize: 6.9,
          color: field.key == 'Material' ? blue : ink,
          fontWeight: pw.FontWeight.bold,
          height: 1.08,
        ),
      ),
    ],
  );

  static pw.Widget _table({
    required List<String> headers,
    required List<int> widths,
    required List<List<String>> rows,
    required PdfColor line,
    required PdfColor ink,
    required PdfColor muted,
  }) {
    final columnWidths = <int, pw.TableColumnWidth>{};
    for (var i = 0; i < widths.length; i++) {
      columnWidths[i] = pw.FlexColumnWidth(widths[i].toDouble());
    }
    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: line, width: .5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF1F1F1),
          ),
          children: headers
              .map(
                (h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 5,
                  ),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 7.2,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: row
                .map(
                  (value) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: pw.Text(
                      value,
                      style: pw.TextStyle(
                        fontSize: 7.1,
                        color: muted,
                        height: 1.25,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};
  static Map<String, Map<String, dynamic>> _mapMap(dynamic value) =>
      value is Map
      ? value.map(
          (key, row) => MapEntry(
            key.toString(),
            row is Map<String, dynamic>
                ? row
                : Map<String, dynamic>.from(row as Map),
          ),
        )
      : <String, Map<String, dynamic>>{};
  static Map<String, List<Map<String, dynamic>>> _listMap(dynamic value) =>
      value is Map
      ? value.map(
          (key, rows) => MapEntry(
            key.toString(),
            rows is List
                ? rows.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : <Map<String, dynamic>>[],
          ),
        )
      : <String, List<Map<String, dynamic>>>{};
  static List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : <Map<String, dynamic>>[];

  static double _num(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  static String _dash(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == '—' || text == '□' || text == '☒') return '-';
    return text;
  }

  static String _qty(dynamic value) {
    final n = _num(value);
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _dateTime(dynamic value) {
    if (value == null) return '-';
    final d = DateTime.tryParse(value.toString())?.toLocal();
    if (d == null) return value.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _dimensions(
    Map<String, dynamic> revision,
    Map<String, Map<String, dynamic>> units,
  ) {
    final symbol = units[revision['dimension_uom_id']?.toString()]?['symbol']
        ?.toString();
    final values = [
      if (_num(revision['width']) != 0) 'Ancho ${_qty(revision['width'])}',
      if (_num(revision['height']) != 0) 'Alto ${_qty(revision['height'])}',
      if (_num(revision['length']) != 0) 'Largo ${_qty(revision['length'])}',
      if (_num(revision['thickness']) != 0)
        'Grosor ${_qty(revision['thickness'])}',
    ];
    if (values.isEmpty) return '-';
    return '${values.join(' / ')} ${symbol ?? ''}'.trim();
  }

  static String _weight(
    Map<String, dynamic> revision,
    Map<String, Map<String, dynamic>> units,
  ) {
    if (_num(revision['weight']) == 0) return '-';
    final symbol = units[revision['weight_uom_id']?.toString()]?['symbol']
        ?.toString();
    return '${_qty(revision['weight'])} ${symbol ?? ''}'.trim();
  }

  static String _materialSpecsSummary(
    Map<String, dynamic> revision,
    List<Map<String, dynamic>> attributes,
    Map<String, Map<String, dynamic>> attributeDefinitions,
    Map<String, Map<String, dynamic>> units,
  ) {
    final parts = _materialSpecPairs(
      revision,
      attributes,
      attributeDefinitions,
      units,
    ).map((entry) => '${entry.key}: ${entry.value}').toList();
    return parts.isEmpty ? '-' : parts.join(' | ');
  }

  static List<MapEntry<String, String>> _materialSpecPairs(
    Map<String, dynamic> revision,
    List<Map<String, dynamic>> attributes,
    Map<String, Map<String, dynamic>> attributeDefinitions,
    Map<String, Map<String, dynamic>> units,
  ) {
    final parts = <MapEntry<String, String>>[
      if (_dash(revision['material_description']) != '-')
        MapEntry('Material', _dash(revision['material_description'])),
      if (_dash(revision['color_description']) != '-')
        MapEntry('Color', _dash(revision['color_description'])),
      if (_dimensions(revision, units) != '-')
        MapEntry('Dimensiones', _dimensions(revision, units)),
      if (_weight(revision, units) != '-')
        MapEntry('Peso', _weight(revision, units)),
      if (_dash(revision['general_tolerance_notes']) != '-')
        MapEntry('Tolerancia', _dash(revision['general_tolerance_notes'])),
    ];
    for (final value in attributes.where(_hasAttributeValue).take(5)) {
      final definition =
          attributeDefinitions[value['attribute_definition_id']?.toString()] ??
          const {};
      final label =
          definition['label']?.toString() ??
          definition['attribute_key']?.toString() ??
          'Atributo';
      final attrUnit = units[definition['uom_id']?.toString()]?['symbol'];
      parts.add(
        MapEntry(label, '${_attributeValue(value)} ${attrUnit ?? ''}'.trim()),
      );
    }
    return parts;
  }

  static String _attributeValue(Map<String, dynamic> value) {
    for (final key in [
      'value_text',
      'value_number',
      'value_boolean',
      'value_date',
      'value_json',
    ]) {
      final raw = value[key];
      if (raw == null) continue;
      if (raw is String && raw.trim().isEmpty) continue;
      if (raw is bool) return raw ? 'Si' : 'No';
      return raw.toString();
    }
    return '-';
  }

  static bool _hasAttributeValue(Map<String, dynamic> value) {
    for (final key in [
      'value_text',
      'value_number',
      'value_boolean',
      'value_date',
      'value_json',
    ]) {
      final raw = value[key];
      if (raw == null) continue;
      if (raw is String && raw.trim().isEmpty) continue;
      if (raw is Iterable && raw.isEmpty) continue;
      if (raw is Map && raw.isEmpty) continue;
      return true;
    }
    return false;
  }

  static String _shortDate(dynamic value) {
    if (value == null) return '-';
    final d = DateTime.tryParse(value.toString())?.toLocal();
    if (d == null) return '-';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _status(dynamic value) {
    switch (value?.toString()) {
      case 'draft':
        return 'Borrador';
      case 'planned':
        return 'Planificada';
      case 'ready':
        return 'Lista';
      case 'in_progress':
        return 'En proceso';
      case 'on_hold':
        return 'En pausa';
      case 'completed':
        return 'Completada';
      case 'cancelled':
        return 'Cancelada';
      case 'pending':
        return 'Pendiente';
      case 'skipped':
        return 'Omitida';
      case 'passed':
        return 'Aprobado';
      case 'failed':
        return 'Rechazado';
      case 'not_applicable':
        return 'No aplica';
      case 'low':
        return 'Baja';
      case 'normal':
        return 'Normal';
      case 'high':
        return 'Alta';
      case 'urgent':
        return 'Urgente';
      case 'material':
        return 'Materia prima';
      case 'subassembly':
        return 'Subensamble';
      case 'packaging':
        return 'Empaque';
      case 'consumable':
        return 'Consumible';
      case 'byproduct':
        return 'Subproducto';
      default:
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) return '-';
        return text.replaceAll('_', ' ');
    }
  }
}
