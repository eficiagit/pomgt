import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_plus/excel_plus.dart';

/// What a spreadsheet column maps to on the material being imported.
enum MaterialImportColumnKind {
  sku,
  name,
  description,
  materialCategoryCode,
  baseUomCode,
  costCurrencyCode,
  costAmount,
  isActive,
  dynamicAttribute,
}

/// One column of the import template — either a fixed base-field column or
/// one generated from a `material_attribute_definitions` row for the
/// selected material type.
class MaterialImportColumn {
  const MaterialImportColumn({
    required this.header,
    required this.required,
    required this.kind,
    this.hint,
    this.attribute,
  });

  final String header;
  final bool required;
  final MaterialImportColumnKind kind;
  final String? hint;
  final Map<String, dynamic>? attribute;

  /// Header as it appears in the file, with the "required" marker.
  String get fileHeader => required ? '$header *' : header;

  String get dataTypeLabel {
    if (kind != MaterialImportColumnKind.dynamicAttribute) {
      return switch (kind) {
        MaterialImportColumnKind.costAmount => 'Número',
        MaterialImportColumnKind.isActive => 'Sí / No',
        _ => 'Texto',
      };
    }
    return switch (attribute?['data_type']?.toString()) {
      'integer' => 'Entero',
      'decimal' => 'Número decimal',
      'boolean' => 'Sí / No',
      'date' => 'Fecha (AAAA-MM-DD)',
      'select' => 'Una opción de la lista',
      'multiselect' => 'Una o más opciones, separadas por coma',
      _ => 'Texto',
    };
  }
}

/// Builds the ordered column list for a material type: fixed base fields
/// first, then one column per active attribute definition (already
/// filtered/ordered by `MaterialRepository.attributes(materialTypeId)`).
List<MaterialImportColumn> buildImportColumns(
  List<Map<String, dynamic>> attributes,
) {
  final columns = <MaterialImportColumn>[
    const MaterialImportColumn(
      header: 'SKU',
      required: true,
      kind: MaterialImportColumnKind.sku,
      hint: 'Único por material.',
    ),
    const MaterialImportColumn(
      header: 'Nombre',
      required: true,
      kind: MaterialImportColumnKind.name,
    ),
    const MaterialImportColumn(
      header: 'Descripción',
      required: false,
      kind: MaterialImportColumnKind.description,
    ),
    const MaterialImportColumn(
      header: 'Categoría de material',
      required: false,
      kind: MaterialImportColumnKind.materialCategoryCode,
      hint: 'Código de la categoría (ver Datos maestros → Categorías).',
    ),
    const MaterialImportColumn(
      header: 'Unidad base',
      required: true,
      kind: MaterialImportColumnKind.baseUomCode,
      hint: 'Código de la unidad de medida, ej. KG, PZA, M.',
    ),
    const MaterialImportColumn(
      header: 'Moneda de costo',
      required: false,
      kind: MaterialImportColumnKind.costCurrencyCode,
      hint: 'Código ISO, ej. MXN, USD.',
    ),
    const MaterialImportColumn(
      header: 'Costo estándar',
      required: false,
      kind: MaterialImportColumnKind.costAmount,
    ),
    const MaterialImportColumn(
      header: 'Activo',
      required: false,
      kind: MaterialImportColumnKind.isActive,
      hint: 'Sí / No. Vacío = Sí.',
    ),
  ];
  for (final attribute in attributes) {
    if (attribute['is_active'] == false) continue;
    columns.add(
      MaterialImportColumn(
        header: attribute['label']?.toString() ?? 'Atributo',
        required: attribute['is_required'] == true,
        kind: MaterialImportColumnKind.dynamicAttribute,
        attribute: attribute,
      ),
    );
  }
  return columns;
}

/// An example value shown on the template's sample row — illustrative only,
/// never imported as real data (the importer always treats row 2 like any
/// other data row, so a real import must replace it).
String _exampleValueFor(
  MaterialImportColumn column,
  Map<String, List<Map<String, dynamic>>> optionsByAttribute,
) {
  switch (column.kind) {
    case MaterialImportColumnKind.sku:
      return 'MAT-0001';
    case MaterialImportColumnKind.name:
      return 'Nombre del material';
    case MaterialImportColumnKind.description:
      return '';
    case MaterialImportColumnKind.materialCategoryCode:
      return '';
    case MaterialImportColumnKind.baseUomCode:
      return 'PZA';
    case MaterialImportColumnKind.costCurrencyCode:
      return 'MXN';
    case MaterialImportColumnKind.costAmount:
      return '0';
    case MaterialImportColumnKind.isActive:
      return 'Sí';
    case MaterialImportColumnKind.dynamicAttribute:
      final attribute = column.attribute!;
      final type = attribute['data_type']?.toString();
      switch (type) {
        case 'boolean':
          return 'Sí';
        case 'integer':
          return '1';
        case 'decimal':
          return '1.0';
        case 'date':
          return '2026-01-01';
        case 'select':
        case 'multiselect':
          final options = optionsByAttribute[attribute['id']?.toString()];
          if (options == null || options.isEmpty) return '';
          return options.first['option_label']?.toString() ?? '';
        default:
          return '';
      }
  }
}

/// Valid-values / format note shown in the on-screen table and in the
/// .xlsx "Instrucciones" sheet.
String columnNotes(
  MaterialImportColumn column,
  Map<String, List<Map<String, dynamic>>> optionsByAttribute,
) {
  if (column.kind != MaterialImportColumnKind.dynamicAttribute) {
    return column.hint ?? '';
  }
  final attribute = column.attribute!;
  final type = attribute['data_type']?.toString();
  if (type == 'select' || type == 'multiselect') {
    final options = optionsByAttribute[attribute['id']?.toString()] ?? const [];
    final labels = options
        .where((o) => o['is_active'] != false)
        .map((o) => o['option_label']?.toString() ?? '')
        .where((l) => l.isNotEmpty)
        .join(', ');
    return labels.isEmpty
        ? 'Sin opciones configuradas.'
        : 'Valores válidos: $labels';
  }
  return attribute['help_text']?.toString() ?? '';
}

Uint8List buildTemplateXlsxBytes(
  List<MaterialImportColumn> columns,
  Map<String, List<Map<String, dynamic>>> optionsByAttribute,
) {
  final excel = Excel.createExcel();
  final mainSheetName = 'Materiales';
  final sheet = excel[mainSheetName];
  final headerStyle = CellStyle(bold: true);

  for (var i = 0; i < columns.length; i++) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      TextCellValue(columns[i].fileHeader),
      cellStyle: headerStyle,
    );
  }
  sheet.appendRow([
    for (final column in columns)
      TextCellValue(_exampleValueFor(column, optionsByAttribute)),
  ]);

  const instructionsSheetName = 'Instrucciones';
  final instructions = excel[instructionsSheetName];
  for (var i = 0; i < 4; i++) {
    instructions.updateCell(
      CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      TextCellValue(['Columna', 'Obligatoria', 'Tipo de dato', 'Notas'][i]),
      cellStyle: headerStyle,
    );
  }
  for (final column in columns) {
    instructions.appendRow([
      TextCellValue(column.header),
      TextCellValue(column.required ? 'Sí' : 'No'),
      TextCellValue(column.dataTypeLabel),
      TextCellValue(columnNotes(column, optionsByAttribute)),
    ]);
  }
  excel.setDefaultSheet(mainSheetName);
  // excel_plus always creates a blank "Sheet1" alongside explicitly named
  // sheets — drop it so the file only has the two sheets we built.
  if (excel.tables.containsKey('Sheet1') &&
      mainSheetName != 'Sheet1' &&
      instructionsSheetName != 'Sheet1') {
    excel.delete('Sheet1');
  }

  final bytes = excel.save();
  if (bytes == null) {
    throw StateError('No fue posible generar la plantilla .xlsx.');
  }
  return Uint8List.fromList(bytes);
}

Uint8List buildTemplateCsvBytes(List<MaterialImportColumn> columns) {
  // addBom so Excel correctly detects UTF-8 (otherwise accented characters
  // like "Código"/"Categoría" render as garbage when reopened in Excel).
  final csvCodec = Csv(addBom: true);
  final content = csvCodec.encode([
    [for (final column in columns) column.fileHeader],
    [for (final column in columns) _exampleValueFor(column, const {})],
  ]);
  return Uint8List.fromList(utf8.encode(content));
}
