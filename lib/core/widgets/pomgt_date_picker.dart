import 'motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';

/// POMGT's own date and time pickers.
///
/// Flutter's stock Material pickers (month calendar + clock dial) tested as
/// confusing, so these replace them everywhere a date or time is picked in
/// the app: a centered month grid with a Continuar button for dates, and a
/// centered iPhone-style hour / minute / AM-PM wheel for time.

const _weekdayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Opens POMGT's calendar picker. Pick a day, then confirm with Continuar.
Future<DateTime?> showPomgtDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  return showPomgtDialog<DateTime>(
    context: context,
    builder: (_) => Center(
      child: _PomgtDatePickerDialog(
        initialDate: initialDate ?? now,
        firstDate: firstDate ?? DateTime(now.year - 20),
        lastDate: lastDate ?? DateTime(now.year + 20),
      ),
    ),
  );
}

/// Opens POMGT's time picker: hour / minute / AM-PM wheels, like iOS.
Future<TimeOfDay?> showPomgtTimePicker(
  BuildContext context, {
  TimeOfDay? initialTime,
}) {
  return showPomgtDialog<TimeOfDay>(
    context: context,
    builder: (_) => Center(
      child: _PomgtTimePickerDialog(
        initialTime: initialTime ?? TimeOfDay.now(),
      ),
    ),
  );
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: SizedBox(width: width.clamp(0.0, maxWidth), child: child),
      ),
    );
  }
}

class _PomgtDatePickerDialog extends StatefulWidget {
  const _PomgtDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_PomgtDatePickerDialog> createState() => _PomgtDatePickerDialogState();
}

class _PomgtDatePickerDialogState extends State<_PomgtDatePickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  DateTime get _first => DateTime(
    widget.firstDate.year,
    widget.firstDate.month,
    widget.firstDate.day,
  );
  DateTime get _last => DateTime(
    widget.lastDate.year,
    widget.lastDate.month,
    widget.lastDate.day,
  );

  @override
  void initState() {
    super.initState();
    _selected = _clamp(widget.initialDate);
    _month = DateTime(_selected.year, _selected.month);
  }

  DateTime _clamp(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(_first)) return _first;
    if (d.isAfter(_last)) return _last;
    return d;
  }

  bool _inRange(DateTime day) => !day.isBefore(_first) && !day.isAfter(_last);

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _goToday() {
    final today = _clamp(DateTime.now());
    setState(() {
      _month = DateTime(today.year, today.month);
      _selected = today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();
    final today = DateTime.now();

    return _PickerCard(
      width: 308,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Selecciona una fecha',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: PomgtColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.chevronLeft, size: 17),
                onPressed: () => _changeMonth(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[_month.month - 1]} ${_month.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: PomgtColors.ink,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.chevronRight, size: 17),
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: PomgtColors.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _dayCell(r * 7 + c, leading, daysInMonth, today),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: _goToday, child: const Text('Hoy')),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('Continuar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(int index, int leading, int daysInMonth, DateTime today) {
    final dayNum = index - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 34);
    }
    final date = DateTime(_month.year, _month.month, dayNum);
    final enabled = _inRange(date);
    final isSelected = _isSameDay(_selected, date);
    final isToday = _isSameDay(today, date);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => setState(() => _selected = date) : null,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? PomgtColors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isToday && !isSelected
                ? Border.all(color: PomgtColors.blue, width: 1)
                : null,
          ),
          child: Text(
            '$dayNum',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: !enabled
                  ? PomgtColors.subtle
                  : isSelected
                  ? Colors.white
                  : PomgtColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _PomgtTimePickerDialog extends StatefulWidget {
  const _PomgtTimePickerDialog({required this.initialTime});
  final TimeOfDay initialTime;

  @override
  State<_PomgtTimePickerDialog> createState() => _PomgtTimePickerDialogState();
}

class _PomgtTimePickerDialogState extends State<_PomgtTimePickerDialog> {
  late int _hour12 = _to12(widget.initialTime.hour);
  late int _minute = widget.initialTime.minute;
  // 0 = AM, 1 = PM.
  late int _period = widget.initialTime.hour >= 12 ? 1 : 0;

  static int _to12(int hour24) {
    final h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  TimeOfDay get _result {
    var hour24 = _hour12 % 12;
    if (_period == 1) hour24 += 12;
    return TimeOfDay(hour: hour24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    return _PickerCard(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Selecciona una hora',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              color: PomgtColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                IgnorePointer(
                  child: Container(
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: PomgtColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _wheel(
                        values: [for (var i = 1; i <= 12; i++) '$i'],
                        selected: _hour12 - 1,
                        onChanged: (v) => setState(() => _hour12 = v + 1),
                      ),
                    ),
                    const Text(
                      ':',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: PomgtColors.ink,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: _wheel(
                        values: [
                          for (var i = 0; i < 60; i++)
                            i.toString().padLeft(2, '0'),
                        ],
                        selected: _minute,
                        onChanged: (v) => setState(() => _minute = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: _wheel(
                        values: const ['a. m.', 'p. m.'],
                        selected: _period,
                        onChanged: (v) => setState(() => _period = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _result),
                  child: const Text('Continuar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required List<String> values,
    required int selected,
    required ValueChanged<int> onChanged,
  }) {
    return CupertinoPicker(
      itemExtent: 34,
      scrollController: FixedExtentScrollController(initialItem: selected),
      onSelectedItemChanged: onChanged,
      selectionOverlay: const SizedBox.shrink(),
      children: [
        for (final value in values)
          Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15.5,
                color: PomgtColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
