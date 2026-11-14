import 'motion.dart';

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
        if (busy || icon != null)
          AnimatedSwitcher(
            duration: PomgtMotion.duration(context, PomgtMotion.fast),
            child: busy
                ? SizedBox(
                    key: const ValueKey('busy'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation(
                        primary ? Colors.white : PomgtColors.ink,
                      ),
                    ),
                  )
                : Icon(icon, key: ValueKey(icon), size: 18),
          ),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    final handler = busy ? null : onPressed;
    return primary
        ? FilledButton(onPressed: handler, child: child)
        : OutlinedButton(onPressed: handler, child: child);
  }
}
