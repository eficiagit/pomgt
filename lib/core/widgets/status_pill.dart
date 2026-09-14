import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';
import '../utils/ui_copy.dart';

class StatusPill extends StatelessWidget {
  const StatusPill(this.value, {super.key, this.plain = false});
  final String value;
  final bool plain;

  Color get color {
    final v = value.toLowerCase();
    if (v.contains('active') ||
        v.contains('activo') ||
        v.contains('approved') ||
        v.contains('aprob') ||
        v.contains('completed') ||
        v.contains('complet') ||
        v.contains('termin') ||
        v.contains('delivered')) {
      return PomgtColors.success;
    }
    if (v.contains('cancel') ||
        v.contains('rechaz') ||
        v.contains('reject') ||
        v.contains('obsolete') ||
        v.contains('obsoleto') ||
        v.contains('critical')) {
      return PomgtColors.danger;
    }
    if (v.contains('pending') ||
        v.contains('pendiente') ||
        v.contains('hold') ||
        v.contains('paus') ||
        v.contains('draft') ||
        v.contains('borrador')) {
      return PomgtColors.warning;
    }
    return PomgtColors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final isDraft =
        value.toLowerCase().contains('draft') ||
        value.toLowerCase().contains('borrador');
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: plain ? 8 : 6,
          height: plain ? 8 : 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: plain ? 8 : 6),
        Text(
          UiCopy.enumLabel(value),
          style: TextStyle(
            color: plain ? PomgtColors.ink : color,
            fontSize: plain ? 12 : 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );

    if (plain) {
      return content;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: isDraft
          ? null
          : BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: PomgtRadii.borderSm,
            ),
      child: content,
    );
  }
}
