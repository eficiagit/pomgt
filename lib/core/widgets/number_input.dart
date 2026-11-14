import 'package:flutter/services.dart';

/// Formats a numeric text field with thousands separators while typing
/// (`1234567.5` → `1,234,567.5`) and keeps the caret where the user expects it.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({
    this.allowDecimal = true,
    this.allowNegative = false,
  });

  final bool allowDecimal;
  final bool allowNegative;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final caret = newValue.selection.isValid
        ? newValue.selection.extentOffset.clamp(0, text.length)
        : text.length;

    final buffer = StringBuffer();
    var negative = false;
    var seenDot = false;
    var significantBeforeCaret = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      var keep = false;
      if (ch == '-' && allowNegative && !negative && buffer.isEmpty) {
        negative = true;
        keep = true;
      } else if (ch == '.' && allowDecimal && !seenDot) {
        seenDot = true;
        buffer.write('.');
        keep = true;
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        buffer.write(ch);
        keep = true;
      }
      if (keep && i < caret) significantBeforeCaret++;
    }

    final raw = buffer.toString();
    final dot = raw.indexOf('.');
    var intPart = dot == -1 ? raw : raw.substring(0, dot);
    final decimals = dot == -1 ? '' : raw.substring(dot);
    intPart = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped = intPart.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = '${negative ? '-' : ''}$grouped$decimals';

    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < significantBeforeCaret) {
      if (formatted[offset] != ',') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Formats an existing value (`80000`, `1234.5`) for display in a numeric field.
String formatNumberText(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (text.isEmpty) return '';
  return const ThousandsInputFormatter(allowNegative: true)
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
      .text;
}

/// Parses text written in a [ThousandsInputFormatter] field.
num? parseNumberText(String? text) {
  if (text == null) return null;
  final clean = text.replaceAll(',', '').trim();
  if (clean.isEmpty) return null;
  return num.tryParse(clean);
}
