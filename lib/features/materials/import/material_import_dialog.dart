import '../../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/pomgt_loading.dart';
import '../../../core/widgets/scroll_to_top.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/pomgt_theme.dart';
import '../../../core/utils/app_notice.dart';
import '../../../core/utils/error_copy.dart';
import '../../../data/repositories/lookup_repository.dart';
import '../../../data/repositories/material_repository.dart';
import '../dynamic_material_attributes.dart';
import 'material_import_columns.dart';
import 'material_import_parser.dart';

enum _ImportOutcomeStatus { created, failed }

class _ImportOutcome {
  const _ImportOutcome(this.rowNumber, this.sku, this.status, {this.error});
  final int rowNumber;
  final String sku;
  final _ImportOutcomeStatus status;
  final String? error;
}

/// Bulk-imports materials from a .xlsx/.csv file, scoped to one material
/// type at a time (each type has its own spec columns via the dynamic
/// material attributes system). Three steps: pick the type, download the
/// matching template and upload a filled file, review validation results
/// and import.
class MaterialImportDialog extends StatefulWidget {
  const MaterialImportDialog({super.key});

  @override
  State<MaterialImportDialog> createState() => _MaterialImportDialogState();
}

class _MaterialImportDialogState extends State<MaterialImportDialog> {
  int _step = 0;
  static const _stepLabels = [
    'Tipo de material',
    'Plantilla y carga',
    'Revisión',
  ];

  late Future<List<Map<String, dynamic>>> _typesFuture;

  String? _materialTypeId;
  String? _materialTypeLabel;
  bool _loadingColumns = false;
  List<Map<String, dynamic>> _attributes = const [];
  Map<String, List<Map<String, dynamic>>> _optionsByAttribute = {};
  List<MaterialImportColumn> _columns = const [];

  bool _processingFile = false;
  String? _fileName;
  String? _fileError;
  MaterialImportValidationResult? _validation;

  bool _importing = false;
  List<_ImportOutcome>? _results;

  final _templateScroll = ScrollController();
  final _errorsScroll = ScrollController();

  MaterialRepository get _materials => context.read<MaterialRepository>();
  LookupRepository get _lookups => context.read<LookupRepository>();

  @override
  void initState() {
    super.initState();
    _typesFuture = _materials.materialTypes();
  }

  @override
  void dispose() {
    _templateScroll.dispose();
    _errorsScroll.dispose();
    super.dispose();
  }

  Future<void> _selectType(Map<String, dynamic> type) async {
    setState(() {
      _materialTypeId = type['id'].toString();
      _materialTypeLabel = type['name']?.toString() ?? type['code']?.toString();
      _loadingColumns = true;
    });
    try {
      final attributes = await _materials.attributes(_materialTypeId!);
      final selectableIds = attributes
          .where(
            (a) =>
                a['data_type'] == 'select' || a['data_type'] == 'multiselect',
          )
          .map((a) => a['id'].toString())
          .toSet();
      final options = await _materials.optionsForAttributes(selectableIds);
      final optionsByAttribute = <String, List<Map<String, dynamic>>>{};
      for (final option in options) {
        final id = option['attribute_definition_id']?.toString();
        if (id == null) continue;
        optionsByAttribute.putIfAbsent(id, () => []).add(option);
      }
      if (!mounted) return;
      setState(() {
        _attributes = attributes;
        _optionsByAttribute = optionsByAttribute;
        _columns = buildImportColumns(attributes);
        _loadingColumns = false;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingColumns = false);
      showPomgtSnackBar(
        context,
        ErrorCopy.message(
          e,
          fallback: 'No fue posible cargar el tipo de material.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _downloadTemplate({required bool xlsx}) async {
    try {
      final bytes = xlsx
          ? buildTemplateXlsxBytes(_columns, _optionsByAttribute)
          : buildTemplateCsvBytes(_columns);
      final slug = (_materialTypeLabel ?? 'material').toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '_',
      );
      final filename = 'plantilla_materiales_$slug.${xlsx ? 'xlsx' : 'csv'}';
      await FilePicker.saveFile(
        fileName: filename,
        bytes: bytes,
        mimeType: xlsx
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'text/csv',
      );
    } catch (e) {
      if (!mounted) return;
      showPomgtSnackBar(
        context,
        ErrorCopy.message(e, fallback: 'No fue posible generar la plantilla.'),
        isError: true,
      );
    }
  }

  Future<void> _pickAndValidateFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
    );
    if (file == null || !mounted) return;
    setState(() {
      _processingFile = true;
      _fileName = file.name;
      _fileError = null;
      _validation = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final rawRows = parseImportFile(bytes, file.name);
      final results = await Future.wait([
        _materials.materials(),
        _lookups.rows('units_of_measure'),
        _materials.categories(),
        _lookups.rows('currencies'),
      ]);
      final existingSkus = results[0]
          .map((m) => m['sku']?.toString().toUpperCase())
          .whereType<String>()
          .toSet();
      final validation = validateImportRows(
        rawRows: rawRows,
        columns: _columns,
        materialTypeId: _materialTypeId!,
        attributes: _attributes,
        optionsByAttribute: _optionsByAttribute,
        existingSkus: existingSkus,
        units: results[1],
        categories: results[2],
        currencies: results[3],
      );
      if (!mounted) return;
      setState(() {
        _processingFile = false;
        _validation = validation;
        _step = 2;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processingFile = false;
        _fileError = ErrorCopy.message(
          e,
          fallback: 'No fue posible leer el archivo.',
        );
      });
    }
  }

  Future<void> _import() async {
    final validation = _validation;
    if (validation == null || validation.hasBlockingErrors) return;
    setState(() {
      _importing = true;
      _results = null;
    });
    final outcomes = <_ImportOutcome>[];
    for (final row in validation.rows) {
      try {
        await _materials.createMaterial(
          material: row.material,
          attributeValues: materialAttributePayload(
            _attributes,
            row.attributeValues,
            includeNulls: false,
          ),
        );
        outcomes.add(
          _ImportOutcome(row.rowNumber, row.sku, _ImportOutcomeStatus.created),
        );
      } catch (e) {
        outcomes.add(
          _ImportOutcome(
            row.rowNumber,
            row.sku,
            _ImportOutcomeStatus.failed,
            error: ErrorCopy.message(e, fallback: 'No fue posible crearlo.'),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _results = outcomes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 80).clamp(0.0, 760.0);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.cloudUpload, color: PomgtColors.ink, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('Cargar materiales · ${_stepLabels[_step]}')),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context, _results != null),
            icon: const Icon(LucideIcons.x, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: MediaQuery.sizeOf(context).height * .72,
        child: _stepBody(),
      ),
      actions: _actions(),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _typeStep();
      case 1:
        return _templateStep();
      default:
        return _reviewStep();
    }
  }

  Widget _typeStep() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _typesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PomgtLoading();
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              ErrorCopy.message(snapshot.error!),
              style: const TextStyle(color: PomgtColors.danger),
            ),
          );
        }
        final types = snapshot.data ?? const <Map<String, dynamic>>[];
        if (types.isEmpty) {
          return const Center(
            child: Text(
              'No hay tipos de material configurados todavía.',
              style: TextStyle(color: PomgtColors.muted),
            ),
          );
        }
        if (_loadingColumns) {
          return const PomgtLoading();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '¿Qué tipo de material vas a cargar? Cada tipo tiene sus propias especificaciones, así que la plantilla cambia según lo que elijas aquí.',
              style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ScrollToTopArea(
                padding: const EdgeInsets.all(10),
                builder: (context, controller) => PomgtListView.separated(
                  controller: controller,
                  itemCount: types.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final type = types[i];
                    return ListTile(
                      leading: const Icon(LucideIcons.box, size: 20),
                      title: Text(type['name']?.toString() ?? 'Tipo'),
                      subtitle: type['description'] != null
                          ? Text(type['description'].toString())
                          : null,
                      trailing: const Icon(LucideIcons.chevronRight, size: 16),
                      onTap: () => _selectType(type),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _templateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Plantilla para "${_materialTypeLabel ?? ''}"',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Text(
          'Descarga la plantilla, llénala y vuelve a subirla. Las columnas con * son obligatorias.',
          style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ScrollToTopArea(
            controller: _templateScroll,
            padding: const EdgeInsets.all(10),
            builder: (context, _) => Scrollbar(
              controller: _templateScroll,
              child: SingleChildScrollView(
                controller: _templateScroll,
                child: DataTable(
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text('Columna')),
                    DataColumn(label: Text('Obligatoria')),
                    DataColumn(label: Text('Tipo de dato')),
                    DataColumn(label: Text('Notas')),
                  ],
                  rows: [
                    for (final column in _columns)
                      DataRow(
                        cells: [
                          DataCell(Text(column.header)),
                          DataCell(Text(column.required ? 'Sí' : 'No')),
                          DataCell(Text(column.dataTypeLabel)),
                          DataCell(
                            SizedBox(
                              width: 240,
                              child: Text(
                                columnNotes(column, _optionsByAttribute),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _downloadTemplate(xlsx: true),
              icon: const Icon(LucideIcons.fileText, size: 16),
              label: const Text('Descargar plantilla .xlsx'),
            ),
            OutlinedButton.icon(
              onPressed: () => _downloadTemplate(xlsx: false),
              icon: const Icon(LucideIcons.fileText, size: 16),
              label: const Text('Descargar plantilla .csv'),
            ),
            FilledButton.icon(
              onPressed: _processingFile ? null : _pickAndValidateFile,
              icon: _processingFile
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.upload, size: 16),
              label: Text(_processingFile ? 'Leyendo…' : 'Seleccionar archivo'),
            ),
          ],
        ),
        if (_fileError != null) ...[
          const SizedBox(height: 10),
          Text(
            _fileError!,
            style: const TextStyle(color: PomgtColors.danger, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _reviewStep() {
    final results = _results;
    if (results != null) return _resultsView(results);

    final validation = _validation;
    if (validation == null) {
      return const Center(
        child: Text(
          'Sube un archivo en el paso anterior para continuar.',
          style: TextStyle(color: PomgtColors.muted),
        ),
      );
    }

    if (_importing) {
      return const PomgtLoading();
    }

    if (validation.fileError != null) {
      return _errorList(
        title: 'El archivo no se puede importar',
        messages: [validation.fileError!],
      );
    }

    final badRows = validation.rows.where((r) => !r.isValid).toList();
    if (badRows.isNotEmpty) {
      return _errorList(
        title:
            '${badRows.length} de ${validation.rows.length} fila(s) tienen problemas',
        messages: [
          for (final row in badRows)
            for (final error in row.errors)
              'Fila ${row.rowNumber} (SKU ${row.sku.isEmpty ? '—' : row.sku}): $error',
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: PomgtColors.blueSoft,
            borderRadius: PomgtRadii.borderSm,
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.circleCheck,
                color: PomgtColors.blue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${validation.rows.length} material(es) listos para importar desde "$_fileName".',
                  style: const TextStyle(
                    color: PomgtColors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ScrollToTopArea(
            padding: const EdgeInsets.all(10),
            builder: (context, controller) => PomgtListView.separated(
              controller: controller,
              itemCount: validation.rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final row = validation.rows[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(LucideIcons.box, size: 18),
                  title: Text('${row.sku} · ${row.material['name'] ?? ''}'),
                  subtitle: Text('Fila ${row.rowNumber}'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorList({required String title, required List<String> messages}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.triangleAlert,
              color: PomgtColors.danger,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: PomgtColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Corrige el archivo y vuelve a subirlo — nada se importa hasta que todo esté correcto.',
          style: TextStyle(color: PomgtColors.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ScrollToTopArea(
            controller: _errorsScroll,
            padding: const EdgeInsets.all(10),
            builder: (context, _) => Scrollbar(
              controller: _errorsScroll,
              child: PomgtListView.separated(
                controller: _errorsScroll,
                itemCount: messages.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    messages[i],
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultsView(List<_ImportOutcome> outcomes) {
    final created = outcomes
        .where((o) => o.status == _ImportOutcomeStatus.created)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$created de ${outcomes.length} material(es) importados.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ScrollToTopArea(
            padding: const EdgeInsets.all(10),
            builder: (context, controller) => PomgtListView.separated(
              controller: controller,
              itemCount: outcomes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final outcome = outcomes[i];
                final ok = outcome.status == _ImportOutcomeStatus.created;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    ok ? LucideIcons.circleCheck : LucideIcons.circleX,
                    color: ok ? PomgtColors.success : PomgtColors.danger,
                    size: 20,
                  ),
                  title: Text('Fila ${outcome.rowNumber} · ${outcome.sku}'),
                  subtitle: ok
                      ? const Text('Importado.')
                      : Text(outcome.error ?? ''),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _actions() {
    if (_results != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Listo'),
        ),
      ];
    }
    final back = TextButton(
      onPressed: _step == 0
          ? () => Navigator.pop(context, false)
          : () => setState(() => _step -= 1),
      child: Text(_step == 0 ? 'Cancelar' : 'Atrás'),
    );
    if (_step < 2) return [back];

    final validation = _validation;
    final canImport =
        validation != null && !validation.hasBlockingErrors && !_importing;
    return [
      back,
      FilledButton.icon(
        onPressed: canImport ? _import : null,
        icon: _importing
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.check, size: 16),
        label: Text(_importing ? 'Importando…' : 'Importar'),
      ),
    ];
  }
}
