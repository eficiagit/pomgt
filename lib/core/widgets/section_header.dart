import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';
import 'info_tip.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.help,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String help;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact ? MediaQuery.sizeOf(context).width - 56 : 640,
              ),
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            InfoTip(help),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(color: PomgtColors.muted, height: 1.35),
          ),
        ],
      ],
    );
    if (trailing == null) return titleBlock;
    // A Wrap would let `trailing` float right next to a short title instead
    // of pinning it to the far right — push it there explicitly (and stack
    // it below, full width, once the panel is too narrow for both).
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [titleBlock, const SizedBox(height: 10), trailing!],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 12),
        trailing!,
      ],
    );
  }
}
