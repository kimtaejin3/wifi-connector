import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/core/utils/text_normalizer.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

import 'support/ocr_fixture.dart';

const _parser = WifiCredentialParser();

void main() {
  group('파서: 단어 간격 표시 글자', () {
    test('이름의 표시 글자는 밑줄이 된다', () {
      final c = _parser.parse('WIFI: Lumi${gapMarker}Cafe\nPW: lumi7788');
      expect(c.ssid, 'Lumi_Cafe');
      expect(c.password, 'lumi7788');
    });

    test('비밀번호의 표시 글자는 빈 문자가 된다', () {
      final c = _parser.parse('SSID: cafe_momo\nPW: abc${gapMarker}1234');
      expect(c.password, 'abc1234');
    });

    test('보통 공백(진짜 띄어쓰기)은 그대로 둔다', () {
      final c = _parser.parse('WIFI: Momo Coffee Roasters\nPW: roast0101');
      expect(c.ssid, 'Momo Coffee Roasters');
    });

    test('결과의 어떤 후보 값에도 표시 글자가 남지 않는다', () {
      final c = _parser.parse('WIFI: Lumi${gapMarker}Cafe\nPW: lumi${gapMarker}7788');
      for (final cand in [...c.candidatesOf(WifiCandidateType.ssid), ...c.candidatesOf(WifiCandidateType.password)]) {
        expect(cand.value.contains(gapMarker), isFalse, reason: cand.value);
      }
    });
  });

  group('fixture: 단어 간격 표시 글자', () {
    const parser = WifiCredentialParser();
    String ssidOf(String name) => parser.parse(OcrFixture.load(name).toOcrResult().layoutText).ssid ?? '';

    test('variants-43 진짜 띄어쓰기 이름은 그대로다', () => expect(ssidOf('variants-43'), 'Momo Coffee Roasters'));
  });
}
