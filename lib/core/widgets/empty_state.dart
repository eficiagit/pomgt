import 'motion.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = LucideIcons.inbox,
  });
  final String title;
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PomgtReveal(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight.isFinite && constraints.maxHeight < 260;
          final content = Center(
            child: Padding(
              padding: EdgeInsets.all(compact ? 12 : 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!compact) ...[
                      SizedBox(
                        width: 144,
                        height: 104,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SvgPicture.asset(
                              'assets/illustrations/empty-records.svg',
                              excludeFromSemantics: true,
                            ),
                            Positioned(
                              left: 51,
                              top: 51,
                              child: Icon(
                                icon,
                                size: 22,
                                color: PomgtColors.blueHover,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ] else ...[
                      Icon(icon, size: 20, color: PomgtColors.ink),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: compact ? 4 : 7),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 1 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: const TextStyle(
                        color: PomgtColors.muted,
                        height: 1.45,
                      ),
                    ),
                    if (action != null) ...[
                      SizedBox(height: compact ? 8 : 18),
                      action!,
                    ],
                  ],
                ),
              ),
            ),
          );
          if (!constraints.maxHeight.isFinite) return content;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: content,
            ),
          );
        },
      ),
    );
  }
}
