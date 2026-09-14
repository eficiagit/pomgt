import 'dart:typed_data';
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

    final pdf = pw.Document(
      title: 'Orden de producción ${order['op_number'] ?? ''}',
      author: 'POMGT',
      subject: 'Orden de producción',
      creator: 'POMGT - Production Order Management',
    );

    const blue = PdfColor.fromInt(0xFF444444);
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
        pw.Text(label, style: const pw.TextStyle(fontSize: 7.2, color: muted)),
        pw.SizedBox(height: 2),
        pw.Text(
          _dash(value),
          style: pw.TextStyle(
            fontSize: 8.4,
            color: ink,
            fontWeight: pw.FontWeight.bold,
            height: 1.15,
          ),
        ),
      ],
    );

    pw.Widget sectionTitle(String title) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 10, bottom: 7),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11.2,
          fontWeight: pw.FontWeight.bold,
          color: ink,
        ),
      ),
    );

    pw.Widget divider() => pw.Container(height: .8, color: line);

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
              width: .8,
              height: 84,
              margin: const pw.EdgeInsets.symmetric(horizontal: 18),
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
            pw.Image(logo, width: 98, fit: pw.BoxFit.contain),
            pw.Spacer(),
            pw.SizedBox(
              width: 168,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    order['op_number']?.toString() ?? 'OP',
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: blue,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  statusBadge(_status(order['status'])),
                  pw.SizedBox(height: 7),
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
        pw.SizedBox(height: 20),
        pw.Text(
          'ORDEN DE PRODUCCIÓN',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Centro de control de la operación de manufactura.',
          style: const pw.TextStyle(fontSize: 7.8, color: muted),
        ),
        pw.SizedBox(height: 12),
        divider(),
      ],
    );

    final customerName =
        customer['trade_name']?.toString().trim().isNotEmpty == true
        ? customer['trade_name'].toString()
        : customer['legal_name']?.toString() ?? '-';

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(42, 20, 42, 24),
          theme: theme,
        ),
        header: header,
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 9),
          padding: const pw.EdgeInsets.only(top: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: line)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: 'POMGT',
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: muted,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    const pw.TextSpan(
                      text: '   Production Order Management',
                      style: pw.TextStyle(fontSize: 5.8, color: muted),
                    ),
                  ],
                ),
              ),
              pw.Text(
                'Documento generado el $generatedAt\nSistema POMGT',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 5.8, color: muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          sectionTitle('Resumen de la orden'),
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

          divider(),
          sectionTitle('Planeación y ejecución'),
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

          divider(),
          sectionTitle('Secuencia de fabricación'),
          if (operations.isEmpty)
            _empty('La orden todavía no tiene operaciones preparadas.', muted)
          else
            _table(
              headers: const [
                'Paso',
                'Operación',
                'Centro / máquina',
                'Estado',
                'Cantidad',
                'Inicio / fin',
                'Firma',
              ],
              widths: const [8, 21, 19, 12, 12, 16, 18],
              rows: operations.map((op) {
                final wc =
                    workCenters[op['work_center_id']?.toString()]?['name']
                        ?.toString() ??
                    '-';
                final machine =
                    machines[op['machine_id']?.toString()]?['name']
                        ?.toString() ??
                    '';
                return [
                  '${op['sequence_no'] ?? '-'}',
                  '${op['operation_code'] ?? ''}\n${op['name'] ?? '-'}',
                  machine.isEmpty ? wc : '$wc\n$machine',
                  _status(op['status']),
                  '${_qty(op['completed_quantity'])} / ${_qty(op['planned_quantity'])}',
                  '${_shortDate(op['actual_start_at'] ?? op['planned_start_at'])}\n${_shortDate(op['actual_end_at'] ?? op['planned_end_at'])}',
                  '\n______________',
                ];
              }).toList(),
              line: line,
              ink: ink,
              muted: muted,
            ),

          divider(),
          sectionTitle('Materiales requeridos y consumo'),
          if (materials.isEmpty)
            _empty('No hay materiales congelados para esta orden.', muted)
          else
            _table(
              headers: const [
                'Material',
                'Tipo',
                'Requerido',
                'Surtido',
                'Consumido',
                'Merma',
              ],
              widths: const [30, 16, 14, 14, 14, 12],
              rows: materials.map((m) {
                final material =
                    products[m['material_product_id']?.toString()] ?? const {};
                final unit = units[m['uom_id']?.toString()] ?? const {};
                final symbol = unit['symbol']?.toString() ?? '';
                return [
                  '${material['sku'] ?? ''}\n${material['name'] ?? 'Material'}',
                  _status(m['component_type']),
                  '${_qty(m['required_quantity'])} $symbol',
                  '${_qty(m['issued_quantity'])} $symbol',
                  '${_qty(m['consumed_quantity'])} $symbol',
                  '${_qty(m['scrap_quantity'])} $symbol',
                ];
              }).toList(),
              line: line,
              ink: ink,
              muted: muted,
            ),

          divider(),
          sectionTitle('Calidad y verificaciones'),
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
                      _empty('Sin controles.', muted)
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
                      _empty('Sin verificaciones.', muted)
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
