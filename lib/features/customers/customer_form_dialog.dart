import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/error_copy.dart';
import '../../core/widgets/info_tip.dart';
import '../../data/phase1_schema.dart';
import '../../data/repositories/generic_repository.dart';
import '../../data/repositories/lookup_repository.dart';

/// Formulario especializado para clientes. Mantiene la estructura técnica de
/// PostgreSQL fuera de la interfaz y solamente presenta datos que un usuario
/// necesita entender para dar de alta o editar un cliente.
class CustomerFormDialog extends StatefulWidget {
  const CustomerFormDialog({super.key, this.original, this.onSaved});

  final Map<String, dynamic>? original;
  final ValueChanged<Map<String, dynamic>>? onSaved;

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _legalName = TextEditingController();
  final _tradeName = TextEditingController();
  final _taxId = TextEditingController();
  final _website = TextEditingController();
  final _notes = TextEditingController();

  String? _countryCode = 'MX';
  String? _currencyCode;
  String? _paymentTermId;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  late Future<List<List<Map<String, dynamic>>>> _future;
  List<Map<String, dynamic>> _currencies = const [];
  List<Map<String, dynamic>> _paymentTerms = const [];

  GenericRepository get _repository => context.read<GenericRepository>();
  LookupRepository get _lookups => context.read<LookupRepository>();
  bool get _editing => widget.original != null;

  @override
  void initState() {
    super.initState();
    final row = widget.original;
    if (row != null) {
      _legalName.text = row['legal_name']?.toString() ?? '';
      _tradeName.text = row['trade_name']?.toString() ?? '';
      _taxId.text = row['tax_id']?.toString() ?? '';
      _website.text = row['website']?.toString() ?? '';
      _notes.text = row['notes']?.toString() ?? '';
      _countryCode = _normalizeCountry(row['tax_country_code']?.toString());
      _currencyCode = row['default_currency_code']?.toString();
      _paymentTermId = row['payment_term_id']?.toString();
      _isActive = row['is_active'] != false;
    }
    _future = _load();
  }

  @override
  void dispose() {
    _legalName.dispose();
    _tradeName.dispose();
    _taxId.dispose();
    _website.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<List<List<Map<String, dynamic>>>> _load() async {
    final result = await Future.wait([
      _lookups.rows('currencies'),
      _lookups.rows('payment_terms'),
    ]);
    _currencies = result[0];
    _paymentTerms = result[1];
    if (_currencyCode == null && _currencies.isNotEmpty) {
      final mxn = _currencies
          .where((row) => row['code']?.toString() == 'MXN')
          .toList();
      _currencyCode = (mxn.isNotEmpty ? mxn.first : _currencies.first)['code']
          ?.toString();
    }
    return result;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = <String, dynamic>{
        'legal_name': _legalName.text.trim(),
        'trade_name': _nullable(_tradeName.text),
        'tax_id': _nullable(_taxId.text),
        'tax_country_code': _countryCode,
        'website': _nullable(_website.text),
        'default_currency_code': _currencyCode,
        'payment_term_id': _paymentTermId,
        'notes': _nullable(_notes.text),
        'is_active': _isActive,
      };
      final spec = Phase1Schema.tables['customers']!;
      final saved = _editing
          ? await _repository.updateAnyRow(spec, widget.original!, values)
          : await _repository.createRow(spec, values);
      _lookups.invalidate('customers');
      widget.onSaved?.call(saved);
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
          maxWidth: 860,
          maxHeight: MediaQuery.sizeOf(context).height * .90,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
          child: FutureBuilder<List<List<Map<String, dynamic>>>>(
            future: _future,
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
                  height: 280,
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
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            CupertinoIcons.building_2_fill,
                            size: 25,
                            color: PomgtColors.ink,
                          ),
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
                                          ? 'Editar cliente'
                                          : 'Nuevo cliente',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const InfoTip(
                                    'Crea la ficha maestra del cliente. El código de cliente se genera automáticamente y nunca necesitas capturar identificadores internos.',
                                    size: 16,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _editing
                                    ? 'Actualiza la información principal. Direcciones, contactos, documentos y requisitos se administran desde la ficha del cliente.'
                                    : 'Registra primero sus datos fiscales y comerciales. Después podrás completar direcciones, contactos, documentos y requisitos.',
                                style: const TextStyle(
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
                            _section(
                              context,
                              title: 'Información fiscal',
                              help:
                                  'Datos utilizados para identificar fiscalmente al cliente. México y Estados Unidos se guardan internamente como MX y US para cumplir con el formato de la base de datos.',
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide = constraints.maxWidth >= 680;
                                  final fields = <Widget>[
                                    TextFormField(
                                      controller: _legalName,
                                      decoration: const InputDecoration(
                                        labelText: 'Razón social *',
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Ingresa la razón social'
                                          : null,
                                    ),
                                    TextFormField(
                                      controller: _taxId,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'RFC / identificación fiscal',
                                      ),
                                    ),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'country-${_countryCode ?? ''}',
                                      ),
                                      initialValue:
                                          const {
                                            'MX',
                                            'US',
                                          }.contains(_countryCode)
                                          ? _countryCode
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'País fiscal',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'MX',
                                          child: Text('México'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'US',
                                          child: Text('Estados Unidos'),
                                        ),
                                      ],
                                      onChanged: (value) =>
                                          setState(() => _countryCode = value),
                                    ),
                                  ];
                                  return _responsiveFields(
                                    constraints.maxWidth,
                                    fields,
                                    wide: wide,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 28),
                            _section(
                              context,
                              title: 'Información comercial',
                              help:
                                  'Nombre que verá el equipo en el sistema, sitio web y datos generales de referencia.',
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final fields = <Widget>[
                                    TextFormField(
                                      controller: _tradeName,
                                      decoration: const InputDecoration(
                                        labelText: 'Nombre comercial',
                                      ),
                                    ),
                                    TextFormField(
                                      controller: _website,
                                      decoration: const InputDecoration(
                                        labelText: 'Sitio web',
                                        hintText: 'https://empresa.com',
                                      ),
                                      validator: (value) {
                                        final text = value?.trim() ?? '';
                                        if (text.isEmpty) return null;
                                        final uri = Uri.tryParse(text);
                                        return uri == null ||
                                                (!uri.hasScheme &&
                                                    !text.contains('.'))
                                            ? 'Ingresa un sitio web válido'
                                            : null;
                                      },
                                    ),
                                  ];
                                  return _responsiveFields(
                                    constraints.maxWidth,
                                    fields,
                                    wide: constraints.maxWidth >= 680,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 28),
                            _section(
                              context,
                              title: 'Condiciones predeterminadas',
                              help:
                                  'Estos valores se propondrán automáticamente al crear pedidos para el cliente y podrán cambiarse en cada pedido.',
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final fields = <Widget>[
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'currency-${_currencyCode ?? ''}',
                                      ),
                                      initialValue:
                                          _currencies.any(
                                            (row) =>
                                                row['code']?.toString() ==
                                                _currencyCode,
                                          )
                                          ? _currencyCode
                                          : null,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Moneda predeterminada *',
                                      ),
                                      items: _currencies
                                          .map(
                                            (row) => DropdownMenuItem<String>(
                                              value: row['code']?.toString(),
                                              child: Text(
                                                _lookups.display(
                                                  Phase1Schema
                                                      .tables['currencies']!,
                                                  row,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) =>
                                          setState(() => _currencyCode = value),
                                      validator: (value) => value == null
                                          ? 'Selecciona una moneda'
                                          : null,
                                    ),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'term-${_paymentTermId ?? ''}',
                                      ),
                                      initialValue:
                                          _paymentTerms.any(
                                            (row) =>
                                                row['id']?.toString() ==
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
                                            (row) => DropdownMenuItem<String>(
                                              value: row['id']?.toString(),
                                              child: Text(
                                                _lookups.display(
                                                  Phase1Schema
                                                      .tables['payment_terms']!,
                                                  row,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) => setState(
                                        () => _paymentTermId = value,
                                      ),
                                    ),
                                  ];
                                  return _responsiveFields(
                                    constraints.maxWidth,
                                    fields,
                                    wide: constraints.maxWidth >= 680,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 28),
                            _section(
                              context,
                              title: 'Notas y estado',
                              help:
                                  'Las notas son contexto administrativo general. Desactivar un cliente lo conserva en el historial pero permite retirarlo de flujos nuevos cuando la interfaz aplique filtros de activos.',
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _notes,
                                    minLines: 2,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                      labelText: 'Notas',
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: const Text(
                                      'Cliente activo',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      'Mantén activo al cliente mientras pueda utilizarse en nuevas operaciones.',
                                    ),
                                    value: _isActive,
                                    onChanged: (value) =>
                                        setState(() => _isActive = value),
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
                                      : 'Crear cliente'),
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

  Widget _section(
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

  Widget _responsiveFields(
    double width,
    List<Widget> fields, {
    required bool wide,
  }) {
    if (!wide) {
      return Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            fields[i],
          ],
        ],
      );
    }
    final itemWidth = (width - 26) / 2;
    return Wrap(
      spacing: 26,
      runSpacing: 16,
      children: fields
          .map((field) => SizedBox(width: itemWidth, child: field))
          .toList(),
    );
  }

  static String? _normalizeCountry(String? value) {
    final upper = value?.trim().toUpperCase();
    if (upper == 'MX' || upper == 'MEXICO' || upper == 'MÉXICO') return 'MX';
    if (upper == 'US' ||
        upper == 'USA' ||
        upper == 'UNITED STATES' ||
        upper == 'ESTADOS UNIDOS')
      return 'US';
    return upper == null || upper.isEmpty ? 'MX' : null;
  }

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();
}
