import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/pomgt_theme.dart';
import '../../core/utils/ui_copy.dart';

class DynamicMaterialAttributeForm extends StatefulWidget {
  const DynamicMaterialAttributeForm({
    super.key,
    required this.attributes,
    required this.options,
    required this.values,
    required this.onChanged,
    required this.units,
  });

  final List<Map<String, dynamic>> attributes;
  final Map<String, List<Map<String, dynamic>>> options;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Map<String, Map<String, dynamic>> units;

  @override
  State<DynamicMaterialAttributeForm> createState() =>
      _DynamicMaterialAttributeFormState();
}

class _DynamicMaterialAttributeFormState
    extends State<DynamicMaterialAttributeForm> {
  final _controllers = <String, TextEditingController>{};

  @override
  void didUpdateWidget(covariant DynamicMaterialAttributeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.attributes.map((e) => e['id'].toString()).toSet();
    for (final key in _controllers.keys.toList()) {
      if (!currentIds.contains(key)) _controllers.remove(key)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _set(String id, dynamic value) {
    final next = Map<String, dynamic>.from(widget.values)..[id] = value;
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.attributes.where((row) => row['is_active'] != false).toList()
          ..sort((a, b) {
            final section = (a['section_name'] ?? '').toString().compareTo(
              (b['section_name'] ?? '').toString(),
            );
            if (section != 0) return section;
            return ((a['sort_order'] as num?)?.toInt() ?? 0).compareTo(
              ((b['sort_order'] as num?)?.toInt() ?? 0),
            );
          });
    if (active.isEmpty) {
      return const Text(
        'Este tipo de material todavía no tiene especificaciones configuradas.',
        style: TextStyle(color: PomgtColors.muted),
      );
    }

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final attr in active) {
      final section = attr['section_name']?.toString().trim();
      groups
          .putIfAbsent(
            section?.isEmpty ?? true ? 'General' : section!,
            () => [],
          )
          .add(attr);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          if (groups.length > 1) ...[
            Text(
              entry.key,
              style: const TextStyle(
                color: PomgtColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              return Wrap(
                spacing: 16,
                runSpacing: 14,
                children: entry.value.map((attr) {
                  final full = attr['data_type'] == 'long_text';
                  return SizedBox(
                    width: wide && !full
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth,
                    child: _input(attr),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _input(Map<String, dynamic> attr) {
    final id = attr['id'].toString();
    final type = attr['data_type']?.toString() ?? 'text';
    final required = attr['is_required'] == true;
    final label = '${attr['label'] ?? 'Atributo'}${required ? ' *' : ''}';
    final unit = widget.units[attr['uom_id']?.toString()];
    final suffix = unit == null ? null : Text(unit['symbol']?.toString() ?? '');

    if (type == 'boolean') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(attr['label']?.toString() ?? 'Atributo'),
        value: widget.values[id] == true,
        onChanged: (value) => _set(id, value ?? false),
      );
    }

    if (type == 'select') {
      final rows = widget.options[id] ?? const <Map<String, dynamic>>[];
      return DropdownButtonFormField<String>(
        initialValue: widget.values[id]?.toString().isEmpty ?? true
            ? null
            : widget.values[id]?.toString(),
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: attr['help_text']?.toString(),
        ),
        items: rows
            .where((row) => row['is_active'] != false)
            .map(
              (row) => DropdownMenuItem<String>(
                value: row['option_value']?.toString(),
                child: Text(row['option_label']?.toString() ?? ''),
              ),
            )
            .toList(),
        onChanged: (value) => _set(id, value),
        validator: required
            ? (value) => value == null ? 'Campo requerido' : null
            : null,
      );
    }

    if (type == 'multiselect') {
      final selected =
          (widget.values[id] as List?)?.map((e) => e.toString()).toSet() ??
          <String>{};
      final rows = widget.options[id] ?? const <Map<String, dynamic>>[];
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: attr['help_text']?.toString(),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: rows.where((row) => row['is_active'] != false).map((row) {
            final value = row['option_value']?.toString() ?? '';
            return FilterChip(
              label: Text(row['option_label']?.toString() ?? value),
              selected: selected.contains(value),
              onSelected: (checked) {
                final next = {...selected};
                checked ? next.add(value) : next.remove(value);
                _set(id, next.toList());
              },
            );
          }).toList(),
        ),
      );
    }

    final controller = _controllers.putIfAbsent(
      id,
      () => TextEditingController(text: widget.values[id]?.toString() ?? ''),
    );
    final date = type == 'date';
    return TextFormField(
      controller: controller,
      readOnly: date,
      minLines: type == 'long_text' ? 3 : 1,
      maxLines: type == 'long_text' ? 6 : 1,
      keyboardType: type == 'integer' || type == 'decimal'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: attr['placeholder']?.toString(),
        helperText: attr['help_text']?.toString(),
        suffix: suffix,
        suffixIcon: date ? const Icon(CupertinoIcons.calendar, size: 17) : null,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'Campo requerido';
        }
        if (value == null || value.trim().isEmpty) return null;
        if (type == 'integer' && int.tryParse(value) == null) {
          return 'Entero inválido';
        }
        if (type == 'decimal' && _parseDecimal(value) == null) {
          return 'Número inválido';
        }
        return null;
      },
      onChanged: (value) => _set(id, value),
      onTap: date ? () => _pickDate(id, controller) : null,
    );
  }

  Future<void> _pickDate(String id, TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    final value = DateFormat('yyyy-MM-dd').format(picked);
    controller.text = value;
    _set(id, value);
  }
}

class DynamicMaterialAttributeViewer extends StatelessWidget {
  const DynamicMaterialAttributeViewer({
    super.key,
    required this.attributes,
    required this.values,
    required this.options,
    required this.units,
  });

  final List<Map<String, dynamic>> attributes;
  final List<Map<String, dynamic>> values;
  final Map<String, List<Map<String, dynamic>>> options;
  final Map<String, Map<String, dynamic>> units;

  @override
  Widget build(BuildContext context) {
    final valueByAttr = {
      for (final value in values)
        value['attribute_definition_id']?.toString(): value,
    };
    final rows =
        attributes
            .where(
              (attr) =>
                  attr['is_active'] != false ||
                  valueByAttr.containsKey(attr['id']?.toString()),
            )
            .toList()
          ..sort(
            (a, b) => ((a['sort_order'] as num?)?.toInt() ?? 0).compareTo(
              ((b['sort_order'] as num?)?.toInt() ?? 0),
            ),
          );
    if (rows.isEmpty) {
      return const Text(
        'Sin especificaciones configuradas.',
        style: TextStyle(color: PomgtColors.muted),
      );
    }
    return Column(
      children: rows.map((attr) {
        final value = valueByAttr[attr['id']?.toString()];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 190,
                child: Text(
                  attr['label']?.toString() ?? 'Atributo',
                  style: const TextStyle(
                    color: PomgtColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _display(attr, value),
                  style: const TextStyle(
                    color: PomgtColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _display(Map<String, dynamic> attr, Map<String, dynamic>? value) {
    if (value == null) return '—';
    final type = attr['data_type']?.toString();
    String raw;
    switch (type) {
      case 'integer':
      case 'decimal':
        raw = value['value_number']?.toString() ?? '—';
        break;
      case 'boolean':
        raw = value['value_boolean'] == true ? 'Sí' : 'No';
        break;
      case 'date':
        raw = value['value_date']?.toString() ?? '—';
        break;
      case 'multiselect':
        final selected =
            (value['value_json'] as List?)?.map((e) => e.toString()).toSet() ??
            <String>{};
        final labels =
            (options[attr['id']?.toString()] ?? const <Map<String, dynamic>>[])
                .where(
                  (option) =>
                      selected.contains(option['option_value']?.toString()),
                )
                .map((option) => option['option_label']?.toString() ?? '')
                .where((label) => label.isNotEmpty)
                .toList();
        raw = labels.isEmpty ? '—' : labels.join(', ');
        break;
      case 'select':
        final selected = value['value_text']?.toString();
        final match =
            (options[attr['id']?.toString()] ?? const <Map<String, dynamic>>[])
                .where(
                  (option) => option['option_value']?.toString() == selected,
                )
                .toList();
        raw = match.isEmpty
            ? (selected ?? '—')
            : match.first['option_label']?.toString() ?? '—';
        break;
      default:
        raw = value['value_text']?.toString() ?? '—';
    }
    final unit = units[attr['uom_id']?.toString()];
    final symbol = unit?['symbol']?.toString();
    return symbol == null || symbol.isEmpty || raw == '—'
        ? raw
        : '$raw $symbol';
  }
}

List<Map<String, dynamic>> materialAttributePayload(
  List<Map<String, dynamic>> attributes,
  Map<String, dynamic> values, {
  String? revisionId,
  List<Map<String, dynamic>> existing = const [],
  bool includeNulls = true,
}) {
  final existingByAttr = {
    for (final row in existing) row['attribute_definition_id']?.toString(): row,
  };
  return attributes.map((attr) {
    final id = attr['id'].toString();
    final type = attr['data_type']?.toString() ?? 'text';
    final value = values[id];
    final current = existingByAttr[id];
    final row = <String, dynamic>{
      if (current?['id'] != null) 'id': current!['id'],
      ...?(revisionId == null ? null : {'product_revision_id': revisionId}),
      'attribute_definition_id': id,
      'value_text': null,
      'value_number': null,
      'value_boolean': null,
      'value_date': null,
      'value_json': null,
    };
    switch (type) {
      case 'integer':
      case 'decimal':
        row['value_number'] = value == null || value.toString().trim().isEmpty
            ? null
            : _parseDecimal(value.toString());
        break;
      case 'boolean':
        row['value_boolean'] = value == true;
        break;
      case 'date':
        row['value_date'] = value == null || value.toString().trim().isEmpty
            ? null
            : value.toString();
        break;
      case 'multiselect':
        row['value_json'] = value is List ? value : const [];
        break;
      default:
        row['value_text'] = value?.toString().trim().isEmpty ?? true
            ? null
            : value.toString();
    }
    if (!includeNulls) {
      row.removeWhere((key, value) => value == null);
    }
    return row;
  }).toList();
}

String? materialAttributeValidationError(
  List<Map<String, dynamic>> attributes,
  Map<String, dynamic> values,
) {
  for (final attr in attributes) {
    final id = attr['id'].toString();
    final type = attr['data_type']?.toString() ?? 'text';
    final label = attr['label']?.toString() ?? 'Atributo';
    final required = attr['is_required'] == true;
    final value = values[id];
    final text = value?.toString().trim() ?? '';

    if (required) {
      final empty = switch (type) {
        'boolean' => false,
        'multiselect' => value is! List || value.isEmpty,
        _ => text.isEmpty,
      };
      if (empty) return '$label es requerido.';
    }

    if (text.isEmpty) continue;
    if (type == 'integer' && int.tryParse(text) == null) {
      return '$label debe ser un entero.';
    }
    if (type == 'decimal' && _parseDecimal(text) == null) {
      return '$label debe ser un número decimal.';
    }
  }
  return null;
}

num? _parseDecimal(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final normalized = text.contains(',') && !text.contains('.')
      ? text.replaceAll(',', '.')
      : text.replaceAll(',', '');
  return num.tryParse(normalized);
}

Map<String, dynamic> materialAttributeFormValues(
  List<Map<String, dynamic>> attributes,
  List<Map<String, dynamic>> values,
) {
  final attrById = {for (final attr in attributes) attr['id'].toString(): attr};
  final result = <String, dynamic>{};
  for (final value in values) {
    final attrId = value['attribute_definition_id']?.toString();
    if (attrId == null) continue;
    final type = attrById[attrId]?['data_type']?.toString() ?? 'text';
    switch (type) {
      case 'integer':
      case 'decimal':
        result[attrId] = value['value_number']?.toString();
        break;
      case 'boolean':
        result[attrId] = value['value_boolean'] == true;
        break;
      case 'date':
        result[attrId] = value['value_date']?.toString();
        break;
      case 'multiselect':
        result[attrId] = value['value_json'] is List
            ? value['value_json']
            : const [];
        break;
      default:
        result[attrId] = value['value_text']?.toString();
    }
  }
  return result;
}

String materialDataTypeLabel(String value) => UiCopy.enumLabel(value);
