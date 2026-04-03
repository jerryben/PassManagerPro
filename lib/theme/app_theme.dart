import 'package:flutter/material.dart';

class AppTheme {
  // ── Palette ───────────────────────────────────────────────────
  static const Color background    = Color(0xFF0F1117);
  static const Color surface       = Color(0xFF1A1D27);
  static const Color surfaceAlt    = Color(0xFF252836);
  static const Color primary       = Color(0xFF6C63FF);
  static const Color secondary     = Color(0xFF00D4AA);
  static const Color error         = Color(0xFFFF4757);
  static const Color warning       = Color(0xFFFFB347);
  static const Color success       = Color(0xFF2ED573);
  static const Color textPrimary   = Color(0xFFE8E8F0);
  static const Color textSecondary = Color(0xFF9090A8);
  static const Color border        = Color(0xFF2E3147);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          background: background,
          surface: surface,
          primary: primary,
          secondary: secondary,
          error: error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: textSecondary),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: error),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textSecondary),
          prefixIconColor: textSecondary,
          suffixIconColor: textSecondary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: primary),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: border),
          ),
          margin: EdgeInsets.zero,
        ),
        dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        textTheme: const TextTheme(
          bodyLarge:   TextStyle(color: textPrimary),
          bodyMedium:  TextStyle(color: textSecondary),
          titleLarge:  TextStyle(color: textPrimary,   fontWeight: FontWeight.bold),
          titleMedium: TextStyle(color: textPrimary,   fontWeight: FontWeight.w600),
          labelSmall:  TextStyle(color: textSecondary, fontSize: 11),
        ),
      );
}
