// 단어 간격 표시 글자(U+2009)가 파서 밖으로 새지 않는지 검사한다:
// 정규화·불확실 글자 위치·투표기·결과 값 어디에도 남거나 위치를 틀어지게 하면 안 된다.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/utils/text_normalizer.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/credential_voter.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'support/ocr_fixture.dart';

const _extractor = WifiCredentialExtractor();

OcrLine _line(String text, {Map<int, double> low = const {}}) => OcrLine(
      text,
      const Rect.fromLTWH(0, 0, 400, 40),
      chars: [
        for (var i = 0; i < text.length; i++) OcrChar(text[i], low[i] ?? 0.99),
      ],
    );

OcrResult _result(List<OcrLine> lines) => OcrResult(
      script: TextRecognitionScript.korean,
      text: lines.map((l) => l.text.replaceAll(gapMarker, ' ')).join('\n'),
      layoutText: layoutRows(lines),
      lines: lines,
    );

void main() {
  group('정규화', () {
    test('normalizeOcrText는 표시 글자를 지우거나 다른 글자로 바꾸지 않는다 (파서가 값을 정리할 때 쓴다)', () {
      expect(normalizeOcrText('Lumi${gapMarker}Cafe'), 'Lumi${gapMarker}Cafe');
    });
  });

  group('불확실 글자 위치', () {
    test('이름의 표시 글자 자리를 밑줄 위치로 맞춰 불확실 글자를 찾는다', () {
      // "WIFI: Lumi<표시>Cafe": 'C'(값 인덱스 5)를 불확실하게 읽음
      const text = 'WIFI: Lumi${gapMarker}Cafe';
      final lines = [_line(text, low: {text.indexOf('C'): 0.3})];
      expect(uncertainCharIndexes('Lumi_Cafe', lines), {5});
    });

    test('비밀번호의 표시 글자는 값에 없으니 건너뛰고 위치를 맞춘다', () {
      const text = 'PW: lumi${gapMarker}7788';
      final lines = [_line(text, low: {text.indexOf('7'): 0.3})];
      expect(uncertainCharIndexes('lumi7788', lines), {4});
    });
  });

  group('추출기·투표기', () {
    OcrResult frame() => _result([
          _line('WIFI: Lumi${gapMarker}Cafe'),
          _line('PW: lumi${gapMarker}7788'),
        ]);

    test('추출 결과의 값·후보 어디에도 표시 글자가 없다', () {
      final c = _extractor.fromOcrResults([frame()]);
      expect(c.ssid, 'Lumi_Cafe');
      expect(c.password, 'lumi7788');
      for (final cand in c.candidates) {
        expect(cand.value.contains(gapMarker), isFalse, reason: cand.value);
      }
    });

    test('여러 프레임을 투표해도 값에 표시 글자가 없고 안정으로 읽힌다', () {
      final voter = CredentialVoter();
      for (var i = 0; i < 4; i++) {
        voter.add(_extractor.fromOcrResults([frame()]));
      }
      final vote = voter.vote();
      expect(vote.ssid?.value, 'Lumi_Cafe');
      expect(vote.password?.value, 'lumi7788');
      expect(vote.isStable, isTrue);
      final shown = voter.toCredential(vote, sources: [_extractor.fromOcrResults([frame()])]);
      expect(shown.ssid!.contains(gapMarker), isFalse);
      expect(shown.password!.contains(gapMarker), isFalse);
      for (final cand in shown.candidates) {
        expect(cand.value.contains(gapMarker), isFalse);
      }
    });
  });

  test('모든 fixture의 추출 결과(값·후보)에 표시 글자가 남지 않는다', () {
    for (final name in OcrFixture.names()) {
      final c = _extractor.fromOcrResults([OcrFixture.load(name).toOcrResult()]);
      for (final v in [c.ssid, c.password, ...c.candidates.map((x) => x.value)]) {
        expect(v?.contains(gapMarker) ?? false, isFalse, reason: '$name: $v');
      }
      // 불확실 글자 위치는 값 안의 위치여야 한다
      for (final i in c.ssidUncertainIndexes) {
        expect(i, lessThan(c.ssid!.length), reason: name);
      }
      for (final i in c.passwordUncertainIndexes) {
        expect(i, lessThan(c.password!.length), reason: name);
      }
    }
  });
}
