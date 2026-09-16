import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/feature_controllers.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/app_notice.dart';
import '../../core/utils/error_copy.dart';
import '../../core/utils/ui_copy.dart';
import '../../core/widgets/detail_sections.dart';
import '../../core/widgets/entity_crud_panel.dart';
import '../../core/widgets/info_tip.dart';
import '../../core/widgets/linked_documents_panel.dart';
import '../../core/widgets/record_workspace.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../customers/customer_form_dialog.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RecordWorkspace(
      title: 'Pedidos',
      help:
          'Registra necesidades provenientes de un pedido, una OC del cliente, una orden interna, un pronóstico, una reposición o producción para inventario. Cada línea puede liberarse a una o varias órdenes de producción.',
      masterTable: 'customer_orders',
      controller: context.watch<OrdersController>(),
      createLabel: 'Nuevo pedido',
      createDialogBuilder: (_) => const _OrderFormDialog(),
      editDialogBuilder: (_, row) => _OrderFormDialog(original: row),
      detailBuilder: (context, row) => _OrderDetail(order: row),
      showRowActions: true,
      rowLeadingIcon: CupertinoIcons.doc_text,
      plainRowStatus: true,
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
    final changed = await showDialog<bool>(
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
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Selecciona una fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
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
                return const SizedBox(
                  height: 320,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
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
                          CupertinoIcons.doc_plaintext,
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
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
                          icon: const Icon(CupertinoIcons.xmark, size: 20),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _formSection(
                              context,
                              title: 'Origen y cliente',
                              help:
                                  'Indica de dónde proviene la necesidad. Pedido de cliente y OC requieren cliente; orden interna, pronóstico y reposición pueden existir sin cliente.',
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final wide = c.maxWidth >= 700;
                                  final source =
                                      DropdownButtonFormField<String>(
                                        initialValue: _sourceType,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Origen *',
                                        ),
                                        items:
                                            const [
                                                  'customer_order',
                                                  'customer_po',
                                                  'internal_order',
                                                  'forecast',
                                                  'inventory_replenishment',
                                                  'make_to_stock',
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
                                          () => _sourceType = v ?? _sourceType,
                                        ),
                                      );
                                  final customer = Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            'customer-${_customerId ?? ''}-${_customers.length}',
                                          ),
                                          initialValue:
                                              _customers.any(
                                                (e) =>
                                                    e['id']?.toString() ==
                                                    _customerId,
                                              )
                                              ? _customerId
                                              : null,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText:
                                                'Cliente${_customerRequired ? ' *' : ''}',
                                            helperText: _customers.isEmpty
                                                ? 'Todavía no hay clientes registrados.'
                                                : (_customerRequired
                                                      ? 'Requerido para el origen seleccionado.'
                                                      : 'Opcional para este origen.'),
                                          ),
                                          items: _customers
                                              .map(
                                                (e) => DropdownMenuItem(
                                                  value: e['id'].toString(),
                                                  child: Text(
                                                    _lookups.display(
                                                      Phase1Schema
                                                          .tables['customers']!,
                                                      e,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
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
                                            CupertinoIcons.add,
                                            size: 19,
                                          ),
                                        ),
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
                                  icon: const Icon(
                                    CupertinoIcons.add,
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
                              help:
                                  'La OC del cliente y la referencia externa son opcionales. Las fechas ayudan a priorizar y planear la fabricación.',
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final wide = c.maxWidth >= 700;
                                  final fields = <Widget>[
                                    TextFormField(
                                      controller: _customerPo,
                                      decoration: const InputDecoration(
                                        labelText: 'OC del cliente',
                                      ),
                                    ),
                                    TextFormField(
                                      controller: _externalReference,
                                      decoration: const InputDecoration(
                                        labelText: 'Referencia externa',
                                      ),
                                    ),
                                    TextFormField(
                                      controller: _orderDate,
                                      readOnly: true,
                                      onTap: () => _pickDate(_orderDate),
                                      decoration: const InputDecoration(
                                        labelText: 'Fecha del pedido *',
                                        suffixIcon: Icon(
                                          CupertinoIcons.calendar,
                                          size: 17,
                                        ),
                                      ),
                                      validator: (v) => v == null || v.isEmpty
                                          ? 'Selecciona la fecha'
                                          : null,
                                    ),
                                    TextFormField(
                                      controller: _deliveryDate,
                                      readOnly: true,
                                      onTap: () => _pickDate(_deliveryDate),
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Fecha solicitada de entrega',
                                        suffixIcon: Icon(
                                          CupertinoIcons.calendar,
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
                              help:
                                  'La moneda y condición de pago se precargan desde el cliente cuando están configuradas, pero pueden modificarse para este pedido.',
                              child: LayoutBuilder(
                                builder: (context, c) {
                                  final wide = c.maxWidth >= 700;
                                  final fields = <Widget>[
                                    DropdownButtonFormField<String>(
                                      initialValue: _priority,
                                      decoration: const InputDecoration(
                                        labelText: 'Prioridad *',
                                      ),
                                      items:
                                          const [
                                                'low',
                                                'normal',
                                                'high',
                                                'urgent',
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
                                        () => _priority = v ?? _priority,
                                      ),
                                    ),
                                    DropdownButtonFormField<String>(
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
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'currency-${_currencyCode ?? ''}',
                                      ),
                                      initialValue:
                                          _currencies.any(
                                            (e) =>
                                                e['code']?.toString() ==
                                                _currencyCode,
                                          )
                                          ? _currencyCode
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Moneda *',
                                      ),
                                      items: _currencies
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e['code'].toString(),
                                              child: Text(
                                                _lookups.display(
                                                  Phase1Schema
                                                      .tables['currencies']!,
                                                  e,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _currencyCode = v),
                                      validator: (v) => v == null
                                          ? 'Selecciona una moneda'
                                          : null,
                                    ),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'payment-${_paymentTermId ?? ''}',
                                      ),
                                      initialValue:
                                          _paymentTerms.any(
                                            (e) =>
                                                e['id']?.toString() ==
                                                _paymentTermId,
                                          )
                                          ? _paymentTermId
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Condición de pago',
                                      ),
                                      items: _paymentTerms
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e['id'].toString(),
                                              child: Text(
                                                _lookups.display(
                                                  Phase1Schema
                                                      .tables['payment_terms']!,
                                                  e,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _paymentTermId = v),
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
                                help:
                                    'Solo se muestran contactos y direcciones del cliente seleccionado. Al guardar, POMGT conserva una copia histórica de las direcciones elegidas.',
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final wide = c.maxWidth >= 700;
                                    final contact = DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'contact-${_contactId ?? ''}-${_contacts.length}',
                                      ),
                                      initialValue:
                                          _contacts.any(
                                            (e) =>
                                                e['id']?.toString() ==
                                                _contactId,
                                          )
                                          ? _contactId
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Contacto del cliente',
                                      ),
                                      items: _contacts
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e['id'].toString(),
                                              child: Text(
                                                _lookups.display(
                                                  Phase1Schema
                                                      .tables['customer_contacts']!,
                                                  e,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _contactId = v),
                                    );
                                    Widget addressField(
                                      String label,
                                      String? value,
                                      ValueChanged<String?> change,
                                    ) => DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        '$label-${value ?? ''}-${_addresses.length}',
                                      ),
                                      initialValue:
                                          _addresses.any(
                                            (e) => e['id']?.toString() == value,
                                          )
                                          ? value
                                          : null,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: label,
                                      ),
                                      items: _addresses
                                          .map(
                                            (e) => DropdownMenuItem(
                                              value: e['id'].toString(),
                                              child: Text(
                                                _addressLabel(e),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
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
                            ],
                            const SizedBox(height: 26),
                            _formSection(
                              context,
                              title: 'Notas e instrucciones',
                              help:
                                  'Usa notas para contexto administrativo e instrucciones especiales para requisitos que deben acompañar la planeación o producción.',
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _instructions,
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Instrucciones especiales',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _notes,
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Notas',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 10),
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
                                      ? Icons.save_outlined
                                      : Icons.add_rounded,
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
      final changed = await showDialog<bool>(
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
                icon: CupertinoIcons.doc_text,
                title: order['order_number']?.toString() ?? 'Pedido',
                subtitle: parts.join(' · '),
                status: order['status']?.toString(),
                plainStatus: true,
                help:
                    'Cabecera del pedido. Las direcciones pueden conservar una copia histórica para que cambios futuros del cliente no modifiquen pedidos anteriores.',
                onEdit: edit,
              ),
              Expanded(
                child: DetailSections(
                  sections: [
                    DetailSection(
                      label: 'Resumen',
                      help: 'Origen, cliente, fechas y condiciones.',
                      icon: Icons.dashboard_outlined,
                      child: _OrderSummary(order: order),
                    ),
                    DetailSection(
                      label: 'Líneas',
                      help: 'Productos, cantidades, precios y requisitos.',
                      icon: Icons.list_alt_outlined,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: EntityCrudPanel(
                          table: 'customer_order_lines',
                          repository: generic,
                          lookups: lookups,
                          fixedValues: {'customer_order_id': id},
                          title: 'Líneas del pedido',
                          description:
                              'Productos y cantidades solicitadas. POMGT conserva la descripción y requisitos de cada línea para mantener la trazabilidad del pedido original.',
                          flatList: true,
                        ),
                      ),
                    ),
                    DetailSection(
                      label: 'Producción',
                      help: 'Liberación de líneas a producción.',
                      icon: Icons.precision_manufacturing_outlined,
                      child: _ReleasePanel(orderId: id),
                    ),
                    DetailSection(
                      label: 'Documentos',
                      help: 'OC, capturas, correos y especificaciones.',
                      icon: Icons.folder_copy_outlined,
                      child: LinkedDocumentsPanel(
                        entityField: 'customer_order_id',
                        entityId: id,
                        title: 'Documentos del pedido',
                        help:
                            'Carga y previsualiza la orden de compra del cliente, capturas de mensajes, correos, especificaciones u otra evidencia relacionada con el pedido.',
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
        return SingleChildScrollView(
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
    final result = await showDialog<_ReleaseRequest>(
      context: context,
      builder: (_) => _ReleaseDialog(maxQuantity: pending),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<OrderRepository>().releaseLineToProduction(
        orderLineId: line['customer_order_line_id'].toString(),
        quantities: result.quantities,
        requiredAt: result.requiredAt,
        priority: result.priority,
      );
      if (!mounted) return;
      showPomgtNotice(context, title: 'Orden(es) de producción creada(s).');
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
                icon: const Icon(CupertinoIcons.refresh, size: 18),
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
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                if (snapshot.hasError)
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        ErrorCopy.message(
                          snapshot.error!,
                          fallback:
                              'No fue posible cargar la información del pedido.',
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
                    ];
                final rows = data[0];
                final products = data[1];
                final units = data[2];
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

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final requested =
                        (r['requested_quantity'] as num?)?.toDouble() ?? 0;
                    final allocated =
                        (r['allocated_quantity'] as num?)?.toDouble() ?? 0;
                    final pending =
                        (r['quantity_pending_release'] as num?)?.toDouble() ??
                        0;
                    final progress = requested == 0
                        ? 0.0
                        : (allocated / requested).clamp(0.0, 1.0).toDouble();
                    final uom = unitName(r['uom_id']);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Wrap(
                        spacing: compact ? 12 : 18,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: compact ? double.infinity : 360,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 4,
                                  backgroundColor: PomgtColors.line,
                                  color: PomgtColors.blue,
                                ),
                              ],
                            ),
                          ),
                          _Amount(label: 'Solicitado', value: requested),
                          _Amount(label: 'Asignado', value: allocated),
                          _Amount(label: 'Pendiente', value: pending),
                          FilledButton.tonal(
                            onPressed: pending > 0 ? () => _release(r) : null,
                            child: Text(pending > 0 ? 'Crear OP' : 'Liberado'),
                          ),
                        ],
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
        () => error =
            'Ingresa cantidades válidas separadas por coma. Ej. 100000, 50000, 50000',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 640;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(CupertinoIcons.hammer, size: 21),
          SizedBox(width: 10),
          Expanded(child: Text('Crear orden(es) de producción')),
          SizedBox(width: 7),
          InfoTip(
            'Puedes dividir una sola línea en varias OP. Cada cantidad se convierte en una orden independiente y queda asignada a esta línea.',
          ),
        ],
      ),
      content: SizedBox(
        width: compact ? screenWidth - 56 : 560,
        child: SingleChildScrollView(
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
              DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Prioridad'),
                items: const ['low', 'normal', 'high', 'urgent']
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(UiCopy.enumLabel(e)),
                      ),
                    )
                    .toList(),
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
                trailing: const Icon(CupertinoIcons.calendar, size: 18),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: submit, child: const Text('Crear OP')),
      ],
    );
  }
}
