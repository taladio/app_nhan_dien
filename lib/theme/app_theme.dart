import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _green = Color(0xFF39745D);
  static const _ink = Color(0xFF24332C);
  static const _muted = Color(0xFF66766E);
  static const _canvas = Color(0xFFF5F7F3);
  static const _line = Color(0xFFE5EBE5);

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _green,
          brightness: Brightness.light,
          surface: Colors.white,
        ).copyWith(
          primary: _green,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE1EFE8),
          onPrimaryContainer: const Color(0xFF244C3C),
          secondary: const Color(0xFFC58B55),
          onSecondary: Colors.white,
          surface: Colors.white,
          surfaceContainerHighest: const Color(0xFFF0F3EF),
          onSurface: _ink,
          onSurfaceVariant: _muted,
          error: const Color(0xFFB44F43),
          errorContainer: const Color(0xFFFFEAE5),
          onErrorContainer: const Color(0xFF672D27),
          outline: const Color(0xFF89978F),
          outlineVariant: _line,
        );

    final roundedShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
    );
    final inputShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: const BorderSide(color: _line),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _canvas,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: _canvas,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _ink,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: _ink,
          fontSize: 27,
          height: 1.18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: TextStyle(
          color: _ink,
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: _ink,
          fontSize: 17,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: _ink, fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(color: _ink, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: _muted, fontSize: 12, height: 1.4),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputShape,
        enabledBorder: inputShape,
        focusedBorder: inputShape.copyWith(
          borderSide: const BorderSide(color: _green, width: 1.8),
        ),
        errorBorder: inputShape.copyWith(
          borderSide: const BorderSide(color: Color(0xFFB44F43)),
        ),
        focusedErrorBorder: inputShape.copyWith(
          borderSide: const BorderSide(color: Color(0xFFB44F43), width: 1.8),
        ),
        labelStyle: const TextStyle(color: _muted),
        floatingLabelStyle: const TextStyle(color: _green),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(56, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: roundedShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _green,
          minimumSize: const Size(56, 50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: _green, width: 1.2),
          shape: roundedShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _green,
          minimumSize: const Size(48, 46),
          shape: roundedShape,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: const Color(0xFFF0F4EF),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFDCECE3),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: states.contains(WidgetState.selected) ? 24 : 22,
            color: states.contains(WidgetState.selected) ? _green : _muted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0F3EF),
        selectedColor: const Color(0xFFE1EFE8),
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: const TextStyle(color: _ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      dividerColor: _line,
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
