import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_text.dart';

class AppColors {
  static const bg = Color(0xFFEEF1F6);
  static const grid = Color(0xFFDDE3EC);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2A4D);
  static const sub = Color(0xFF6B7280);
  static const primary = Color(0xFF2F4AA8);
  static const accent = Color(0xFFFFC94A);
  static const aiBubble = Color(0xFFEAF0FF);
  static const danger = Color(0xFFE5484D);
  static const ok = Color(0xFF2FA36B);
  static const errorCard = Color(0xFFFFE4EC);
  static const sidebar = Color(0xFFF7F9FC);
  static const sideSelected = Color(0xFFE3E9F3);
  static const line = Color(0xFFD5DCE8);
  static const wash = Color(0xFFD9E4F4);

  static const md = Color(0xFF4B5563);
  static const pdf = Color(0xFFE5484D);
  static const docx = Color(0xFF2F6FE4);
  static const pptx = Color(0xFFF2783B);
  static const xlsx = Color(0xFF2FA36B);
  static const hwpx = Color(0xFF1FA3B8);
  static const txt = Color(0xFFB8A47A);
  static const calc = Color(0xFF8E99A8);
}

class AppDims {
  static const cardRadius = 16.0;
  static const borderWidth = 1.8;
  static const desktopHeader = 64.0;
  static const portraitHeader = 56.0;
  static const sidebarWide = 232.0;
  static const sidebarNarrow = 76.0;
  static const rail = 58.0;
  static const contentMax = 1100.0;
  static const recentPanel = 300.0;
}

BoxDecoration cardDecoration({Color color = AppColors.paper, bool lifted = false}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(AppDims.cardRadius),
  border: Border.all(color: AppColors.ink, width: AppDims.borderWidth),
  boxShadow: [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: lifted ? 0.22 : 0.12),
      offset: Offset(0, lifted ? 8 : 4),
      blurRadius: lifted ? 18 : 10,
    ),
  ],
);

/// Small pill buttons and chips share this outline.
const pillBorder = StadiumBorder(side: BorderSide(color: AppColors.ink, width: 1.3));

class ReadingSettings {
  const ReadingSettings({this.fontLevel = 3, this.lineLevel = 4});

  final int fontLevel;
  final int lineLevel;

  double get fontFactor => 1 + (fontLevel - 3) * 0.1;
  double get lineHeight => 1.45 * (1 + (lineLevel - 4) * 0.1);

  ReadingSettings copyWith({int? fontLevel, int? lineLevel}) =>
      ReadingSettings(fontLevel: fontLevel ?? this.fontLevel, lineLevel: lineLevel ?? this.lineLevel);
}

String? _fontFamily(AppLang lang) => switch (lang) {
  AppLang.ko => GoogleFonts.notoSansKr().fontFamily,
  AppLang.ja => GoogleFonts.notoSansJp().fontFamily,
  AppLang.en => GoogleFonts.notoSans().fontFamily,
};

TextStyle? _withHeight(TextStyle? s, double h) => s?.copyWith(height: h);

ThemeData buildTheme(AppLang lang, ReadingSettings reading) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.paper,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: _fontFamily(lang),
  );
  final t = base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  final h = reading.lineHeight;
  final text = t.copyWith(
    displayLarge: _withHeight(t.displayLarge, h),
    displayMedium: _withHeight(t.displayMedium, h),
    displaySmall: _withHeight(t.displaySmall, h),
    headlineLarge: _withHeight(t.headlineLarge, h),
    headlineMedium: _withHeight(t.headlineMedium, h),
    headlineSmall: _withHeight(t.headlineSmall, h),
    titleLarge: _withHeight(t.titleLarge, h),
    titleMedium: _withHeight(t.titleMedium, h),
    titleSmall: _withHeight(t.titleSmall, h),
    bodyLarge: _withHeight(t.bodyLarge, h),
    bodyMedium: _withHeight(t.bodyMedium, h),
    bodySmall: _withHeight(t.bodySmall, h),
    labelLarge: _withHeight(t.labelLarge, h),
    labelMedium: _withHeight(t.labelMedium, h),
    labelSmall: _withHeight(t.labelSmall, h),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: const BorderSide(color: AppColors.ink, width: 1.4),
  );
  return base.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        shape: shape,
        side: const BorderSide(color: AppColors.ink, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.ink, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.paper,
      shape: pillBorder,
      side: const BorderSide(color: AppColors.ink, width: 1.3),
      labelStyle: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.paper,
      indicatorColor: AppColors.sideSelected,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) =>
            TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: AppColors.ink),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.ink),
      ),
    ),
    checkboxTheme: CheckboxThemeData(side: const BorderSide(color: AppColors.ink, width: 1.6)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
