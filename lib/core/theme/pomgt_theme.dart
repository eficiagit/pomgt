import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PomgtColors {
  static const ink = Color(0xFF111827);
  static const secondaryInk = Color(0xFF374151);
  static const muted = Color(0xFF6B7280);
  static const subtle = Color(0xFFD1D5DB);
  static const line = Color(0xFFE5E7EB);
  static const lineStrong = Color(0xFFD8DEE8);
  static const appBg = Color(0xFFF6F8FB);
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF3F5F8);
  static const navy = Color(0xFF233653);
  static const navySelected = Color(0x1F3C82F6);
  static const navySelectedBorder = Color(0x663C82F6);
  static const navyHover = Color(0xFF1A2A43);
  static const blue = Color(0xFF3B82F6);
  static const blueHover = Color(0xFF2563EB);
  static const blueSoft = Color(0xFFEAF2FF);
  static const mint = Color(0xFF10B981);
  static const mintSoft = Color(0xFFDFF8EE);
  static const amber = Color(0xFFF97316);
  static const amberSoft = Color(0xFFFFEDD5);
  static const rose = Color(0xFFEF4444);
  static const roseSoft = Color(0xFFFEE2E2);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF97316);
  static const danger = Color(0xFFEF4444);
}

class PomgtRadii {
  static const sm = Radius.circular(6);
  static const md = Radius.circular(8);
  static const borderSm = BorderRadius.all(sm);
  static const borderMd = BorderRadius.all(md);
}

class PomgtShadows {
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: .08),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ];
}

class PomgtTypography {
  static const display = 'Rajdhani';
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
    fontFamily: PomgtTypography.body,
    fontFamilyFallback: PomgtTypography.fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: PomgtColors.appBg,
    dividerColor: PomgtColors.line,
    splashFactory: NoSplash.splashFactory,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    textTheme: TextTheme(
      displaySmall: GoogleFonts.rajdhani(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      headlineMedium: GoogleFonts.rajdhani(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      headlineSmall: GoogleFonts.rajdhani(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleLarge: GoogleFonts.rajdhani(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleMedium: GoogleFonts.rajdhani(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      titleSmall: GoogleFonts.ibmPlexSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      bodyLarge: GoogleFonts.ibmPlexSans(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: PomgtColors.secondaryInk,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.ibmPlexSans(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: PomgtColors.secondaryInk,
        height: 1.4,
      ),
      bodySmall: GoogleFonts.ibmPlexSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: PomgtColors.muted,
        height: 1.35,
      ),
      labelLarge: GoogleFonts.ibmPlexSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.ink,
      ),
      labelMedium: GoogleFonts.ibmPlexSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        color: PomgtColors.secondaryInk,
      ),
      labelSmall: GoogleFonts.ibmPlexSans(
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
      shadowColor: Colors.black.withValues(alpha: .12),
      shape: const RoundedRectangleBorder(borderRadius: PomgtRadii.borderMd),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PomgtColors.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: PomgtRadii.borderSm,
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: PomgtRadii.borderSm,
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.blue, width: 1.3),
        borderRadius: PomgtRadii.borderSm,
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: PomgtColors.danger),
        borderRadius: PomgtRadii.borderSm,
      ),
      labelStyle: const TextStyle(
        color: PomgtColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: PomgtColors.ink,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: const TextStyle(color: PomgtColors.muted),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PomgtColors.ink,
        borderRadius: PomgtRadii.borderSm,
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        height: 1.35,
      ),
      waitDuration: const Duration(milliseconds: 220),
      showDuration: const Duration(seconds: 6),
    ),
    dialogTheme: const DialogThemeData(
      elevation: 0,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: PomgtRadii.borderMd),
    ),
    drawerTheme: const DrawerThemeData(
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      elevation: 8,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: PomgtRadii.borderMd),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: PomgtColors.ink,
        fixedSize: const Size(42, 42),
        shape: const RoundedRectangleBorder(borderRadius: PomgtRadii.borderSm),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            elevation: 0,
            backgroundColor: PomgtColors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtRadii.borderSm,
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 160),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: .18);
              }
              if (states.contains(WidgetState.hovered)) {
                return Colors.white.withValues(alpha: .10);
              }
              return null;
            }),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            elevation: 0,
            foregroundColor: PomgtColors.ink,
            backgroundColor: PomgtColors.canvas,
            side: const BorderSide(color: PomgtColors.lineStrong),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: const RoundedRectangleBorder(
              borderRadius: PomgtRadii.borderSm,
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ).copyWith(
            animationDuration: const Duration(milliseconds: 160),
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
      style: TextButton.styleFrom(
        foregroundColor: PomgtColors.blueHover,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: const RoundedRectangleBorder(borderRadius: PomgtRadii.borderSm),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ).copyWith(animationDuration: const Duration(milliseconds: 160)),
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: PomgtColors.blue,
      dividerColor: PomgtColors.line,
      labelColor: PomgtColors.ink,
      unselectedLabelColor: PomgtColors.muted,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      unselectedLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PomgtColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: PomgtRadii.borderMd),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(false),
      thickness: WidgetStatePropertyAll(5),
      radius: PomgtRadii.sm,
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
        color: PomgtColors.secondaryInk,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      dataTextStyle: const TextStyle(
        color: PomgtColors.ink,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
      ),
      headingRowColor: const WidgetStatePropertyAll(PomgtColors.canvas),
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
