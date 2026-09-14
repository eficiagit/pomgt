import 'package:flutter/material.dart';
import '../theme/pomgt_theme.dart';

class PomgtMotion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
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
        : Colors.transparent;
    final dy = _pressed
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
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onHighlightChanged: interactive ? _setPressed : null,
          onTap: interactive ? widget.onTap : null,
          onDoubleTap: interactive ? widget.onDoubleTap : null,
          child: AnimatedSlide(
            duration: PomgtMotion.fast,
            curve: PomgtMotion.curve,
            offset: Offset(0, dy / 40),
            child: AnimatedContainer(
              duration: PomgtMotion.fast,
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
    return AnimatedSwitcher(
      duration: PomgtMotion.medium,
      switchInCurve: PomgtMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: PomgtMotion.curve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.018, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
