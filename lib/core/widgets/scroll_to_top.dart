import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';

import '../theme/pomgt_theme.dart';
import 'motion.dart';

/// Wraps a scrollable region with a small floating "back to top" button
/// that fades/scales in once the user has scrolled past [showAfter], and
/// smoothly animates back to the top when tapped.
///
/// The caller doesn't hand this widget a scrollable child directly — it
/// owns the [ScrollController] (unless one is passed in) and hands it to
/// [builder], so any scrollable (`ListView`, `CustomScrollView`,
/// `SingleChildScrollView`, `PomgtListView`…) can opt in by just wiring
/// that controller into its own `controller:` parameter.
class ScrollToTopArea extends StatefulWidget {
  const ScrollToTopArea({
    super.key,
    required this.builder,
    this.controller,
    this.showAfter = 240,
    this.alignment = Alignment.bottomRight,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget Function(BuildContext context, ScrollController controller)
  builder;
  final ScrollController? controller;
  final double showAfter;
  final AlignmentGeometry alignment;
  final EdgeInsets padding;

  @override
  State<ScrollToTopArea> createState() => _ScrollToTopAreaState();
}

class _ScrollToTopAreaState extends State<ScrollToTopArea> {
  late final ScrollController _controller;
  late final bool _ownsController;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ScrollController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final show =
        _controller.hasClients && _controller.offset > widget.showAfter;
    if (show != _visible) setState(() => _visible = show);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _controller.animateTo(
      0,
      duration: PomgtMotion.duration(context, PomgtMotion.medium),
      curve: PomgtMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.builder(context, _controller),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_visible,
            child: Align(
              alignment: widget.alignment,
              child: Padding(
                padding: widget.padding,
                child: AnimatedScale(
                  scale: _visible ? 1 : 0.6,
                  duration: PomgtMotion.duration(context, PomgtMotion.fast),
                  curve: PomgtMotion.curve,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: PomgtMotion.duration(context, PomgtMotion.fast),
                    child: _ScrollToTopButton(onPressed: _scrollToTop),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollToTopButton extends StatelessWidget {
  const _ScrollToTopButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: PomgtColors.ink,
    shape: const CircleBorder(),
    elevation: 4,
    shadowColor: const Color(0x33152737),
    child: Tooltip(
      message: 'Subir al inicio',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(LucideIcons.arrowUp, size: 18, color: Colors.white),
        ),
      ),
    ),
  );
}
