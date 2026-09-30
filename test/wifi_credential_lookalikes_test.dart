import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';

void main() {
  const extractor = WifiCredentialExtractor();

  List<String> values(WifiCredential c, WifiCandidateType type) => c.candidatesOf(type).map((c) => c.value).toList();

  WifiCredential credential({String? ssid, String? password}) => WifiCredential(
        ssid: ssid,
        password: password,
        ssidConfidence: ssid == null ? 0 : 0.95,
        passwordConfidence: password == null ? 0 : 0.97,
        candidates: [
          if (ssid != null) WifiCandidate(value: ssid, type: WifiCandidateType.ssid, score: 0.95),
          if (password != null) WifiCandidate(value: password, type: WifiCandidateType.password, score: 0.97),
        ],
      );

  test('OCR이 확신해도 O와 0을 서로 바꾼 값을 후보로 넣는다', () {
    final result = extractor.withLookalikes(credential(ssid: 'MOMO_5G', password: 'coffee2O24'));

    expect(result.password, 'coffee2O24');
    expect(values(result, WifiCandidateType.password), contains('coffee2024'));
    expect(values(result, WifiCandidateType.ssid), containsAll(['M0MO_5G', 'MOM0_5G', 'M0M0_5G']));
  });

  test('숫자 0과 소문자 o도 알파벳 O 쪽으로 바꿔 본다', () {
    final result = extractor.withLookalikes(credential(password: 'k0ok1234'));
    expect(values(result, WifiCandidateType.password), containsAll(['kOok1234', 'k00k1234']));
  });

  test('후보만 늘리고 선택된 값과 확신도는 그대로 둔다', () {
    final before = credential(ssid: 'OLLEH_5G', password: 'pass0000');
    final result = extractor.withLookalikes(before);
    expect(result.ssid, before.ssid);
    expect(result.password, before.password);
    expect(result.ssidConfidence, before.ssidConfidence);
    expect(result.passwordConfidence, before.passwordConfidence);
    // 선택된 값이 여전히 1순위
    expect(values(result, WifiCandidateType.password).first, 'pass0000');
  });

  test('결과 화면 후보 칩에 보이도록 1순위와 점수 차가 작다', () {
    final result = extractor.withLookalikes(credential(password: 'coffee2O24'));
    final top = result.candidatesOf(WifiCandidateType.password).first.score;
    final swapped = result.candidatesOf(WifiCandidateType.password).firstWhere((c) => c.value == 'coffee2024');
    expect(top - swapped.score, lessThan(0.05));
  });

  test('O·0·o가 없으면 그대로', () {
    final before = credential(ssid: 'cafe_5G', password: 'abc12345');
    expect(identical(extractor.withLookalikes(before), before), isTrue);
  });

  test('바꿀 자리가 많아도 후보 수가 폭발하지 않는다', () {
    final result = extractor.withLookalikes(credential(password: '00000000'));
    expect(values(result, WifiCandidateType.password).length, lessThanOrEqualTo(8));
    expect(values(result, WifiCandidateType.password), contains('OOOOOOOO'));
  });
}
