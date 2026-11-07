// 이름(SSID) 앞뒤의 장식 기호 떼기. 모든 이름·비밀번호는 지어낸 값이다.
//
// 안내문은 "◆ 모모양꼬치 ◆"처럼 이름 양쪽에 작은 장식을 붙이곤 한다. 앞쪽 장식은 셀을 나눌 때
// 글머리표 규칙이 떼지만, 뒤쪽 장식은 이름에 남았다. OCR은 작은 마름모를 `·` `•` `.` `,`로 바꿔 읽기도 한다.
// 장식 떼기는 이름에만 한다. 비밀번호 끝의 `~` `*` `!` `#`는 흔한 진짜 글자다.
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

const _parser = WifiCredentialParser();

void main() {
  group('이름 앞뒤 장식 기호를 뗀다', () {
    for (final (raw, why) in [
      ('◆모모양꼬치◆', '양쪽 마름모'),
      ('◇ 모모양꼬치 ◇', '양쪽 빈 마름모, 띄어 씀'),
      ('·모모양꼬치·', '양쪽 가운뎃점 (작은 마름모를 OCR이 읽은 모양)'),
      ('• 모모양꼬치 •', '양쪽 글머리표, 띄어 씀'),
      ('모모양꼬치•', '뒤쪽만 남은 장식'),
      ('모모양꼬치 ·', '뒤쪽만, 띄어 씀'),
      ('★모모양꼬치★', '양쪽 별'),
      ('♥ 모모양꼬치 ♥', '양쪽 하트'),
      ('✿모모양꼬치✿', '양쪽 꽃'),
      ('❖ 모모양꼬치 ❖', '양쪽 장식 마름모'),
      ('▶ 모모양꼬치 ◀', '양쪽 화살촉'),
      ('■모모양꼬치■', '양쪽 네모'),
      ('.모모양꼬치,', '마름모를 마침표·쉼표로 읽은 양쪽'),
      ('모모양꼬치 .', '뒤쪽 마침표, 띄어 씀'),
      ('모모양꼬치.', '한글 이름 바로 뒤 마침표 (한글 이름은 문장부호로 끝나지 않는다)'),
    ]) {
      test('$raw → 모모양꼬치 ($why)', () {
        final c = _parser.parse('WIFI\n$raw\nMomok123~');
        expect(c.ssid, '모모양꼬치');
        expect(c.password, 'Momok123~');
      });
    }

    test('영문 이름도 양쪽 장식을 뗀다', () {
      final c = _parser.parse('와이파이 : ★cafe_momo★\n비밀번호 : momo12345');
      expect(c.ssid, 'cafe_momo');
      expect(c.password, 'momo12345');
    });

    test('이름표 같은 줄의 이름 뒤 장식', () {
      final c = _parser.parse('WIFI : 모모 •\nPW : abc12345');
      expect(c.ssid, '모모');
    });

    test('후보 목록에도 장식 붙은 이름이 남지 않는다', () {
      final c = _parser.parse('WIFI\n• 모모양꼬치 •\nMomok123~');
      final ssids = c.candidatesOf(WifiCandidateType.ssid).map((e) => e.value);
      expect(ssids.where((v) => v.contains('•')), isEmpty, reason: '$ssids');
    });
  });

  group('진짜 글자는 그대로 둔다', () {
    test('이름 끝 느낌표', () {
      expect(_parser.parse('WIFI : 모모!\nPW : abc12345').ssid, '모모!');
    });

    test('영문 이름 끝 마침표 (한쪽만, 붙어 있음)', () {
      expect(_parser.parse('WIFI : momo_cafe.\nPW : abc12345').ssid, 'momo_cafe.');
    });

    test('이름 끝 +, 하이픈 (붙어 있음)', () {
      expect(_parser.parse('WIFI : momo_LGU+\nPW : abc12345').ssid, 'momo_LGU+');
      expect(_parser.parse('WIFI : momo-\nPW : abc12345').ssid, 'momo-');
    });

    test('이름 가운데 가운뎃점', () {
      expect(_parser.parse('WIFI : 카페·바_momo\nPW : abc12345').ssid, '카페·바_momo');
    });

    for (final pw in ['abc123~', 'abc123*', 'abc123!', 'abc123#', 'abc-1234', 'abc12345.', 'abc12345-', 'abc12345+']) {
      test('비밀번호 $pw', () {
        final c = _parser.parse('WIFI : momo_cafe\nPW : $pw');
        expect(c.ssid, 'momo_cafe');
        expect(c.password, pw);
      });
    }

    test('비밀번호 줄의 장식 모양 끝 글자도 그대로 (이름표 없는 카드)', () {
      final c = _parser.parse('WIFI\n◆모모양꼬치◆\nMomok123*');
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123*');
    });
  });
}
