import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/pomgt_theme.dart';

/// Shared presentation for content that is still loading. Button progress stays
/// inline; compact containers retain a small indicator instead of a skeleton.
class PomgtLoading extends StatelessWidget {
  const PomgtLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Cargando información',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 200 || constraints.maxHeight < 180) {
              return Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    value: reduceMotion ? .75 : null,
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: TickerMode(
                    enabled: !reduceMotion,
                    child: Skeletonizer.zone(
                      effect: const PulseEffect(
                        from: PomgtColors.line,
                        to: PomgtColors.surfaceAlt,
                        duration: Duration(milliseconds: 1400),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(height: 20),
                            Row(
                              children: [
                                const Bone.square(size: 32),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FractionallySizedBox(
                                        widthFactor: i == 1 ? .65 : .85,
                                        child: const Bone(height: 12),
                                      ),
                                      const SizedBox(height: 8),
                                      const FractionallySizedBox(
                                        widthFactor: .45,
                                        child: Bone(height: 8),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
