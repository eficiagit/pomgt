import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';

class InfoTip extends StatelessWidget {
  const InfoTip(this.message, {super.key, this.size = 17});
  final String message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Icon(
          Icons.help_outline_rounded,
          size: size,
          color: PomgtColors.muted,
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
