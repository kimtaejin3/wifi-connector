// 비밀번호 끝 물결표(`~`)를 OCR이 하이픈(`-`)으로 읽는 경우. 모든 이름·비밀번호는 지어낸 값이다.
//
// 실제 식당 안내문 사진(검은 판, 굵은 흰 글씨, 끝이 `~`)을 시뮬레이터 ML Kit로 원본·확대·축소·자르기
// 여섯 번 읽었더니 다섯 번은 끝 `~`를 `-`로, 한 번만 `~`로 읽었다. 반대로 안내문의 `-`를 `~`로 읽은
// fixture는 없다 (docs/recognition-audit.md P4-4). 그래서
// - 셔터 한 장: 비밀번호 끝의 `-`는 불확실한 글자로 표시하고 `~` 후보를 둔다 (값은 그대로).
// - 결과 화면: 비밀번호 끝이 `-`면 `~`, `~`면 `-` 후보를 둔다.
// - 실시간 다수결: 같은 자리에 `~`와 `-`가 섞여 나오면 `~`를 고른다 (`@`와 `0` 처리와 같은 방식).
// - 연결 실패 후 확인 후보(confusable_chars)에도 `~` ↔ `-`.
// 하이픈이 진짜인 비밀번호(`abc-1234`)의 가운데 `-`는 건드리지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/confusable_chars.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/credential_voter.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';

const _extractor = WifiCredentialExtractor();

/// iOS ML Kit처럼 글자 신뢰도가 없는 OCR 결과 (실제 사진에서 읽힌 행 구조와 같은 모양).
OcrResult _ocr(String text) =>
    OcrResult(script: TextRecognitionScript.korean, text: text, layoutText: text);

List<String> _passwords(WifiCredential c) => c.candidatesOf(WifiCandidateType.password).map((e) => e.value).toList();

void main() {
  group('셔터 한 장: 비밀번호 끝 하이픈', () {
    test('사진에서 읽힌 모양(이름 앞뒤 장식, 끝 -) → 이름은 장식 없이, 끝 글자는 불확실 + ~ 후보', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치•\nMomok123-')]);
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123-', reason: 'OCR이 읽은 값은 그대로 1순위 (추측으로 바꾸지 않는다)');
      expect(c.passwordUncertainIndexes, contains(8));
      expect(c.passwordConfidence, lessThan(WifiCredential.confidentThreshold), reason: '확인 필요');
      expect(_passwords(c), contains('Momok123~'));
    });

    test('끝이 ~로 읽혔으면 그대로', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치·\nMomok123~')]);
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123~');
      expect(c.passwordUncertainIndexes, isNot(contains(8)));
    });

    test('가운데 하이픈은 불확실로 보지 않는다', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI : momo_cafe\nPW : abc-1234')]);
      expect(c.password, 'abc-1234');
      expect(c.passwordUncertainIndexes, isEmpty);
      expect(_passwords(c), isNot(contains('abc~1234')));
    });

    test('다른 불확실한 글자가 두 개 넘게 있어도 끝 하이픈의 ~ 후보는 만든다', () {
      final result = _extractor.withSubstitutions(const WifiCredential(
        password: '11111111-',
        passwordConfidence: 0.9,
        candidates: [WifiCandidate(value: '11111111-', type: WifiCandidateType.password, score: 0.9)],
        passwordUncertainIndexes: {0, 1, 2, 8},
      ));
      expect(_passwords(result), contains('11111111~'));
      expect(_passwords(result), isNot(contains('11l11111-')), reason: '나머지는 여전히 앞에서 두 개까지');
    });
  });

  group('결과 화면 후보 (withLookalikes)', () {
    test('셔터 한 장 → 결과 화면: ~ 후보가 O·0 후보에 밀리지 않고 칩 세 개 안에 든다', () {
      final c = _extractor.withLookalikes(_extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치•\nMomok123-')]));
      final shown = _passwords(c).where((v) => v != c.password).take(3);
      expect(shown, contains('Momok123~'));
    });

    WifiCredential credential(String password) => WifiCredential(
          ssid: 'momo_cafe',
          password: password,
          ssidConfidence: 0.95,
          passwordConfidence: 0.95,
          candidates: [
            const WifiCandidate(value: 'momo_cafe', type: WifiCandidateType.ssid, score: 0.95),
            WifiCandidate(value: password, type: WifiCandidateType.password, score: 0.95),
          ],
        );

    test('끝 - → ~ 후보', () {
      final c = _extractor.withLookalikes(credential('Momok123-'));
      expect(c.password, 'Momok123-');
      expect(_passwords(c), containsAllInOrder(['Momok123-', 'Momok123~']));
    });

    test('끝 ~ → - 후보 (둘 다 남아 한 탭으로 고칠 수 있다)', () {
      final c = _extractor.withLookalikes(credential('Momok123~'));
      expect(c.password, 'Momok123~');
      expect(_passwords(c), containsAllInOrder(['Momok123~', 'Momok123-']));
    });

    test('가운데 하이픈·물결표는 건드리지 않는다', () {
      expect(_passwords(_extractor.withLookalikes(credential('abc-1234'))), ['abc-1234']);
      expect(_passwords(_extractor.withLookalikes(credential('abc~1234'))), ['abc~1234']);
    });

    test('이름 끝 하이픈은 건드리지 않는다', () {
      final c = _extractor.withLookalikes(const WifiCredential(
        ssid: 'momo-',
        ssidConfidence: 0.95,
        candidates: [WifiCandidate(value: 'momo-', type: WifiCandidateType.ssid, score: 0.95)],
      ));
      expect(c.candidatesOf(WifiCandidateType.ssid).map((e) => e.value), isNot(contains('momo~')));
    });
  });

  group('실시간 다수결', () {
    test('같은 자리에 ~와 -가 섞이면 ~ (사진 여섯 번 중 한 번만 ~로 읽힌 경우)', () {
      final field = CredentialVoter.voteValues([
        for (var i = 0; i < 5; i++) ('Momok123-', 1),
        ('Momok123~', 1),
      ])!;
      expect(field.value, 'Momok123~');
      expect(field.uncertainIndexes, contains(8), reason: '자리는 불확실로 표시');
      expect(field.agreement, 1.0, reason: '~와 -는 같은 글자를 읽은 표로 센다');
    });

    test('모두 -로 읽혔으면 -', () {
      final field = CredentialVoter.voteValues([for (var i = 0; i < 4; i++) ('abc-1234', 1)])!;
      expect(field.value, 'abc-1234');
      expect(field.uncertainIndexes, isEmpty);
    });

    test('밑줄과 섞여도 ~가 있으면 ~', () {
      final field = CredentialVoter.voteValues([('Momok123-', 1), ('Momok123_', 1), ('Momok123~', 1)])!;
      expect(field.value, 'Momok123~');
    });

    test('투표 결과 화면에도 - 후보가 남는다', () {
      final voter = CredentialVoter();
      WifiCredential frame(String pw) => _extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치•\n$pw')]);
      for (final pw in ['Momok123-', 'Momok123-', 'Momok123~', 'Momok123-']) {
        voter.add(frame(pw));
      }
      final vote = voter.vote();
      final c = _extractor.withLookalikes(voter.toCredential(vote, sources: [frame('Momok123-')]));
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123~');
      expect(_passwords(c), containsAll(['Momok123~', 'Momok123-']));
    });
  });

  group('연결 실패 후 확인 후보', () {
    test('~ ↔ -', () {
      expect(confusableVariants('Momok123-').map((v) => v.value), contains('Momok123~'));
      expect(confusableVariants('Momok123~').map((v) => v.value), contains('Momok123-'));
      final v = confusableVariants('Momok123~').firstWhere((v) => v.value == 'Momok123-');
      expect(v.description, '~(물결표) → -(하이픈)');
    });
  });
}
