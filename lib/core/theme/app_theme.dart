import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 화면 전체에서 쓰는 색. 강조색은 인디고 하나뿐이고, 라운드는 카드 20 / 버튼·입력 16으로 통일한다.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.danger,
    required this.shadow,
  });

  static const light = AppPalette(
    background: Color(0xFFF3F5FB),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1F33),
    muted: Color(0xFF7C819A),
    hairline: Color(0xFFE6E9F4),
    accent: Color(0xFF5B67F1),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEDEFFE),
    success: Color(0xFF2EB872),
    danger: Color(0xFFE0475B),
    // 배경색 계열로 물들인 그림자. 검정 그림자는 쓰지 않는다.
    shadow: Color(0x1A2C3A8C),
  );

  static const dark = AppPalette(
    background: Color(0xFF0F1220),
    card: Color(0xFF191D30),
    ink: Color(0xFFF2F3FA),
    muted: Color(0xFF9AA0BC),
    hairline: Color(0xFF262B44),
    accent: Color(0xFF7B85FF),
    onAccent: Color(0xFF0F1220),
    accentSoft: Color(0xFF232A55),
    success: Color(0xFF4CD08A),
    danger: Color(0xFFF06A7A),
    shadow: Color(0x40000000),
  );

  final Color background;
  final Color card;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color success;
  final Color danger;
  final Color shadow;

  static const cardRadius = 20.0;
  static const controlRadius = 16.0;

  List<BoxShadow> get cardShadow => [
        BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 10)),
      ];

  static AppPalette of(BuildContext context) => Theme.of(context).extension<AppPalette>()!;

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) => t < 0.5 ? this : (other ?? this);
}

abstract final class AppTheme {
  static ThemeData light() => _build(AppPalette.light, Brightness.light);
  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: brightness).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      surface: p.background,
      onSurface: p.ink,
      onSurfaceVariant: p.muted,
      surfaceContainerHighest: p.card,
      outlineVariant: p.hairline,
      error: p.danger,
    );

    // iOS에서 Android식 물결(ripple) 효과를 쓰지 않는다.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      splashFactory: isIOS ? NoSplash.splashFactory : null,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: p.ink, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      textTheme: Typography.material2021(platform: defaultTargetPlatform).black.apply(
            bodyColor: p.ink,
            displayColor: p.ink,
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        hintStyle: TextStyle(color: p.muted),
        border: _border(p.hairline),
        enabledBorder: _border(p.hairline),
        focusedBorder: _border(p.accent, width: 1.5),
        errorBorder: _border(p.danger),
        focusedErrorBorder: _border(p.danger, width: 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppPalette.controlRadius)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.muted,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.card,
        side: BorderSide(color: p.hairline),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? p.accent : p.muted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? p.accent : p.muted,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.hairline, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.ink,
        contentTextStyle: TextStyle(color: p.background, fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppPalette.controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
}
