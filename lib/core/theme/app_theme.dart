import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 흰색/검정 중심의 Material 3 테마.
abstract final class AppTheme {
  static const success = Color(0xFF1E9E5A);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF111111);
    final background = isDark ? const Color(0xFF0B0B0C) : Colors.white;
    final field = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F4);
    final muted = isDark ? const Color(0xFF9A9AA0) : const Color(0xFF6E6E73);

    final scheme = ColorScheme.fromSeed(seedColor: Colors.black, brightness: brightness).copyWith(
      primary: foreground,
      onPrimary: background,
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      surfaceContainerHighest: field,
      error: const Color(0xFFE5484D),
    );

    // iOS에서 Android식 물결(ripple) 효과를 쓰지 않는다.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: isIOS ? NoSplash.splashFactory : null,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: TextStyle(color: muted),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(foreground, width: 1.5),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
}
