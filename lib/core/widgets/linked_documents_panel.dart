import 'motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'pomgt_loading.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/document_repository.dart';
import '../theme/pomgt_theme.dart';
import '../utils/app_notice.dart';
import '../utils/error_copy.dart';
import 'info_tip.dart';
import 'pomgt_button.dart';
import 'scroll_to_top.dart';

class LinkedDocumentsPanel extends StatefulWidget {
  const LinkedDocumentsPanel({
    super.key,
    required this.entityField,
    required this.entityId,
    required this.title,
    required this.help,
    this.documentTypes = const [
      'Constancia fiscal',
      'Orden de compra',
      'Especificación',
      'Diseño / arte',
      'Contrato',
      'Captura de mensaje',
      'Otro',
    ],
  });

  final String entityField;
  final String entityId;
  final String title;
  final String help;
  final List<String> documentTypes;

  @override
  State<LinkedDocumentsPanel> createState() => _LinkedDocumentsPanelState();
}

class _LinkedDocumentsPanelState extends State<LinkedDocumentsPanel> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _uploading = false;

  DocumentRepository get repository => context.read<DocumentRepository>();

  @override
  void initState() {
    super.initState();
    _future = Future.value(const []);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = repository.linkedDocuments(
        entityField: widget.entityField,
        entityId: widget.entityId,
      );
    });
  }

  Future<void> _upload() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
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
    final meta = await showPomgtDialog<_DocumentMeta>(
      context: context,
      builder: (_) =>
          _DocumentMetaDialog(filename: file.name, types: widget.documentTypes),
    );
    if (meta == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await repository.createUploadAndLink(
        entityField: widget.entityField,
        entityId: widget.entityId,
        title: meta.title,
        documentType: meta.type,
        description: meta.description,
        bytes: bytes,
        filename: file.name,
        mimeType: _mime(file.extension),
      );
      if (!mounted) return;
      showPomgtSnackBar(context, 'Archivo cargado correctamente.');
      _reload();
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _preview(Map<String, dynamic> row) async {
    final path = row['object_path']?.toString();
    if (path == null || path.isEmpty) return;
    try {
      final url = await repository.storage.signedUrl(path);
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (e) {
      if (mounted) {
        showPomgtSnackBar(context, ErrorCopy.message(e), isError: true);
      }
    }
  }

  Future<void> _unlink(Map<String, dynamic> row) async {
    final ok = await showPomgtDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: pomgtDialogTitle(
          context,
          'Quitar documento',
          onClose: () => Navigator.pop(context, false),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: const Text(
            'El archivo dejará de aparecer en esta sección. El documento original y su historial de versiones se conservarán en el repositorio documental.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar vínculo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repository.unlink(row['link_id'].toString());
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 7),
                  InfoTip(widget.help),
                ],
              ),
              PomgtButton(
                label: _uploading ? 'Cargando…' : 'Subir archivo',
                icon: LucideIcons.cloudUpload,
                busy: _uploading,
                onPressed: _uploading ? null : _upload,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const PomgtLoading();
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      ErrorCopy.message(
                        snapshot.error!,
                        fallback: 'No fue posible cargar los documentos.',
                      ),
                      style: const TextStyle(color: PomgtColors.danger),
                    ),
                  );
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.file,
                          size: 30,
                          color: PomgtColors.subtle,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Todavía no hay documentos',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Carga constancias, órdenes, capturas, diseños u otros archivos relacionados.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PomgtColors.muted),
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: _upload,
                          icon: const Icon(LucideIcons.plus, size: 16),
                          label: const Text('Agregar primer archivo'),
                        ),
                      ],
                    ),
                  );
                }
                return ScrollToTopArea(
                  padding: const EdgeInsets.all(10),
                  builder: (context, controller) => PomgtListView.separated(
                    controller: controller,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.fileText,
                              size: 21,
                              color: PomgtColors.secondaryInk,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row['title']?.toString() ??
                                        row['original_filename']?.toString() ??
                                        'Documento',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${row['document_type'] ?? 'Documento'} · ${row['original_filename'] ?? 'Sin archivo'} · ${_size(row['size_bytes'])}',
                                    style: const TextStyle(
                                      color: PomgtColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _preview(row),
                              icon: const Icon(LucideIcons.eye, size: 16),
                              label: const Text('Previsualizar'),
                            ),
                            PopupMenuButton<String>(
                              popUpAnimationStyle: PomgtMotion.style(context),
                              tooltip: 'Más acciones',
                              onSelected: (v) {
                                if (v == 'unlink') _unlink(row);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'unlink',
                                  child: Text('Quitar de esta sección'),
                                ),
                              ],
                              icon: const Icon(LucideIcons.ellipsis, size: 18),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
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

class _DocumentMeta {
  const _DocumentMeta({
    required this.title,
    required this.type,
    this.description,
  });
  final String title;
  final String type;
  final String? description;
}

class _DocumentMetaDialog extends StatefulWidget {
  const _DocumentMetaDialog({required this.filename, required this.types});
  final String filename;
  final List<String> types;
  @override
  State<_DocumentMetaDialog> createState() => _DocumentMetaDialogState();
}

class _DocumentMetaDialogState extends State<_DocumentMetaDialog> {
  late final TextEditingController title;
  final description = TextEditingController();
  late String type;

  @override
  void initState() {
    super.initState();
    final dot = widget.filename.lastIndexOf('.');
    title = TextEditingController(
      text: dot > 0 ? widget.filename.substring(0, dot) : widget.filename,
    );
    type = widget.types.first;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 640;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.filePlus, size: 22, color: PomgtColors.ink),
          const SizedBox(width: 10),
          const Expanded(child: Text('Información del documento')),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: compact ? width - 56 : 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Título *',
                  hintText: 'Escribe un título para el documento',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                errorBuilder: pomgtValidationMessage,
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de documento *',
                ),
                items: widget.types
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => type = v ?? type),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción / notas',
                  hintText: 'Contexto adicional sobre este documento…',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.filename,
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                  ),
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
          onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _DocumentMeta(
                title: title.text.trim(),
                type: type,
                description: description.text.trim().isEmpty
                    ? null
                    : description.text.trim(),
              ),
            );
          },
          child: const Text('Cargar archivo'),
        ),
      ],
    );
  }
}
