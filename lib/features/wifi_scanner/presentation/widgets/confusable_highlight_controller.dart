import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// OCR이 서로 헷갈리기 쉬운 글자(`0/O/o`, `1/l/I/|`)를 다른 색으로 보여주는 입력 컨트롤러.
///
/// 어느 쪽이 맞는지는 앱이 알 수 없으므로 값을 고치지 않고, 사용자가 안내문과
/// 비교할 위치만 눈에 띄게 한다. `obscureText`일 때는 EditableText가 이 span을
/// 쓰지 않으므로 비밀번호 숨김 상태에서는 강조가 드러나지 않는다.
class ConfusableHighlightController extends TextEditingController {
  ConfusableHighlightController({super.text});

  static final confusables = RegExp(r'[0Oo1lI|]');

  static bool hasConfusables(String text) => confusables.hasMatch(text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // 한글 조합 중에는 기본 밑줄 표시를 유지한다.
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    if (!hasConfusables(text)) return TextSpan(style: style, text: text);

    final highlight = (style ?? const TextStyle()).copyWith(
      color: AppTheme.attention,
      fontWeight: FontWeight.w700,
    );
    final children = <InlineSpan>[];
    var start = 0;
    for (final m in confusables.allMatches(text)) {
      if (m.start > start) children.add(TextSpan(text: text.substring(start, m.start)));
      children.add(TextSpan(text: m[0], style: highlight));
      start = m.end;
    }
    if (start < text.length) children.add(TextSpan(text: text.substring(start)));
    return TextSpan(style: style, children: children);
  }
}
