import '../widgets/motion.dart';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class PomgtColors {
  static const ink = Color(0xFF152737);
  static const secondaryInk = Color(0xFF3A4E5E);
  static const muted = Color(0xFF6B7280);
  static const subtle = Color(0xFFB8C2CF);
  static const line = Color(0xFFE4E9F0);
  static const lineStrong = Color(0xFFD4DDE8);
  static const appBg = Color(0xFFF6F8FB);
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF6F8FB);
  static const navy = Color(0xFF152737);
  static const navySelected = Color(0xFFEAF2FF);
  static const navySelectedBorder = Color(0xFFCDDEFA);
  static const navIcon = Color(0xFF738197);
  static const navyHover = Color(0xFF1A2A43);
  static const blue = Color(0xFF1973FF);
  static const blueHover = Color(0xFF0F5CE0);
  static const blueSoft = Color(0xFFE8F0FF);
  static const mint = Color(0xFF10B981);
  static const mintSoft = Color(0xFFDFF8EE);
  static const amber = Color(0xFFFBA933);
  static const amberSoft = Color(0xFFFFF1DC);
  static const rose = Color(0xFFEF4444);
  static const roseSoft = Color(0xFFFEE2E2);
  static const violet = Color(0xFF7C5CFC);
  static const violetSoft = Color(0xFFEEE9FF);
  static const cyan = Color(0xFF0EA5B7);
  static const cyanSoft = Color(0xFFE1F6F8);
  static const slate = Color(0xFF64748B);
  static const slateSoft = Color(0xFFEEF1F5);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFFBA933);
  static const danger = Color(0xFFEF4444);
}

class PomgtRadii {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(14);
  static const pillRadius = Radius.circular(999);
  static const borderSm = BorderRadius.all(sm);
  static const borderMd = BorderRadius.all(md);
  static const borderPill = BorderRadius.all(pillRadius);
}

class PomgtButtonStyle {
  static const height = 42.0;
  static const radius = BorderRadius.all(Radius.circular(8));
  static const gradientTop = Color(0xFF4A92FF);
  static const gradientBottom = PomgtColors.blue;
  static const border = Color(0xFF0F5CE0);
  static const hoverTop = Color(0xFF6BA8FF);
  static const hoverBottom = Color(0xFF3585FF);
  static const pressedTop = Color(0xFF1973FF);
  static const pressedBottom = Color(0xFF0F5CE0);
  static const pressedBorder = Color(0xFF0B47B8);
  static const hoverDuration = PomgtMotion.fast;
  static const text = TextStyle(
    fontFamily: PomgtTypography.body,
    fontFamilyFallback: PomgtTypography.fallback,
    fontWeight: FontWeight.w500,
    fontSize: 14,
  );
}

class PomgtShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x06152737), blurRadius: 12, offset: Offset(0, 3)),
  ];
  static const overlay = <BoxShadow>[
    BoxShadow(color: Color(0x14152737), blurRadius: 28, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x08152737), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

class PomgtTypography {
  static const display = 'IBM Plex Sans';
  static const body = 'IBM Plex Sans';
  static const fallback = [
    'Aptos',
    'Segoe UI',
    'Roboto',
    'Arial',
    'sans-serif',
  ];
}

ThemeData buildPomgtTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PomgtColors.blue,
    brightness: Brightness.light,
    surface: PomgtColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    extensions: const [
      SkeletonizerConfigData(
        effect: PulseEffect(
          from: PomgtColors.line,
          to: PomgtColors.surfaceAlt,
          duration: Duration(milliseconds: 1400),
        ),
      ),
    ],
    fontFamily: PomgtTypography.body,
    fontFamilyFallback: PomgtTypography.fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: PomgtColors.appBg,
    shadowColor: const Color(0x24152737),
    dividerColor: PomgtColors.line,
    splashFactory: NoSplash.splashFactory,
    hoverColor: PomgtColors.blue.withValues(alpha: .04),
    focusColor: PomgtColors.blue.withValues(alpha: .10),
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
      },
    ),
    textTheme: TextTheme(
      displaySmall: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      headlineMedium: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      headlineSmall: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleLarge: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleMedium: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleSmall: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      bodyLarge: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: PomgtColors.secondaryInk,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: PomgtColors.secondaryInk,
        height: 1.4,
      ),
      bodySmall: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: PomgtColors.muted,
        height: 1.35,
      ),
      labelLarge: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      labelMedium: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.secondaryInk,
      ),
      labelSmall: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        color: PomgtColors.muted,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: PomgtColors.surface,
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: PomgtRadii.borderMd,
        side: BorderSide(color: PomgtColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PomgtColors.surfaceAlt,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      alignLabelWithHint: true,
      helperStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.muted,
        fontSize: 12,
        height: 1.4,
      ),
      errorStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.danger,
        fontSize: 12,
        height: 1.4,
      ),
      prefixIconColor: PomgtColors.muted,
      suffixIconColor: PomgtColors.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderSm,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderSm,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.blue, width: 1.3),
        borderRadius: PomgtRadii.borderSm,
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.line),
        borderRadius: PomgtRadii.borderSm,
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.danger, width: 1.3),
        borderRadius: PomgtRadii.borderSm,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.danger),
        borderRadius: PomgtRadii.borderSm,
      ),
      labelStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.ink.withValues(alpha: 0.65),
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        // Same color + opacity as the auth screen's hint text
        // (lib/features/auth/login_screen.dart's _hintStyle).
        color: PomgtColors.muted.withValues(alpha: 0.65),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PomgtColors.ink,
        borderRadius: PomgtRadii.borderSm,
      ),
      textStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: Colors.white,
        fontSize: 12,
        height: 1.35,
      ),
      waitDuration: PomgtMotion.medium,
      showDuration: const Duration(seconds: 6),
    ),
    dialogTheme: const DialogThemeData(
      elevation: 8,
      shadowColor: Color(0x24152737),
      surfaceTintColor: Colors.transparent,
      backgroundColor: PomgtColors.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: PomgtRadii.borderMd,
        side: BorderSide(color: PomgtColors.line),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      shadowColor: const Color(0x24152737),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: PomgtRadii.borderMd,
        side: const BorderSide(color: PomgtColors.line),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style:
          IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: PomgtColors.ink,
            minimumSize: const Size(36, 36),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtRadii.borderSm,
            ),
          ).copyWith(
            animationDuration: PomgtMotion.fast,
            foregroundBuilder: PomgtMotion.buttonFeedback,
          ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, PomgtButtonStyle.height),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtButtonStyle.radius,
            ),
            textStyle: PomgtButtonStyle.text,
          ).copyWith(
            animationDuration: PomgtMotion.fast,
            foregroundBuilder: PomgtMotion.buttonFeedback,
            backgroundBuilder: (context, states, child) {
              final disabled = states.contains(WidgetState.disabled);
              final pressed = states.contains(WidgetState.pressed);
              final hovered = states.contains(WidgetState.hovered);
              final top = pressed
                  ? PomgtButtonStyle.pressedTop
                  : hovered
                  ? PomgtButtonStyle.hoverTop
                  : PomgtButtonStyle.gradientTop;
              final bottom = pressed
                  ? PomgtButtonStyle.pressedBottom
                  : hovered
                  ? PomgtButtonStyle.hoverBottom
                  : PomgtButtonStyle.gradientBottom;
              return AnimatedContainer(
                duration: PomgtMotion.duration(context, PomgtMotion.fast),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  gradient: disabled
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [top, bottom],
                        ),
                  color: disabled ? PomgtColors.line : null,
                  borderRadius: PomgtButtonStyle.radius,
                  border: Border.all(
                    color: disabled
                        ? PomgtColors.lineStrong
                        : pressed
                        ? PomgtButtonStyle.pressedBorder
                        : PomgtButtonStyle.border,
                  ),
                ),
                child: child,
              );
            },
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            elevation: 0,
            foregroundColor: PomgtColors.ink,
            backgroundColor: PomgtColors.canvas,
            side: const BorderSide(color: PomgtColors.lineStrong),
            minimumSize: const Size(0, PomgtButtonStyle.height),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtButtonStyle.radius,
            ),
            textStyle: PomgtButtonStyle.text,
          ).copyWith(
            animationDuration: PomgtMotion.fast,
            foregroundBuilder: PomgtMotion.buttonFeedback,
            side: WidgetStateProperty.resolveWith((states) {
              final active =
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed);
              return BorderSide(
                color: active ? PomgtColors.blue : PomgtColors.lineStrong,
              );
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return PomgtColors.blue.withValues(alpha: .14);
              }
              if (states.contains(WidgetState.hovered)) {
                return PomgtColors.blue.withValues(alpha: .08);
              }
              return null;
            }),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: PomgtColors.blueHover,
            minimumSize: const Size(0, PomgtButtonStyle.height),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtButtonStyle.radius,
            ),
            textStyle: PomgtButtonStyle.text,
          ).copyWith(
            animationDuration: PomgtMotion.fast,
            foregroundBuilder: PomgtMotion.buttonFeedback,
          ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: PomgtColors.blue,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: PomgtColors.line,
      labelColor: PomgtColors.ink,
      unselectedLabelColor: PomgtColors.muted,
      // Material 3's TabBar derives its hover/press feedback from
      // overlayColor, not the legacy ambient ThemeData.hoverColor - without
      // this, every TabBar in the app renders with no visible hover at all.
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return PomgtColors.blue.withValues(alpha: .10);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return PomgtColors.blue.withValues(alpha: .06);
        }
        return null;
      }),
      labelStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.ink,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: PomgtRadii.borderMd,
        side: const BorderSide(color: PomgtColors.line),
      ),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(6),
      thumbColor: WidgetStatePropertyAll(Color(0x66738197)),
      radius: PomgtRadii.sm,
    ),
    dividerTheme: const DividerThemeData(
      color: PomgtColors.line,
      thickness: 1,
      space: 24,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PomgtColors.blue,
      linearTrackColor: PomgtColors.blueSoft,
      circularTrackColor: PomgtColors.blueSoft,
      strokeWidth: 2,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: PomgtColors.muted,
      textColor: PomgtColors.ink,
      selectedColor: PomgtColors.blueHover,
      selectedTileColor: PomgtColors.blueSoft,
      shape: RoundedRectangleBorder(borderRadius: PomgtRadii.borderSm),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: const BorderSide(color: PomgtColors.slate, width: 1.3),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.secondaryInk,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      dataTextStyle: const TextStyle(
        fontFamily: PomgtTypography.body,
        fontFamilyFallback: PomgtTypography.fallback,
        color: PomgtColors.ink,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      headingRowColor: const WidgetStatePropertyAll(PomgtColors.surfaceAlt),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return PomgtColors.navySelected;
        }
        if (states.contains(WidgetState.hovered)) {
          return PomgtColors.surfaceAlt;
        }
        return PomgtColors.canvas;
      }),
      dividerThickness: 1,
    ),
  );
}
