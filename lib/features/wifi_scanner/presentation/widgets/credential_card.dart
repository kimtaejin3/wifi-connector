import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// SSID 또는 비밀번호 하나를 보여주는 카드. 읽기 전용이면 텍스트, 편집 중이면 같은 자리에 입력창.
class CredentialCard extends StatelessWidget {
  const CredentialCard({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.accent = false,
    this.editable = false,
    this.autofocus = false,
    this.hint,
    this.error,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;

  /// 인디고 배경의 강조 카드 (네트워크 이름).
  final bool accent;
  final bool editable;
  final bool autofocus;
  final String? hint;
  final String? error;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final foreground = accent ? p.onAccent : p.ink;
    final secondary = accent ? p.onAccent.withValues(alpha: 0.72) : p.muted;
    final valueStyle = TextStyle(
      color: foreground,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.2,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            color: accent ? p.accent : p.card,
            borderRadius: BorderRadius.circular(AppPalette.cardRadius),
            boxShadow: p.cardShadow,
            border: error != null ? Border.all(color: p.danger, width: 1.5) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent ? p.onAccent.withValues(alpha: 0.18) : p.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent ? p.onAccent : p.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: secondary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (editable)
                      TextField(
                        controller: controller,
                        autofocus: autofocus,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: textInputAction,
                        style: valueStyle,
                        cursorColor: foreground,
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: hint,
                          hintStyle: valueStyle.copyWith(color: secondary, fontWeight: FontWeight.w500),
                        ),
                        onChanged: onChanged,
                        onSubmitted: onSubmitted,
                      )
                    else
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => Text(
                          value.text.isEmpty ? (hint ?? '') : value.text,
                          style: value.text.isEmpty
                              ? valueStyle.copyWith(color: secondary, fontWeight: FontWeight.w500)
                              : valueStyle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 6),
            child: Text(error!, style: TextStyle(color: p.danger, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }
}
