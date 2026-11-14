import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as forui;
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

import 'pomgt_theme.dart';

/// Keeps the two component libraries on POMGT's typography and palette.
class PomgtComponentTheme extends StatelessWidget {
  const PomgtComponentTheme({super.key, required this.child});

  final Widget child;

  static final shadTheme = shad.ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const shad.ShadBlueColorScheme.light(),
    textTheme: shad.ShadTextTheme(family: PomgtTypography.body),
    radius: PomgtRadii.borderSm,
  );

  static final foruiTheme = forui.FTheme.neutral.light.desktop;

  static forui.FAccessibility motionAccessibility(BuildContext context) =>
      forui.FAccessibility(
        accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
        motion: MediaQuery.disableAnimationsOf(context)
            ? forui.FAccessibilityMotion.disabled
            : forui.FAccessibilityMotion.all,
        focusHighlight:
            FocusManager.instance.highlightMode ==
            FocusHighlightMode.traditional,
      );

  @override
  Widget build(BuildContext context) => forui.FTheme(
    data: foruiTheme,
    accessibility: motionAccessibility(context),
    child: shad.ShadTheme(data: shadTheme, child: child),
  );
}
