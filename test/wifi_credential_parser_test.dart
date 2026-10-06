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

  group('WIFI 글자 없이 아이콘만 있는 안내문', () {
    test('아이콘을 OCR이 엉뚱한 글자로 읽어도 값은 살린다', () {
      expectParsed('令 cafe_momo\n🔒 momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('? cafe_momo\n? momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('@ MomoCafe_5G\n@ coffee2024!', ssid: 'MomoCafe_5G', password: 'coffee2024!');
    });

    test('아이콘이 따로 떨어진 셀로 읽혀도 무시한다', () {
      expectParsed('令\tcafe_momo\n🔒\tmomo1234', ssid: 'cafe_momo', password: 'momo1234');
    });

    test('이름표 없는 한 단어 다음 줄이 비밀번호 모양이면 앞줄을 이름으로 본다', () {
      expectParsed('MomoCafe\ncoffee2024!', ssid: 'MomoCafe', password: 'coffee2024!');
      expectParsed('令 MomoCafe\n🔒 coffee2024!', ssid: 'MomoCafe', password: 'coffee2024!');
      expectParsed('MOMO CAFE\nMomoGuest\nmomo12345', ssid: 'MomoGuest', password: 'momo12345');
    });

    test('이름표 없이 추측한 값은 확신하지 않는다 (사용자가 확인)', () {
      final r = parser.parse('MomoCafe\ncoffee2024!');
      expect(r.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(r.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
    });

    test('제목이나 인사말 한 단어는 이름으로 보지 않는다', () {
      expectParsed('WELCOME\nEnjoy your coffee', ssid: null, password: null);
      expectParsed('FREE\nmomo12345', ssid: null, password: 'momo12345');
    });

    test('이름표가 있으면 추측보다 이름표를 따른다', () {
      expectParsed('MomoCafe\nSSID: cafe_real\nPW: real12345', ssid: 'cafe_real', password: 'real12345');
    });

    test('아이콘 뒤에 이름표가 있어도 그대로 읽는다', () {
      expectParsed('令 Wi-Fi : cafe_momo\n🔒 PW : momo1234', ssid: 'cafe_momo', password: 'momo1234');
    });
  });

  group('한글 와이파이 표기', () {
    test('여러 가지 한글 이름표', () {
      expectParsed('와이파이 : cafe_momo\n비밀번호 : momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('와이 파이 : cafe_momo\n비번 : momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('와이파이 이름 : MomoCafe\n와이파이 비밀번호 : momo1234', ssid: 'MomoCafe', password: 'momo1234');
      expectParsed('와이파이명 MomoCafe\n와이파이 비번 momo1234', ssid: 'MomoCafe', password: 'momo1234');
      expectParsed('무선인터넷 : MomoCafe\n암호 : momo1234', ssid: 'MomoCafe', password: 'momo1234');
      expectParsed('무료 와이파이\nMomoCafe\n비밀번호\nmomo1234', ssid: 'MomoCafe', password: 'momo1234');
    });

    test('문장형 한글 안내', () {
      expectParsed('와이파이는 MomoCafe 이고 비밀번호는 momo1234 입니다',
          ssid: 'MomoCafe', password: 'momo1234');
    });
  });

  group('사용자가 보내준 실패 안내문 (1.0.1)', () {
    const zoneHead = 'Wifi Zone\n병원에서는 내원하시는 분들의 편의를 위해\n무료와이파이를 운영하고 있습니다.\n';
    const freeHead = 'CREE MIAY\n와이파이 이용방법\n';

    test('Wifi Zone 안내문 (ID / PW 검은 상자)', () {
      expectParsed('${zoneHead}ID\tatozpartners\nPW 123456789', ssid: 'atozpartners', password: '123456789');
      expectParsed('${zoneHead}ID\natozpartners\nPW\n123456789', ssid: 'atozpartners', password: '123456789');
    });

    test('ID와 PW를 OCR이 비슷한 글자로 읽어도', () {
      expectParsed('${zoneHead}IO\tatozpartners\nPW 123456789', ssid: 'atozpartners', password: '123456789');
      expectParsed('${zoneHead}lD\tatozpartners\nPVV 123456789', ssid: 'atozpartners', password: '123456789');
      expectParsed('${zoneHead}I.D\tatozpartners\nP.W 123456789', ssid: 'atozpartners', password: '123456789');
    });

    test('FREE WIFI 안내문: "와이파이 이용방법"은 이름이 아니다', () {
      expectParsed('${freeHead}1D\tWINPT_PPT\nPW\t123456789*', ssid: 'WINPT_PPT', password: '123456789*');
      expectParsed('${freeHead}ID | WINPT_PPT\nPW | 123456789*', ssid: 'WINPT_PPT', password: '123456789*');
    });

    test('글자 사이가 벌어진 I D / P W 이름표', () {
      expectParsed('${freeHead}I D\tWINPT_PPT\nP W\t123456789*', ssid: 'WINPT_PPT', password: '123456789*');
      expectParsed('${freeHead}I  D WINPT_PPT\nP  W 123456789*', ssid: 'WINPT_PPT', password: '123456789*');
      expectParsed('S S I D : cafe_momo\nP A S S W O R D : momo1234', ssid: 'cafe_momo', password: 'momo1234');
    });

    test('이름표를 못 읽어도 숫자+기호 비밀번호는 추측한다', () {
      expectParsed('${freeHead}WINPT_PPT\n123456789*', ssid: 'WINPT_PPT', password: '123456789*');
    });

    test('와이파이 다음에 오는 안내 문구는 이름으로 보지 않는다', () {
      for (final phrase in ['이용방법', '사용방법', '접속방법', '연결방법', '이용 안내', '접속 안내', '이용 방법']) {
        expectParsed('와이파이 $phrase\nID: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      }
    });

    test('이름표 없는 일반 단어는 여전히 오탐하지 않는다', () {
      expectParsed('WIFI\nWelcome to our cafe', ssid: null, password: null);
      expectParsed('IO 단자 안내\n전원을 켜세요', ssid: null, password: null);
      expectParsed('영업시간 10:00~22:00\nID: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('영업시간 10:00~22:00', ssid: null, password: null);
    });
  });

  group('검색으로 모은 실제 안내문 표기', () {
    // 국내 카페 공개 목록과 해외 안내문 템플릿에서 모은 표기 형식. 값은 모두 가상이다.
    const cases = <(String, String, String)>[
      ('KT_GIGA_A1B2 :: PW= 3xyz0ab123', 'KT_GIGA_A1B2', '3xyz0ab123'),
      ('Wi-Fi :: AB1234\nPW :: zz_1112223', 'AB1234', 'zz_1112223'),
      ('WIFI : Lemon House\nPW : bbbbbbbb', 'Lemon House', 'bbbbbbbb'),
      ('Network Name: TheParks\nPassword: sample123', 'TheParks', 'sample123'),
      ('Network ID: Blue Cabin\nPassword: 1234%ab@XYZ', 'Blue Cabin', '1234%ab@XYZ'),
      ('NETWORK: myhome123\nPASSWORD: guest5678', 'myhome123', 'guest5678'),
      ('WiFi Name\nMINT BAR\nPassword\nmintbar1234', 'MINT BAR', 'mintbar1234'),
      ('Guest WiFi\nNetwork: Sample Cafe\nPass: scafe777', 'Sample Cafe', 'scafe777'),
      ('Username: cafe_guest\nPassword: guest1234', 'cafe_guest', 'guest1234'),
      ('SSID: Momo_Free_WiFi\nKey: 00000000', 'Momo_Free_WiFi', '00000000'),
      ('Network: Smith_Home\nOur home wifi password is: welcome2024', 'Smith_Home', 'welcome2024'),
      ('와이파이명: 모모책방\n비밀번호: momo4321', '모모책방', 'momo4321'),
      ('아이디 : momo\n비번 : momo12345', 'momo', 'momo12345'),
      ('무선랜 : MomoTea\n암호 : aaaaabbbbb', 'MomoTea', 'aaaaabbbbb'),
      ('고객용 와이파이 : KT_GiGA_2G_momocoffee\n비밀번호 : a1234567890', 'KT_GiGA_2G_momocoffee', 'a1234567890'),
      ('WiFi Password Is\ncoffee2024\nNetwork: Bean_Guest', 'Bean_Guest', 'coffee2024'),
      ('SCAN TO CONNECT\nNETWORK\nmomo_guest\nPASSWORD\nmomo1234', 'momo_guest', 'momo1234'),
      ('Wi-Fi 이름 / Name : cafe_momo\n비밀번호 / Password : momo1234', 'cafe_momo', 'momo1234'),
      ('ID: cafe_momo  PW: momo1234', 'cafe_momo', 'momo1234'),
      ('Wifi: cafe_momo, Password: momo1234', 'cafe_momo', 'momo1234'),
      ('ＷＩＦＩ：cafe_momo ＰＷ：momo1234', 'cafe_momo', 'momo1234'),
      ('Free Wi-Fi\nConnect to "Momo Guest"\nPassword: momo1234', 'Momo Guest', 'momo1234'),
      ('Join "Momo_Guest"\nPW: momo1234', 'Momo_Guest', 'momo1234'),
      ('WIFI | cafe_momo\nPW | momo1234', 'cafe_momo', 'momo1234'),
      ('Network → cafe_momo\nPassword → momo1234', 'cafe_momo', 'momo1234'),
      ('WLAN : cafe_momo\nWPA2 Key : momo1234', 'cafe_momo', 'momo1234'),
      ('와이파이 : cafe_momo\n와이파이 비밀번호는 momo1234 입니다', 'cafe_momo', 'momo1234'),
      ('인터넷 : cafe_momo\n인터넷 비밀번호 : momo1234', 'cafe_momo', 'momo1234'),
      ('WiFi ID : cafe_momo\nWiFi PASS : momo1234', 'cafe_momo', 'momo1234'),
    ];
    for (final (text, ssid, password) in cases) {
      test(text.replaceAll('\n', ' / '), () => expectParsed(text, ssid: ssid, password: password));
    }

    test('비밀번호 없음 표기', () {
      expectParsed('WIFI : KT_momo_free (비밀번호 없음)', ssid: 'KT_momo_free', password: null);
      expect(parser.parse('WIFI : KT_momo_free\nPW : 없음').isOpenNetwork, isTrue);
    });

    test('공백 있는 이름은 밑줄 버전이 1순위여도 원래 값이 후보에 남는다', () {
      final r = parser.parse('Wi-Fi Network: Momo 5G\nWi-Fi Password: Momo#2024');
      expect(r.candidatesOf(WifiCandidateType.ssid).map((c) => c.value), containsAll(['Momo_5G', 'Momo 5G']));
    });

    test('새 이름표 단어가 다른 문구를 잡지 않는다', () {
      expectParsed('쿠폰 Code: SUMMER2024\nWIFI: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('Join our membership today!\nWIFI: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('인터넷 사용 가능\nWIFI: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('Name your price\nWIFI: cafe_momo\nPW: momo1234', ssid: 'cafe_momo', password: 'momo1234');
      expectParsed('Join our membership today!', ssid: null, password: null);
      expectParsed('Scan to connect', ssid: null, password: null);
    });
  });

  group('밑줄을 공백으로 읽은 공유기 이름 (1.0.2 실패 사례)', () {
    const tail = '\nPW : 0123456789';

    test('밑줄을 모두 공백으로 읽어도 밑줄 이름을 1순위로', () {
      final r = parser.parse('Free Wi-Fi\nID : KT WIFI 5G F3D6$tail');
      expect(r.ssid, 'KT_WIFI_5G_F3D6');
      expect(r.password, '0123456789');
      // 추측한 값이니 확인하도록 한다. 공백 버전은 후보에 남긴다.
      expect(r.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(r.candidatesOf(WifiCandidateType.ssid).map((c) => c.value), contains('KT WIFI 5G F3D6'));
    });

    test('밑줄을 일부만 공백으로 읽어도 밑줄 이름이 이긴다', () {
      for (final id in ['KT_WIFI 5G_F3D6', 'KT WIFI_5G_F3D6', 'KT_WIFI_5G F3D6']) {
        expectParsed('Free Wi-Fi\nID : $id$tail', ssid: 'KT_WIFI_5G_F3D6', password: '0123456789');
        expectParsed('Free Wi-Fi\nID :\t$id$tail', ssid: 'KT_WIFI_5G_F3D6', password: '0123456789');
      }
    });

    test('다른 통신사·공유기 이름도', () {
      expectParsed('WIFI : SK WiFiGIGA 3A2B\nPW : 1234567890', ssid: 'SK_WiFiGIGA_3A2B', password: '1234567890');
      expectParsed('SSID : U+Net 4C1D 5G\nPW : abcd1234', ssid: 'U+Net_4C1D_5G', password: 'abcd1234');
      expectParsed('Wi-Fi : iptime 5G 2F\nPW : abcd1234', ssid: 'iptime_5G_2F', password: 'abcd1234');
    });

    test('일반 가게 이름의 공백은 그대로 둔다', () {
      expectParsed('WIFI : Lemon House\nPW : bbbbbbbb', ssid: 'Lemon House', password: 'bbbbbbbb');
      expectParsed('WiFi Name\nMINT BAR\nPassword\nmintbar1234', ssid: 'MINT BAR', password: 'mintbar1234');
    });

    test('밑줄이 제대로 읽힌 이름은 확신한다', () {
      final r = parser.parse('Free Wi-Fi\nID : KT_WIFI_5G_F3D6$tail');
      expect(r.ssid, 'KT_WIFI_5G_F3D6');
      expect(r.ssidConfidence, greaterThanOrEqualTo(WifiCredential.confidentThreshold));
    });
  });

  group('이름표 없이 이름과 비밀번호 두 줄만 있는 안내문 (1.0.8 실패 사례)', () {
    test('둘 다 영문+숫자여도 윗줄이 이름, 아랫줄이 비밀번호', () {
      expectParsed('katszen01\na024026055', ssid: 'katszen01', password: 'a024026055');
      expectParsed('MomoCafe2F\nmomo2024!', ssid: 'MomoCafe2F', password: 'momo2024!');
      expectParsed('cafe1234\ncafe1234!', ssid: 'cafe1234', password: 'cafe1234!');
      expectParsed('abc12345\nxyz98765', ssid: 'abc12345', password: 'xyz98765');
    });

    test('아이콘 글자나 가게 이름 줄이 섞여도', () {
      expectParsed('令\nkatszen01\na024026055', ssid: 'katszen01', password: 'a024026055');
      expectParsed('令 katszen01\na024026055', ssid: 'katszen01', password: 'a024026055');
      expectParsed('CAFE KATSZEN\nkatszen01\na024026055', ssid: 'katszen01', password: 'a024026055');
      expectParsed('katszen01\na024026055\n영업시간 10:00~22:00', ssid: 'katszen01', password: 'a024026055');
    });

    test('OCR이 두 줄을 한 줄로 붙여 읽어도', () {
      expectParsed('katszen01 a024026055', ssid: 'katszen01', password: 'a024026055');
    });

    test('세 줄이 이어지면 앞의 두 줄을 이름과 비밀번호로 본다', () {
      expectParsed('katszen01\na024026055\nevent2024', ssid: 'katszen01', password: 'a024026055');
    });

    test('추측이므로 확신하지 않는다 (사용자가 확인)', () {
      final r = parser.parse('katszen01\na024026055');
      expect(r.ssidConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(r.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
    });

    test('전화번호는 비밀번호로 추측하지 않는다', () {
      expectParsed('MomoCafe\n02-1234-5678', ssid: null, password: null);
      expectParsed('Tel 010-1234-5678', ssid: null, password: null);
      expectParsed('katszen01\na024026055\n02-1234-5678', ssid: 'katszen01', password: 'a024026055');
      // 숫자와 기호가 섞였어도 전화번호 모양이 아니면 비밀번호 후보다.
      expectParsed('CREE MIAY\nWINPT_PPT\n123456789*', ssid: 'WINPT_PPT', password: '123456789*');
    });

    test('이름표가 있으면 이름표를 따른다', () {
      expectParsed('katszen01\nSSID: real_cafe\nPW: real12345', ssid: 'real_cafe', password: 'real12345');
      expectParsed('ID: katszen01\nPW: a024026055', ssid: 'katszen01', password: 'a024026055');
    });

    test('한 줄 문장은 이름과 비밀번호로 쪼개지 않는다', () {
      expectParsed('Enjoy coffee2024', ssid: null, password: null);
      expectParsed('Welcome to cafe1234', ssid: null, password: null);
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
