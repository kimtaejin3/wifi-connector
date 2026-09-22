import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/utils/text_normalizer.dart';

void main() {
  test('전각 영문/숫자/기호를 반각으로', () {
    expect(normalizeOcrText('Ｔｅｓｔ１２３４５！'), 'Test12345!');
    expect(normalizeOcrText('ＰＷ：ａｂｃ'), 'PW:abc');
  });

  test('대시/따옴표 변형을 ASCII로', () {
    expect(normalizeOcrText('cafe–momo—5G‐x'), 'cafe-momo-5G-x');
    expect(normalizeOcrText('it’s “ok”'), 'it\'s "ok"');
  });

  test('보이지 않는 문자 제거, 특수 공백은 일반 공백', () {
    expect(normalizeOcrText('abc​123﻿'), 'abc123');
    expect(normalizeOcrText('a b　c'), 'a b c');
  });

  test('한글과 일반 ASCII, 대소문자는 그대로', () {
    expect(normalizeOcrText('카페모모 CafeABC_!@#'), '카페모모 CafeABC_!@#');
  });
}
