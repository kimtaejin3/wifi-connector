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
      final base = extractor.fromOcrResults([latin('W-Fi: momo_5G')]);
      expect(base.hasSsid, isTrue);
      expect(base.hasPassword, isFalse);
      final other = extractor.fromOcrResults([korean('Wi-Fi: 들니다\nPassword: @cat54796')]);
      final filled = extractor.fillMissing(base, other);
      expect(filled.ssid, 'momo_5G');
      expect(filled.password, '@cat54796');
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

  group('한쪽만 찾았을 때 원문으로 보완', () {
    test('행 재구성에서 비밀번호를 놓치면 원문에서 채운다', () {
      // 넓은 자간 때문에 행 재구성이 라벨과 값을 다른 행으로 흩어 놓은 경우
      final r = OcrResult(
        script: TextRecognitionScript.korean,
        text: 'WIFI : cafe_momo\nPW : momo12345',
        layoutText: 'WIFI : cafe_momo\nPW\nzz\nmomo 12 345',
      );
      final c = extractor.fromOcrResults([r]);
      expect(c.ssid, 'cafe_momo');
      expect(c.password, 'momo12345');
    });

    test('행 재구성에서 찾은 값은 원문이 바꾸지 않는다', () {
      final r = OcrResult(
        script: TextRecognitionScript.latin,
        text: 'WIFI : other_net\nPW : momo12345',
        layoutText: 'WIFI : cafe_momo',
      );
      final c = extractor.fromOcrResults([r]);
      expect(c.ssid, 'cafe_momo');
      expect(c.password, 'momo12345');
    });
  });

  test('fillMissing은 기준보다 낮은 추측 후보를 쓰지 않는다', () {
    final base = extractor.fromOcrResults([latin('WIFI : cafe_momo')]);
    final guess = extractor.fromOcrResults([latin('cafe_momo\nmomo12345')]);
    expect(guess.password, 'momo12345');
    expect(extractor.fillMissing(base, guess, minScore: 0.6).password, isNull);
    final labeled = extractor.fromOcrResults([latin('PW : momo12345')]);
    expect(extractor.fillMissing(base, labeled, minScore: 0.6).password, 'momo12345');
  });

  group('preferred', () {
    final results = [
      korean('SSID: cafe\nPW: hel1o1234'),
      latin('SSID: cafe\nPW: hello1234'),
    ];

    test('주어진 인식기를 우선한다', () {
      expect(extractor.fromOcrResults(results, preferred: TextRecognitionScript.korean).password, 'hel1o1234');
      expect(extractor.fromOcrResults(results, preferred: TextRecognitionScript.latin).password, 'hello1234');
    });
  });

  group('ScriptPreference', () {
    final hangul = [korean('비밀번호 : abc12345')];
    final ascii = [korean('PW : abc12345')];

    test('첫 프레임은 그 프레임의 한글 여부를 따른다', () {
      expect(ScriptPreference().update(hangul), TextRecognitionScript.korean);
      expect(ScriptPreference().update(ascii), TextRecognitionScript.latin);
    });

    test('한글이 한두 프레임 빠져도 바꾸지 않는다', () {
      final p = ScriptPreference();
      for (var i = 0; i < 6; i++) {
        p.update(hangul);
      }
      expect(p.update(ascii), TextRecognitionScript.korean);
      expect(p.update(ascii), TextRecognitionScript.korean);
    });

    test('한글이 대부분 사라지면 라틴으로 바꾼다', () {
      final p = ScriptPreference();
      for (var i = 0; i < 4; i++) {
        p.update(hangul);
      }
      for (var i = 0; i < 6; i++) {
        p.update(ascii);
      }
      expect(p.update(ascii), TextRecognitionScript.latin);
    });

    test('영문 안내문에 가끔 한글로 잘못 읽힌 프레임이 섞여도 라틴을 유지한다', () {
      final p = ScriptPreference();
      for (var i = 0; i < 6; i++) {
        p.update(ascii);
      }
      expect(p.update(hangul), TextRecognitionScript.latin);
      expect(p.update(hangul), TextRecognitionScript.latin);
    });
  });
}
