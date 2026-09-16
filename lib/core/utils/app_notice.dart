import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';

void showPomgtSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  showPomgtNotice(
    context,
    title: isError ? 'No fue posible completar la acción.' : message,
    description: isError ? message : 'Cambio registrado correctamente.',
    isError: isError,
  );
}

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
      final width = media.size.width < 460 ? media.size.width - 28 : 420.0;
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
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isError
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.bell_fill,
                        color: isError ? PomgtColors.rose : PomgtColors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                height: 1.18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (description != null &&
                                description.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PomgtColors.subtle,
                                  fontSize: 12,
                                  height: 1.25,
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
                            size: 16,
                          ),
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
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
