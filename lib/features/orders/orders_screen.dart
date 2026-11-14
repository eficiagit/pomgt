import '../../core/widgets/motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/pomgt_loading.dart';

import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../controllers/feature_controllers.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/categorized_picker.dart';
import '../../core/widgets/detail_sections.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../core/widgets/number_input.dart';
import '../../core/widgets/record_workspace.dart';
import '../../core/widgets/scroll_to_top.dart';
import '../../core/widgets/selected_product_row.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/bom_repository.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/routing_repository.dart';
import '../bom/link_bom_dialog.dart';
import '../customers/customer_form_dialog.dart';
import '../routings/link_routing_dialog.dart';
import '../../core/widgets/pomgt_date_picker.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RecordWorkspace(
      title: 'Pedidos',
      titleIcon: LucideIcons.fileText,
      help: 'Registra necesidades provenientes de un pedido, una OC del cliente, una orden interna, un pronóstico, una reposición o producción para inventario. Cada línea puede liberarse a una o varias órdenes de producción.',
      masterTable: 'customer_orders',
      controller: context.watch<OrdersController>(),
      createLabel: 'Nuevo pedido',
      createDialogBuilder: (_) => const _CreateOrderWizardDialog(),
      editDialogBuilder: (_, row) => _OrderFormDialog(original: row),
      detailBuilder: (context, row) => _OrderDetail(order: row),
      showRowActions: true,
      rowLeadingIcon: LucideIcons.fileText,
      plainRowStatus: true,
      onDelete: (row) =>
          context.read<OrderRepository>().deleteOrder(row['id'].toString()),
    );
  }
}

/// A picked-but-not-yet-uploaded file for step 3 of [_CreateOrderWizardDialog].
class _PendingFile {
  _PendingFile({required this.name, required this.bytes, this.mimeType})
    // pdfrx caches/identifies a loaded document by this sourceName (see
    // PdfDocumentRefData), not by object identity of the bytes — unlike the
    // `printing` package's PdfPreview, which restarted (and briefly went
    // blank) on every rebuild because it compared the `build` closure by
    // reference. A unique, stable sourceName per file means pdfrx keeps
    // reusing the same decoded document across rebuilds and across the two
    // simultaneous viewers (side panel + full-screen), with no flicker.
    : sourceId = '${DateTime.now().microsecondsSinceEpoch}-$name';
  final String name;
  final Uint8List bytes;
  final String? mimeType;
  final String sourceId;

  // Memoized once per file, so switching the "Texto" tab back and forth
  // doesn't re-run pdfium extraction every time.
  Future<String>? extractedText;
}

/// Pulls the plain text out of a PDF via pdfium (pdfrx), independent of its
/// rendered page layout. Some PDFs — commonly ones exported from HTML/print
/// pipelines with tables — report wrong per-character bounding boxes to the
/// renderer, which makes the on-page selection highlight look like a
/// nonsensical block instead of following the text. The extracted string
/// itself is usually still correct even when those per-glyph boxes are not,
/// so this gives a reliable way to select/copy regardless.
Future<String> _extractPdfText(Uint8List bytes, String sourceName) async {
  await pdfrxFlutterInitialize();
  final document = await PdfDocument.openData(
    bytes,
    sourceName: sourceName,
    allowDataOwnershipTransfer: false,
  );
  try {
    final buffer = StringBuffer();
    for (final page in document.pages) {
      final text = await page.loadStructuredText();
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(text.fullText);
    }
    final result = buffer.toString().trim();
    return result.isEmpty
        ? 'No se encontró texto extraíble en este documento (puede ser una imagen escaneada).'
        : result;
  } finally {
    await document.dispose();
  }
}

String? _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1 ? null : name.substring(dot + 1);
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String? _mimeForExtension(String? ext) {
  switch (ext?.toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return null;
  }
}

/// Creates a new pedido in three steps: origin/client, one or many product
/// lines picked from a checkbox search (instead of one line at a time), and
/// finally any supporting files — all inside a single dialog. Editing an
/// existing pedido keeps using [_OrderFormDialog] plus the separate
/// Líneas/Documentos tabs in its detail view.
class _CreateOrderWizardDialog extends StatefulWidget {
  const _CreateOrderWizardDialog();

  @override
  State<_CreateOrderWizardDialog> createState() =>
      _CreateOrderWizardDialogState();
}

class _CreateOrderWizardDialogState extends State<_CreateOrderWizardDialog> {
  int _step = 0;
  final _step1FormKey = GlobalKey<FormState>();

  // Step 1 — origin and client.
  final _externalReference = TextEditingController();
  final _orderDate = TextEditingController();
  final _deliveryDate = TextEditingController();
  final _notes = TextEditingController();
  final _instructions = TextEditingController();
  String _sourceType = 'customer_order';
  String _priority = 'normal';
  String? _customerId;
  String? _contactId;
  String? _billingAddressId;
  String? _shippingAddressId;
  String? _currencyCode;
  String? _paymentTermId;

  late Future<List<List<Map<String, dynamic>>>> _baseFuture;
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _currencies = const [];
  List<Map<String, dynamic>> _paymentTerms = const [];
  List<Map<String, dynamic>> _contacts = const [];
  List<Map<String, dynamic>> _addresses = const [];

  // Step 2 — products.
  late Future<List<List<Map<String, dynamic>>>> _productsFuture;
  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _productTypes = const [];
  List<Map<String, dynamic>> _uoms = const [];
  List<Map<String, dynamic>> _boms = const [];
  List<Map<String, dynamic>> _bomRevisions = const [];
  List<Map<String, dynamic>> _routings = const [];
  List<Map<String, dynamic>> _routingRevisions = const [];
  final List<String> _selectedProductOrder = [];
  final Set<String> _selectedProductIds = {};
  final Map<String, TextEditingController> _qtyControllers = {};
  String? _lineError;

  // Step 2 — inline "crear producto nuevo" form, used while previewing an
  // attached reference document so a missing product can be registered
  // without leaving the wizard.
  bool _showNewProductForm = false;
  final _newProductFormKey = GlobalKey<FormState>();
  final _newSku = TextEditingController();
  final _newName = TextEditingController();
  String? _newCategoryId;
  String? _newProductTypeId;
  String? _newUomId;
  bool _newProductSaving = false;
  String? _newProductError;

  // Reference document(s) — attachable from step 1 onward and kept visible
  // as a side preview across every step. Also doubles as the files attached
  // in step 3 ("Documentos de respaldo"); both share this same list.
  final List<_PendingFile> _files = [];
  int _previewFileIndex = 0;
  String _documentType = 'Otro';
  static const _documentTypes = [
    'Orden de compra / OC',
    'Captura de mensaje',
    'Correo',
    'Especificación',
    'Diseño / arte',
    'Otro',
  ];

  bool _saving = false;
  String? _error;
  // Set once the order row itself is created, so a retry after a partial
  // failure (a line or a file upload) never creates a duplicate order.
  String? _createdOrderId;

  GenericRepository get _generic => context.read<GenericRepository>();
  LookupRepository get _lookups => context.read<LookupRepository>();
  DocumentRepository get _documents => context.read<DocumentRepository>();
  bool get _customerRequired =>
      _sourceType == 'customer_order' || _sourceType == 'customer_po';

  @override
  void initState() {
    super.initState();
    _orderDate.text = _wizardDate(DateTime.now());
    _baseFuture = _loadBase();
    _productsFuture = _loadProducts();
  }

  @override
  void dispose() {
    _externalReference.dispose();
    _orderDate.dispose();
    _deliveryDate.dispose();
    _notes.dispose();
    _instructions.dispose();
    _newSku.dispose();
    _newName.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<List<Map<String, dynamic>>>> _loadBase() async {
    final data = await Future.wait([
      _lookups.rows('customers', refresh: true),
      _lookups.rows('currencies'),
      _lookups.rows('payment_terms'),
    ]);
    _customers = data[0];
    _currencies = data[1];
    _paymentTerms = data[2];
    if (_currencyCode == null && _currencies.isNotEmpty) {
      final mxn = _currencies
          .where((e) => e['code']?.toString() == 'MXN')
          .toList();
      _currencyCode = (mxn.isNotEmpty ? mxn.first : _currencies.first)['code']
          ?.toString();
    }
    return data;
  }

  Future<List<List<Map<String, dynamic>>>> _loadProducts() async {
    final data = await Future.wait([
      _lookups.rows('products', refresh: true),
      _lookups.rows('product_categories'),
      _lookups.rows('product_types'),
      _lookups.rows('units_of_measure'),
      _lookups.rows('boms'),
      _lookups.rows('bom_revisions'),
      _lookups.rows('routings'),
      _lookups.rows('routing_revisions'),
    ]);
    _products = data[0]
        .where((p) => p['is_sellable'] != false && p['is_active'] != false)
        .toList();
    _categories = data[1];
    _productTypes = data[2];
    _uoms = data[3];
    _boms = data[4];
    _bomRevisions = data[5];
    _routings = data[6];
    _routingRevisions = data[7];
    _prefillNewProductDefaults();
    return data;
  }

  Set<String> get _missingBomProductIds => productIdsMissingActiveBom(
    _selectedProductOrder,
    boms: _boms,
    bomRevisions: _bomRevisions,
  );

  Set<String> get _missingRoutingProductIds => productIdsMissingActiveRouting(
    _selectedProductOrder,
    products: _products,
    routings: _routings,
    routingRevisions: _routingRevisions,
  );

  Future<void> _linkBom(Map<String, dynamic> product) async {
    final created = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LinkBomDialog(product: product, activateRevision: true),
    );
    if (created != true || !mounted) return;
    _boms = await _lookups.rows('boms', refresh: true);
    _bomRevisions = await _lookups.rows('bom_revisions', refresh: true);
    if (mounted) setState(() {});
  }

  Future<void> _linkRouting(Map<String, dynamic> product) async {
    final created = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LinkRoutingDialog(product: product),
    );
    if (created != true || !mounted) return;
    _routings = await _lookups.rows('routings', refresh: true);
    _routingRevisions = await _lookups.rows('routing_revisions', refresh: true);
    if (mounted) setState(() {});
  }

  /// Pre-selects sensible defaults for the inline "crear producto nuevo"
  /// form: the base unit defaults to "pz" when it exists (the overwhelming
  /// default for finished goods here); category and product type only
  /// auto-select when there's exactly one option — with more than one,
  /// there's a real choice to make, so they're left for the user to pick.
  void _prefillNewProductDefaults() {
    if (_categories.length == 1) {
      _newCategoryId ??= _categories.first['id']?.toString();
    }
    if (_productTypes.length == 1) {
      _newProductTypeId ??= _productTypes.first['id']?.toString();
    }
    final pz = _uoms
        .where(
          (u) =>
              const {'PZ', 'PZA'}.contains(u['code']?.toString().toUpperCase()),
        )
        .toList();
    if (pz.isNotEmpty) {
      _newUomId ??= pz.first['id']?.toString();
    } else if (_uoms.length == 1) {
      _newUomId ??= _uoms.first['id']?.toString();
    }
  }

  Future<void> _createProductInline() async {
    if (!(_newProductFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _newProductSaving = true;
      _newProductError = null;
    });
    try {
      final created = await _generic.createRow(
        Phase1Schema.tables['products']!,
        {
          'sku': _newSku.text.trim(),
          'name': _newName.text.trim(),
          'category_id': _newCategoryId,
          'product_type_catalog_id': _newProductTypeId,
          'base_uom_id': _newUomId,
          'product_type': 'finished_good',
          'owner_customer_id': _customerId,
          'is_customer_specific': _customerId != null,
          'is_manufacturable': true,
        },
      );
      _lookups.invalidate('products');
      final refreshed = await _lookups.rows('products', refresh: true);
      final id = created['id'].toString();
      if (!mounted) return;
      setState(() {
        _products = refreshed
            .where((p) => p['is_sellable'] != false && p['is_active'] != false)
            .toList();
        _selectedProductIds.add(id);
        _selectedProductOrder.add(id);
        _qtyControllers[id] = TextEditingController(text: '1');
        _showNewProductForm = false;
        _newSku.clear();
        _newName.clear();
        _newCategoryId = null;
        _newProductTypeId = null;
        _newUomId = null;
        // Defaults are cleared above for a blank form; re-applying them
        // here means every product added through this form gets the same
        // smart defaults, not just the first one.
        _prefillNewProductDefaults();
        _newProductSaving = false;
        _lineError = null;
      });
      showPomgtSnackBar(context, 'Producto creado y agregado al pedido.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _newProductError = ErrorCopy.message(
          e,
          fallback: 'No fue posible crear el producto.',
        );
        _newProductSaving = false;
      });
    }
  }

  Future<void> _loadCustomerChildren(String customerId) async {
    final results = await Future.wait([
      _generic.listRows(
        Phase1Schema.tables['customer_contacts']!,
        filters: {'customer_id': customerId},
      ),
      _generic.listRows(
        Phase1Schema.tables['customer_addresses']!,
        filters: {'customer_id': customerId},
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _contacts = results[0];
      _addresses = results[1];
      if (_contactId != null &&
          !_contacts.any((e) => e['id']?.toString() == _contactId))
        _contactId = null;
      if (_billingAddressId != null &&
          !_addresses.any((e) => e['id']?.toString() == _billingAddressId))
        _billingAddressId = null;
      if (_shippingAddressId != null &&
          !_addresses.any((e) => e['id']?.toString() == _shippingAddressId))
        _shippingAddressId = null;
    });
  }

  Future<void> _selectCustomer(String? value) async {
    setState(() {
      _customerId = value;
      _contactId = null;
      _billingAddressId = null;
      _shippingAddressId = null;
      _contacts = const [];
      _addresses = const [];
    });
    if (value == null) return;
    final match = _customers
        .where((e) => e['id']?.toString() == value)
        .toList();
    if (match.isNotEmpty) {
      final customer = match.first;
      setState(() {
        _currencyCode =
            customer['default_currency_code']?.toString() ?? _currencyCode;
        _paymentTermId = customer['payment_term_id']?.toString();
      });
    }
    await _loadCustomerChildren(value);
  }

  Future<void> _createCustomer() async {
    Map<String, dynamic>? created;
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(onSaved: (row) => created = row),
    );
    if (changed != true || !mounted || created == null) return;
    _lookups.invalidate('customers');
    _customers = await _lookups.rows('customers', refresh: true);
    await _selectCustomer(created!['id']?.toString());
    if (mounted) setState(() {});
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showPomgtDatePicker(
      context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.text = _wizardDate(picked);
  }

  Map<String, dynamic>? _addressSnapshot(String? id) {
    if (id == null) return null;
    final rows = _addresses.where((e) => e['id']?.toString() == id).toList();
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row.remove('created_at');
    row.remove('updated_at');
    return row;
  }

  void _toggleProduct(String productId) {
    setState(() {
      if (_selectedProductIds.remove(productId)) {
        _selectedProductOrder.remove(productId);
        _qtyControllers.remove(productId)?.dispose();
      } else {
        _selectedProductIds.add(productId);
        _selectedProductOrder.add(productId);
        _qtyControllers[productId] = TextEditingController(text: '1');
      }
      _lineError = null;
    });
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;
    for (final file in result) {
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        continue;
      }
      _files.add(
        _PendingFile(
          name: file.name,
          bytes: bytes,
          mimeType: _mimeForExtension(file.extension),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _addDroppedFiles(List<DropItem> items) async {
    for (final item in items) {
      Uint8List bytes;
      try {
        bytes = await item.readAsBytes();
      } catch (_) {
        continue;
      }
      _files.add(
        _PendingFile(
          name: item.name,
          bytes: bytes,
          mimeType: item.mimeType ?? _mimeForExtension(_extensionOf(item.name)),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  bool _validateStep1() {
    if (!(_step1FormKey.currentState?.validate() ?? false)) return false;
    if (_customerRequired && _customerId == null) {
      setState(
        () => _error = 'Selecciona un cliente para este origen de pedido.',
      );
      return false;
    }
    setState(() => _error = null);
    return true;
  }

  bool _validateStep2() {
    if (_selectedProductIds.isEmpty) {
      setState(
        () => _lineError = 'Agrega al menos un producto con su cantidad.',
      );
      return false;
    }
    for (final id in _selectedProductIds) {
      final qty = parseNumberText(_qtyControllers[id]?.text);
      if (qty == null || qty <= 0) {
        setState(
          () => _lineError = 'Captura una cantidad válida para cada producto.',
        );
        return false;
      }
    }
    setState(() => _lineError = null);
    return true;
  }

  void _goNext() {
    if (_step == 0 && !_validateStep1()) return;
    if (_step == 1 && !_validateStep2()) return;
    setState(() => _step += 1);
  }

  void _goBack() => setState(() => _step -= 1);

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var orderId = _createdOrderId;
      if (orderId == null) {
        final orderValues = <String, dynamic>{
          'source_type': _sourceType,
          'customer_id': _customerId,
          'customer_contact_id': _customerId == null ? null : _contactId,
          'external_reference': _wizardNullable(_externalReference.text),
          'order_date': _orderDate.text,
          'requested_delivery_date': _wizardNullable(_deliveryDate.text),
          'status': 'draft',
          'priority': _priority,
          'currency_code': _currencyCode,
          'payment_term_id': _paymentTermId,
          'billing_address_id': _customerId == null ? null : _billingAddressId,
          'shipping_address_id': _customerId == null
              ? null
              : _shippingAddressId,
          'billing_address_snapshot': _customerId == null
              ? null
              : _addressSnapshot(_billingAddressId),
          'shipping_address_snapshot': _customerId == null
              ? null
              : _addressSnapshot(_shippingAddressId),
          'notes': _wizardNullable(_notes.text),
          'special_instructions': _wizardNullable(_instructions.text),
        };
        final orderSpec = Phase1Schema.tables['customer_orders']!;
        final order = await _generic.createRow(orderSpec, orderValues);
        orderId = order['id'].toString();
        // Recorded immediately: if a line or file fails below, retrying
        // must reuse this order instead of creating a duplicate.
        _createdOrderId = orderId;
      }

      final lineSpec = Phase1Schema.tables['customer_order_lines']!;
      // Lines that save successfully are removed from the pending list, so
      // a retry after a failure only resends what's left.
      while (_selectedProductOrder.isNotEmpty) {
        final productId = _selectedProductOrder.first;
        final product = _products
            .where((p) => p['id']?.toString() == productId)
            .toList();
        if (product.isNotEmpty) {
          final qty = parseNumberText(_qtyControllers[productId]?.text) ?? 0;
          await _generic.createRow(lineSpec, {
            'customer_order_id': orderId,
            'product_id': productId,
            'requested_quantity': qty,
            'uom_id': product.first['base_uom_id'],
            'requested_delivery_date': _wizardNullable(_deliveryDate.text),
            'discount_pct': 0,
            'tax_pct': 0,
            'line_status': 'open',
            'requirement_snapshot': const <String, dynamic>{},
          });
        }
        _selectedProductOrder.removeAt(0);
        _selectedProductIds.remove(productId);
        _qtyControllers.remove(productId)?.dispose();
      }

      while (_files.isNotEmpty) {
        final file = _files.first;
        final dot = file.name.lastIndexOf('.');
        final title = dot > 0 ? file.name.substring(0, dot) : file.name;
        await _documents.createUploadAndLink(
          entityField: 'customer_order_id',
          entityId: orderId,
          title: title,
          documentType: _documentType,
          bytes: file.bytes,
          filename: file.name,
          mimeType: file.mimeType,
        );
        _files.removeAt(0);
      }

      _lookups.invalidate('customer_orders');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _createdOrderId == null
              ? ErrorCopy.message(e)
              : '${ErrorCopy.message(e)} El pedido ya se creó; vuelve a intentar para guardar lo que falta.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _wizardDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String? _wizardNullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  String _addressLabel(Map<String, dynamic> row) {
    final pieces = <String>[
      if (row['label'] != null && row['label'].toString().trim().isNotEmpty)
        row['label'].toString(),
      if (row['line1'] != null) row['line1'].toString(),
      if (row['city'] != null) row['city'].toString(),
    ];
    return pieces.isEmpty ? 'Dirección' : pieces.join(' · ');
  }

  static const _wizardBaseWidth = 920.0;
  static const _wizardPreviewWidth = 560.0;
  static const _wizardPreviewMinWidth = 340.0;

  Future<void> _openFullPreview() async {
    var localIndex = _files.isEmpty
        ? 0
        : _previewFileIndex.clamp(0, _files.length - 1);
    await showPomgtDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 820.0),
            height: MediaQuery.sizeOf(context).height * .88,
            child: _ReferenceDocumentPreview(
              files: _files,
              activeIndex: localIndex,
              expanded: true,
              onSelect: (i) {
                localIndex = i;
                setDialogState(() {});
                setState(() => _previewFileIndex = i);
              },
              onRemove: (i) {
                setDialogState(() {});
                setState(() {
                  _files.removeAt(i);
                  if (_previewFileIndex >= _files.length) {
                    _previewFileIndex = _files.isEmpty ? 0 : _files.length - 1;
                  }
                  localIndex = _previewFileIndex;
                });
              },
              onAddFiles: () async {
                await _addFiles();
                setDialogState(() {});
              },
              onFilesDropped: (items) async {
                await _addDroppedFiles(items);
                setDialogState(() {});
              },
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final maxAvailableWidth = media.width - 48;
    // The side-by-side layout needs the left pane to stay comfortably
    // usable; below that, the preview collapses to a compact bar that opens
    // a full-screen preview instead of squeezing both panes.
    final canShowSidePane =
        maxAvailableWidth >= _wizardBaseWidth + _wizardPreviewMinWidth;
    final previewWidth = canShowSidePane
        ? (maxAvailableWidth - _wizardBaseWidth).clamp(
            _wizardPreviewMinWidth,
            _wizardPreviewWidth,
          )
        : _wizardPreviewMinWidth;
    final targetWidth =
        (canShowSidePane ? _wizardBaseWidth + previewWidth : _wizardBaseWidth)
            .clamp(0.0, maxAvailableWidth);
    final dialogHeight = (media.height * .88).clamp(420.0, media.height - 48);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedContainer(
        duration: PomgtMotion.duration(context, PomgtMotion.slow),
        curve: Curves.easeOutCubic,
        width: targetWidth,
        height: dialogHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _wizardHeader(),
                    const SizedBox(height: 16),
                    _StepIndicator(step: _step),
                    if (!canShowSidePane) ...[
                      const SizedBox(height: 14),
                      _CompactFileBar(
                        fileName: _files.isEmpty
                            ? null
                            : _files[_previewFileIndex.clamp(
                                    0,
                                    _files.length - 1,
                                  )]
                                  .name,
                        count: _files.length,
                        onView: _openFullPreview,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Expanded(child: _stepBody()),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            LucideIcons.circleAlert,
                            size: 18,
                            color: PomgtColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: PomgtColors.danger,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    _wizardActions(),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                duration: PomgtMotion.duration(context, PomgtMotion.slow),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerRight,
                widthFactor: canShowSidePane ? 1.0 : 0.0,
                child: SizedBox(
                  width: previewWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        child: _ReferenceDocumentPreview(
                          files: _files,
                          activeIndex: _files.isEmpty
                              ? 0
                              : _previewFileIndex.clamp(0, _files.length - 1),
                          onSelect: (i) =>
                              setState(() => _previewFileIndex = i),
                          onRemove: (i) => setState(() {
                            _files.removeAt(i);
                            if (_previewFileIndex >= _files.length) {
                              _previewFileIndex = _files.isEmpty
                                  ? 0
                                  : _files.length - 1;
                            }
                          }),
                          onAddFiles: _addFiles,
                          onFilesDropped: _addDroppedFiles,
                          onExpand: _openFullPreview,
                          onClose: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wizardHeader() {
    const titles = ['Origen y cliente', 'Productos', 'Documentos'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.fileText, size: 25, color: PomgtColors.ink),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nuevo pedido · ${titles[_step]}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Captura el origen, agrega uno o varios productos con su cantidad y adjunta los archivos de respaldo.',
                style: TextStyle(color: PomgtColors.muted, height: 1.4),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: const Icon(LucideIcons.x, size: 20),
        ),
      ],
    );
  }

  Widget _wizardActions() {
    final back = _step == 0
        ? TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          )
        : TextButton.icon(
            onPressed: _saving ? null : _goBack,
            icon: const Icon(LucideIcons.chevronLeft, size: 15),
            label: const Text('Atrás'),
          );
    final forward = _step < 2
        ? FilledButton.icon(
            onPressed: _saving ? null : _goNext,
            icon: const Icon(LucideIcons.chevronRight, size: 16),
            label: const Text('Continuar'),
          )
        : FilledButton.icon(
            onPressed: _saving ? null : _finish,
            icon: _saving
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.plus, size: 16),
            label: Text(_saving ? 'Guardando…' : 'Crear pedido'),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [forward, const SizedBox(height: 8), back],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [back, forward],
        );
      },
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _step1();
      case 1:
        return _step2();
      default:
        return _step3();
    }
  }

  Widget _step1() {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: _baseFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 320, child: PomgtLoading());
        }
        if (snapshot.hasError) {
          return SizedBox(
            height: 260,
            child: Center(
              child: Text(
                ErrorCopy.message(snapshot.error!),
                style: const TextStyle(color: PomgtColors.danger),
              ),
            ),
          );
        }
        return Form(
          key: _step1FormKey,
          child: ScrollToTopArea(
            padding: const EdgeInsets.all(16),
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _formSection(
                    context,
                    title: 'Origen y cliente',
                    help: 'Indica de dónde proviene la necesidad. Pedido de cliente y OC requieren cliente; orden interna, pronóstico y reposición pueden existir sin cliente.',
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 700;
                        final source = CategorizedSearchPicker(
                          label: 'Origen *',
                          hint: 'Buscar origen…',
                          value: _sourceType,
                          items: [
                            for (final value in const [
                              'customer_order',
                              'customer_po',
                              'internal_order',
                              'forecast',
                              'inventory_replenishment',
                              'make_to_stock',
                            ])
                              PickerItem(
                                id: value,
                                label: UiCopy.enumLabel(value),
                                category: 'Orígenes',
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _sourceType = value ?? _sourceType,
                          ),
                        );
                        final customer = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 20,
                                bottom: 8,
                              ),
                              child: Text(
                                _customers.isEmpty
                                    ? 'Todavía no hay clientes registrados.'
                                    : (_customerRequired
                                          ? 'Requerido para el origen seleccionado.'
                                          : 'Opcional para este origen.'),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: PomgtColors.muted),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: CategorizedSearchPicker(
                                    key: ValueKey(
                                      'customer-${_customerId ?? ''}-${_customers.length}',
                                    ),
                                    label:
                                        'Cliente${_customerRequired ? ' *' : ''}',
                                    hint: 'Buscar cliente…',
                                    value:
                                        _customers.any(
                                          (e) =>
                                              e['id']?.toString() ==
                                              _customerId,
                                        )
                                        ? _customerId
                                        : null,
                                    items: [
                                      for (final e in _customers)
                                        PickerItem(
                                          id: e['id'].toString(),
                                          label: _lookups.display(
                                            Phase1Schema.tables['customers']!,
                                            e,
                                          ),
                                          category: 'Clientes',
                                        ),
                                    ],
                                    onChanged: _selectCustomer,
                                    validator: (_) =>
                                        _customerRequired && _customerId == null
                                        ? 'Selecciona un cliente'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Agregar cliente',
                                  child: IconButton(
                                    onPressed: _createCustomer,
                                    icon: const Icon(
                                      LucideIcons.plus,
                                      size: 19,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                        if (!wide) {
                          return Column(
                            children: [
                              source,
                              const SizedBox(height: 16),
                              customer,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: source),
                            const SizedBox(width: 28),
                            Expanded(child: customer),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_customers.isEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _createCustomer,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text('Agregar el primer cliente'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  _formSection(
                    context,
                    title: 'Referencias y fechas',
                    help: 'La referencia externa es opcional. La fecha de entrega se aplicará a todas las líneas del pedido. La OC del cliente se adjunta como documento en el último paso.',
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 700;
                        final fields = <Widget>[
                          TextFormField(
                            errorBuilder: pomgtValidationMessage,
                            controller: _externalReference,
                            decoration: const InputDecoration(
                              labelText: 'Referencia externa',
                              hintText: 'Ej. folio interno o de otro sistema',
                            ),
                          ),
                          TextFormField(
                            errorBuilder: pomgtValidationMessage,
                            controller: _orderDate,
                            readOnly: true,
                            onTap: () => _pickDate(_orderDate),
                            decoration: const InputDecoration(
                              labelText: 'Fecha del pedido *',
                              hintText: 'Selecciona una fecha',
                              suffixIcon: Icon(LucideIcons.calendar, size: 17),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Selecciona la fecha'
                                : null,
                          ),
                          TextFormField(
                            errorBuilder: pomgtValidationMessage,
                            controller: _deliveryDate,
                            readOnly: true,
                            onTap: () => _pickDate(_deliveryDate),
                            decoration: const InputDecoration(
                              labelText: 'Fecha solicitada de entrega',
                              hintText: 'Selecciona una fecha',
                              helperText:
                                  'Se aplica a todas las líneas del pedido.',
                              suffixIcon: Icon(LucideIcons.calendar, size: 17),
                            ),
                          ),
                        ];
                        if (!wide)
                          return Column(children: _wizardSpaced(fields));
                        return Wrap(
                          spacing: 28,
                          runSpacing: 16,
                          children: fields
                              .map(
                                (e) => SizedBox(
                                  width: (c.maxWidth - 28) / 2,
                                  child: e,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 26),
                  _formSection(
                    context,
                    title: 'Condiciones',
                    help: 'La moneda y condición de pago se precargan desde el cliente cuando están configuradas.',
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final wide = c.maxWidth >= 700;
                        final fields = <Widget>[
                          CategorizedSearchPicker(
                            label: 'Prioridad *',
                            hint: 'Buscar prioridad…',
                            value: _priority,
                            items: [
                              for (final v in [
                                'low',
                                'normal',
                                'high',
                                'urgent',
                              ])
                                PickerItem(
                                  id: v,
                                  label: UiCopy.enumLabel(v),
                                  category: 'Prioridades',
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _priority = v ?? _priority),
                          ),
                          CategorizedSearchPicker(
                            key: ValueKey('currency-${_currencyCode ?? ''}'),
                            label: 'Moneda *',
                            hint: 'Buscar moneda…',
                            value:
                                _currencies.any(
                                  (e) => e['code']?.toString() == _currencyCode,
                                )
                                ? _currencyCode
                                : null,
                            items: [
                              for (final e in _currencies)
                                PickerItem(
                                  id: e['code'].toString(),
                                  label: _lookups.display(
                                    Phase1Schema.tables['currencies']!,
                                    e,
                                  ),
                                  category: 'Monedas',
                                ),
                            ],
                            onChanged: (v) => setState(() => _currencyCode = v),
                            validator: (v) =>
                                v == null ? 'Selecciona una moneda' : null,
                          ),
                          QuickCreateField(
                            table: 'payment_terms',
                            repository: _generic,
                            lookups: _lookups,
                            isEmpty: _paymentTerms.isEmpty,
                            onCreated: (row) => setState(() {
                              _paymentTerms = [..._paymentTerms, row];
                              _paymentTermId = row['id']?.toString();
                            }),
                            child: CategorizedSearchPicker(
                              key: ValueKey('payment-${_paymentTermId ?? ''}'),
                              label: 'Condición de pago',
                              hint: 'Buscar condición…',
                              value:
                                  _paymentTerms.any(
                                    (e) =>
                                        e['id']?.toString() == _paymentTermId,
                                  )
                                  ? _paymentTermId
                                  : null,
                              items: [
                                for (final e in _paymentTerms)
                                  PickerItem(
                                    id: e['id'].toString(),
                                    label: _lookups.display(
                                      Phase1Schema.tables['payment_terms']!,
                                      e,
                                    ),
                                    category: 'Condiciones de pago',
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _paymentTermId = v),
                            ),
                          ),
                        ];
                        if (!wide)
                          return Column(children: _wizardSpaced(fields));
                        return Wrap(
                          spacing: 28,
                          runSpacing: 16,
                          children: fields
                              .map(
                                (e) => SizedBox(
                                  width: (c.maxWidth - 28) / 2,
                                  child: e,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                  if (_customerId != null) ...[
                    const SizedBox(height: 26),
                    _formSection(
                      context,
                      title: 'Contacto y direcciones',
                      help: 'Solo se muestran contactos y direcciones del cliente seleccionado.',
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final wide = c.maxWidth >= 700;
                          final contact = CategorizedSearchPicker(
                            key: ValueKey(
                              'contact-${_contactId ?? ''}-${_contacts.length}',
                            ),
                            label: 'Contacto del cliente',
                            hint: 'Buscar contacto…',
                            value:
                                _contacts.any(
                                  (e) => e['id']?.toString() == _contactId,
                                )
                                ? _contactId
                                : null,
                            items: [
                              for (final e in _contacts)
                                PickerItem(
                                  id: e['id'].toString(),
                                  label: _lookups.display(
                                    Phase1Schema.tables['customer_contacts']!,
                                    e,
                                  ),
                                  category: 'Contactos',
                                ),
                            ],
                            onChanged: (v) => setState(() => _contactId = v),
                          );
                          Widget addressField(
                            String label,
                            String? value,
                            ValueChanged<String?> change,
                          ) => CategorizedSearchPicker(
                            key: ValueKey(
                              '$label-${value ?? ''}-${_addresses.length}',
                            ),
                            label: label,
                            hint: 'Buscar dirección…',
                            value:
                                _addresses.any(
                                  (e) => e['id']?.toString() == value,
                                )
                                ? value
                                : null,
                            items: [
                              for (final e in _addresses)
                                PickerItem(
                                  id: e['id'].toString(),
                                  label: _addressLabel(e),
                                  category: 'Direcciones',
                                ),
                            ],
                            onChanged: change,
                          );
                          final fields = <Widget>[
                            contact,
                            addressField(
                              'Dirección de facturación',
                              _billingAddressId,
                              (v) => setState(() => _billingAddressId = v),
                            ),
                            addressField(
                              'Dirección de envío',
                              _shippingAddressId,
                              (v) => setState(() => _shippingAddressId = v),
                            ),
                          ];
                          if (!wide)
                            return Column(children: _wizardSpaced(fields));
                          return Wrap(
                            spacing: 28,
                            runSpacing: 16,
                            children: fields
                                .map(
                                  (e) => SizedBox(
                                    width: (c.maxWidth - 28) / 2,
                                    child: e,
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  _formSection(
                    context,
                    title: 'Notas e instrucciones',
                    help: 'Usa notas para contexto administrativo e instrucciones especiales para producción.',
                    child: Column(
                      children: [
                        TextFormField(
                          errorBuilder: pomgtValidationMessage,
                          controller: _instructions,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Instrucciones especiales',
                            hintText: 'Indicaciones para producción…',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          errorBuilder: pomgtValidationMessage,
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Notas',
                            hintText: 'Contexto administrativo…',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  _formSection(
                    context,
                    title: 'Documento de referencia',
                    help: 'Adjunta la OC del cliente o cualquier documento con las partidas del pedido para verlo en vista previa mientras avanzas por los pasos.',
                    child: Text(
                      _files.isEmpty
                          ? 'Adjunta o arrastra un archivo en el panel de la derecha — queda visible mientras capturas los productos.'
                          : '${_files.length == 1 ? 'Documento adjunto' : '${_files.length} documentos adjuntos'}: puedes agregar más o quitarlos desde el panel de la derecha.',
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _step2() {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 320, child: PomgtLoading());
        }
        final categoryNames = {
          for (final c in _categories)
            c['id'].toString(): (c['name'] ?? '').toString(),
        };
        return ScrollToTopArea(
          padding: const EdgeInsets.all(16),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _formSection(
                  context,
                  title: 'Agregar productos',
                  help: 'Busca por SKU o nombre, marca todos los productos que necesites en esta sesión y luego captura la cantidad de cada uno.',
                  child: MultiCategorizedPicker(
                    label: 'Buscar producto',
                    hint: 'Escribe el SKU o el nombre…',
                    items: [
                      for (final p in _products)
                        PickerItem(
                          id: p['id'].toString(),
                          label: '${p['sku']} · ${p['name']}',
                          category:
                              categoryNames[p['category_id']?.toString()] ??
                              'Sin categoría',
                        ),
                    ],
                    selectedIds: _selectedProductIds,
                    onToggle: _toggleProduct,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _showNewProductForm = !_showNewProductForm,
                    ),
                    icon: Icon(
                      _showNewProductForm
                          ? LucideIcons.chevronUp
                          : LucideIcons.circlePlus,
                      size: 16,
                    ),
                    label: Text(
                      _showNewProductForm
                          ? 'Ocultar formulario'
                          : '¿No existe el producto? Créalo aquí',
                    ),
                  ),
                ),
                PomgtAnimatedSize(
                  duration: PomgtMotion.duration(context, PomgtMotion.medium),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _showNewProductForm
                      ? _newProductForm()
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 20),
                Text(
                  'Productos seleccionados (${_selectedProductOrder.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (_selectedProductOrder.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'Todavía no has agregado productos.',
                      style: TextStyle(color: PomgtColors.muted),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final id in _selectedProductOrder)
                        Builder(
                          builder: (context) {
                            final product = _products.firstWhere(
                              (p) => p['id'].toString() == id,
                              orElse: () => const {},
                            );
                            return SelectedProductRow(
                              product: product,
                              controller: _qtyControllers[id]!,
                              onRemove: () => _toggleProduct(id),
                              missingBom: _missingBomProductIds.contains(id),
                              onLinkBom: () => _linkBom(product),
                              missingRouting: _missingRoutingProductIds
                                  .contains(id),
                              onLinkRouting: () => _linkRouting(product),
                            );
                          },
                        ),
                    ],
                  ),
                if (_lineError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _lineError!,
                    style: const TextStyle(
                      color: PomgtColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _newProductForm() {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: PomgtRadii.borderMd,
        border: Border.all(color: PomgtColors.line),
      ),
      child: Form(
        key: _newProductFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.box, size: 16, color: PomgtColors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nuevo producto',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _customerId == null ? 'Se creará en el catálogo general.' : 'Se creará como producto específico del cliente seleccionado en el paso 1.',
              style: const TextStyle(color: PomgtColors.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 520;
                final sku = TextFormField(
                  errorBuilder: pomgtValidationMessage,
                  controller: _newSku,
                  decoration: const InputDecoration(
                    labelText: 'SKU *',
                    hintText: 'Ej. PROD-0001',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                );
                final name = TextFormField(
                  errorBuilder: pomgtValidationMessage,
                  controller: _newName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    hintText: 'Escribe el nombre del producto',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                );
                if (!wide) {
                  return Column(
                    children: [sku, const SizedBox(height: 14), name],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sku),
                    const SizedBox(width: 16),
                    Expanded(child: name),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            QuickCreateField(
              table: 'product_categories',
              repository: _generic,
              lookups: _lookups,
              isEmpty: _categories.isEmpty,
              onCreated: (row) => setState(() {
                _categories = [..._categories, row];
                _newCategoryId = row['id']?.toString();
              }),
              child: CategorizedSearchPicker(
                label: 'Categoría',
                hint: 'Buscar categoría…',
                value: _newCategoryId,
                items: [
                  for (final c in _categories)
                    PickerItem(
                      id: c['id'].toString(),
                      label: '${c['code']} · ${c['name']}',
                      category: 'Categorías',
                    ),
                ],
                onChanged: (v) => setState(() => _newCategoryId = v),
              ),
            ),
            const SizedBox(height: 14),
            QuickCreateField(
              table: 'product_types',
              repository: _generic,
              lookups: _lookups,
              isEmpty: _productTypes.isEmpty,
              onCreated: (row) => setState(() {
                _productTypes = [..._productTypes, row];
                _newProductTypeId = row['id']?.toString();
              }),
              child: CategorizedSearchPicker(
                label: 'Tipo de producto *',
                hint: 'Buscar tipo…',
                value: _newProductTypeId,
                items: [
                  for (final t in _productTypes)
                    PickerItem(
                      id: t['id'].toString(),
                      label: '${t['code']} · ${t['name']}',
                      category: 'Tipos de producto',
                    ),
                ],
                onChanged: (v) => setState(() => _newProductTypeId = v),
                validator: (v) => v == null ? 'Selecciona un tipo' : null,
              ),
            ),
            const SizedBox(height: 14),
            QuickCreateField(
              table: 'units_of_measure',
              repository: _generic,
              lookups: _lookups,
              isEmpty: _uoms.isEmpty,
              onCreated: (row) => setState(() {
                _uoms = [..._uoms, row];
                _newUomId = row['id']?.toString();
              }),
              child: CategorizedSearchPicker(
                label: 'Unidad base *',
                hint: 'Buscar unidad…',
                value: _newUomId,
                items: [
                  for (final u in _uoms)
                    PickerItem(
                      id: u['id'].toString(),
                      label: '${u['code']} · ${u['name']}',
                      category: 'Unidades',
                    ),
                ],
                onChanged: (v) => setState(() => _newUomId = v),
                validator: (v) => v == null ? 'Selecciona una unidad' : null,
              ),
            ),
            if (_newProductError != null) ...[
              const SizedBox(height: 10),
              Text(
                _newProductError!,
                style: const TextStyle(
                  color: PomgtColors.danger,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _newProductSaving ? null : _createProductInline,
                icon: _newProductSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.plus, size: 16),
                label: Text(_newProductSaving ? 'Creando…' : 'Crear y agregar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step3() {
    return ScrollToTopArea(
      padding: const EdgeInsets.all(16),
      builder: (context, controller) => SingleChildScrollView(
        controller: controller,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _formSection(
              context,
              title: 'Documentos de respaldo',
              help: 'Opcional. Adjunta la OC del cliente, correos, especificaciones o cualquier evidencia relacionada con el pedido.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    errorBuilder: pomgtValidationMessage,
                    initialValue: _documentType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento',
                    ),
                    items: _documentTypes
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _documentType = v ?? _documentType),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _addFiles,
                    icon: const Icon(LucideIcons.paperclip, size: 16),
                    label: const Text('Agregar archivos'),
                  ),
                  const SizedBox(height: 14),
                  if (_files.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Sin archivos adjuntos. Puedes crear el pedido y agregarlos después desde Documentos.',
                        style: TextStyle(color: PomgtColors.muted),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (var i = 0; i < _files.length; i++)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: PomgtColors.line),
                              borderRadius: PomgtRadii.borderSm,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.file,
                                  size: 17,
                                  color: PomgtColors.muted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _files[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        _fileSize(_files[i].bytes.length),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: PomgtColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Quitar',
                                  icon: const Icon(LucideIcons.x, size: 16),
                                  onPressed: () =>
                                      setState(() => _files.removeAt(i)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formSection(
    BuildContext context, {
    required String title,
    required String help,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 7),
            InfoTip(help, size: 15),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }

  static List<Widget> _wizardSpaced(List<Widget> widgets) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      if (i > 0) result.add(const SizedBox(height: 16));
      result.add(widgets[i]);
    }
    return result;
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final int step;
  static const _labels = ['Origen y cliente', 'Productos', 'Documentos'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= step ? PomgtColors.blue : PomgtColors.line,
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= step ? PomgtColors.blue : PomgtColors.surfaceAlt,
                  border: Border.all(
                    color: i <= step ? PomgtColors.blue : PomgtColors.line,
                    width: 1.5,
                  ),
                ),
                child: i < step
                    ? const Icon(
                        LucideIcons.check,
                        size: 16,
                        color: Colors.white,
                      )
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: i == step ? Colors.white : PomgtColors.muted,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                  color: i == step ? PomgtColors.ink : PomgtColors.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Compact banner shown on narrow screens instead of the side-by-side
/// preview pane, which doesn't fit. Opens the same preview full-screen.
class _CompactFileBar extends StatelessWidget {
  const _CompactFileBar({
    required this.fileName,
    required this.count,
    required this.onView,
  });
  final String? fileName;
  final int count;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final label = fileName == null
        ? 'Adjuntar documento de referencia'
        : (count > 1 ? '$fileName y ${count - 1} más' : fileName!);
    return Material(
      color: PomgtColors.blueSoft,
      borderRadius: PomgtRadii.borderSm,
      child: InkWell(
        borderRadius: PomgtRadii.borderSm,
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                fileName == null ? LucideIcons.paperclip : LucideIcons.fileText,
                size: 16,
                color: PomgtColors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: PomgtColors.blue,
                  ),
                ),
              ),
              Icon(
                fileName == null ? LucideIcons.plus : LucideIcons.eye,
                size: 15,
                color: PomgtColors.blue,
              ),
              const SizedBox(width: 4),
              Text(
                fileName == null ? 'Adjuntar' : 'Ver documento',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PomgtColors.blue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Side (or full-screen, on narrow layouts) preview of the reference
/// document(s) attached to the pedido, so their code/description/quantity
/// can be read while filling in products in step 2. Doubles as the upload
/// entry point: it accepts OS drag-and-drop anywhere over it, in every
/// state (empty or already previewing a file).
class _ReferenceDocumentPreview extends StatefulWidget {
  const _ReferenceDocumentPreview({
    required this.files,
    required this.activeIndex,
    required this.onSelect,
    required this.onRemove,
    required this.onAddFiles,
    required this.onFilesDropped,
    required this.onClose,
    this.onExpand,
    this.expanded = false,
  });
  final List<_PendingFile> files;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int>? onRemove;
  final VoidCallback onAddFiles;
  final ValueChanged<List<DropItem>> onFilesDropped;
  final VoidCallback? onClose;
  // Opens the same preview full-screen with the PDF's own zoom/page
  // controls, for reading small text comfortably. There is no selectable
  // text layer here (the PDF is rasterized), so this is the practical
  // substitute: a much bigger, zoomable view instead of literal copy/paste.
  final VoidCallback? onExpand;
  final bool expanded;

  @override
  State<_ReferenceDocumentPreview> createState() =>
      _ReferenceDocumentPreviewState();
}

class _ReferenceDocumentPreviewState extends State<_ReferenceDocumentPreview> {
  bool _dragging = false;
  bool _showText = false;

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final hasFiles = files.isNotEmpty;
    final index = hasFiles ? widget.activeIndex.clamp(0, files.length - 1) : 0;
    final file = hasFiles ? files[index] : null;
    final isPdf = file?.mimeType == 'application/pdf';

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        widget.onFilesDropped(details.files);
      },
      child: AnimatedContainer(
        duration: PomgtMotion.duration(context, PomgtMotion.fast),
        color: _dragging ? PomgtColors.blueSoft : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 10, 10),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.fileText,
                    size: 16,
                    color: PomgtColors.blue,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Documento de referencia',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasFiles && widget.onExpand != null)
                    IconButton(
                      tooltip: 'Ampliar y hacer zoom',
                      icon: const Icon(LucideIcons.zoomIn, size: 18),
                      onPressed: widget.onExpand,
                    ),
                  if (hasFiles)
                    IconButton(
                      tooltip: 'Adjuntar otro documento',
                      icon: const Icon(LucideIcons.plus, size: 18),
                      onPressed: widget.onAddFiles,
                    ),
                  if (widget.onClose != null)
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(LucideIcons.x, size: 17),
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
            if (files.length > 1)
              SizedBox(
                height: 34,
                child: PomgtListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        files[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    selected: i == index,
                    onSelected: (_) => widget.onSelect(i),
                  ),
                ),
              ),
            if (isPdf) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Vista'),
                        icon: Icon(LucideIcons.fileText, size: 14),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Texto'),
                        icon: Icon(LucideIcons.textCursor, size: 14),
                      ),
                    ],
                    selected: {_showText},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    onSelectionChanged: (selection) =>
                        setState(() => _showText = selection.first),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: hasFiles
                    ? _FilePreview(
                        file: file!,
                        expanded: widget.expanded,
                        showText: isPdf && _showText,
                      )
                    : _DropzoneEmptyState(
                        dragging: _dragging,
                        onTap: widget.onAddFiles,
                      ),
              ),
            ),
            if (hasFiles)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${file!.name} · ${_fileSize(file.bytes.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: PomgtColors.muted,
                        ),
                      ),
                    ),
                    if (widget.onRemove != null)
                      IconButton(
                        tooltip: 'Quitar documento',
                        icon: const Icon(LucideIcons.trash2, size: 15),
                        onPressed: () => widget.onRemove!(index),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DropzoneEmptyState extends StatelessWidget {
  const _DropzoneEmptyState({required this.dragging, required this.onTap});
  final bool dragging;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: PomgtRadii.borderMd,
      onTap: onTap,
      child: DottedBorderBox(
        active: dragging,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.cloudUpload,
                size: 36,
                color: dragging ? PomgtColors.blue : PomgtColors.muted,
              ),
              const SizedBox(height: 12),
              Text(
                dragging
                    ? 'Suelta aquí para adjuntar'
                    : 'Arrastra la OC u otro documento aquí',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: dragging ? PomgtColors.blue : PomgtColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'o haz clic para elegir un archivo. Puedes adjuntar varios.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PomgtColors.muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed-border frame for the empty dropzone state. Flutter has no built-in
/// dashed border, so this paints one with a small [CustomPainter].
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: active ? PomgtColors.blue : PomgtColors.line,
        active: active,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = active ? 2 : 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({
    required this.file,
    this.expanded = false,
    this.showText = false,
  });
  final _PendingFile file;
  final bool expanded;
  // Some PDFs report broken per-glyph bounds to the renderer (the on-page
  // selection highlight turns into a nonsensical block instead of following
  // the text). When true, shows the extracted plain text instead — always
  // reliably selectable, since it's plain Flutter text, not an overlay on
  // pdfium's page rendering.
  final bool showText;

  bool get _isImage => (file.mimeType ?? '').startsWith('image/');
  bool get _isPdf => file.mimeType == 'application/pdf';

  @override
  Widget build(BuildContext context) {
    if (_isImage) {
      return ClipRRect(
        borderRadius: PomgtRadii.borderSm,
        child: ColoredBox(
          color: PomgtColors.surfaceAlt,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: expanded ? 8 : 4,
            child: Image.memory(
              file.bytes,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),
      );
    }
    if (_isPdf) {
      if (showText) {
        return _ExtractedTextView(file: file);
      }
      // PdfViewer (pdfrx) renders through pdfium and has real text
      // selection/copy and pinch/scroll zoom built in — unlike the
      // `printing` package's PdfPreview, which only rasterizes pages with
      // no text layer at all. Keyed and cached by file.sourceId, not by
      // widget/byte identity, so it doesn't reload on unrelated rebuilds.
      return ClipRRect(
        borderRadius: PomgtRadii.borderSm,
        child: ColoredBox(
          color: PomgtColors.surfaceAlt,
          child: PdfViewer.data(
            file.bytes,
            key: ValueKey(file.sourceId),
            sourceName: file.sourceId,
            useProgressiveLoading: false,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PomgtColors.surfaceAlt,
        borderRadius: PomgtRadii.borderSm,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.file, size: 40, color: PomgtColors.muted),
              const SizedBox(height: 10),
              Text(
                file.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Vista previa no disponible para este tipo de archivo.',
                style: TextStyle(color: PomgtColors.muted, fontSize: 11.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtractedTextView extends StatefulWidget {
  const _ExtractedTextView({required this.file});
  final _PendingFile file;

  @override
  State<_ExtractedTextView> createState() => _ExtractedTextViewState();
}

class _ExtractedTextViewState extends State<_ExtractedTextView> {
  late Future<String> _future;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = widget.file.extractedText ??= _extractPdfText(
      widget.file.bytes,
      widget.file.sourceId,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ExtractedTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file) {
      _future = widget.file.extractedText ??= _extractPdfText(
        widget.file.bytes,
        widget.file.sourceId,
      );
    }
  }

  Future<void> _copyAll(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showPomgtSnackBar(context, 'Texto copiado.');
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PomgtColors.surfaceAlt,
        borderRadius: PomgtRadii.borderSm,
      ),
      child: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  ErrorCopy.message(
                    snapshot.error!,
                    fallback: 'No fue posible extraer el texto del documento.',
                  ),
                  style: const TextStyle(color: PomgtColors.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final text = snapshot.data ?? '';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Texto extraído del documento',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          color: PomgtColors.muted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyAll(text),
                      icon: const Icon(LucideIcons.clipboard, size: 14),
                      label: const Text('Copiar todo'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ScrollToTopArea(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  builder: (context, _) => Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderFormDialog extends StatefulWidget {
  const _OrderFormDialog({this.original});
  final Map<String, dynamic>? original;

  @override
  State<_OrderFormDialog> createState() => _OrderFormDialogState();
}

class _OrderFormDialogState extends State<_OrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _externalReference = TextEditingController();
  final _customerPo = TextEditingController();
  final _orderDate = TextEditingController();
  final _deliveryDate = TextEditingController();
  final _notes = TextEditingController();
  final _instructions = TextEditingController();

  String _sourceType = 'customer_order';
  String _status = 'draft';
  String _priority = 'normal';
  String? _customerId;
  String? _contactId;
  String? _billingAddressId;
  String? _shippingAddressId;
  String? _currencyCode;
  String? _paymentTermId;
  bool _saving = false;
  String? _error;

  late Future<List<List<Map<String, dynamic>>>> _baseFuture;
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _currencies = const [];
  List<Map<String, dynamic>> _paymentTerms = const [];
  List<Map<String, dynamic>> _contacts = const [];
  List<Map<String, dynamic>> _addresses = const [];

  GenericRepository get _generic => context.read<GenericRepository>();
  LookupRepository get _lookups => context.read<LookupRepository>();
  bool get _editing => widget.original != null;
  bool get _customerRequired =>
      _sourceType == 'customer_order' || _sourceType == 'customer_po';

  @override
  void initState() {
    super.initState();
    final row = widget.original;
    if (row != null) {
      _sourceType = row['source_type']?.toString() ?? 'customer_order';
      _status = row['status']?.toString() ?? 'draft';
      _priority = row['priority']?.toString() ?? 'normal';
      _customerId = row['customer_id']?.toString();
      _contactId = row['customer_contact_id']?.toString();
      _billingAddressId = row['billing_address_id']?.toString();
      _shippingAddressId = row['shipping_address_id']?.toString();
      _currencyCode = row['currency_code']?.toString();
      _paymentTermId = row['payment_term_id']?.toString();
      _externalReference.text = row['external_reference']?.toString() ?? '';
      _customerPo.text = row['customer_po_number']?.toString() ?? '';
      _orderDate.text = row['order_date']?.toString() ?? '';
      _deliveryDate.text = row['requested_delivery_date']?.toString() ?? '';
      _notes.text = row['notes']?.toString() ?? '';
      _instructions.text = row['special_instructions']?.toString() ?? '';
    } else {
      final now = DateTime.now();
      _orderDate.text = _date(now);
    }
    _baseFuture = _loadBase();
  }

  @override
  void dispose() {
    _externalReference.dispose();
    _customerPo.dispose();
    _orderDate.dispose();
    _deliveryDate.dispose();
    _notes.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<List<List<Map<String, dynamic>>>> _loadBase() async {
    final data = await Future.wait([
      _lookups.rows('customers', refresh: true),
      _lookups.rows('currencies'),
      _lookups.rows('payment_terms'),
    ]);
    _customers = data[0];
    _currencies = data[1];
    _paymentTerms = data[2];
    if (_currencyCode == null && _currencies.isNotEmpty) {
      final mxn = _currencies
          .where((e) => e['code']?.toString() == 'MXN')
          .toList();
      _currencyCode = (mxn.isNotEmpty ? mxn.first : _currencies.first)['code']
          ?.toString();
    }
    if (_customerId != null) await _loadCustomerChildren(_customerId!);
    return data;
  }

  Future<void> _loadCustomerChildren(String customerId) async {
    final results = await Future.wait([
      _generic.listRows(
        Phase1Schema.tables['customer_contacts']!,
        filters: {'customer_id': customerId},
      ),
      _generic.listRows(
        Phase1Schema.tables['customer_addresses']!,
        filters: {'customer_id': customerId},
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _contacts = results[0];
      _addresses = results[1];
      if (_contactId != null &&
          !_contacts.any((e) => e['id']?.toString() == _contactId))
        _contactId = null;
      if (_billingAddressId != null &&
          !_addresses.any((e) => e['id']?.toString() == _billingAddressId))
        _billingAddressId = null;
      if (_shippingAddressId != null &&
          !_addresses.any((e) => e['id']?.toString() == _shippingAddressId))
        _shippingAddressId = null;
    });
  }

  Future<void> _selectCustomer(String? value) async {
    setState(() {
      _customerId = value;
      _contactId = null;
      _billingAddressId = null;
      _shippingAddressId = null;
      _contacts = const [];
      _addresses = const [];
    });
    if (value == null) return;
    final match = _customers
        .where((e) => e['id']?.toString() == value)
        .toList();
    if (match.isNotEmpty) {
      final customer = match.first;
      setState(() {
        _currencyCode =
            customer['default_currency_code']?.toString() ?? _currencyCode;
        _paymentTermId = customer['payment_term_id']?.toString();
      });
    }
    await _loadCustomerChildren(value);
  }

  Future<void> _createCustomer() async {
    Map<String, dynamic>? created;
    final changed = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(onSaved: (row) => created = row),
    );
    if (changed != true || !mounted || created == null) return;
    _lookups.invalidate('customers');
    _customers = await _lookups.rows('customers', refresh: true);
    await _selectCustomer(created!['id']?.toString());
    if (mounted) setState(() {});
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showPomgtDatePicker(
      context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.text = _date(picked);
  }

  Map<String, dynamic>? _addressSnapshot(String? id) {
    if (id == null) return null;
    final rows = _addresses.where((e) => e['id']?.toString() == id).toList();
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    row.remove('created_at');
    row.remove('updated_at');
    return row;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_customerRequired && _customerId == null) {
      setState(
        () => _error = 'Selecciona un cliente para este origen de pedido.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = <String, dynamic>{
        'source_type': _sourceType,
        'customer_id': _customerId,
        'customer_contact_id': _customerId == null ? null : _contactId,
        'external_reference': _nullable(_externalReference.text),
        'customer_po_number': _nullable(_customerPo.text),
        'order_date': _orderDate.text,
        'requested_delivery_date': _nullable(_deliveryDate.text),
        'status': _status,
        'priority': _priority,
        'currency_code': _currencyCode,
        'payment_term_id': _paymentTermId,
        'billing_address_id': _customerId == null ? null : _billingAddressId,
        'shipping_address_id': _customerId == null ? null : _shippingAddressId,
        'billing_address_snapshot': _customerId == null
            ? null
            : _addressSnapshot(_billingAddressId),
        'shipping_address_snapshot': _customerId == null
            ? null
            : _addressSnapshot(_shippingAddressId),
        'notes': _nullable(_notes.text),
        'special_instructions': _nullable(_instructions.text),
      };
      final spec = Phase1Schema.tables['customer_orders']!;
      if (_editing) {
        await _generic.updateAnyRow(spec, widget.original!, values);
      } else {
        await _generic.createRow(spec, values);
      }
      _lookups.invalidate('customer_orders');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ErrorCopy.message(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
          child: FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: _baseFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 320, child: PomgtLoading());
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 260,
                  child: Center(
                    child: Text(
                      ErrorCopy.message(snapshot.error!),
                      style: const TextStyle(color: PomgtColors.danger),
                    ),
                  ),
                );
              }
              return Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          LucideIcons.fileText,
                          size: 25,
                          color: PomgtColors.ink,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _editing
                                          ? 'Editar pedido'
                                          : 'Nuevo pedido',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const InfoTip(
                                    'Registra el origen de la necesidad, cliente, fechas y condiciones. Las direcciones se filtran por cliente y se guarda una copia histórica al guardar el pedido.',
                                    size: 16,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Captura la necesidad comercial sin exponer identificadores técnicos. Después podrás agregar líneas, documentos y liberar producción.',
                                style: TextStyle(
                                  color: PomgtColors.muted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(LucideIcons.x, size: 20),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    Flexible(
                      child: ScrollToTopArea(
                        padding: const EdgeInsets.all(16),
                        builder: (context, controller) => SingleChildScrollView(
                          controller: controller,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _formSection(
                                context,
                                title: 'Origen y cliente',
                                help: 'Indica de dónde proviene la necesidad. Pedido de cliente y OC requieren cliente; orden interna, pronóstico y reposición pueden existir sin cliente.',
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final wide = c.maxWidth >= 700;
                                    final source = CategorizedSearchPicker(
                                      label: 'Origen *',
                                      hint: 'Buscar origen…',
                                      value: _sourceType,
                                      items: [
                                        for (final value in const [
                                          'customer_order',
                                          'customer_po',
                                          'internal_order',
                                          'forecast',
                                          'inventory_replenishment',
                                          'make_to_stock',
                                        ])
                                          PickerItem(
                                            id: value,
                                            label: UiCopy.enumLabel(value),
                                            category: 'Orígenes',
                                          ),
                                      ],
                                      onChanged: (value) => setState(
                                        () =>
                                            _sourceType = value ?? _sourceType,
                                      ),
                                    );
                                    final customer = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 20,
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            _customers.isEmpty
                                                ? 'Todavía no hay clientes registrados.'
                                                : (_customerRequired
                                                      ? 'Requerido para el origen seleccionado.'
                                                      : 'Opcional para este origen.'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: PomgtColors.muted,
                                                ),
                                          ),
                                        ),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Expanded(
                                              child: CategorizedSearchPicker(
                                                key: ValueKey(
                                                  'customer-${_customerId ?? ''}-${_customers.length}',
                                                ),
                                                label:
                                                    'Cliente${_customerRequired ? ' *' : ''}',
                                                hint: 'Buscar cliente…',
                                                value:
                                                    _customers.any(
                                                      (e) =>
                                                          e['id']?.toString() ==
                                                          _customerId,
                                                    )
                                                    ? _customerId
                                                    : null,
                                                items: [
                                                  for (final e in _customers)
                                                    PickerItem(
                                                      id: e['id'].toString(),
                                                      label: _lookups.display(
                                                        Phase1Schema
                                                            .tables['customers']!,
                                                        e,
                                                      ),
                                                      category: 'Clientes',
                                                    ),
                                                ],
                                                onChanged: _selectCustomer,
                                                validator: (_) =>
                                                    _customerRequired &&
                                                        _customerId == null
                                                    ? 'Selecciona un cliente'
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Tooltip(
                                              message: 'Agregar cliente',
                                              child: IconButton(
                                                onPressed: _createCustomer,
                                                icon: const Icon(
                                                  LucideIcons.plus,
                                                  size: 19,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                    if (!wide)
                                      return Column(
                                        children: [
                                          source,
                                          const SizedBox(height: 16),
                                          customer,
                                        ],
                                      );
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Expanded(child: source),
                                        const SizedBox(width: 28),
                                        Expanded(child: customer),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              if (_customers.isEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _createCustomer,
                                    icon: const Icon(
                                      LucideIcons.plus,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Agregar el primer cliente',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 26),
                              _formSection(
                                context,
                                title: 'Referencias y fechas',
                                help: 'La OC del cliente y la referencia externa son opcionales. Las fechas ayudan a priorizar y planear la fabricación.',
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final wide = c.maxWidth >= 700;
                                    final fields = <Widget>[
                                      TextFormField(
                                        errorBuilder: pomgtValidationMessage,
                                        controller: _customerPo,
                                        decoration: const InputDecoration(
                                          labelText: 'OC del cliente',
                                          hintText:
                                              'Ej. número de orden de compra',
                                        ),
                                      ),
                                      TextFormField(
                                        errorBuilder: pomgtValidationMessage,
                                        controller: _externalReference,
                                        decoration: const InputDecoration(
                                          labelText: 'Referencia externa',
                                          hintText: 'Ej. folio interno o de otro sistema',
                                        ),
                                      ),
                                      TextFormField(
                                        errorBuilder: pomgtValidationMessage,
                                        controller: _orderDate,
                                        readOnly: true,
                                        onTap: () => _pickDate(_orderDate),
                                        decoration: const InputDecoration(
                                          labelText: 'Fecha del pedido *',
                                          hintText: 'Selecciona una fecha',
                                          suffixIcon: Icon(
                                            LucideIcons.calendar,
                                            size: 17,
                                          ),
                                        ),
                                        validator: (v) => v == null || v.isEmpty
                                            ? 'Selecciona la fecha'
                                            : null,
                                      ),
                                      TextFormField(
                                        errorBuilder: pomgtValidationMessage,
                                        controller: _deliveryDate,
                                        readOnly: true,
                                        onTap: () => _pickDate(_deliveryDate),
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Fecha solicitada de entrega',
                                          hintText: 'Selecciona una fecha',
                                          suffixIcon: Icon(
                                            LucideIcons.calendar,
                                            size: 17,
                                          ),
                                        ),
                                      ),
                                    ];
                                    if (!wide)
                                      return Column(children: _spaced(fields));
                                    return Wrap(
                                      spacing: 28,
                                      runSpacing: 16,
                                      children: fields
                                          .map(
                                            (e) => SizedBox(
                                              width: (c.maxWidth - 28) / 2,
                                              child: e,
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 26),
                              _formSection(
                                context,
                                title: 'Condiciones',
                                help: 'La moneda y condición de pago se precargan desde el cliente cuando están configuradas, pero pueden modificarse para este pedido.',
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final wide = c.maxWidth >= 700;
                                    final fields = <Widget>[
                                      CategorizedSearchPicker(
                                        label: 'Prioridad *',
                                        hint: 'Buscar prioridad…',
                                        value: _priority,
                                        items: [
                                          for (final v in [
                                            'low',
                                            'normal',
                                            'high',
                                            'urgent',
                                          ])
                                            PickerItem(
                                              id: v,
                                              label: UiCopy.enumLabel(v),
                                              category: 'Prioridades',
                                            ),
                                        ],
                                        onChanged: (v) => setState(
                                          () => _priority = v ?? _priority,
                                        ),
                                      ),
                                      DropdownButtonFormField<String>(
                                        errorBuilder: pomgtValidationMessage,
                                        initialValue: _status,
                                        decoration: const InputDecoration(
                                          labelText: 'Estado *',
                                        ),
                                        items:
                                            const [
                                                  'draft',
                                                  'confirmed',
                                                  'partially_released',
                                                  'released',
                                                  'partially_completed',
                                                  'completed',
                                                  'cancelled',
                                                ]
                                                .map(
                                                  (v) => DropdownMenuItem(
                                                    value: v,
                                                    child: Text(
                                                      UiCopy.enumLabel(v),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                        onChanged: (v) => setState(
                                          () => _status = v ?? _status,
                                        ),
                                      ),
                                      CategorizedSearchPicker(
                                        key: ValueKey(
                                          'currency-${_currencyCode ?? ''}',
                                        ),
                                        label: 'Moneda *',
                                        hint: 'Buscar moneda…',
                                        value:
                                            _currencies.any(
                                              (e) =>
                                                  e['code']?.toString() ==
                                                  _currencyCode,
                                            )
                                            ? _currencyCode
                                            : null,
                                        items: [
                                          for (final e in _currencies)
                                            PickerItem(
                                              id: e['code'].toString(),
                                              label: _lookups.display(
                                                Phase1Schema
                                                    .tables['currencies']!,
                                                e,
                                              ),
                                              category: 'Monedas',
                                            ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _currencyCode = v),
                                        validator: (v) => v == null
                                            ? 'Selecciona una moneda'
                                            : null,
                                      ),
                                      QuickCreateField(
                                        table: 'payment_terms',
                                        repository: _generic,
                                        lookups: _lookups,
                                        isEmpty: _paymentTerms.isEmpty,
                                        onCreated: (row) => setState(() {
                                          _paymentTerms = [
                                            ..._paymentTerms,
                                            row,
                                          ];
                                          _paymentTermId = row['id']
                                              ?.toString();
                                        }),
                                        child: CategorizedSearchPicker(
                                          key: ValueKey(
                                            'payment-${_paymentTermId ?? ''}',
                                          ),
                                          label: 'Condición de pago',
                                          hint: 'Buscar condición…',
                                          value:
                                              _paymentTerms.any(
                                                (e) =>
                                                    e['id']?.toString() ==
                                                    _paymentTermId,
                                              )
                                              ? _paymentTermId
                                              : null,
                                          items: [
                                            for (final e in _paymentTerms)
                                              PickerItem(
                                                id: e['id'].toString(),
                                                label: _lookups.display(
                                                  Phase1Schema
                                                      .tables['payment_terms']!,
                                                  e,
                                                ),
                                                category: 'Condiciones de pago',
                                              ),
                                          ],
                                          onChanged: (v) => setState(
                                            () => _paymentTermId = v,
                                          ),
                                        ),
                                      ),
                                    ];
                                    if (!wide)
                                      return Column(children: _spaced(fields));
                                    return Wrap(
                                      spacing: 28,
                                      runSpacing: 16,
                                      children: fields
                                          .map(
                                            (e) => SizedBox(
                                              width: (c.maxWidth - 28) / 2,
                                              child: e,
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              ),
                              if (_customerId != null) ...[
                                const SizedBox(height: 26),
                                _formSection(
                                  context,
                                  title: 'Contacto y direcciones',
                                  help: 'Solo se muestran contactos y direcciones del cliente seleccionado. Al guardar, POMGT conserva una copia histórica de las direcciones elegidas.',
                                  child: LayoutBuilder(
                                    builder: (context, c) {
                                      final wide = c.maxWidth >= 700;
                                      final contact = CategorizedSearchPicker(
                                        key: ValueKey(
                                          'contact-${_contactId ?? ''}-${_contacts.length}',
                                        ),
                                        label: 'Contacto del cliente',
                                        hint: 'Buscar contacto…',
                                        value:
                                            _contacts.any(
                                              (e) =>
                                                  e['id']?.toString() ==
                                                  _contactId,
                                            )
                                            ? _contactId
                                            : null,
                                        items: [
                                          for (final e in _contacts)
                                            PickerItem(
                                              id: e['id'].toString(),
                                              label: _lookups.display(
                                                Phase1Schema
                                                    .tables['customer_contacts']!,
                                                e,
                                              ),
                                              category: 'Contactos',
                                            ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _contactId = v),
                                      );
                                      Widget addressField(
                                        String label,
                                        String? value,
                                        ValueChanged<String?> change,
                                      ) => CategorizedSearchPicker(
                                        key: ValueKey(
                                          '$label-${value ?? ''}-${_addresses.length}',
                                        ),
                                        label: label,
                                        hint: 'Buscar dirección…',
                                        value:
                                            _addresses.any(
                                              (e) =>
                                                  e['id']?.toString() == value,
                                            )
                                            ? value
                                            : null,
                                        items: [
                                          for (final e in _addresses)
                                            PickerItem(
                                              id: e['id'].toString(),
                                              label: _addressLabel(e),
                                              category: 'Direcciones',
                                            ),
                                        ],
                                        onChanged: change,
                                      );
                                      final fields = <Widget>[
                                        contact,
                                        addressField(
                                          'Dirección de facturación',
                                          _billingAddressId,
                                          (v) => setState(
                                            () => _billingAddressId = v,
                                          ),
                                        ),
                                        addressField(
                                          'Dirección de envío',
                                          _shippingAddressId,
                                          (v) => setState(
                                            () => _shippingAddressId = v,
                                          ),
                                        ),
                                      ];
                                      if (!wide)
                                        return Column(
                                          children: _spaced(fields),
                                        );
                                      return Wrap(
                                        spacing: 28,
                                        runSpacing: 16,
                                        children: fields
                                            .map(
                                              (e) => SizedBox(
                                                width: (c.maxWidth - 28) / 2,
                                                child: e,
                                              ),
                                            )
                                            .toList(),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              const SizedBox(height: 26),
                              _formSection(
                                context,
                                title: 'Notas e instrucciones',
                                help: 'Usa notas para contexto administrativo e instrucciones especiales para requisitos que deben acompañar la planeación o producción.',
                                child: Column(
                                  children: [
                                    TextFormField(
                                      errorBuilder: pomgtValidationMessage,
                                      controller: _instructions,
                                      minLines: 2,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        labelText: 'Instrucciones especiales',
                                        hintText:
                                            'Indicaciones para producción…',
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      errorBuilder: pomgtValidationMessage,
                                      controller: _notes,
                                      minLines: 2,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        labelText: 'Notas',
                                        hintText: 'Contexto administrativo…',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            LucideIcons.circleAlert,
                            size: 18,
                            color: PomgtColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: PomgtColors.danger,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _editing
                                      ? LucideIcons.save
                                      : LucideIcons.plus,
                                  size: 16,
                                ),
                          label: Text(
                            _saving
                                ? 'Guardando…'
                                : (_editing
                                      ? 'Guardar cambios'
                                      : 'Crear pedido'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _formSection(
    BuildContext context, {
    required String title,
    required String help,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 7),
            InfoTip(help, size: 15),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    );
  }

  String _addressLabel(Map<String, dynamic> row) {
    final pieces = <String>[
      if (row['label'] != null && row['label'].toString().trim().isNotEmpty)
        row['label'].toString(),
      if (row['line1'] != null) row['line1'].toString(),
      if (row['city'] != null) row['city'].toString(),
    ];
    return pieces.isEmpty ? 'Dirección' : pieces.join(' · ');
  }

  static List<Widget> _spaced(List<Widget> widgets) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      if (i > 0) result.add(const SizedBox(height: 16));
      result.add(widgets[i]);
    }
    return result;
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final generic = context.read<GenericRepository>();
    final lookups = context.read<LookupRepository>();
    final id = order['id'].toString();

    Future<void> edit() async {
      final changed = await showPomgtDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OrderFormDialog(original: order),
      );
      if (changed == true && context.mounted)
        context.read<OrdersController>().refresh();
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: lookups.rows('customers'),
      builder: (context, snapshot) {
        final customers = snapshot.data ?? const <Map<String, dynamic>>[];
        final matches = customers
            .where(
              (c) => c['id']?.toString() == order['customer_id']?.toString(),
            )
            .toList();
        final customerName = matches.isEmpty
            ? null
            : lookups.display(Phase1Schema.tables['customers']!, matches.first);
        final parts = <String>[
          UiCopy.enumLabel(order['source_type']?.toString() ?? ''),
          if (customerName != null) customerName,
          if (order['customer_po_number'] != null &&
              order['customer_po_number'].toString().trim().isNotEmpty)
            'OC ${order['customer_po_number']}',
          if (order['requested_delivery_date'] != null)
            'Entrega ${order['requested_delivery_date']}',
        ];
        return Container(
          color: Colors.white,
          child: Column(
            children: [
              DetailHeader(
                icon: LucideIcons.fileText,
                title: order['order_number']?.toString() ?? 'Pedido',
                subtitle: parts.join(' · '),
                status: order['status']?.toString(),
                plainStatus: true,
                help: 'Cabecera del pedido. Las direcciones pueden conservar una copia histórica para que cambios futuros del cliente no modifiquen pedidos anteriores.',
                onEdit: edit,
              ),
              Expanded(
                child: DetailSections(
                  sections: [
                    DetailSection(
                      label: 'Resumen',
                      help: 'Origen, cliente, fechas y condiciones.',
                      icon: LucideIcons.layoutDashboard,
                      child: _OrderSummary(order: order),
                    ),
                    DetailSection(
                      label: 'Líneas',
                      help: 'Productos, cantidades, precios y requisitos.',
                      icon: LucideIcons.list,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: EntityCrudPanel(
                          table: 'customer_order_lines',
                          repository: generic,
                          lookups: lookups,
                          fixedValues: {'customer_order_id': id},
                          title: 'Líneas del pedido',
                          description: 'Productos y cantidades solicitadas. POMGT conserva la descripción y requisitos de cada línea para mantener la trazabilidad del pedido original.',
                          flatList: true,
                        ),
                      ),
                    ),
                    DetailSection(
                      label: 'Producción',
                      help: 'Liberación de líneas a producción.',
                      icon: LucideIcons.factory,
                      child: _ReleasePanel(orderId: id),
                    ),
                    DetailSection(
                      label: 'Documentos',
                      help: 'OC, capturas, correos y especificaciones.',
                      icon: LucideIcons.folders,
                      child: LinkedDocumentsPanel(
                        entityField: 'customer_order_id',
                        entityId: id,
                        title: 'Documentos del pedido',
                        help: 'Carga y previsualiza la orden de compra del cliente, capturas de mensajes, correos, especificaciones u otra evidencia relacionada con el pedido.',
                        documentTypes: const [
                          'Orden de compra / OC',
                          'Captura de mensaje',
                          'Correo',
                          'Especificación',
                          'Diseño / arte',
                          'Otro',
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([
        lookups.rows('customers'),
        lookups.rows('payment_terms'),
      ]),
      builder: (context, snapshot) {
        final data =
            snapshot.data ??
            <List<Map<String, dynamic>>>[
              <Map<String, dynamic>>[],
              <Map<String, dynamic>>[],
            ];
        String resolve(int index, dynamic id, String table) {
          if (id == null) return '—';
          final matches = data[index]
              .where((r) => r['id']?.toString() == id.toString())
              .toList();
          return matches.isEmpty
              ? '—'
              : lookups.display(Phase1Schema.tables[table]!, matches.first);
        }

        final rows = <MapEntry<String, String>>[
          MapEntry('Cliente', resolve(0, order['customer_id'], 'customers')),
          MapEntry(
            'Origen',
            UiCopy.enumLabel(order['source_type']?.toString() ?? ''),
          ),
          MapEntry(
            'OC del cliente',
            order['customer_po_number']?.toString() ?? '—',
          ),
          MapEntry(
            'Referencia externa',
            order['external_reference']?.toString() ?? '—',
          ),
          MapEntry('Fecha de pedido', order['order_date']?.toString() ?? '—'),
          MapEntry(
            'Entrega solicitada',
            order['requested_delivery_date']?.toString() ?? '—',
          ),
          MapEntry(
            'Prioridad',
            UiCopy.enumLabel(order['priority']?.toString() ?? 'normal'),
          ),
          MapEntry('Moneda', order['currency_code']?.toString() ?? '—'),
          MapEntry(
            'Condición de pago',
            resolve(1, order['payment_term_id'], 'payment_terms'),
          ),
          MapEntry(
            'Estado',
            UiCopy.enumLabel(order['status']?.toString() ?? ''),
          ),
        ];
        return ScrollToTopArea(
          padding: const EdgeInsets.all(16),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Datos del pedido',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 7),
                    const InfoTip(
                      'Información comercial y fechas utilizadas para planear la producción. Los datos relacionados se seleccionan desde catálogos para reducir errores de captura.',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth > 850 ? 4 : 2;
                    final w = (c.maxWidth - (cols - 1) * 26) / cols;
                    return Wrap(
                      spacing: 26,
                      runSpacing: 22,
                      children: rows
                          .map(
                            (r) => SizedBox(
                              width: w,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.key,
                                    style: const TextStyle(
                                      color: PomgtColors.muted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    r.value,
                                    style: const TextStyle(
                                      color: PomgtColors.ink,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                if (order['special_instructions'] != null &&
                    order['special_instructions']
                        .toString()
                        .trim()
                        .isNotEmpty) ...[
                  const SizedBox(height: 34),
                  const Text(
                    'Instrucciones especiales',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(order['special_instructions'].toString()),
                ],
                if (order['notes'] != null &&
                    order['notes'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Notas',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(order['notes'].toString()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReleasePanel extends StatefulWidget {
  const _ReleasePanel({required this.orderId});
  final String orderId;

  @override
  State<_ReleasePanel> createState() => _ReleasePanelState();
}

class _ReleasePanelState extends State<_ReleasePanel> {
  late Future<List<Map<String, dynamic>>> future;
  final Set<String> _selectedLineIds = {};

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      context.read<OrderRepository>().orderLineProductionStatus(widget.orderId);

  void reload() {
    setState(() {
      future = _load();
    });
  }

  Future<void> _release(Map<String, dynamic> line) async {
    final pending = (line['quantity_pending_release'] as num?)?.toDouble() ?? 0;
    if (pending <= 0) return;
    final result = await showPomgtDialog<_ReleaseRequest>(
      context: context,
      builder: (_) => _ReleaseDialog(maxQuantity: pending),
    );
    if (result == null || !mounted) return;
    try {
      final repository = context.read<OrderRepository>();
      // Splitting one line into several OPs counts as "released together",
      // so they share a lote too — a single OP (the common case) doesn't
      // need one.
      final batchNumber = result.quantities.length > 1
          ? await repository.nextBatchNumber()
          : null;
      if (!mounted) return;
      await repository.releaseLineToProduction(
        orderLineId: line['customer_order_line_id'].toString(),
        quantities: result.quantities,
        requiredAt: result.requiredAt,
        priority: result.priority,
        batchNumber: batchNumber,
      );
      if (!mounted) return;
      showPomgtNotice(
        context,
        title: batchNumber == null
            ? 'Orden de producción creada.'
            : 'Órdenes de producción creadas en el lote $batchNumber.',
      );
      reload();
    } catch (e) {
      if (mounted) {
        showPomgtNotice(
          context,
          title: 'No fue posible completar la operación.',
          description: ErrorCopy.message(e),
          isError: true,
        );
      }
    }
  }

  Future<void> _linkBom(Map<String, dynamic> product) async {
    final created = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LinkBomDialog(product: product, activateRevision: true),
    );
    if (created == true && mounted) reload();
  }

  Future<void> _linkRouting(Map<String, dynamic> product) async {
    final created = await showPomgtDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LinkRoutingDialog(product: product),
    );
    if (created == true && mounted) reload();
  }

  Future<void> _bulkRelease(List<Map<String, dynamic>> rows) async {
    final selected = rows
        .where(
          (r) => _selectedLineIds.contains(
            r['customer_order_line_id']?.toString(),
          ),
        )
        .toList();
    if (selected.isEmpty) return;
    final result = await showPomgtDialog<_BulkReleaseRequest>(
      context: context,
      builder: (_) => _BulkReleaseDialog(lineCount: selected.length),
    );
    if (result == null || !mounted) return;
    final repository = context.read<OrderRepository>();
    // All OPs released together in this batch share one lote, so they can
    // be found and treated as the same job even though each keeps its own
    // product/BOM/routing.
    final batchNumber = await repository.nextBatchNumber();
    if (!mounted) return;
    final failedIds = <String>{};
    var successCount = 0;
    final errors = <String>[];
    for (final line in selected) {
      final lineId = line['customer_order_line_id'].toString();
      final pending =
          (line['quantity_pending_release'] as num?)?.toDouble() ?? 0;
      if (pending <= 0) continue;
      try {
        await repository.releaseLineToProduction(
          orderLineId: lineId,
          quantities: [pending],
          requiredAt: result.requiredAt,
          priority: result.priority,
          batchNumber: batchNumber,
        );
        successCount++;
      } catch (e) {
        failedIds.add(lineId);
        errors.add(ErrorCopy.message(e));
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedLineIds
        ..clear()
        ..addAll(failedIds);
    });
    reload();
    if (errors.isEmpty) {
      showPomgtNotice(
        context,
        title:
            'Se crearon $successCount orden(es) de producción en el lote $batchNumber.',
      );
    } else {
      showPomgtNotice(
        context,
        title: 'Se crearon $successCount de ${selected.length} orden(es).',
        description: errors.join('\n'),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lookups = context.read<LookupRepository>();
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact
                      ? MediaQuery.sizeOf(context).width - 70
                      : 520,
                ),
                child: Text(
                  'Liberación a producción',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const InfoTip(
                'Convierte una línea del pedido en una o varias órdenes de producción. La suma de asignaciones nunca puede superar la cantidad solicitada.',
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: reload,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<List<Map<String, dynamic>>>>(
              future: Future.wait([
                future,
                lookups.rows('products'),
                lookups.rows('units_of_measure'),
                lookups.rows('boms'),
                lookups.rows('bom_revisions'),
                lookups.rows('routings'),
                lookups.rows('routing_revisions'),
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const PomgtLoading();
                if (snapshot.hasError)
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        ErrorCopy.message(
                          snapshot.error!,
                          fallback: 'No fue posible cargar la información del pedido.',
                        ),
                        softWrap: true,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(
                          color: PomgtColors.danger,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                final data =
                    snapshot.data ??
                    <List<Map<String, dynamic>>>[
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                      <Map<String, dynamic>>[],
                    ];
                final rows = data[0];
                final products = data[1];
                final units = data[2];
                final boms = data[3];
                final bomRevisions = data[4];
                final routings = data[5];
                final routingRevisions = data[6];
                final missingBomProductIds = productIdsMissingActiveBom(
                  rows
                      .map((r) => r['product_id']?.toString())
                      .whereType<String>(),
                  boms: boms,
                  bomRevisions: bomRevisions,
                );
                final missingRoutingProductIds = productIdsMissingActiveRouting(
                  rows
                      .map((r) => r['product_id']?.toString())
                      .whereType<String>(),
                  products: products,
                  routings: routings,
                  routingRevisions: routingRevisions,
                );
                if (rows.isEmpty)
                  return const Center(
                    child: Text(
                      'Agrega líneas al pedido para poder liberar producción.',
                      style: TextStyle(color: PomgtColors.muted),
                    ),
                  );

                String productName(dynamic id) {
                  final m = products
                      .where((p) => p['id']?.toString() == id?.toString())
                      .toList();
                  return m.isEmpty
                      ? 'Producto'
                      : lookups.display(
                          Phase1Schema.tables['products']!,
                          m.first,
                        );
                }

                String unitName(dynamic id) {
                  final m = units
                      .where((u) => u['id']?.toString() == id?.toString())
                      .toList();
                  return m.isEmpty
                      ? ''
                      : lookups.display(
                          Phase1Schema.tables['units_of_measure']!,
                          m.first,
                        );
                }

                // A product without an active BOM or routing can't be
                // released to production at all — not even as a draft OP —
                // since there would be nothing to eventually prepare it with.
                final pendingLineIds = rows
                    .where(
                      (r) =>
                          ((r['quantity_pending_release'] as num?)
                                      ?.toDouble() ??
                                  0) >
                              0 &&
                          !missingBomProductIds.contains(
                            r['product_id']?.toString(),
                          ) &&
                          !missingRoutingProductIds.contains(
                            r['product_id']?.toString(),
                          ),
                    )
                    .map((r) => r['customer_order_line_id']?.toString())
                    .whereType<String>()
                    .toSet();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pendingLineIds.length > 1) ...[
                      _BulkReleaseBar(
                        totalPending: pendingLineIds.length,
                        selectedCount: _selectedLineIds.length,
                        allSelected: pendingLineIds
                            .difference(_selectedLineIds)
                            .isEmpty,
                        onToggleAll: (selectAll) => setState(() {
                          if (selectAll) {
                            _selectedLineIds
                              ..clear()
                              ..addAll(pendingLineIds);
                          } else {
                            _selectedLineIds.clear();
                          }
                        }),
                        onRelease: _selectedLineIds.isEmpty
                            ? null
                            : () => _bulkRelease(rows),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: ScrollToTopArea(
                        padding: const EdgeInsets.all(16),
                        builder: (context, controller) => PomgtListView.separated(
                          controller: controller,
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final lineId = r['customer_order_line_id']
                                ?.toString();
                            final productId = r['product_id']?.toString();
                            final requested =
                                (r['requested_quantity'] as num?)?.toDouble() ??
                                0;
                            final allocated =
                                (r['allocated_quantity'] as num?)?.toDouble() ??
                                0;
                            final pending =
                                (r['quantity_pending_release'] as num?)
                                    ?.toDouble() ??
                                0;
                            final progress = requested == 0
                                ? 0.0
                                : (allocated / requested)
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                            final uom = unitName(r['uom_id']);
                            final missingBom = missingBomProductIds.contains(
                              productId,
                            );
                            final missingRouting = missingRoutingProductIds
                                .contains(productId);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Wrap(
                                spacing: compact ? 12 : 18,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Tooltip(
                                    message: missingBom
                                        ? 'Vincula materiales antes de liberar este producto a producción.'
                                        : missingRouting
                                        ? 'Vincula una ruta de fabricación antes de liberar este producto a producción.'
                                        : '',
                                    child: Checkbox(
                                      value:
                                          lineId != null &&
                                          _selectedLineIds.contains(lineId),
                                      onChanged:
                                          (pending > 0 &&
                                              lineId != null &&
                                              !missingBom &&
                                              !missingRouting)
                                          ? (checked) => setState(() {
                                              if (checked == true) {
                                                _selectedLineIds.add(lineId);
                                              } else {
                                                _selectedLineIds.remove(lineId);
                                              }
                                            })
                                          : null,
                                    ),
                                  ),
                                  SizedBox(
                                    width: compact ? double.infinity : 360,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          productName(r['product_id']),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${r['production_order_count'] ?? 0} OP creadas${uom.isEmpty ? '' : ' · $uom'}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: PomgtColors.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        PomgtProgressIndicator(
                                          value: progress,
                                          minHeight: 4,
                                          backgroundColor: PomgtColors.line,
                                          color: PomgtColors.blue,
                                        ),
                                      ],
                                    ),
                                  ),
                                  _Amount(
                                    label: 'Solicitado',
                                    value: requested,
                                  ),
                                  _Amount(label: 'Asignado', value: allocated),
                                  _Amount(label: 'Pendiente', value: pending),
                                  if (missingBom)
                                    OutlinedButton.icon(
                                      onPressed: () => _linkBom(
                                        products.firstWhere(
                                          (p) =>
                                              p['id']?.toString() == productId,
                                          orElse: () => const {},
                                        ),
                                      ),
                                      icon: const Icon(
                                        LucideIcons.triangleAlert,
                                        size: 15,
                                        color: PomgtColors.warning,
                                      ),
                                      label: const Text('Vincular materiales'),
                                    ),
                                  if (missingRouting)
                                    OutlinedButton.icon(
                                      onPressed: () => _linkRouting(
                                        products.firstWhere(
                                          (p) =>
                                              p['id']?.toString() == productId,
                                          orElse: () => const {},
                                        ),
                                      ),
                                      icon: const Icon(
                                        LucideIcons.triangleAlert,
                                        size: 15,
                                        color: PomgtColors.warning,
                                      ),
                                      label: const Text('Vincular ruta'),
                                    ),
                                  FilledButton.tonalIcon(
                                    onPressed:
                                        (pending > 0 &&
                                            !missingBom &&
                                            !missingRouting)
                                        ? () => _release(r)
                                        : null,
                                    icon: pending > 0
                                        ? const Icon(LucideIcons.plus, size: 16)
                                        : const Icon(
                                            LucideIcons.check,
                                            size: 16,
                                          ),
                                    label: Text(
                                      pending > 0 ? 'Crear OP' : 'Liberado',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: PomgtColors.muted),
        ),
        const SizedBox(height: 4),
        Text(
          _fmt(value),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  static String _fmt(double n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(4);
}

/// Always visible once there's more than one pending line, so bulk release
/// is discoverable without first noticing the per-row checkboxes. Doubles
/// as a "select all" toggle and, once something's checked, the release
/// trigger.
class _BulkReleaseBar extends StatelessWidget {
  const _BulkReleaseBar({
    required this.totalPending,
    required this.selectedCount,
    required this.allSelected,
    required this.onToggleAll,
    required this.onRelease,
  });
  final int totalPending;
  final int selectedCount;
  final bool allSelected;
  final ValueChanged<bool> onToggleAll;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PomgtColors.blueSoft,
        borderRadius: PomgtRadii.borderSm,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            borderRadius: PomgtRadii.borderSm,
            onTap: () => onToggleAll(!allSelected),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: allSelected
                        ? true
                        : (selectedCount > 0 ? null : false),
                    tristate: true,
                    onChanged: (_) => onToggleAll(!allSelected),
                  ),
                  Text(
                    selectedCount == 0
                        ? 'Seleccionar las $totalPending partidas pendientes'
                        : '$selectedCount de $totalPending partidas pendientes seleccionadas',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: PomgtColors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selectedCount > 0)
            FilledButton.icon(
              onPressed: onRelease,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(
                'Liberar $selectedCount partida${selectedCount == 1 ? '' : 's'}',
              ),
            ),
        ],
      ),
    );
  }
}

class _BulkReleaseRequest {
  const _BulkReleaseRequest(this.priority, this.requiredAt);
  final String priority;
  final DateTime? requiredAt;
}

class _BulkReleaseDialog extends StatefulWidget {
  const _BulkReleaseDialog({required this.lineCount});
  final int lineCount;

  @override
  State<_BulkReleaseDialog> createState() => _BulkReleaseDialogState();
}

class _BulkReleaseDialogState extends State<_BulkReleaseDialog> {
  String _priority = 'normal';
  DateTime? _requiredAt;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.hammer, size: 21, color: PomgtColors.ink),
          const SizedBox(width: 10),
          const Expanded(child: Text('Liberar varias partidas')),
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
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Se creará una orden de producción por cada una de las ${widget.lineCount} partidas seleccionadas, usando su cantidad pendiente completa.',
              style: const TextStyle(color: PomgtColors.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            CategorizedSearchPicker(
              label: 'Prioridad',
              hint: 'Buscar prioridad…',
              value: _priority,
              items: [
                for (final e in ['low', 'normal', 'high', 'urgent'])
                  PickerItem(
                    id: e,
                    label: UiCopy.enumLabel(e),
                    category: 'Prioridades',
                  ),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'normal'),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Fecha requerida',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                _requiredAt == null
                    ? 'Usar fecha del pedido o definir después'
                    : '${_requiredAt!.day}/${_requiredAt!.month}/${_requiredAt!.year}',
              ),
              trailing: const Icon(LucideIcons.calendar, size: 18),
              onTap: () async {
                final d = await showPomgtDatePicker(
                  context,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime(2100),
                  initialDate: _requiredAt ?? DateTime.now(),
                );
                if (d != null && mounted) setState(() => _requiredAt = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _BulkReleaseRequest(_priority, _requiredAt),
          ),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Crear órdenes'),
        ),
      ],
    );
  }
}

class _ReleaseRequest {
  const _ReleaseRequest(this.quantities, this.requiredAt, this.priority);
  final List<double> quantities;
  final DateTime? requiredAt;
  final String priority;
}

class _ReleaseDialog extends StatefulWidget {
  const _ReleaseDialog({required this.maxQuantity});
  final double maxQuantity;

  @override
  State<_ReleaseDialog> createState() => _ReleaseDialogState();
}

class _ReleaseDialogState extends State<_ReleaseDialog> {
  late final TextEditingController splits;
  String priority = 'normal';
  DateTime? requiredAt;
  String? error;

  @override
  void initState() {
    super.initState();
    splits = TextEditingController(text: widget.maxQuantity.toString());
  }

  @override
  void dispose() {
    splits.dispose();
    super.dispose();
  }

  void submit() {
    try {
      final q = splits.text
          .split(RegExp(r'[,;\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map(double.parse)
          .toList();
      if (q.isEmpty || q.any((e) => e <= 0)) throw const FormatException();
      final total = q.fold<double>(0, (a, b) => a + b);
      if (total > widget.maxQuantity + 0.000001) {
        setState(
          () => error =
              'La suma ($total) supera el pendiente (${widget.maxQuantity}).',
        );
        return;
      }
      Navigator.pop(context, _ReleaseRequest(q, requiredAt, priority));
    } catch (_) {
      setState(
        () => error = 'Ingresa cantidades válidas separadas por coma. Ej. 100000, 50000, 50000',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 640;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.hammer, size: 21, color: PomgtColors.ink),
          const SizedBox(width: 10),
          const Expanded(child: Text('Crear orden(es) de producción')),
          const SizedBox(width: 7),
          const InfoTip(
            'Puedes dividir una sola línea en varias OP. Cada cantidad se convierte en una orden independiente y queda asignada a esta línea.',
          ),
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
        width: compact ? screenWidth - 56 : 560,
        child: ScrollToTopArea(
          padding: const EdgeInsets.all(12),
          builder: (context, controller) => SingleChildScrollView(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cantidad pendiente: ${widget.maxQuantity}',
                  style: const TextStyle(color: PomgtColors.muted),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: splits,
                  decoration: const InputDecoration(
                    labelText: 'Cantidades de las OP',
                    hintText: '100000, 50000, 50000',
                  ),
                ),
                const SizedBox(height: 16),
                CategorizedSearchPicker(
                  label: 'Prioridad',
                  hint: 'Buscar prioridad…',
                  value: priority,
                  items: [
                    for (final e in ['low', 'normal', 'high', 'urgent'])
                      PickerItem(
                        id: e,
                        label: UiCopy.enumLabel(e),
                        category: 'Prioridades',
                      ),
                  ],
                  onChanged: (v) => setState(() => priority = v ?? 'normal'),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Fecha requerida',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    requiredAt == null
                        ? 'Usar fecha del pedido o definir después'
                        : '${requiredAt!.day}/${requiredAt!.month}/${requiredAt!.year}',
                  ),
                  trailing: const Icon(LucideIcons.calendar, size: 18),
                  onTap: () async {
                    final d = await showPomgtDatePicker(
                      context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime(2100),
                      initialDate: requiredAt ?? DateTime.now(),
                    );
                    if (d != null && mounted) setState(() => requiredAt = d);
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: PomgtColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: submit,
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Crear OP'),
        ),
      ],
    );
  }
}
