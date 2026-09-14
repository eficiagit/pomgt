import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';

class PomgtButton extends StatelessWidget {
  const PomgtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = true,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 1.7),
          )
        else if (icon != null)
          Icon(icon, size: 17),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );

    if (!primary) {
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          elevation: 0,
          foregroundColor: PomgtColors.ink,
          backgroundColor: PomgtColors.canvas,
          side: const BorderSide(color: PomgtColors.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: const RoundedRectangleBorder(
            borderRadius: PomgtRadii.borderSm,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
        child: child,
      );
    }

    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: PomgtColors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: const RoundedRectangleBorder(borderRadius: PomgtRadii.borderSm),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
      child: child,
    );
  }
}
