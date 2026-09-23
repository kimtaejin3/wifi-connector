import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';

void main() {
  const extractor = WifiCredentialExtractor();

  test('불확실한 첫 글자 0은 @ 후보를 가장 앞에 둔다', () {
    final result = extractor.withSubstitutions(const WifiCredential(
      ssid: 'kkk_5G',
      password: '0kim54796',
      ssidConfidence: 0.95,
      passwordConfidence: 0.97,
      candidates: [
        WifiCandidate(value: 'kkk_5G', type: WifiCandidateType.ssid, score: 0.95),
        WifiCandidate(value: '0kim54796', type: WifiCandidateType.password, score: 0.97),
      ],
      passwordUncertainIndexes: {0},
    ));

    expect(result.password, '0kim54796');
    expect(result.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
    expect(result.ssidConfidence, 0.95);
    final passwords = result.candidatesOf(WifiCandidateType.password).map((c) => c.value).toList();
    expect(passwords.first, '0kim54796');
    expect(passwords.sublist(1, 4), ['@kim54796', 'Okim54796', 'okim54796']);
  });

  test('불확실한 글자가 없으면 그대로', () {
    const credential = WifiCredential(
      ssid: 'cafe',
      ssidConfidence: 0.95,
      candidates: [WifiCandidate(value: 'cafe', type: WifiCandidateType.ssid, score: 0.95)],
    );
    expect(identical(extractor.withSubstitutions(credential), credential), isTrue);
  });

  test('불확실한 글자는 앞에서 두 개까지만 조합한다', () {
    final result = extractor.withSubstitutions(const WifiCredential(
      password: '11111111',
      passwordConfidence: 0.9,
      candidates: [WifiCandidate(value: '11111111', type: WifiCandidateType.password, score: 0.9)],
      passwordUncertainIndexes: {0, 1, 2, 3, 4, 5, 6, 7},
    ));
    final values = result.candidatesOf(WifiCandidateType.password).map((c) => c.value).toList();
    // 원본 + (인덱스 0의 4개 + 인덱스 1의 4개)
    expect(values.length, 9);
    expect(values, contains('l1111111'));
    expect(values, contains('1l111111'));
    expect(values, isNot(contains('11l11111')));
  });

  test('이미 있는 후보와 겹치면 중복으로 넣지 않는다', () {
    final result = extractor.withSubstitutions(const WifiCredential(
      ssid: 'cafe_5G',
      ssidConfidence: 0.95,
      candidates: [
        WifiCandidate(value: 'cafe_5G', type: WifiCandidateType.ssid, score: 0.95),
        WifiCandidate(value: 'cafe-5G', type: WifiCandidateType.ssid, score: 0.9),
      ],
      ssidUncertainIndexes: {4},
    ));
    final values = result.candidatesOf(WifiCandidateType.ssid).map((c) => c.value).toList();
    expect(values.where((v) => v == 'cafe-5G').length, 1);
  });
}
