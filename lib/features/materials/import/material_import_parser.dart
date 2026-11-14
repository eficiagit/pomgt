import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_plus/excel_plus.dart';

import '../dynamic_material_attributes.dart';
import 'material_import_columns.dart';

/// Reads an uploaded .xlsx/.xls/.csv file into raw string rows (header row
/// included, every cell stringified) — the two formats converge here so the
/// rest of the importer never needs to know which one was uploaded.
List<List<String>> parseImportFile(Uint8List bytes, String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.csv')) {
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    final rows = Csv().decode(content);
    return [
      for (final row in rows)
        [for (final cell in row) cell?.toString().trim() ?? ''],
    ];
  }
  if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const [];
    final sheet = workbook.tables.containsKey('Materiales')
        ? workbook.tables['Materiales']!
        : workbook.tables.values.first;
    return [
      for (final row in sheet.rows)
        [for (final cell in row) cell?.value?.toString().trim() ?? ''],
    ];
  }
  throw const FormatException(
    'Formato no soportado. Sube un archivo .xlsx o .csv.',
  );
}

String _normalize(String value) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const to = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final buffer = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i == -1 ? ch : to[i].toLowerCase());
  }
  return buffer.toString().replaceAll(RegExp(r'\s+\*$'), '').trim();
}

bool? _parseBool(String raw) {
  final value = _normalize(raw);
  if (value.isEmpty) return null;
  if (['si', 'sí', 'true', '1', 'yes', 'x'].contains(value)) return true;
  if (['no', 'false', '0'].contains(value)) return false;
  return null;
}

/// One validated (or not) spreadsheet row.
class MaterialImportRow {
  MaterialImportRow({
    required this.rowNumber,
    required this.sku,
    required this.material,
    required this.attributeValues,
    required this.errors,
  });

  /// 1-based row number as it appears in the spreadsheet (header is row 1).
  final int rowNumber;
  final String sku;
  final Map<String, dynamic> material;
  final Map<String, dynamic> attributeValues;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class MaterialImportValidationResult {
  const MaterialImportValidationResult({required this.rows, this.fileError});
  final List<MaterialImportRow> rows;

  /// Set when the file itself can't be processed at all (missing required
  /// columns, empty file) — in that case [rows] is always empty.
  final String? fileError;

  bool get hasBlockingErrors =>
      fileError != null || rows.isEmpty || rows.any((r) => !r.isValid);
}

/// Validates every row of an already-parsed file against [columns] for the
/// selected material type. Collects every problem found (not just the
/// first) so the user can fix everything in one pass.
MaterialImportValidationResult validateImportRows({
  required List<List<String>> rawRows,
  required List<MaterialImportColumn> columns,
  required String materialTypeId,
  required List<Map<String, dynamic>> attributes,
  required Map<String, List<Map<String, dynamic>>> optionsByAttribute,
  required Set<String> existingSkus,
  required List<Map<String, dynamic>> units,
  required List<Map<String, dynamic>> categories,
  required List<Map<String, dynamic>> currencies,
}) {
  if (rawRows.isEmpty) {
    return const MaterialImportValidationResult(
      rows: [],
      fileError: 'El archivo está vacío.',
    );
  }

  final header = rawRows.first;
  final headerIndex = <int, MaterialImportColumn>{};
  final missingRequired = <String>[];
  for (final column in columns) {
    final idx = header.indexWhere(
      (h) => _normalize(h) == _normalize(column.header),
    );
    if (idx == -1) {
      if (column.required) missingRequired.add(column.header);
      continue;
    }
    headerIndex[idx] = column;
  }
  if (missingRequired.isNotEmpty) {
    return MaterialImportValidationResult(
      rows: const [],
      fileError: 'Faltan columnas obligatorias: ${missingRequired.join(', ')}.',
    );
  }

  final unitsByCode = {
    for (final u in units) (u['code']?.toString() ?? '').toUpperCase(): u,
  };
  final categoriesByCode = {
    for (final c in categories) (c['code']?.toString() ?? '').toUpperCase(): c,
  };
  final currenciesByCode = {
    for (final c in currencies) (c['code']?.toString() ?? '').toUpperCase(): c,
  };

  final seenSkus = <String>{};
  final rows = <MaterialImportRow>[];

  for (var i = 1; i < rawRows.length; i++) {
    final raw = rawRows[i];
    if (raw.every((cell) => cell.trim().isEmpty)) continue;
    final rowNumber = i + 1;
    final errors = <String>[];
    final material = <String, dynamic>{'material_type_id': materialTypeId};
    final attrValues = <String, dynamic>{};
    var sku = '';

    String cellAt(int index) => index < raw.length ? raw[index].trim() : '';

    for (final entry in headerIndex.entries) {
      final column = entry.value;
      final cell = cellAt(entry.key);
      switch (column.kind) {
        case MaterialImportColumnKind.sku:
          sku = cell;
          if (sku.isEmpty) {
            errors.add('SKU es requerido.');
          } else {
            final key = sku.toUpperCase();
            if (existingSkus.contains(key)) {
              errors.add('El SKU "$sku" ya existe en el catálogo.');
            } else if (!seenSkus.add(key)) {
              errors.add('El SKU "$sku" está repetido en el archivo.');
            }
            material['sku'] = sku;
          }
        case MaterialImportColumnKind.name:
          if (cell.isEmpty) errors.add('Nombre es requerido.');
          material['name'] = cell;
        case MaterialImportColumnKind.description:
          if (cell.isNotEmpty) material['description'] = cell;
        case MaterialImportColumnKind.materialCategoryCode:
          if (cell.isNotEmpty) {
            final match = categoriesByCode[cell.toUpperCase()];
            if (match == null) {
              errors.add('La categoría "$cell" no existe.');
            } else {
              material['material_category_id'] = match['id'];
            }
          }
        case MaterialImportColumnKind.baseUomCode:
          if (cell.isEmpty) {
            errors.add('Unidad base es requerida.');
          } else {
            final match = unitsByCode[cell.toUpperCase()];
            if (match == null) {
              errors.add('La unidad "$cell" no existe.');
            } else {
              material['base_uom_id'] = match['id'];
            }
          }
        case MaterialImportColumnKind.costCurrencyCode:
          if (cell.isNotEmpty) {
            final match = currenciesByCode[cell.toUpperCase()];
            if (match == null) {
              errors.add('La moneda "$cell" no existe.');
            } else {
              material['standard_cost_currency_code'] = match['code'];
            }
          }
        case MaterialImportColumnKind.costAmount:
          if (cell.isNotEmpty) {
            final parsed = num.tryParse(cell.replaceAll(',', ''));
            if (parsed == null) {
              errors.add('Costo estándar debe ser un número.');
            } else {
              material['standard_cost'] = parsed;
            }
          }
        case MaterialImportColumnKind.isActive:
          material['is_active'] = _parseBool(cell) ?? true;
        case MaterialImportColumnKind.dynamicAttribute:
          final attribute = column.attribute!;
          final id = attribute['id'].toString();
          final type = attribute['data_type']?.toString();
          switch (type) {
            case 'boolean':
              attrValues[id] = _parseBool(cell) ?? false;
            case 'multiselect':
              final parts = cell
                  .split(RegExp(r'[,;]'))
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final options = optionsByAttribute[id] ?? const [];
              final resolved = <String>[];
              for (final part in parts) {
                final match = options.where(
                  (o) =>
                      _normalize(o['option_label']?.toString() ?? '') ==
                          _normalize(part) ||
                      _normalize(o['option_value']?.toString() ?? '') ==
                          _normalize(part),
                );
                if (match.isEmpty) {
                  errors.add(
                    '${column.header}: "$part" no es una opción válida.',
                  );
                } else {
                  resolved.add(match.first['option_value']?.toString() ?? part);
                }
              }
              attrValues[id] = resolved;
            case 'select':
              if (cell.isNotEmpty) {
                final options = optionsByAttribute[id] ?? const [];
                final match = options.where(
                  (o) =>
                      _normalize(o['option_label']?.toString() ?? '') ==
                          _normalize(cell) ||
                      _normalize(o['option_value']?.toString() ?? '') ==
                          _normalize(cell),
                );
                if (match.isEmpty) {
                  errors.add(
                    '${column.header}: "$cell" no es una opción válida.',
                  );
                } else {
                  attrValues[id] =
                      match.first['option_value']?.toString() ?? cell;
                }
              }
            default:
              attrValues[id] = cell;
          }
      }
    }

    final attributeError = materialAttributeValidationError(
      attributes,
      attrValues,
    );
    if (attributeError != null) errors.add(attributeError);

    rows.add(
      MaterialImportRow(
        rowNumber: rowNumber,
        sku: sku,
        material: material,
        attributeValues: attrValues,
        errors: errors,
      ),
    );
  }

  return MaterialImportValidationResult(rows: rows);
}
