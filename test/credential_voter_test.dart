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
        ('@cat54796', 1),
        ('0cat54796', 1),
        ('@cat54796', 1),
        ('@cat547g6', 1),
      ])!;
      expect(field.value, '@cat54796');
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
        ('momo_5G', 1),
        ('momo 5G', 1),
        ('mom5G', 1),
        ('momo_5G', 1),
      ])!;
      expect(field.value, 'momo_5G');
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
      voter.add(reading(ssid: 'momo_5G', password: '@cat54796'));
      voter.add(reading(ssid: 'momo_5G', password: '0cat54796'));
      expect(voter.vote().isStable, isFalse);
      voter.add(reading(ssid: 'momo_5G', password: '@cat54796'));
      final vote = voter.vote();
      expect(vote.isStable, isTrue);
      expect(vote.password!.value, '@cat54796');
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
        voter.add(reading(ssid: 'momo_5G', password: '@cat54796'));
      }
      final still = reading(ssid: 'momo_5G', password: '0cat54796');
      final combined = voter.combine(still);
      expect(combined.password, '@cat54796');
      expect(combined.ssid, 'momo_5G');
      final passwords = combined.candidatesOf(WifiCandidateType.password).map((c) => c.value).toList();
      expect(passwords.first, '@cat54796');
      expect(passwords, contains('0cat54796'));
    });

    test('실시간 판독이 없으면 사진 결과 그대로', () {
      final still = reading(ssid: 'cafe', password: 'abc12345');
      expect(identical(CredentialVoter().combine(still), still), isTrue);
    });

    test('일치율이 낮으면 확인 필요 수준으로 신뢰도를 낮춘다', () {
      final voter = CredentialVoter();
      voter.add(reading(password: '@cat54796'));
      voter.add(reading(password: '0cat54796'));
      voter.add(reading(password: 'Ocat54796'));
      final credential = voter.toCredential(voter.vote(), sources: const []);
      expect(credential.passwordConfidence, lessThan(WifiCredential.confidentThreshold));
      expect(credential.passwordUncertainIndexes, {0});
    });
  });

  group('heldOver (배너 유지)', () {
    VotedField field(String v, {int support = 3, double agreement = 1}) =>
        VotedField(value: v, support: support, agreement: agreement, uncertainIndexes: const {});
    final shown = VoteResult(ssid: field('cafe_momo'), password: field('momo12345'));

    test('흔들려서 불안정해진 투표는 보이던 결과를 유지한다', () {
      final shaky = VoteResult(ssid: field('cafe_momo', support: 1), password: null);
      expect(shaky.heldOver(shown), same(shown));
      expect(const VoteResult().heldOver(shown), same(shown));
    });

    test('같은 값이 다시 안정되면 새 투표로 바꾼다', () {
      final again = VoteResult(ssid: field('cafe_momo'), password: field('momo12345', agreement: 0.8));
      expect(again.heldOver(shown), same(again));
    });

    test('다른 값이 안정되게 읽히면 바꾼다', () {
      final other = VoteResult(ssid: field('bakery'), password: field('bread0909'));
      expect(other.heldOver(shown), same(other));
    });

    test('한 항목만 다른 값으로 안정돼도 지운다', () {
      final half = VoteResult(ssid: field('bakery'), password: field('xx', support: 1));
      expect(half.heldOver(shown).isStable, isFalse);
      expect(half.heldOver(shown).ssid, isNull);
    });

    test('보이던 것이 없으면 안정될 때까지 비어 있다', () {
      final shaky = VoteResult(ssid: field('cafe_momo', support: 2));
      expect(shaky.heldOver(const VoteResult()).ssid, isNull);
    });
  });
}
