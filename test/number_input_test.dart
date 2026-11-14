import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomgt/core/widgets/number_input.dart';

TextEditingValue _type(ThousandsInputFormatter f, String from, String to, [int? caret]) =>
    f.formatEditUpdate(
      TextEditingValue(text: from),
      TextEditingValue(
        text: to,
        selection: TextSelection.collapsed(offset: caret ?? to.length),
      ),
    );

void main() {
  const f = ThousandsInputFormatter();
  test('groups thousands while typing', () {
    expect(_type(f, '8000', '80000').text, '80,000');
    expect(_type(f, '1,234', '1,2345').text, '12,345');
    expect(_type(f, '', '1234567.5').text, '1,234,567.5');
    expect(_type(f, '', '0005').text, '5');
    expect(_type(f, '', '1.2.3').text, '1.23');
    expect(_type(f, '', 'abc').text, '');
  });
  test('caret stays after the typed digit', () {
    // "1,234" -> user inserts 9 after the "1" => "19,234" caret after 9
    final v = _type(f, '1,234', '19,234', 2);
    expect(v.text, '19,234');
    expect(v.selection.baseOffset, 2);
  });
  test('negative and integer-only modes', () {
    const n = ThousandsInputFormatter(allowNegative: true);
    expect(_type(n, '', '-1234').text, '-1,234');
    const i = ThousandsInputFormatter(allowDecimal: false);
    expect(_type(i, '', '12.5').text, '125');
  });
  test('helpers', () {
    expect(formatNumberText(80000), '80,000');
    expect(formatNumberText('1234.50'), '1,234.50');
    expect(parseNumberText('1,234.5'), 1234.5);
    expect(parseNumberText(''), null);
  });
}
