import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/feature_controllers.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return RecordWorkspace(
      title: 'Documentos',
      help:
          'Repositorio documental versionado. Un documento puede tener múltiples versiones y vincularse a clientes, productos, revisiones, pedidos, estructuras de fabricación, rutas de fabricación, órdenes de producción, entregas y calidad.',
      masterTable: 'documents',
      controller: context.watch<DocumentsController>(),
      createLabel: 'Nuevo documento',
      detailBuilder: (context, row) => _DocumentDetail(document: row),
    );
  }
}

class _DocumentDetail extends StatelessWidget {
  const _DocumentDetail({required this.document});
  final Map<String, dynamic> document;
  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = document['id'].toString();
    Future<void> edit() async {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EntityFormDialog(
          spec: Phase1Schema.tables['documents']!,
          repository: generic,
          lookups: lookups,
          original: document,
        ),
      );
      if (changed == true && context.mounted) {
        context.read<DocumentsController>().refresh();
      }
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          DetailHeader(
            icon: CupertinoIcons.doc_text,
            title: document['title']?.toString() ?? 'Documento',
            subtitle:
                '${document['document_code'] ?? 'Sin código'} · ${document['document_type']} · ${UiCopy.enumLabel(document['confidentiality']?.toString() ?? '')}',
            status: document['status']?.toString(),
            help:
                'Documento lógico. Las versiones almacenan el archivo real; los vínculos determinan dónde se utiliza y opcionalmente fijan una versión específica.',
            onEdit: edit,
          ),
          const Divider(height: 1),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: PomgtColors.surfaceAlt,
                      borderRadius: PomgtRadii.borderSm,
                    ),
                    child: const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      dividerColor: Colors.transparent,
                      indicatorColor: PomgtColors.blue,
                      indicator: BoxDecoration(
                        color: PomgtColors.canvas,
                        borderRadius: PomgtRadii.borderSm,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: PomgtColors.ink,
                      unselectedLabelColor: PomgtColors.muted,
                      tabs: [
                        HelpTab(
                          label: 'Información',
                          help: 'Metadatos generales del documento lógico.',
                        ),
                        HelpTab(
                          label: 'Versiones',
                          help:
                              'Archivos cargados y su historial de versiones inmutables.',
                        ),
                        HelpTab(
                          label: 'Vínculos',
                          help:
                              'Entidades de POMGT donde se utiliza el documento y la versión que queda fijada.',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _DocumentSummary(document: document),
                        _VersionsPanel(documentId: id),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: EntityCrudPanel(
                            table: 'document_links',
                            repository: generic,
                            lookups: lookups,
                            fixedValues: {'document_id': id},
                            title: 'Vínculos',
                            description:
                                'Relaciona este documento con una entidad de POMGT. Si fijas una versión, ese vínculo seguirá apuntando exactamente a esa versión aun cuando después se suban archivos nuevos.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary({required this.document});
  final Map<String, dynamic> document;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Información documental',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 7),
            const InfoTip(
              'Metadatos del documento, independientes de la versión del archivo.',
            ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 38,
          runSpacing: 22,
          children: [
            _KV('Código', '${document['document_code'] ?? '—'}'),
            _KV('Tipo', '${document['document_type']}'),
            _KV(
              'Estado',
              UiCopy.enumLabel(document['status']?.toString() ?? ''),
            ),
            _KV(
              'Confidencialidad',
              UiCopy.enumLabel(document['confidentiality']?.toString() ?? ''),
            ),
          ],
        ),
        if (document['description'] != null) ...[
          const SizedBox(height: 30),
          Text(
            document['description'].toString(),
            style: const TextStyle(
              color: PomgtColors.secondaryInk,
              height: 1.5,
            ),
          ),
        ],
      ],
    ),
  );
}

class _VersionsPanel extends StatefulWidget {
  const _VersionsPanel({required this.documentId});
  final String documentId;
  @override
  State<_VersionsPanel> createState() => _VersionsPanelState();
}

class _VersionsPanelState extends State<_VersionsPanel> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      context.read<DocumentRepository>().service.list(
        'document_versions',
        equals: {'document_id': widget.documentId},
        orderBy: 'version_no',
        ascending: false,
      );
  void reload() {
    setState(() {
      future = _load();
    });
  }

  Future<void> upload() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
    final repository = context.read<DocumentRepository>();
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      showPomgtSnackBar(
        context,
        'No fue posible leer el archivo seleccionado.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    final meta = await showDialog<_VersionMeta>(
      context: context,
      builder: (_) => _VersionDialog(filename: file.name),
    );
    if (meta == null || !mounted) return;
    try {
      await repository.uploadVersion(
        documentId: widget.documentId,
        bytes: bytes,
        filename: file.name,
        mimeType: _mime(file.extension),
        versionLabel: meta.label,
        changeNotes: meta.notes,
      );
      if (!mounted) return;
      showPomgtSnackBar(context, 'Nueva versión cargada.');
      reload();
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      }
    }
  }

  Future<void> open(Map<String, dynamic> row) async {
    try {
      final url = await context.read<DocumentRepository>().storage.signedUrl(
        row['object_path'].toString(),
      );
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Versiones del archivo',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 7),
            const InfoTip(
              'Cada carga crea una versión inmutable. Una sola versión se marca como actual; los vínculos pueden fijar cualquier versión anterior.',
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: upload,
              icon: const Icon(CupertinoIcons.cloud_upload, size: 17),
              label: const Text('Subir versión'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    ErrorCopy.message(
                      snap.error!,
                      fallback: 'No fue posible cargar las versiones.',
                    ),
                    style: const TextStyle(color: PomgtColors.danger),
                  ),
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const Center(
                  child: Text(
                    'Todavía no hay archivos. Sube la primera versión.',
                    style: TextStyle(color: PomgtColors.muted),
                  ),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    leading: const Icon(CupertinoIcons.doc, size: 20),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            r['original_filename']?.toString() ?? 'Archivo',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (r['is_current'] == true) ...[
                          const SizedBox(width: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            color: PomgtColors.blueSoft,
                            child: const Text(
                              'Actual',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: PomgtColors.blue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${r['version_label'] ?? 'v${r['version_no']}'} · ${_size(r['size_bytes'])}${r['change_notes'] == null ? '' : ' · ${r['change_notes']}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Abrir archivo',
                      onPressed: () => open(r),
                      icon: const Icon(
                        CupertinoIcons.arrow_up_right_square,
                        size: 18,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );

  static String? _mime(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'svg':
        return 'image/svg+xml';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  static String _size(dynamic value) {
    final b = (value as num?)?.toDouble() ?? 0;
    if (b < 1024) return '${b.toInt()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _VersionMeta {
  const _VersionMeta(this.label, this.notes);
  final String? label;
  final String? notes;
}

class _VersionDialog extends StatefulWidget {
  const _VersionDialog({required this.filename});
  final String filename;
  @override
  State<_VersionDialog> createState() => _VersionDialogState();
}

class _VersionDialogState extends State<_VersionDialog> {
  final label = TextEditingController();
  final notes = TextEditingController();
  @override
  void dispose() {
    label.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 620;
    return AlertDialog(
      title: const Text('Nueva versión'),
      content: SizedBox(
        width: compact ? width - 56 : 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.filename,
                style: const TextStyle(color: PomgtColors.muted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: label,
                decoration: const InputDecoration(
                  labelText: 'Etiqueta de versión',
                  hintText: 'Ej. Rev C',
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notas del cambio',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _VersionMeta(
              label.text.trim().isEmpty ? null : label.text.trim(),
              notes.text.trim().isEmpty ? null : notes.text.trim(),
            ),
          ),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PomgtColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: PomgtColors.ink,
          ),
        ),
      ],
    ),
  );
}
