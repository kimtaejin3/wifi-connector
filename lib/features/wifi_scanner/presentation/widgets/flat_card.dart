import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 그림자 없이 얇은 테두리로만 구분하는 카드.
class FlatCard extends StatelessWidget {
  const FlatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppPalette.cardRadius),
      side: BorderSide(color: borderColor ?? p.hairline),
    );
    return Material(
      color: p.card,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 카드 안의 한 항목: 작은 라벨 + 값. 편집 중이면 값 자리에 테두리 없는 입력창.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.large = false,
    this.editable = false,
    this.autofocus = false,
    this.hint,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String? label;
  final TextEditingController controller;

  /// 네트워크 이름처럼 화면의 주인공인 값은 크게.
  final bool large;
  final bool editable;
  final bool autofocus;
  final String? hint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final valueStyle = TextStyle(
      color: p.ink,
      fontSize: large ? 30 : 22,
      fontWeight: large ? FontWeight.w700 : FontWeight.w600,
      height: 1.25,
      letterSpacing: large ? -0.5 : -0.2,
    );
    final hintStyle = valueStyle.copyWith(color: p.muted, fontWeight: FontWeight.w500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
        ],
        if (editable)
          TextField(
            controller: controller,
            autofocus: autofocus,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: textInputAction,
            style: valueStyle,
            cursorColor: p.accent,
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hint,
              hintStyle: hintStyle,
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          )
        else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => Text(
              value.text.isEmpty ? (hint ?? '') : value.text,
              style: value.text.isEmpty ? hintStyle : valueStyle,
            ),
          ),
      ],
    );
  }
}
