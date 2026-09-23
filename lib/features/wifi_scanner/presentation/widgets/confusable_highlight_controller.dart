import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 확인이 필요한 글자를 다른 색으로 보여주는 입력 컨트롤러.
///
/// 두 종류를 강조한다.
/// - 인식기가 자신 없어 한 글자([uncertainIndexes], Android ML Kit이 글자별 신뢰도를 줄 때).
///   사용자가 값을 고치면 위치가 어긋나므로 처음 값 그대로일 때만 표시한다.
/// - OCR이 서로 헷갈리기 쉬운 글자(`0/O/o`, `1/l/I/|`, `5/S`, `8/B`).
///
/// 어느 쪽이 맞는지는 앱이 알 수 없으므로 값을 고치지 않고, 사용자가 안내문과
/// 비교할 위치만 눈에 띄게 한다. `obscureText`일 때는 EditableText가 이 span을
/// 쓰지 않으므로 비밀번호 숨김 상태에서는 강조가 드러나지 않는다.
class ConfusableHighlightController extends TextEditingController {
  ConfusableHighlightController({super.text, this.uncertainIndexes = const {}}) : _original = text ?? '';

  static final confusables = RegExp(r'[0Oo1lI|5S8B]');

  static bool hasConfusables(String text) => confusables.hasMatch(text);

  final Set<int> uncertainIndexes;
  final String _original;

  bool get hasHighlights => hasConfusables(text) || (text == _original && uncertainIndexes.isNotEmpty);

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
    if (!hasHighlights) return TextSpan(style: style, text: text);

    final useUncertain = text == _original;
    final highlight = (style ?? const TextStyle()).copyWith(
      color: AppTheme.attention,
      fontWeight: FontWeight.w700,
    );
    final children = <InlineSpan>[];
    final run = StringBuffer();
    bool? runHighlighted;
    void flush() {
      if (run.isEmpty) return;
      children.add(TextSpan(text: run.toString(), style: runHighlighted! ? highlight : null));
      run.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      final highlighted = confusables.hasMatch(ch) || (useUncertain && uncertainIndexes.contains(i));
      if (runHighlighted != null && highlighted != runHighlighted) flush();
      runHighlighted = highlighted;
      run.write(ch);
    }
    flush();
    return TextSpan(style: style, children: children);
  }
}
