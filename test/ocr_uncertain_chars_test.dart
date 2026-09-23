import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';

OcrLine line(String text, List<double?> confidences) {
  assert(text.length == confidences.length);
  return OcrLine(
    text,
    const Rect.fromLTWH(0, 0, 100, 20),
    chars: [for (var i = 0; i < text.length; i++) OcrChar(text[i], confidences[i])],
  );
}

void main() {
  test('신뢰도가 낮은 글자의 위치를 값 기준 인덱스로 돌려준다', () {
    final lines = [
      line('Password : Coffee!123', [
        ...List.filled(11, 0.99), // "Password : "
        0.99, 0.99, 0.99, 0.99, 0.99, 0.99, // Coffee
        0.31, // !
        0.99, 0.55, 0.99, // 123
      ]),
    ];
    expect(uncertainCharIndexes('Coffee!123', lines), {6, 8});
  });

  test('신뢰도가 없으면(iOS) 아무것도 표시하지 않는다', () {
    final lines = [line('PW: abc12345', List.filled(12, null))];
    expect(uncertainCharIndexes('abc12345', lines), isEmpty);
  });

  test('파서가 공백을 밑줄로 바꾼 값도 원래 줄과 맞춘다', () {
    final lines = [
      line('Wi-Fi : kkk 5G', [...List.filled(8, 0.99), 0.9, 0.9, 0.9, 0.99, 0.4, 0.9]),
    ];
    expect(uncertainCharIndexes('kkk_5G', lines), {4});
  });

  test('전각 문자는 정규화해서 맞춘다', () {
    final lines = [
      line('ＰＷ：Ｔｅｓｔ１', [0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.2]),
    ];
    expect(uncertainCharIndexes('Test1', lines), {4});
  });

  test('기호를 자모/원 문자로 읽어 되돌린 글자는 신뢰도가 높아도 불확실로 본다', () {
    final lines = [
      OcrLine('PW: ○kim', const Rect.fromLTWH(0, 0, 100, 20), chars: [
        for (final ch in 'PW: '.split('')) OcrChar(ch, 0.99),
        const OcrChar('○', 0.95),
        for (final ch in 'kim'.split('')) OcrChar(ch, 0.99),
      ]),
    ];
    expect(uncertainCharIndexes('0kim', lines), {0});
  });

  test('값을 찾지 못하면 빈 집합', () {
    expect(uncertainCharIndexes('nothing', [line('abc', [0.1, 0.1, 0.1])]), isEmpty);
    expect(uncertainCharIndexes('', [line('abc', [0.1, 0.1, 0.1])]), isEmpty);
  });
}
