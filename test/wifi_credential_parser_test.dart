import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

void main() {
  const parser = WifiCredentialParser();

  void expectParsed(String text, {String? ssid, String? password}) {
    final result = parser.parse(text);
    expect(result.ssid, ssid, reason: 'ssid of:\n$text');
    expect(result.password, password, reason: 'password of:\n$text');
  }

  group('PRD 필수 케이스', () {
    test('SSID: / Password: 형식', () {
      expectParsed(
        'SSID: MOMO_WIFI\nPassword: 12345678',
        ssid: 'MOMO_WIFI',
        password: '12345678',
      );
    });

    test('라벨 다음 줄에 값', () {
      expectParsed(
        'WIFI\nMOMO_WIFI\n\nPW\nabc12345',
        ssid: 'MOMO_WIFI',
        password: 'abc12345',
      );
    });

    test('한글 라벨과 한글 SSID', () {
      expectParsed(
        '와이파이 : 카페모모\n비밀번호 : hello1234',
        ssid: '카페모모',
        password: 'hello1234',
      );
    });

    test('헤더 + 공백 구분 라벨, 대소문자/특수문자 보존', () {
      expectParsed(
        'Free WIFI\nNetwork MOMO_GUEST\nPassword Coffee!123',
        ssid: 'MOMO_GUEST',
        password: 'Coffee!123',
      );
    });

    test('MVP 완료 조건 안내문', () {
      expectParsed(
        'FREE WIFI\n\nSSID : TestCafe\nPassword : Test12345',
        ssid: 'TestCafe',
        password: 'Test12345',
      );
    });
  });

  group('PRD 본문 예시', () {
    test('개요 예시', () {
      expectParsed(
        'FREE WIFI\n\nWi-Fi : cafe_momo_5G\nPassword : momo1234',
        ssid: 'cafe_momo_5G',
        password: 'momo1234',
      );
    });

    test('OCR 처리 예시 (앞뒤 무관한 문장 포함)', () {
      expectParsed(
        'WELCOME TO MOMO CAFE\nWIFI\nmomo_cafe_5G\nPASSWORD\nmomo1234\nEnjoy!',
        ssid: 'momo_cafe_5G',
        password: 'momo1234',
      );
    });

    test('Case 3: 콜론 앞뒤 공백', () {
      expectParsed(
        'Wi-Fi : cafe_wifi\nPW : 12345678',
        ssid: 'cafe_wifi',
        password: '12345678',
      );
    });

    test('Case 4: 한글 라벨 + 공백 구분', () {
      expectParsed(
        '와이파이 cafe_wifi\n비밀번호 abc12345',
        ssid: 'cafe_wifi',
        password: 'abc12345',
      );
    });

    test('Candidate 점수 예시', () {
      final result = parser.parse('WIFI\nMOMO_GUEST\nPASSWORD\nhello1234');
      expect(result.ssid, 'MOMO_GUEST');
      expect(result.password, 'hello1234');
      expect(result.ssidConfidence, greaterThanOrEqualTo(0.8));
      expect(result.passwordConfidence, greaterThanOrEqualTo(0.8));
    });
  });

  group('일부만 발견', () {
    test('비밀번호만 있는 안내문은 SSID를 추측하지 않는다', () {
      final result = parser.parse('Wi-Fi Password\nhello1234');
      expect(result.ssid, isNull);
      expect(result.password, 'hello1234');
    });

    test('SSID만 있는 경우', () {
      expectParsed('WiFi: MOMO_CAFE', ssid: 'MOMO_CAFE', password: null);
    });

    test('Wi-Fi 정보가 없는 텍스트', () {
      final result = parser.parse('Americano 4500\nCafe Latte 5000\nThank you');
      expect(result.isEmpty, isTrue);
    });

    test('제목(FREE WIFI) 다음의 문장은 SSID로 잡지 않는다', () {
      expectParsed('FREE WIFI\nEnjoy your coffee', ssid: null, password: null);
      expectParsed('WIFI\nWelcome to our cafe', ssid: null, password: null);
    });

    test('빈 문자열', () {
      expect(parser.parse('').isEmpty, isTrue);
      expect(parser.parse('   \n  \n').isEmpty, isTrue);
    });
  });

  group('값 보존과 정리', () {
    test('비밀번호의 특수문자와 대소문자를 바꾸지 않는다', () {
      expectParsed(r'PW: CafeABC!@#$%&*_-.123', password: r'CafeABC!@#$%&*_-.123');
    });

    test('앞뒤 공백은 제거한다', () {
      expectParsed('  SSID :   cafe_wifi   \n  PW :  abc12345  ',
          ssid: 'cafe_wifi', password: 'abc12345');
    });

    test('전각 콜론과 = 구분자', () {
      expectParsed('SSID：cafe_wifi\nKey = abc12345', ssid: 'cafe_wifi', password: 'abc12345');
    });

    test('뒤에 붙은 괄호 설명은 제거한다', () {
      expectParsed('비밀번호 : 12345678 (숫자 8자리)', password: '12345678');
    });

    test('비밀번호 안의 공백은 보존한다', () {
      expectParsed('Password: my secret pass', password: 'my secret pass');
    });
  });

  group('다양한 라벨 표현', () {
    for (final label in [
      'P/W',
      'PASS',
      'Passcode',
      'Key',
      '비번',
      '암호',
      '패스워드',
      'Passward',
      'WiFi PW',
      '와이파이 비밀번호',
      '와이파이 비번',
    ]) {
      test('비밀번호 라벨: $label', () {
        expectParsed('$label: abc12345', password: 'abc12345');
      });
    }

    for (final label in [
      'Wi-Fi',
      'WiFi',
      'Wifi',
      'WI-FI',
      'SSID',
      'Network',
      'Network Name',
      '와이파이 이름',
      '네트워크',
      '네트워크 이름',
      'WIFI ID',
      'ID',
    ]) {
      test('SSID 라벨: $label', () {
        expectParsed('$label: cafe_wifi', ssid: 'cafe_wifi');
      });
    }

    test('Wi-Fi Password 는 SSID 라벨로 취급하지 않는다', () {
      expectParsed('Wi-Fi Password : hello1234', ssid: null, password: 'hello1234');
    });

    test('WIFI로 시작하는 SSID 값', () {
      expectParsed('WiFi\nWIFI_MOMO\nPW\n12345678', ssid: 'WIFI_MOMO', password: '12345678');
    });

    test('SSID 값 안의 pw 문자열로 분리하지 않는다', () {
      expectParsed('Wi-Fi: cafe_pw_net', ssid: 'cafe_pw_net');
    });

    test('주파수 대역 표기', () {
      expectParsed('Wi-Fi (5G) : cafe_5G\nPW : 12345678', ssid: 'cafe_5G', password: '12345678');
    });

    test('FREE WIFI ZONE 헤더의 ZONE을 SSID로 잡지 않는다', () {
      expectParsed('FREE WIFI ZONE\nID: momo\nPW: 12345678', ssid: 'momo', password: '12345678');
    });

    test('한글 복합 라벨', () {
      expectParsed('와이파이 이름: 카페모모\n와이파이 비번: coffee1234',
          ssid: '카페모모', password: 'coffee1234');
    });
  });

  group('한 줄에 여러 라벨', () {
    test('ID : x   PW : y', () {
      expectParsed('ID : momo_5G   PW : abc12345', ssid: 'momo_5G', password: 'abc12345');
    });

    test('구분자 없이 이어진 Network / PW', () {
      expectParsed('Network: My Cafe PW: 12345678', ssid: 'My Cafe', password: '12345678');
    });

    test('ID/PW : x / y', () {
      expectParsed('ID/PW : momo_5G / abc12345', ssid: 'momo_5G', password: 'abc12345');
    });

    test('WIFI / PW 라벨 다음 줄에 값 두 개', () {
      expectParsed('ID / PW\nmomo_5G / abc12345', ssid: 'momo_5G', password: 'abc12345');
    });
  });

  group('OCR 레이아웃 (셀은 탭으로 구분)', () {
    test('표 형태: 헤더 행 아래 값 행', () {
      expectParsed('SSID\tPASSWORD\ncafe_5G\t12345678', ssid: 'cafe_5G', password: '12345678');
    });

    test('표 형태: 셀 구분 없이 공백만 있는 경우', () {
      expectParsed('SSID PASSWORD\ncafe_5G 12345678', ssid: 'cafe_5G', password: '12345678');
    });

    test('라벨과 값이 같은 행의 다른 셀', () {
      expectParsed('Wi-Fi\tcafe_momo\nPassword\tmomo1234', ssid: 'cafe_momo', password: 'momo1234');
    });

    test('무관한 텍스트 뒤의 라벨 셀', () {
      expectParsed('Americano 4500\tWiFi: momo_cafe\nLatte 5000\tPW: coffee123',
          ssid: 'momo_cafe', password: 'coffee123');
    });
  });

  group('라벨 없는 fallback', () {
    test('SSID처럼 생긴 값은 낮은 신뢰도로 추천한다', () {
      final result = parser.parse('MOMO CAFE\nmomo_cafe_5G\nPassword: momo1234');
      expect(result.ssid, 'momo_cafe_5G');
      expect(result.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(result.password, 'momo1234');
    });

    test('SSID와 비밀번호가 같은 값으로 선택되지 않는다', () {
      final result = parser.parse('Password\ncafe_1234');
      expect(result.password, 'cafe_1234');
      expect(result.ssid, isNot('cafe_1234'));
    });

    test('후보 목록은 점수 내림차순', () {
      final result = parser.parse('WiFi: first_net\nWiFi: second net here\nPW: abc12345');
      final ssids = result.candidatesOf(WifiCandidateType.ssid);
      expect(ssids.first.value, 'first_net');
      for (var i = 1; i < ssids.length; i++) {
        expect(ssids[i - 1].score, greaterThanOrEqualTo(ssids[i].score));
      }
    });
  });

  group('OCR 노이즈 보정', () {
    test('전각 문자', () {
      expectParsed('ＳＳＩＤ：ＴｅｓｔＣａｆｅ\nＰＷ：Ｔｅｓｔ１２３４５', ssid: 'TestCafe', password: 'Test12345');
    });

    test('한글 조사와 문장 종결', () {
      expectParsed('와이파이는 카페모모\n비밀번호는 abc12345 입니다', ssid: '카페모모', password: 'abc12345');
      expectParsed('비밀번호 : abc12345입니다.', password: 'abc12345');
      expectParsed('와이파이가 cafe_momo 이고\n비번은 hello1234예요', ssid: 'cafe_momo', password: 'hello1234');
    });

    test('글머리 기호', () {
      expectParsed('• Wi-Fi : cafe\n▶ PW : abc12345\n- Enjoy', ssid: 'cafe', password: 'abc12345');
    });

    test('구분자 ; 와 |', () {
      expectParsed('SSID; cafe\nPW; abc12345', ssid: 'cafe', password: 'abc12345');
      expectParsed('ID | momo_guest\nPW | hello1234', ssid: 'momo_guest', password: 'hello1234');
    });

    test('라벨 안 띄어쓰기', () {
      expectParsed('와이 파이 : cafe\n비밀 번호 : abc12345', ssid: 'cafe', password: 'abc12345');
      expectParsed('네트 워크 : cafe\n패스 워드 : abc12345', ssid: 'cafe', password: 'abc12345');
    });

    test('Wi-Fi의 i가 빠진 W-Fi, Wi-F', () {
      expectParsed('W-Fi: kkk_5G\nPassword:@kim54796', ssid: 'kkk_5G', password: '@kim54796');
      expectParsed('Wi-F : cafe', ssid: 'cafe');
    });

    test('제목 다음 줄의 문구는 라벨이 붙은 값보다 훨씬 낮은 점수', () {
      final result = parser.parse('FREE WI-FI\n들니다\nWi-Fi: kkk 5G');
      expect(result.ssid, 'kkk_5G');
      final noise = result.candidatesOf(WifiCandidateType.ssid).firstWhere((c) => c.value == '들니다');
      expect(noise.score, lessThan(result.candidatesOf(WifiCandidateType.ssid).first.score - 0.2));
    });

    test('ID를 lD/1D로 오인식', () {
      expectParsed('lD : cafe\nPW : abc12345', ssid: 'cafe', password: 'abc12345');
    });

    test('대시 변형은 하이픈으로', () {
      expectParsed('PW : abc–12345', password: 'abc-12345');
    });

    test('"비밀번호 없음"은 공개 네트워크', () {
      final result = parser.parse('Wi-Fi : cafe_open\n비밀번호 : 없음');
      expect(result.ssid, 'cafe_open');
      expect(result.password, '');
      expect(result.isOpenNetwork, isTrue);
      expect(parser.parse('Password: none').isOpenNetwork, isTrue);
      expect(parser.parse('Password: abc12345').isOpenNetwork, isFalse);
    });
  });

  group('밑줄을 공백으로 읽은 경우', () {
    test('대역 표기 앞 공백은 밑줄을 우선하고 확인을 요청한다', () {
      final result = parser.parse('Wi-Fi : kkk 5G\nPassword : @kim54796');
      expect(result.ssid, 'kkk_5G');
      expect(result.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(result.candidatesOf(WifiCandidateType.ssid).map((c) => c.value), contains('kkk 5G'));
      expect(result.password, '@kim54796');
      expect(result.passwordConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
    });

    test('그 밖의 공백은 원래 값을 유지하고 밑줄/하이픈/공백 제거 후보를 덧붙인다', () {
      final result = parser.parse('Network: My Cafe\nPW: Coffee! 123');
      expect(result.ssid, 'My Cafe');
      expect(result.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(result.candidatesOf(WifiCandidateType.ssid).map((c) => c.value),
          containsAll(['My_Cafe', 'My-Cafe']));
      expect(result.password, 'Coffee! 123');
      expect(result.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
      final passwords = result.candidatesOf(WifiCandidateType.password).map((c) => c.value).toList();
      expect(passwords, containsAll(['Coffee!123', 'Coffee!_123', 'Coffee!-123']));
      // 공백 제거 후보가 다른 변형보다 앞에 온다.
      expect(passwords.indexOf('Coffee!123'), lessThan(passwords.indexOf('Coffee!_123')));
    });

    test('한국어 인식기가 기호를 자모/한자로 읽은 경우', () {
      expectParsed('PW : abcㅡ1234\nSSID : cafe一5G', ssid: 'cafe-5G', password: 'abc-1234');
      expectParsed('PW : pass井12〇4', password: 'pass#1204');
    });

    test('공백이 없으면 후보를 만들지 않는다', () {
      final result = parser.parse('SSID: cafe_5G\nPW: abc12345');
      expect(result.ssidConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
      expect(result.candidatesOf(WifiCandidateType.ssid).length, 1);
    });
  });

  group('여러 인식 결과 병합', () {
    test('같은 결과면 신뢰도를 유지한다', () {
      final a = parser.parse('SSID: cafe\nPW: abc12345');
      final b = parser.parse('SSID: cafe\nPW: abc12345');
      final merged = parser.merge([a, b]);
      expect(merged.ssid, 'cafe');
      expect(merged.password, 'abc12345');
      expect(merged.passwordConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
    });

    test('확신하는 값이 서로 다르면 확인 필요 수준으로 낮추고 후보를 남긴다', () {
      final korean = parser.parse('SSID: cafe\nPW: hel1o1234');
      final latin = parser.parse('SSID: cafe\nPW: hello1234');
      final merged = parser.merge([korean, latin]);
      expect(merged.ssid, 'cafe');
      expect(merged.ssidConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
      expect(merged.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
      final values = merged.candidatesOf(WifiCandidateType.password).map((c) => c.value);
      expect(values, containsAll(['hel1o1234', 'hello1234']));
    });

    test('동점이면 앞선 source가 이긴다', () {
      final first = parser.parse('PW: hello1234');
      final second = parser.parse('PW: hel1o1234');
      expect(parser.merge([first, second]).password, 'hello1234');
      expect(parser.merge([second, first]).password, 'hel1o1234');
    });

    test('라벨 없는 낮은 점수 결과는 확신하는 결과를 뒤집지 못한다', () {
      final korean = parser.parse('비밀번호: abc12345');
      final latin = parser.parse('HIWHS abcl2345');
      final merged = parser.merge([korean, latin]);
      expect(merged.password, 'abc12345');
      expect(merged.passwordConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
    });

    test('빈 입력', () {
      expect(parser.merge([]).isEmpty, isTrue);
      expect(parser.merge([WifiCredential.empty, WifiCredential.empty]).isEmpty, isTrue);
    });
  });

  test('toString은 비밀번호를 노출하지 않는다', () {
    final result = parser.parse('SSID: cafe\nPassword: secret123');
    expect(result.toString(), isNot(contains('secret123')));
    for (final c in result.candidates) {
      expect(c.toString(), isNot(contains('secret123')));
    }
  });
}
