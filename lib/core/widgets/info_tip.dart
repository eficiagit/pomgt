import 'package:forui/forui.dart' as forui;

import '../theme/component_theme.dart';
import 'motion.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';

class InfoTip extends StatelessWidget {
  const InfoTip(this.message, {super.key, this.size = 17});
  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return forui.FTheme(
      data: PomgtComponentTheme.foruiTheme,
      accessibility: PomgtComponentTheme.motionAccessibility(context),
      child: forui.FTooltip(
        style: forui.FTooltipStyle(
          decoration: const BoxDecoration(
            color: PomgtColors.ink,
            borderRadius: PomgtRadii.borderSm,
            boxShadow: PomgtShadows.overlay,
          ),
          textStyle: const TextStyle(
            fontFamily: PomgtTypography.body,
            color: Colors.white,
            fontSize: 12,
            height: 1.4,
          ),
          hapticFeedback: () async {},
          constraints: const BoxConstraints(maxWidth: 360),
          hoverEnterDuration: PomgtMotion.medium,
          longPressExitDuration: const Duration(seconds: 6),
        ),
        tipBuilder: (context, controller) => Text(message),
        child: Semantics(
          label: message,
          child: MouseRegion(
            cursor: SystemMouseCursors.help,
            child: Icon(
              LucideIcons.circleHelp,
              size: size,
              color: PomgtColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiqueta reutilizable para pestañas principales con ayuda contextual al pasar
/// el cursor. Mantiene el texto limpio y evita que el usuario tenga que adivinar
/// qué información vive dentro de cada sección.
class HelpTab extends StatelessWidget {
  const HelpTab({super.key, required this.label, required this.help});
  final String label;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 6),
        InfoTip(help, size: 13.5),
      ],
    );
  }
}
