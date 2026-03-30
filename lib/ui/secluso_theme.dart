//! SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:secluso_flutter/ui/google_fonts.dart';

class SeclusoColors {
  static const Color ink = Color(0xFF0A0A0A);
  static const Color night = Color(0xFF0A0A0A);
  static const Color nightRaised = Color(0xFF121212);
  static const Color nightSoft = Color(0xFF1A1A1A);
  static const Color paper = Color(0xFFFAFAFA);
  static const Color paperMuted = Color(0xFFE5E5E5);
  static const Color gray = Color(0xFF666666);
  static const Color blue = Color(0xFF8BB3EE);
  static const Color blueSoft = Color(0xFFB8D0F5);
  static const Color success = Color(0xFF88D7B2);
  static const Color warning = Color(0xFFF0C08A);
  static const Color danger = Color(0xFFF29BA0);
}

class SeclusoTheme {
  static const double _controlRadius = 12;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: SeclusoColors.blue,
      onPrimary: SeclusoColors.ink,
      secondary: SeclusoColors.ink,
      onSecondary: SeclusoColors.paper,
      error: SeclusoColors.danger,
      onError: SeclusoColors.ink,
      surface: SeclusoColors.paper,
      onSurface: SeclusoColors.ink,
      surfaceContainerHighest: Color(0xFFF2F2F2),
      onSurfaceVariant: SeclusoColors.gray,
      outline: Color(0x260A0A0A),
      outlineVariant: Color(0x120A0A0A),
      shadow: Color(0x22000000),
      scrim: Color(0x80000000),
      inverseSurface: SeclusoColors.ink,
      onInverseSurface: SeclusoColors.paper,
      inversePrimary: SeclusoColors.blueSoft,
    );
    return _buildTheme(scheme);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: SeclusoColors.blue,
      onPrimary: SeclusoColors.ink,
      secondary: SeclusoColors.paper,
      onSecondary: SeclusoColors.ink,
      error: SeclusoColors.danger,
      onError: SeclusoColors.ink,
      surface: SeclusoColors.night,
      onSurface: SeclusoColors.paper,
      surfaceContainerHighest: SeclusoColors.nightRaised,
      onSurfaceVariant: Color(0xB3FAFAFA),
      outline: Color(0x1EFAFAFA),
      outlineVariant: Color(0x14FAFAFA),
      shadow: Colors.black,
      scrim: Color(0xCC000000),
      inverseSurface: SeclusoColors.paper,
      onInverseSurface: SeclusoColors.ink,
      inversePrimary: SeclusoColors.blueSoft,
    );
    return _buildTheme(scheme);
  }

  static ThemeData _buildTheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final filledBackground = isDark ? SeclusoColors.paper : SeclusoColors.ink;
    final filledForeground = isDark ? SeclusoColors.ink : SeclusoColors.paper;
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.inter().fontFamily,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      splashFactory: InkRipple.splashFactory,
    );

    final interTextTheme = GoogleFonts.interTextTheme(base.textTheme);
    final textTheme = interTextTheme.copyWith(
      displayLarge: _editorial(interTextTheme.displayLarge, scheme, 46),
      displayMedium: _editorial(interTextTheme.displayMedium, scheme, 38),
      displaySmall: _editorial(interTextTheme.displaySmall, scheme, 30),
      headlineLarge: _ui(
        interTextTheme.headlineLarge,
        scheme,
        30,
        weight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineMedium: _ui(
        interTextTheme.headlineMedium,
        scheme,
        26,
        weight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      headlineSmall: _ui(
        interTextTheme.headlineSmall,
        scheme,
        22,
        weight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleLarge: _ui(
        interTextTheme.titleLarge,
        scheme,
        20,
        weight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: _ui(
        interTextTheme.titleMedium,
        scheme,
        16,
        weight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: _ui(
        interTextTheme.titleSmall,
        scheme,
        14,
        color: scheme.onSurfaceVariant,
        weight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      bodyLarge: _ui(interTextTheme.bodyLarge, scheme, 16, height: 1.55),
      bodyMedium: _ui(
        interTextTheme.bodyMedium,
        scheme,
        16,
        color: scheme.onSurface.withValues(alpha: 0.82),
        height: 1.55,
      ),
      bodySmall: _ui(
        interTextTheme.bodySmall,
        scheme,
        14,
        color: scheme.onSurface.withValues(alpha: 0.58),
        height: 1.5,
      ),
      labelLarge: _ui(
        interTextTheme.labelLarge,
        scheme,
        14,
        weight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      labelMedium: _ui(
        interTextTheme.labelMedium,
        scheme,
        12,
        color: scheme.onSurfaceVariant,
        weight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
      labelSmall: _ui(
        interTextTheme.labelSmall,
        scheme,
        11,
        color: scheme.onSurfaceVariant,
        weight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            scheme.brightness == Brightness.dark
                ? SeclusoColors.nightRaised
                : SeclusoColors.paper,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            scheme.brightness == Brightness.dark
                ? SeclusoColors.nightRaised
                : const Color(0xFFF3F3F3),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.42),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: _fieldBorder(scheme.outline),
        enabledBorder: _fieldBorder(scheme.outline),
        focusedBorder: _fieldBorder(scheme.primary),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledBackground,
          foregroundColor: filledForeground,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: filledBackground,
          foregroundColor: filledForeground,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.18),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SeclusoColors.blue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: filledBackground,
        foregroundColor: filledForeground,
        elevation: 0,
        extendedTextStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            scheme.brightness == Brightness.dark
                ? SeclusoColors.nightRaised
                : SeclusoColors.paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        modalBackgroundColor:
            scheme.brightness == Brightness.dark
                ? SeclusoColors.nightRaised
                : SeclusoColors.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            scheme.brightness == Brightness.dark
                ? SeclusoColors.nightRaised
                : SeclusoColors.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: SeclusoColors.blue,
        circularTrackColor: scheme.outlineVariant,
        linearTrackColor: scheme.outlineVariant,
      ),
    );
  }

  static TextStyle? _editorial(
    TextStyle? base,
    ColorScheme scheme,
    double size, {
    FontWeight weight = FontWeight.w700,
    FontStyle style = FontStyle.normal,
  }) {
    return GoogleFonts.playfairDisplay(
      textStyle: base?.copyWith(
        color: scheme.onSurface,
        fontSize: size,
        height: 1.08,
        fontWeight: weight,
        fontStyle: style,
        letterSpacing: -0.7,
      ),
    );
  }

  static TextStyle? _ui(
    TextStyle? base,
    ColorScheme scheme,
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.inter(
      textStyle: base?.copyWith(
        color: color ?? scheme.onSurface,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: letterSpacing,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: 1),
    );
  }
}
