import 'package:flutter/material.dart';

/// U-Bike modern design system — clean, spacious, Bolt-style. Keeps the U-Bike
/// blue brand, adds a consistent set of tokens (radii, spacing, shadows) and
/// polished component themes so every screen feels cohesive and premium.
class AppTheme {
  AppTheme._();

  // ---- Brand palette ----
  static const Color primary = Color(0xFF12A0D7);
  static const Color primaryDark = Color(0xFF0B6FA4);
  static const Color accent = Color(0xFF16C784); // fresh green for success/positive
  static const Color ink = Color(0xFF10161F); // near-black text + primary buttons
  static const Color muted = Color(0xFF737D8C); // secondary text
  static const Color line = Color(0xFFE9EDF1); // hairline borders
  static const Color surface = Color(0xFFF3F5F8); // inputs / soft fills
  static const Color bg = Color(0xFFFAFBFC); // scaffold
  static const Color red = Color(0xFFE2483D);
  static const Color green = Color(0xFF16C784);

  // ---- Tokens ----
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 22;
  static const double gap = 16;

  /// Soft, modern elevation for cards and floating controls.
  static List<BoxShadow> get shadow => const [
        BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
      ];
  static List<BoxShadow> get shadowSm => const [
        BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4)),
      ];

  /// Reusable white card surface with rounded corners + soft shadow.
  static BoxDecoration card({double radius = rLg}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadowSm,
      );

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: Colors.white,
    );

    const heading = TextStyle(color: ink, fontWeight: FontWeight.w800, letterSpacing: -0.4);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: const TextTheme(
        displaySmall: heading,
        headlineMedium: heading,
        headlineSmall: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.3),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 20),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w700, fontSize: 16),
        bodyLarge: TextStyle(color: ink, fontSize: 16),
        bodyMedium: TextStyle(color: ink, fontSize: 14),
        labelLarge: TextStyle(fontWeight: FontWeight.w600),
      ).apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink, // Bolt-style bold dark primary action
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: muted, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(rLg))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
      ),
      listTileTheme: const ListTileThemeData(iconColor: ink, textColor: ink),
    );
  }
}
