import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/credential_voter.dart';

WifiCredential reading({String? ssid, String? password}) => WifiCredential(
      ssid: ssid,
      password: password,
      ssidConfidence: ssid == null ? 0 : 0.95,
      passwordConfidence: password == null ? 0 : 0.95,
      candidates: [
        if (ssid != null) WifiCandidate(value: ssid, type: WifiCandidateType.ssid, score: 0.95),
        if (password != null) WifiCandidate(value: password, type: WifiCandidateType.password, score: 0.95),
      ],
    );

void main() {
  group('voteValues', () {
    test('글자 위치별 다수결로 한 프레임짜리 오류를 걸러낸다', () {
      final field = CredentialVoter.voteValues([
        ('@kim54796', 1),
        ('0kim54796', 1),
        ('@kim54796', 1),
        ('@kim547g6', 1),
      ])!;
      expect(field.value, '@kim54796');
      expect(field.support, 4);
      expect(field.agreement, 0.75); // '@' 3/4, '9' 3/4
      expect(field.uncertainIndexes, isEmpty);
    });

    test('일치율이 낮은 글자는 불확실로 표시한다', () {
      final field = CredentialVoter.voteValues([('@kim', 1), ('0kim', 1), ('Okim', 1)])!;
      expect(field.uncertainIndexes, {0});
      expect(field.agreement, closeTo(1 / 3, 0.001));
      expect(field.isStable, isFalse);
    });

    test('길이가 다른 판독은 가장 흔한 길이끼리만 투표한다', () {
      final field = CredentialVoter.voteValues([
        ('kkk_5G', 1),
        ('kkk 5G', 1),
        ('kkk5G', 1),
        ('kkk_5G', 1),
      ])!;
      expect(field.value, 'kkk_5G');
      expect(field.support, 3);
    });

    test('가중치를 반영한다', () {
      final field = CredentialVoter.voteValues([('0kim', 1), ('@kim', 2)])!;
      expect(field.value, '@kim');
    });

    test('빈 입력', () {
      expect(CredentialVoter.voteValues([]), isNull);
    });
  });

  group('CredentialVoter', () {
    test('세 프레임 이상 일치하면 안정', () {
      final voter = CredentialVoter();
      expect(voter.vote().isStable, isFalse);
      voter.add(reading(ssid: 'kkk_5G', password: '@kim54796'));
      voter.add(reading(ssid: 'kkk_5G', password: '0kim54796'));
      expect(voter.vote().isStable, isFalse);
      voter.add(reading(ssid: 'kkk_5G', password: '@kim54796'));
      final vote = voter.vote();
      expect(vote.isStable, isTrue);
      expect(vote.password!.value, '@kim54796');
    });

    test('빈 판독은 세지 않고, 창 크기를 넘으면 오래된 것을 버린다', () {
      final voter = CredentialVoter(window: 2);
      voter.add(WifiCredential.empty);
      expect(voter.count, 0);
      voter.add(reading(ssid: 'a'));
      voter.add(reading(ssid: 'b'));
      voter.add(reading(ssid: 'b'));
      expect(voter.count, 2);
      expect(voter.vote().ssid!.value, 'b');
    });

    test('사진 결과와 합칠 때 실시간 판독이 사진의 오류를 바로잡는다', () {
      final voter = CredentialVoter();
      for (var i = 0; i < 3; i++) {
        voter.add(reading(ssid: 'kkk_5G', password: '@kim54796'));
      }
      final still = reading(ssid: 'kkk_5G', password: '0kim54796');
      final combined = voter.combine(still);
      expect(combined.password, '@kim54796');
      expect(combined.ssid, 'kkk_5G');
      final passwords = combined.candidatesOf(WifiCandidateType.password).map((c) => c.value).toList();
      expect(passwords.first, '@kim54796');
      expect(passwords, contains('0kim54796'));
    });

    test('실시간 판독이 없으면 사진 결과 그대로', () {
      final still = reading(ssid: 'cafe', password: 'abc12345');
      expect(identical(CredentialVoter().combine(still), still), isTrue);
    });

    test('일치율이 낮으면 확인 필요 수준으로 신뢰도를 낮춘다', () {
      final voter = CredentialVoter();
      voter.add(reading(password: '@kim54796'));
      voter.add(reading(password: '0kim54796'));
      voter.add(reading(password: 'Okim54796'));
      final credential = voter.toCredential(voter.vote(), sources: const []);
      expect(credential.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(credential.passwordUncertainIndexes, {0});
    });
  });
}
