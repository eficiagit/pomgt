import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';

void showPomgtNotice(
  BuildContext context, {
  required String title,
  String? description,
  bool isError = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  Timer? timer;
  void close() {
    timer?.cancel();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) {
      final media = MediaQuery.of(context);
      final width = media.size.width < 560 ? media.size.width - 28 : 560.0;
      return Positioned(
        top: media.padding.top + 18,
        right: 14,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset((1 - value) * 18, 0),
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: width),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PomgtColors.ink,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isError ? PomgtColors.danger : PomgtColors.blue)
                        .withValues(alpha: .28),
                  ),
                  boxShadow: PomgtShadows.card,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 10, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (description != null &&
                                description.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                description,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.subtle,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Cerrar',
                        child: IconButton(
                          onPressed: close,
                          icon: const Icon(
                            CupertinoIcons.xmark,
                            color: PomgtColors.subtle,
                            size: 18,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
  timer = Timer(const Duration(seconds: 4), close);
}
