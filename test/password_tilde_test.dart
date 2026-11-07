// 비밀번호 끝 물결표(`~`)를 OCR이 하이픈(`-`)으로 읽는 경우. 모든 이름·비밀번호는 지어낸 값이다.
//
// 실제 식당 안내문 사진(검은 판, 굵은 흰 글씨, 끝이 `~`)을 시뮬레이터 ML Kit로 원본·확대·축소·자르기
// 여섯 번 읽었더니 네 번은 끝 `~`를 `-`로, 한 번은 `-~-`로, 한 번만 `~`로 읽었다. 반대로 안내문의 `-`를 `~`로
// 읽은 fixture는 없다 (docs/recognition-audit.md P4-4). 1순위 값과 다수결은 바꾸지 않고 고칠 길만 연다:
// - 셔터 한 장: 비밀번호 끝의 `-`는 불확실한 글자로 표시하고 `~` 후보를 둔다.
// - 결과 화면: 비밀번호 끝이 `-`면 `~`, `~`면 `-` 후보를 기존 칩 세 개 뒤에 따로 붙인다.
// - 실시간 다수결: 끝 자리의 다수가 `-`인데 `~` 표가 있으면 그 자리만 불확실로 표시하고 `~` 후보를 둔다.
// - 연결 실패 후 확인 후보(confusable_chars): 비밀번호 끝 글자만 `~` ↔ `-`, 자리가 남을 때만.
// 가운데 `-`(`abc-1234`)와 이름은 건드리지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/confusable_chars.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/credential_voter.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';

import 'wifi_result_screen_test.dart' show pumpResult;

const _extractor = WifiCredentialExtractor();

/// iOS ML Kit처럼 글자 신뢰도가 없는 OCR 결과 (실제 사진에서 읽힌 행 구조와 같은 모양).
OcrResult _ocr(String text) =>
    OcrResult(script: TextRecognitionScript.korean, text: text, layoutText: text);

List<String> _passwords(WifiCredential c) => c.candidatesOf(WifiCandidateType.password).map((e) => e.value).toList();

WifiCredential _credential(String password) => WifiCredential(
      ssid: 'momo_cafe',
      password: password,
      ssidConfidence: 0.95,
      passwordConfidence: 0.95,
      candidates: [
        const WifiCandidate(value: 'momo_cafe', type: WifiCandidateType.ssid, score: 0.95),
        WifiCandidate(value: password, type: WifiCandidateType.password, score: 0.95),
      ],
    );

const _oooChips = ['0OO1234-', 'O0O1234-', 'OO01234-'];

void main() {
  group('셔터 한 장: 비밀번호 끝 하이픈', () {
    test('사진에서 읽힌 모양(이름 앞뒤 장식, 끝 -) → 이름은 장식 없이, 끝 글자는 불확실 + ~ 후보', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치•\nMomok123-')]);
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123-', reason: 'OCR이 읽은 값은 그대로 1순위 (추측으로 바꾸지 않는다)');
      expect(c.passwordUncertainIndexes, {8});
      expect(c.passwordConfidence, lessThan(WifiCredential.confidentThreshold), reason: '확인 필요');
      expect(_passwords(c), contains('Momok123~'));
      expect(_passwords(c), isNot(contains('Momok123_')), reason: '끝 하이픈에서는 ~ 후보만');
    });

    test('끝이 ~로 읽혔으면 그대로', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI\n·모모양꼬치·\nMomok123~')]);
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123~');
      expect(c.passwordUncertainIndexes, isEmpty);
    });

    test('가운데 하이픈은 불확실로 보지 않는다', () {
      final c = _extractor.fromOcrResults([_ocr('WIFI : momo_cafe\nPW : abc-1234')]);
      expect(c.password, 'abc-1234');
      expect(c.passwordUncertainIndexes, isEmpty);
      expect(_passwords(c), isNot(contains('abc~1234')));
    });

    test('다른 불확실한 글자가 있어도 끝 하이픈의 ~ 후보를 만들고, 나머지 후보는 그대로', () {
      const credential = WifiCredential(
        password: '11111111-',
        passwordConfidence: 0.9,
        candidates: [WifiCandidate(value: '11111111-', type: WifiCandidateType.password, score: 0.9)],
        passwordUncertainIndexes: {0, 1, 2},
      );
      final before = _passwords(_extractor.withSubstitutions(credential));
      final after = _passwords(_extractor.withTrailingTilde(_extractor.withSubstitutions(credential)));
      expect(after, contains('11111111~'));
      expect(after.where((v) => v != '11111111~'), before, reason: '기존 후보와 순서는 그대로');
    });
  });

  group('결과 화면 후보 (withLookalikes)', () {
    test('끝 - → ~ 후보', () {
      final c = _extractor.withLookalikes(_credential('Momok123-'));
      expect(c.password, 'Momok123-');
      expect(_passwords(c), contains('Momok123~'));
    });

    test('끝 ~ → - 후보 (둘 다 남아 고칠 수 있다)', () {
      final c = _extractor.withLookalikes(_credential('Momok123~'));
      expect(c.password, 'Momok123~');
      expect(_passwords(c), contains('Momok123-'));
    });

    test('~ 후보는 기존 후보의 순서를 바꾸지 않는다 (OOO1234-)', () {
      final values = _passwords(_extractor.withLookalikes(_credential('OOO1234-')));
      expect(values.sublist(0, 4), ['OOO1234-', ..._oooChips]);
      expect(values, contains('OOO1234~'));
    });

    test('가운데 하이픈·물결표는 건드리지 않는다', () {
      expect(_passwords(_extractor.withLookalikes(_credential('abc-1234'))), ['abc-1234']);
      expect(_passwords(_extractor.withLookalikes(_credential('abc~1234'))), ['abc~1234']);
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

  group('결과 화면 칩', () {
    Offset at(WidgetTester tester, String chip) => tester.getTopLeft(find.text(chip));
    bool before(Offset a, Offset b) => a.dy < b.dy - 1 || ((a.dy - b.dy).abs() <= 1 && a.dx < b.dx);

    testWidgets('OOO1234-: 기존 칩 세 개는 그대로이고 ~ 칩은 그 뒤에 붙는다', (tester) async {
      final c = _extractor.withLookalikes(_extractor.fromOcrResults([_ocr('WIFI : momo_cafe\nPW : OOO1234-')]));
      await pumpResult(tester, c);
      for (final chip in [..._oooChips, 'OOO1234~']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      for (var i = 0; i + 1 < _oooChips.length; i++) {
        expect(before(at(tester, _oooChips[i]), at(tester, _oooChips[i + 1])), isTrue, reason: '기존 칩 순서');
      }
      expect(before(at(tester, _oooChips.last), at(tester, 'OOO1234~')), isTrue, reason: '~ 칩은 맨 뒤');
    });

    testWidgets('O·0 후보가 없으면 ~ 칩이 바로 보인다', (tester) async {
      await pumpResult(tester, _extractor.withLookalikes(_extractor.fromOcrResults([_ocr('WIFI : momo_cafe\nPW : Abc12345-')])));
      expect(find.text('Abc12345~'), findsOneWidget);
    });
  });

  group('실시간 다수결', () {
    test('끝 자리 다수가 -이면 - 그대로, 그 자리만 불확실 + 투표 결과에 ~ 후보', () {
      final field = CredentialVoter.voteValues([
        for (var i = 0; i < 5; i++) ('abc1234-', 1),
        ('abc1234~', 1),
      ], trailingTilde: true)!;
      expect(field.value, 'abc1234-');
      expect(field.uncertainIndexes, {7});
      expect(field.tildeAtEnd, isTrue);

      final voter = CredentialVoter();
      WifiCredential frame(String pw) => _extractor.fromOcrResults([_ocr('WIFI : momo_cafe\nPW : $pw')]);
      for (final pw in ['abc1234-', 'abc1234-', 'abc1234-', 'abc1234-', 'abc1234-', 'abc1234~']) {
        voter.add(frame(pw));
      }
      final c = voter.toCredential(voter.vote(), sources: [frame('abc1234-')]);
      expect(c.password, 'abc1234-');
      expect(c.passwordUncertainIndexes, contains(7));
      expect(_passwords(c), containsAllInOrder(['abc1234-', 'abc1234~']));
    });

    test('가운데 자리의 ~ 한 표는 다수결을 뒤집지 않고 표시도 하지 않는다', () {
      final field = CredentialVoter.voteValues([
        for (var i = 0; i < 5; i++) ('abc-1234', 1),
        ('abc~1234', 1),
      ], trailingTilde: true)!;
      expect(field.value, 'abc-1234');
      expect(field.uncertainIndexes, isEmpty);
      expect(field.tildeAtEnd, isFalse);
    });

    test('이름에는 적용하지 않는다', () {
      final field = CredentialVoter.voteValues([
        for (var i = 0; i < 5; i++) ('Momo_Guest', 1),
        ('Momo~Guest', 1),
      ])!;
      expect(field.value, 'Momo_Guest');
      expect(field.uncertainIndexes, isEmpty);
      final end = CredentialVoter.voteValues([for (var i = 0; i < 5; i++) ('momo-', 1), ('momo~', 1)])!;
      expect(end.value, 'momo-');
      expect(end.uncertainIndexes, isEmpty);
    });

    test('모두 -로 읽혔으면 아무 표시도 없다', () {
      final field = CredentialVoter.voteValues([for (var i = 0; i < 4; i++) ('abc1234-', 1)], trailingTilde: true)!;
      expect(field.value, 'abc1234-');
      expect(field.uncertainIndexes, isEmpty);
      expect(field.tildeAtEnd, isFalse);
    });
  });

  group('연결 실패 후 확인 후보', () {
    test('비밀번호 끝 글자만 ~ ↔ -', () {
      expect(confusableVariants('Abc12345-', password: true).map((v) => v.value), contains('Abc12345~'));
      final v = confusableVariants('Abc12345~', password: true).firstWhere((v) => v.value == 'Abc12345-');
      expect(v.description, '~(물결표) → -(하이픈)');
      expect(confusableVariants('abc-1234', password: true).map((v) => v.value), isNot(contains('abc~1234')));
    });

    test('이름과 기존 후보는 그대로', () {
      expect(confusableVariants('momo-').map((v) => v.value), isNot(contains('momo~')));
      final before = confusableVariants('OOO1234-');
      final after = confusableVariants('OOO1234-', password: true);
      expect(after.map((v) => v.value), before.map((v) => v.value), reason: '자리가 차 있으면 ~ 후보를 더하지 않는다');
    });
  });
}
