import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/theme/app_theme.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/widgets/confusable_highlight_controller.dart';

void main() {
  test('헷갈리는 글자 감지', () {
    expect(ConfusableHighlightController.hasConfusables('Test12345'), isTrue); // 1
    expect(ConfusableHighlightController.hasConfusables('cafe_momo'), isTrue); // o
    expect(ConfusableHighlightController.hasConfusables('Cafe_5G'), isTrue); // 5
    expect(ConfusableHighlightController.hasConfusables('cafe_7G'), isFalse);
    expect(ConfusableHighlightController.hasConfusables('카페모모'), isFalse);
  });

  testWidgets('헷갈리는 글자만 강조색으로 나눈다', (tester) async {
    final controller = ConfusableHighlightController(text: 'ab0cd');
    late TextSpan span;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        span = controller.buildTextSpan(
          context: context,
          style: const TextStyle(fontSize: 18),
          withComposing: false,
        );
        return const SizedBox();
      }),
    ));

    final children = span.children!.cast<TextSpan>();
    expect(children.map((c) => c.text), ['ab', '0', 'cd']);
    expect(children[1].style?.color, AppTheme.attention);
    expect(children[0].style?.color, isNull);
    expect(span.toPlainText(), 'ab0cd');
  });

  testWidgets('인식기가 자신 없어 한 글자는 처음 값일 때만 강조한다', (tester) async {
    final controller = ConfusableHighlightController(text: 'cafe', uncertainIndexes: {2});
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      }),
    ));

    var span = controller.buildTextSpan(context: ctx, withComposing: false);
    expect(span.children!.cast<TextSpan>().map((c) => c.text), ['ca', 'f', 'e']);
    expect(controller.hasHighlights, isTrue);

    controller.text = 'cafx';
    span = controller.buildTextSpan(context: ctx, withComposing: false);
    expect(span.children, isNull);
    expect(controller.hasHighlights, isFalse);
  });

  testWidgets('헷갈리는 글자가 없으면 그대로', (tester) async {
    final controller = ConfusableHighlightController(text: 'cafe_7G');
    late TextSpan span;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        span = controller.buildTextSpan(context: context, withComposing: false);
        return const SizedBox();
      }),
    ));
    expect(span.children, isNull);
    expect(span.text, 'cafe_7G');
  });
}
