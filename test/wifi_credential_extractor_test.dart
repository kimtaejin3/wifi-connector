import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';

OcrResult korean(String text) =>
    OcrResult(script: TextRecognitionScript.korean, text: text, layoutText: text);
OcrResult latin(String text) =>
    OcrResult(script: TextRecognitionScript.latin, text: text, layoutText: text);

void main() {
  const extractor = WifiCredentialExtractor();

  test('영문 안내문은 라틴 인식기 결과를 우선한다', () {
    final result = extractor.fromOcrResults([
      korean('SSID: cafe\nPW: hel1o1234'),
      latin('SSID: cafe\nPW: hello1234'),
    ]);
    expect(result.password, 'hello1234');
  });

  test('한글이 있으면 한국어 인식기 결과를 우선한다', () {
    final result = extractor.fromOcrResults([
      korean('와이파이: 카페모모\n비밀번호: hello1234'),
      latin('HIWHS: TIHIOO\nPW: hel1o1234'),
    ]);
    expect(result.ssid, '카페모모');
    expect(result.password, 'hello1234');
  });

  test('행 재구성 텍스트에서 못 찾으면 원문으로 다시 시도한다', () {
    final result = extractor.fromOcrResults([
      OcrResult(
        script: TextRecognitionScript.korean,
        text: 'PW: hello1234',
        layoutText: 'nothing here',
      ),
    ]);
    expect(result.password, 'hello1234');
  });

  group('fillMissing', () {
    test('못 찾은 항목만 채우고 찾은 항목은 유지한다', () {
      final base = extractor.fromOcrResults([latin('W-Fi: kkk_5G')]);
      expect(base.hasSsid, isTrue);
      expect(base.hasPassword, isFalse);
      final other = extractor.fromOcrResults([korean('Wi-Fi: 들니다\nPassword: @kim54796')]);
      final filled = extractor.fillMissing(base, other);
      expect(filled.ssid, 'kkk_5G');
      expect(filled.password, '@kim54796');
      expect(filled.candidatesOf(WifiCandidateType.ssid).map((c) => c.value), isNot(contains('들니다')));
    });

    test('채울 것이 없으면 그대로', () {
      final base = extractor.fromOcrResults([latin('SSID: cafe\nPW: abc12345')]);
      final other = extractor.fromOcrResults([korean('SSID: other\nPW: zzz12345')]);
      expect(identical(extractor.fillMissing(base, other), base), isTrue);
    });
  });

  test('빈 결과', () {
    expect(extractor.fromOcrResults([]).isEmpty, isTrue);
  });
}
