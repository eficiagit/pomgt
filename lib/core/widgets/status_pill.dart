import 'motion.dart';

import 'package:shadcn_ui/shadcn_ui.dart' show ShadBadge, ShadTheme;

import '../theme/component_theme.dart';

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
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: plain ? 8 : 6,
          height: plain ? 8 : 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: plain ? 8 : 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(
            UiCopy.enumLabel(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: plain
                  ? PomgtColors.ink
                  : Color.alphaBlend(
                      Colors.black.withValues(alpha: .27),
                      color,
                    ),
              fontSize: plain ? 12 : 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (plain) {
      return PomgtAnimatedValue(value: value, child: content);
    }

    final badge = ShadBadge.outline(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      backgroundColor: color.withValues(alpha: .08),
      hoverBackgroundColor: color.withValues(alpha: .08),
      foregroundColor: PomgtColors.ink,
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: .20)),
      ),
      child: content,
    );
    final themed = ShadTheme.maybeOf(context) == null
        ? ShadTheme(data: PomgtComponentTheme.shadTheme, child: badge)
        : badge;
    return PomgtAnimatedValue(value: value, child: themed);
  }
}
