import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    required this.icon,
    this.maxLines = 1,
  });

  final String text;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: PomgtColors.navIcon),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ],
    );
  }
}
