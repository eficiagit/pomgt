import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';
import '../widgets/motion.dart';

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
  final motionKey = GlobalKey<_NoticeMotionState>();
  var closing = false;
  void close() {
    if (closing) return;
    closing = true;
    timer?.cancel();
    final motion = motionKey.currentState;
    if (motion == null) {
      if (entry.mounted) entry.remove();
      return;
    }
    unawaited(
      motion.hide().then((_) {
        if (entry.mounted) entry.remove();
      }),
    );
  }

  entry = OverlayEntry(
    builder: (context) {
      final media = MediaQuery.of(context);
      final width = media.size.width < 460 ? media.size.width - 28 : 420.0;
      return Positioned(
        top: media.padding.top + 18,
        right: 14,
        child: _NoticeMotion(
          key: motionKey,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: width),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: PomgtColors.canvas,
                  borderRadius: PomgtRadii.borderMd,
                  border: Border.all(color: PomgtColors.line),
                  boxShadow: PomgtShadows.overlay,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isError
                                    ? LucideIcons.triangleAlert
                                    : LucideIcons.circleCheck,
                                color: isError
                                    ? PomgtColors.danger
                                    : PomgtColors.success,
                                size: 17,
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
                                        color: PomgtColors.ink,
                                        fontSize: 14,
                                        height: 1.18,
                                        fontWeight: FontWeight.w600,
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
                                          color: PomgtColors.muted,
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
                                    LucideIcons.x,
                                    color: PomgtColors.muted,
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

class _NoticeMotion extends StatefulWidget {
  const _NoticeMotion({super.key, required this.child});
  final Widget child;
  @override
  State<_NoticeMotion> createState() => _NoticeMotionState();
}

class _NoticeMotionState extends State<_NoticeMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = PomgtMotion.duration(context, PomgtMotion.medium);
    _controller.reverseDuration = PomgtMotion.duration(
      context,
      PomgtMotion.fast,
    );
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  Future<void> hide() async {
    try {
      await _controller.reverse().orCancel;
    } on TickerCanceled {
      // The navigator/overlay can be disposed during a route change.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller.drive(CurveTween(curve: PomgtMotion.curve)),
    child: SlideTransition(
      position: _controller.drive(
        Tween(
          begin: const Offset(.04, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: PomgtMotion.curve)),
      ),
      transformHitTests: false,
      child: widget.child,
    ),
  );
}
