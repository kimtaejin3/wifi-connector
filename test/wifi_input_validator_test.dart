import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_input_validator.dart';

void main() {
  group('SSID', () {
    test('정상', () {
      expect(WifiInputValidator.ssidError('TestCafe'), isNull);
      expect(WifiInputValidator.ssidError('카페모모'), isNull);
    });

    test('비어 있음', () {
      expect(WifiInputValidator.ssidError(''), isNotNull);
    });

    test('32바이트 초과', () {
      expect(WifiInputValidator.ssidError('a' * 32), isNull);
      expect(WifiInputValidator.ssidError('a' * 33), isNotNull);
      // 한글은 UTF-8로 3바이트
      expect(WifiInputValidator.ssidError('가' * 10), isNull);
      expect(WifiInputValidator.ssidError('가' * 11), isNotNull);
    });
  });

  group('Password', () {
    test('빈 비밀번호는 공개 네트워크로 허용', () {
      expect(WifiInputValidator.passwordError(''), isNull);
    });

    test('8~63자 ASCII', () {
      expect(WifiInputValidator.passwordError('Test12345'), isNull);
      expect(WifiInputValidator.passwordError(r'Coffee!@#$ 123'), isNull);
      expect(WifiInputValidator.passwordError('1234567'), isNotNull);
      expect(WifiInputValidator.passwordError('a' * 63), isNull);
      expect(WifiInputValidator.passwordError('a' * 64), isNotNull);
    });

    test('ASCII가 아닌 문자', () {
      expect(WifiInputValidator.passwordError('비밀번호12345678'), isNotNull);
    });
  });
}
