import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

OcrLine line(String text, double left, double top, {double width = 200, double height = 40}) =>
    OcrLine(text, Rect.fromLTWH(left, top, width, height));

void main() {
  test('같은 높이의 라벨/값 줄을 한 행으로 묶는다', () {
    // ML Kit이 라벨 열과 값 열을 서로 다른 블록으로 돌려준 경우
    final text = layoutRows([
      line('Wi-Fi', 40, 100),
      line('Password', 40, 180),
      line('cafe_momo', 400, 104),
      line('momo1234', 400, 178),
    ]);
    expect(text, 'Wi-Fi\tcafe_momo\nPassword\tmomo1234');

    final credential = const WifiCredentialParser().parse(text);
    expect(credential.ssid, 'cafe_momo');
    expect(credential.password, 'momo1234');
  });

  test('살짝 기울어진 행도 한 행으로 묶는다', () {
    final text = layoutRows([
      line('SSID :', 40, 100),
      line('TestCafe', 300, 112),
    ]);
    expect(text, 'SSID :\tTestCafe');
  });

  test('줄 간격이 있으면 다른 행', () {
    final text = layoutRows([
      line('WIFI', 40, 100),
      line('momo_cafe', 40, 150),
    ]);
    expect(text, 'WIFI\nmomo_cafe');
  });

  test('빈 줄은 무시', () {
    expect(layoutRows([line('  ', 0, 0), line('PW 1234', 0, 100)]), 'PW 1234');
    expect(layoutRows([]), '');
  });
}
