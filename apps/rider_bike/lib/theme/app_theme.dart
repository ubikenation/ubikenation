import 'package:flutter/material.dart';

/// U-Bike brand theme (shared look with the customer app; bike rider uses the
/// green accent as primary action colour, matching the prototype's bike flow).
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF12A0D7);
  static const Color primaryDark = Color(0xFF0B6FA4);
  static const Color green = Color(0xFF2E9E4F);
  static const Color red = Color(0xFFE2483D);
  static const Color ink = Color(0xFF1A2330);
  static const Color muted = Color(0xFF6B7785);
  static const Color surface = Color(0xFFF5F8FA);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: primary, primary: primary, secondary: green);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }
}
