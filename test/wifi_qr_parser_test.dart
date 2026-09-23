import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_qr_parser.dart';

void main() {
  test('표준 WPA QR', () {
    final qr = parseWifiQr('WIFI:T:WPA;S:kkk_5G;P:@kim54796;;')!;
    expect(qr.ssid, 'kkk_5G');
    expect(qr.password, '@kim54796');
    expect(qr.security, 'WPA');
    expect(qr.hidden, isFalse);
  });

  test('필드 순서가 달라도, 숨김 네트워크도', () {
    final qr = parseWifiQr('wifi:S:Cafe Momo;T:WPA2;H:true;P:Coffee!123;')!;
    expect(qr.ssid, 'Cafe Momo');
    expect(qr.password, 'Coffee!123');
    expect(qr.hidden, isTrue);
  });

  test('공개 네트워크는 빈 비밀번호', () {
    final qr = parseWifiQr('WIFI:T:nopass;S:FreeCafe;;')!;
    expect(qr.ssid, 'FreeCafe');
    expect(qr.password, '');
  });

  test('이스케이프된 문자', () {
    final qr = parseWifiQr(r'WIFI:T:WPA;S:a\;b\:c;P:p\\w\,d;;')!;
    expect(qr.ssid, 'a;b:c');
    expect(qr.password, r'p\w,d');
  });

  test('Wi-Fi QR이 아니면 null', () {
    expect(parseWifiQr('https://example.com'), isNull);
    expect(parseWifiQr('WIFI:T:WPA;P:nossid;;'), isNull);
    expect(parseWifiQr(null), isNull);
  });
}
