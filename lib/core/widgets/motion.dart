import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/pomgt_theme.dart';

class PomgtMotion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 300);

  static AnimationStyle style(BuildContext context) => AnimationStyle(
    duration: duration(context, medium),
    reverseDuration: duration(context, fast),
    curve: curve,
    reverseCurve: Curves.easeInCubic,
  );

  static Widget buttonFeedback(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => AnimatedScale(
    scale: states.contains(WidgetState.disabled)
        ? 1
        : states.contains(WidgetState.pressed)
        ? .98
        : 1,
    duration: duration(context, fast),
    curve: curve,
    child: child,
  );
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

class SmoothHover extends StatefulWidget {
  const SmoothHover({
    super.key,
    required this.child,
    this.enabled = true,
    this.hoverColor = PomgtColors.surfaceAlt,
    this.borderColor,
    this.selected = false,
    this.selectedColor = PomgtColors.navySelected,
    this.padding,
    this.lift = .35,
    this.shadow = false,
    this.onTap,
    this.onDoubleTap,
  });

  final Widget child;
  final bool enabled;
  final Color hoverColor;
  final Color? borderColor;
  final bool selected;
  final Color selectedColor;
  final EdgeInsetsGeometry? padding;
  final double lift;
  final bool shadow;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<SmoothHover> createState() => _SmoothHoverState();
}

class _SmoothHoverState extends State<SmoothHover> {
  bool _hovered = false;
  bool _pressed = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
      if (!hovered) _pressed = false;
    });
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && widget.onTap != null;
    final color = widget.selected
        ? widget.selectedColor
        : _hovered && interactive
        ? widget.hoverColor
        : widget.hoverColor.withValues(alpha: 0);
    final dy = MediaQuery.disableAnimationsOf(context)
        ? 0.0
        : _pressed
        ? widget.lift
        : (_hovered && interactive ? -widget.lift : 0.0);
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      opaque: true,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor: interactive
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          hoverColor: Colors.transparent,
          focusColor: PomgtColors.blueSoft,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onHighlightChanged: interactive ? _setPressed : null,
          onTap: interactive ? widget.onTap : null,
          onDoubleTap: interactive ? widget.onDoubleTap : null,
          child: AnimatedSlide(
            duration: PomgtMotion.duration(context, PomgtMotion.fast),
            curve: PomgtMotion.curve,
            offset: Offset(0, dy / 40),
            child: AnimatedContainer(
              duration: PomgtMotion.duration(context, PomgtMotion.fast),
              curve: PomgtMotion.curve,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: color,
                borderRadius: PomgtRadii.borderSm,
                border: widget.borderColor == null
                    ? null
                    : Border.all(color: widget.borderColor!),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class SoftContentSwitch extends StatelessWidget {
  const SoftContentSwitch({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      transitionBuilder: (child, animation, secondaryAnimation) =>
          FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            fillColor: Colors.transparent,
            child: child,
          ),
      child: child,
    );
  }
}

/// Entrance only: rebuilding or validating a form never restarts its motion.
class PomgtReveal extends StatefulWidget {
  const PomgtReveal({super.key, required this.child});
  final Widget child;

  @override
  State<PomgtReveal> createState() => _PomgtRevealState();
}

class _PomgtRevealState extends State<PomgtReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = PomgtMotion.duration(context, PomgtMotion.medium);
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
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
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).chain(CurveTween(curve: PomgtMotion.curve)),
      ),
      transformHitTests: false,
      child: widget.child,
    ),
  );
}

/// Animates the presentation of a changed status without replacing its owner.
class PomgtAnimatedValue extends StatelessWidget {
  const PomgtAnimatedValue({
    super.key,
    required this.value,
    required this.child,
  });
  final Object? value;
  final Widget child;

  @override
  Widget build(BuildContext context) => PomgtAnimatedSize(
    duration: PomgtMotion.duration(context, PomgtMotion.medium),
    curve: PomgtMotion.curve,
    alignment: Alignment.centerLeft,
    child: AnimatedSwitcher(
      duration: PomgtMotion.duration(context, PomgtMotion.fast),
      switchInCurve: PomgtMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ExcludeSemantics(
          excluding: child.key != ValueKey(value),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    ),
  );
}

/// The native controller continues to own tab selection, focus and swipe state.
class PomgtTabController extends StatelessWidget {
  const PomgtTabController({
    super.key,
    required this.length,
    this.initialIndex = 0,
    required this.child,
  });
  final int length;
  final int initialIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: length,
    initialIndex: initialIndex,
    animationDuration: PomgtMotion.duration(context, PomgtMotion.medium),
    child: child,
  );
}

Widget pomgtValidationMessage(BuildContext context, String message) =>
    Semantics(
      liveRegion: true,
      child: PomgtAnimatedValue(
        value: message,
        child: Text(
          message,
          style: Theme.of(context).inputDecorationTheme.errorStyle,
        ),
      ),
    );

/// Uses Flutter's dialog route to preserve its barrier, focus and return value.
Future<T?> showPomgtDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  animationStyle: PomgtMotion.style(context),
  builder: (context) {
    final child = builder(context);
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return ScaleTransition(
      scale: animation.drive(
        Tween(begin: .98, end: 1.0).chain(CurveTween(curve: PomgtMotion.curve)),
      ),
      child: child,
    );
  },
);

/// Standard `AlertDialog.title` for a plain Material dialog: the title text
/// on the left and a "Cerrar" X in the top-right, matching the header every
/// custom `Dialog` (EntityFormDialog, LinkBomDialog, …) already has - so a
/// plain AlertDialog isn't the only kind of modal without that close
/// affordance. [onClose] defaults to a bare pop (consistent with how most
/// dialogs' own Cancelar buttons behave); pass it explicitly only when the
/// dialog's Cancelar pops with a specific value (e.g. `false`) the X should
/// also return.
Widget pomgtDialogTitle(
  BuildContext context,
  String title, {
  VoidCallback? onClose,
  TextStyle? style,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Text(title, style: style)),
      IconButton(
        tooltip: 'Cerrar',
        onPressed: onClose ?? () => Navigator.pop(context),
        icon: const Icon(LucideIcons.x, size: 20),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
      ),
    ],
  );
}

/// Blocks the screen with a small non-dismissible "Generando…"-style modal
/// while [work] runs, then closes it and returns the result - for actions
/// (building/saving a PDF, etc.) that take a moment but have no other
/// loading affordance of their own.
Future<T> runWithPomgtLoadingDialog<T>(
  BuildContext context,
  String message,
  Future<T> Function() work,
) async {
  unawaited(
    showPomgtDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// Lists retain native lazy construction, scrolling, keys and controllers.
class PomgtListView extends ListView {
  PomgtListView({
    super.key,
    super.controller,
    super.scrollDirection,
    super.padding,
    super.shrinkWrap,
    List<Widget> children = const [],
  }) : super(
         children: [
           for (final child in children)
             PomgtReveal(
               key: child.key is GlobalKey ? null : child.key,
               child: child,
             ),
         ],
       );

  PomgtListView.builder({
    super.key,
    super.controller,
    super.scrollDirection,
    super.padding,
    super.shrinkWrap,
    required IndexedWidgetBuilder itemBuilder,
    super.itemCount,
  }) : super.builder(
         itemBuilder: (context, index) {
           final child = itemBuilder(context, index);
           return PomgtReveal(
             key: child.key is GlobalKey ? null : child.key,
             child: child,
           );
         },
       );

  PomgtListView.separated({
    super.key,
    super.controller,
    super.scrollDirection,
    super.padding,
    super.shrinkWrap,
    required IndexedWidgetBuilder itemBuilder,
    required super.separatorBuilder,
    required super.itemCount,
  }) : super.separated(
         itemBuilder: (context, index) {
           final child = itemBuilder(context, index);
           return PomgtReveal(
             key: child.key is GlobalKey ? null : child.key,
             child: child,
           );
         },
       );
}

/// Avoids laying out a zero-duration AnimatedSize during reduced motion. The
/// keyed child also keeps form state when the motion preference changes.
class PomgtAnimatedSize extends StatefulWidget {
  const PomgtAnimatedSize({
    super.key,
    required this.duration,
    required this.child,
    this.reverseDuration,
    this.curve = PomgtMotion.curve,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
  });
  final Duration duration;
  final Duration? reverseDuration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;
  final Widget child;

  @override
  State<PomgtAnimatedSize> createState() => _PomgtAnimatedSizeState();
}

class _PomgtAnimatedSizeState extends State<PomgtAnimatedSize> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (MediaQuery.disableAnimationsOf(context) ||
        widget.duration == Duration.zero) {
      return child;
    }
    return AnimatedSize(
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
      curve: widget.curve,
      alignment: widget.alignment,
      clipBehavior: widget.clipBehavior,
      child: child,
    );
  }
}

/// Replays motion on a visual change while keeping the child subtree mounted.
class PomgtChangeMotion extends StatefulWidget {
  const PomgtChangeMotion({
    super.key,
    required this.value,
    required this.child,
  });
  final Object? value;
  final Widget child;
  @override
  State<PomgtChangeMotion> createState() => _PomgtChangeMotionState();
}

class _PomgtChangeMotionState extends State<PomgtChangeMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    value: 1,
    vsync: this,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = PomgtMotion.duration(context, PomgtMotion.medium);
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant PomgtChangeMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.duration != Duration.zero) {
      _controller.forward(from: 0);
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
    child: widget.child,
  );
}

class PomgtProgressIndicator extends StatelessWidget {
  const PomgtProgressIndicator({
    super.key,
    this.value,
    this.minHeight,
    this.backgroundColor,
    this.color,
    this.valueColor,
  });
  final double? value;
  final double? minHeight;
  final Color? backgroundColor;
  final Color? color;
  final Animation<Color?>? valueColor;

  @override
  Widget build(BuildContext context) {
    Widget indicator(double? progress) => LinearProgressIndicator(
      value: progress,
      minHeight: minHeight,
      backgroundColor: backgroundColor,
      color: color,
      valueColor: valueColor,
    );
    if (value == null) return indicator(null);
    return TweenAnimationBuilder<double>(
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      curve: PomgtMotion.curve,
      tween: Tween(begin: value!, end: value!),
      builder: (context, progress, child) => indicator(progress),
    );
  }
}
