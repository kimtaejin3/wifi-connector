import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
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

  test('빈 결과', () {
    expect(extractor.fromOcrResults([]).isEmpty, isTrue);
  });
}
