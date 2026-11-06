// test_signs의 모든 안내문을 iOS 시뮬레이터 ML Kit로 뽑은 원문 OCR fixture(test/fixtures/ocr)로
// 앱의 사진 인식 경로(WifiCredentialExtractor.fromOcrResults → WifiCredentialParser)에 넣어 정답과 비교한다.
//
// - 정답은 test/support/sign_answers.dart (test_signs의 answers.md를 그대로 옮긴 값, 모두 지어낸 값).
// - 지금 틀리는 안내문은 [knownFailures]에 사유와 함께 두고 skip한다. 이 목록은 실제 결과와도,
//   docs/recognition-audit.md의 "알려진 실패" 표와도 정확히 같아야 한다 (아래 "목록 검사" 그룹).
// - 파서를 고쳐 알려진 실패가 맞게 되면 "알려진 실패 목록이 실제 결과와 같다"가 빨개진다. 그때
//   [knownFailures]와 문서 표에서 그 줄을 지운다. 반대로 맞던 안내문이 틀리면 그 안내문 테스트가 빨개진다.
// - 안내문별 결과(기대·실제·정답 후보 순위·행 재구성/원문 각각의 결과)를 보려면:
//     OCR_FIXTURE_REPORT=build/ocr_fixture_report.md flutter test test/ocr_fixture_test.dart
//   보고서에는 (지어낸) 비밀번호가 들어 있으니 build/ 아래에 둔다. 화면에는 찍지 않는다.
// - fixture를 다시 뽑는 법: tool/render_signs.sh && tool/ocr_dump.sh (docs/recognition-audit.md 1장).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

import 'support/ocr_fixture.dart';
import 'support/sign_answers.dart';

/// 지금 틀리는 안내문과 그 사유. docs/recognition-audit.md "4. 알려진 실패" 표와 같아야 한다.
/// 사유 끝의 P1-1 같은 번호는 그 문서 "5. 개선 항목"의 번호다.
const knownFailures = <String, String>{
  'variety-07': 'OCR이 끝의 1을 l로 읽음(b83kd02jql). 글자만으로는 못 가림 (P4-1)',
  'variety-10': 'OCR이 밑줄을 마침표로 읽음(Sunny.Cafe) (P3-2)',
  'variety-16': 'OCR이 O와 0을 서로 바꿔 읽음(0CEAN_00, 00o00cean). 글자만으로는 못 가림 (P4-1)',
  'variants-04': '값의 자간이 넓어 OCR이 글자 사이에 공백을 넣음(co z y_ho me → co_z_y_ho_me) (P3-3)',
  'variants-06': 'OCR(칠판 손글씨체)이 PW 줄을 통째로 놓침 (P4-2)',
  'variants-08': '손글씨체를 OCR이 잘못 읽음(dream_hou9e, drearm2580) (P4-3)',
  'variants-14': '이모지 아이콘을 OCR이 글자로 읽어 값에 붙임(al Sunrise_Inn, Psunrise2026) (P4-3)',
  'variants-15': 'OCR이 밑줄을 통째로 빠뜨림(nabihostel) (P4-3)',
  'variants-26': '한 줄에 두 대역(WiFi 2.4G 이름 /5G 이름)이 오면 이름표를 버림 (P3-1)',
  'variants-28': 'OCR이 메모가 붙은 PW 줄을 통째로 놓침 (P4-2)',
  'variants-31': 'OCR이 글자를 빠뜨리고 바꿔 읽음(l1Il0Oo2026 → I1l0002026) (P4-1)',
  'variants-32': '다음 줄로 넘어간 비밀번호 뒷부분(345678)을 잇지 않음 (P3-4)',
  'variants-41': 'OCR이 밑줄을 공백으로 읽음(Harbor Guest, 단어 간격이 오히려 넓음) (P3-5)',
  'variants-45': 'OCR이 1을 l로 읽은 floorl_cafe를 고름 (P4-1)',
  'variants-46': 'OCR이 밑줄을 빠뜨리고 z를 Z로 읽음(guestZone) (P4-3)',
  'variants-48': 'OCR이 f와 밑줄을 빠뜨림(OficeGuest 3F) (P4-3)',
  'sign3': 'OCR이 값을 놓침, 비밀번호 없음 (hello1234를 못 읽어 PW 아래 안내 문장은 P2-6이 거름) (P4-2)',
};

const _extractor = WifiCredentialExtractor();
const _parser = WifiCredentialParser();
const _auditDoc = 'docs/recognition-audit.md';

/// 앱이 이 사진을 갤러리에서 골랐을 때와 같은 결과.
WifiCredential recognize(OcrFixture fixture) => _extractor.fromOcrResults([fixture.toOcrResult()]);

/// 정답과 다른 점. 맞으면 null.
String? problemOf(SignAnswer answer, WifiCredential result) {
  if (!answer.isWifi) return result.isEmpty ? null : 'Wi-Fi가 아닌 글에서 결과를 냄';
  final wrong = [
    if (!answer.ssids.contains(result.ssid)) '이름',
    if (result.password != answer.password) '비밀번호',
  ];
  return wrong.isEmpty ? null : '${wrong.join('·')} 틀림';
}

void main() {
  final fixtures = {for (final name in OcrFixture.names()) name: OcrFixture.load(name)};
  final outcomes = <String, (SignAnswer, WifiCredential, String?)>{};
  for (final answer in allSignAnswers) {
    final fixture = fixtures[answer.name];
    if (fixture == null) continue;
    final result = recognize(fixture);
    outcomes[answer.name] = (answer, result, problemOf(answer, result));
  }

  group('안내문 fixture', () {
    for (final answer in allSignAnswers) {
      test('${answer.name} ${answer.form}', () {
        final fixture = fixtures[answer.name];
        expect(fixture, isNotNull, reason: 'fixture가 없어요: $ocrFixtureDir/${answer.name}.json');
        final result = recognize(fixture!);
        if (answer.isWifi) {
          expect(result.ssid, isIn(answer.ssids), reason: '이름');
          expect(result.password, answer.password, reason: '비밀번호');
        } else {
          expect(result.ssid, isNull, reason: 'Wi-Fi가 아닌 글인데 이름을 냄');
          expect(result.password, isNull, reason: 'Wi-Fi가 아닌 글인데 비밀번호를 냄');
        }
      }, skip: knownFailures[answer.name]);
    }
  });

  group('목록 검사', () {
    test('test_signs의 모든 안내문에 fixture와 정답이 하나씩 있다', () {
      final signs = _signsInTestSigns();
      final answers = {for (final a in allSignAnswers) a.name};
      expect(allSignAnswers.length, answers.length, reason: '정답표에 같은 이름이 두 번 있어요');
      expect(fixtures.keys.toSet(), signs, reason: 'fixture 폴더와 test_signs가 달라요 (tool/ocr_dump.sh로 다시 뽑기)');
      expect(answers, signs, reason: '정답표와 test_signs가 달라요');
    });

    test('정답표가 test_signs의 answers.md와 같다', () {
      final fromMarkdown = _answersFromMarkdown();
      expect(fromMarkdown.keys.toSet(), {for (final a in allSignAnswers) a.name});
      for (final a in allSignAnswers) {
        final md = fromMarkdown[a.name]!;
        expect(md.isWifi, a.isWifi, reason: '${a.name} Wi-Fi 여부');
        expect(md.form, a.form, reason: '${a.name} 형태');
        expect(md.ssids, a.ssids, reason: '${a.name} 이름');
        expect(md.password, a.password, reason: '${a.name} 비밀번호');
      }
    });

    test('알려진 실패 목록이 실제 결과와 같다', () {
      final failing = {for (final e in outcomes.entries) if (e.value.$3 != null) e.key};
      final fixed = knownFailures.keys.toSet().difference(failing);
      final broken = failing.difference(knownFailures.keys.toSet());
      expect(fixed, isEmpty, reason: '이제 맞아요. knownFailures와 $_auditDoc 표에서 지워요: $fixed');
      expect(broken, isEmpty, reason: '새로 틀려요 (위 안내문 테스트 참고): $broken');
      expect(knownFailures.values.where((reason) => reason.trim().isEmpty), isEmpty, reason: '사유가 빈 항목');
    });

    test('알려진 실패 목록이 감사 문서의 표와 같다', () {
      expect(_knownFailuresInAuditDoc(), knownFailures.keys.toSet());
    });
  });

  tearDownAll(() {
    final path = Platform.environment['OCR_FIXTURE_REPORT'];
    if (path == null || path.isEmpty) return;
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_report(fixtures, outcomes));
  });
}

// -----------------------------------------------------------------------------
// test_signs 목록

/// test_signs에 있는 안내문 이름: 슬라이드 묶음의 장마다 `<묶음>-NN`, 낱장 HTML·PNG, EXIF 회전 사진.
Set<String> _signsInTestSigns() {
  final names = <String>{};
  final root = Directory('test_signs');
  for (final entry in root.listSync()) {
    final base = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is Directory) {
      final deck = File('${entry.path}/index.html');
      if (!deck.existsSync()) continue;
      final count = '<section class="slide"'.allMatches(deck.readAsStringSync()).length;
      for (var n = 1; n <= count; n++) {
        names.add('$base-${n.toString().padLeft(2, '0')}');
      }
    } else if (base.endsWith('.html') || base.endsWith('.png')) {
      names.add(base.substring(0, base.lastIndexOf('.')));
    }
  }
  names.addAll(photoSources.map((p) => p.$1));
  return names;
}

// -----------------------------------------------------------------------------
// answers.md 읽기

Map<String, SignAnswer> _answersFromMarkdown() {
  final out = <String, SignAnswer>{};
  List<List<String>> rows(String path) => [
        for (final line in File(path).readAsLinesSync())
          if (line.trim().startsWith('|') && line.trim().endsWith('|'))
            line.trim().substring(1, line.trim().length - 1).split('|').map((c) => c.trim()).toList(),
      ].where((r) => !r.every((c) => RegExp(r'^-+$').hasMatch(c)) && r.first != '#' && r.first != '파일').toList();

  List<String> ssids(String cell) => cell.split(' 또는 ').map((s) => s.trim()).toList();
  String? password(String cell) => switch (cell) { '(공개)' => '', '(안 적힘)' => null, _ => cell };

  for (final deck in ['variety', 'variants']) {
    for (final r in rows('test_signs/$deck/answers.md')) {
      final name = '$deck-${r[0].padLeft(2, '0')}';
      out[name] = r.length == 4
          ? SignAnswer.wifi(name, r[1], ssids: ssids(r[2]), password: password(r[3]))
          : SignAnswer.notWifi(name, r[1]);
    }
  }
  for (final r in rows('test_signs/answers.md')) {
    if (r.length == 4) {
      out[r[0]] = SignAnswer.wifi(r[0], r[1], ssids: ssids(r[2]), password: password(r[3]));
    } else if (r.length == 3) {
      // EXIF 회전 사진: 원본과 같은 정답
      final source = out[r[1]];
      if (source != null) out[r[0]] = source.asPhoto(r[0], 'EXIF 회전 ${r[2]} (${r[1]})');
    }
  }
  return out;
}

// -----------------------------------------------------------------------------
// 감사 문서의 알려진 실패 표

Set<String> _knownFailuresInAuditDoc() {
  final doc = File(_auditDoc).readAsStringSync();
  final start = doc.indexOf('<!-- known-failures:start -->');
  final end = doc.indexOf('<!-- known-failures:end -->');
  expect(start, greaterThanOrEqualTo(0), reason: '$_auditDoc에 known-failures 표 표시가 없어요');
  expect(end, greaterThan(start));
  return {
    for (final m in RegExp(r'^\| `([^`]+)` \|', multiLine: true).allMatches(doc.substring(start, end))) m.group(1)!,
  };
}

// -----------------------------------------------------------------------------
// 보고서 (OCR_FIXTURE_REPORT)

String _report(Map<String, OcrFixture> fixtures, Map<String, (SignAnswer, WifiCredential, String?)> outcomes) {
  String show(String? v) => v == null ? '—' : (v.isEmpty ? '(빈 값)' : '`$v`');
  String rank(WifiCredential c, WifiCandidateType type, List<String?> expected) {
    final values = c.candidatesOf(type).map((x) => x.value).toList();
    final i = values.indexWhere(expected.contains);
    return i < 0 ? '없음' : '${i + 1}/${values.length}';
  }

  final b = StringBuffer()
    ..writeln('# OCR fixture 보고서')
    ..writeln()
    ..writeln('`flutter test test/ocr_fixture_test.dart`가 만든 보고서. 값은 모두 지어낸 값이다.')
    ..writeln()
    ..writeln('| fixture | 형태 | 결과 | 기대 이름 | 기대 비밀번호 | 실제 이름 (신뢰도) | 실제 비밀번호 (신뢰도) '
        '| 정답 순위 이름/비번 | 행 재구성만 | 원문만 |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  var pass = 0, known = 0, broken = 0;
  for (final MapEntry(key: name, value: (answer, c, problem)) in outcomes.entries) {
    final status = problem == null ? '통과' : (knownFailures.containsKey(name) ? '알려진 실패' : '새 실패');
    switch (status) {
      case '통과':
        pass++;
      case '알려진 실패':
        known++;
      default:
        broken++;
    }
    final fixture = fixtures[name]!;
    final layout = _parser.parse(fixture.toOcrResult().layoutText);
    final raw = _parser.parse(fixture.text);
    final expectedSsid = answer.isWifi ? answer.ssids.join(' / ') : '(Wi-Fi 아님)';
    final expectedPassword = answer.isWifi ? show(answer.password) : '';
    b.writeln('| `$name` | ${answer.form} | $status${problem == null ? '' : ': $problem'} | $expectedSsid '
        '| $expectedPassword | ${show(c.ssid)} (${c.ssidConfidence.toStringAsFixed(2)}) '
        '| ${show(c.password)} (${c.passwordConfidence.toStringAsFixed(2)}) '
        '| ${answer.isWifi ? '${rank(c, WifiCandidateType.ssid, answer.ssids)} / ${rank(c, WifiCandidateType.password, [answer.password])}' : ''} '
        '| ${show(layout.ssid)} · ${show(layout.password)} | ${show(raw.ssid)} · ${show(raw.password)} |');
  }
  b
    ..writeln()
    ..writeln('통과 $pass · 알려진 실패 $known · 새 실패 $broken (모두 ${outcomes.length})')
    ..writeln()
    ..writeln('## 틀린 안내문의 OCR')
    ..writeln();
  for (final MapEntry(key: name, value: (_, _, problem)) in outcomes.entries) {
    if (problem == null) continue;
    final fixture = fixtures[name]!;
    b
      ..writeln('### `$name` — $problem')
      ..writeln()
      ..writeln('원문(text):')
      ..writeln('```')
      ..writeln(fixture.text)
      ..writeln('```')
      ..writeln('행 재구성(layoutText, 탭은 ⇥):')
      ..writeln('```')
      ..writeln(fixture.toOcrResult().layoutText.replaceAll('\t', ' ⇥ '))
      ..writeln('```')
      ..writeln();
  }
  return b.toString();
}
