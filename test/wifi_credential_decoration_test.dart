// 이름(SSID) 앞뒤의 장식 기호 떼기. 모든 이름·비밀번호는 지어낸 값이다.
//
// 안내문은 "◆ 모모양꼬치 ◆"처럼 이름 양쪽에 작은 장식을 붙이곤 한다. 앞쪽 장식은 셀을 나눌 때
// 글머리표 규칙이 떼지만, 뒤쪽 장식은 이름에 남았다. OCR은 작은 마름모를 `·` `•` `.` `,`로 바꿔 읽기도 한다.
// 장식 떼기는 이름에만 한다. 비밀번호 끝의 `~` `*` `!` `#`는 흔한 진짜 글자다. 이름의 `-` `+` `*`도 진짜 글자일 수 있어
// 양쪽이 이름과 띄어 있을 때만 떼고, 뗀 경우에도 원래 값은 낮은 후보로 남긴다.
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

import 'wifi_result_screen_test.dart' show pumpResult;

const _parser = WifiCredentialParser();

void main() {
  group('이름 앞뒤 장식 기호를 뗀다', () {
    for (final (raw, why) in [
      ('◆모모양꼬치◆', '양쪽 마름모'),
      ('◇ 모모양꼬치 ◇', '양쪽 빈 마름모, 띄어 씀'),
      ('·모모양꼬치·', '양쪽 가운뎃점 (작은 마름모를 OCR이 읽은 모양)'),
      ('• 모모양꼬치 •', '양쪽 글머리표, 띄어 씀'),
      ('모모양꼬치•', '뒤쪽만 남은 장식'),
      ('모모양꼬치 ·', '뒤쪽만, 띄어 씀'),
      ('★모모양꼬치★', '양쪽 별'),
      ('♥ 모모양꼬치 ♥', '양쪽 하트'),
      ('✿모모양꼬치✿', '양쪽 꽃'),
      ('❖ 모모양꼬치 ❖', '양쪽 장식 마름모'),
      ('▶ 모모양꼬치 ◀', '양쪽 화살촉'),
      ('■모모양꼬치■', '양쪽 네모'),
      ('.모모양꼬치,', '마름모를 마침표·쉼표로 읽은 양쪽'),
      ('모모양꼬치 .', '뒤쪽 마침표, 띄어 씀'),
      ('모모양꼬치.', '한글 이름 바로 뒤 마침표 (한글 이름은 문장부호로 끝나지 않는다)'),
    ]) {
      test('$raw → 모모양꼬치 ($why)', () {
        final c = _parser.parse('WIFI\n$raw\nMomok123~');
        expect(c.ssid, '모모양꼬치');
        expect(c.password, 'Momok123~');
      });
    }

    test('영문 이름도 양쪽 장식을 뗀다', () {
      final c = _parser.parse('와이파이 : ★cafe_momo★\n비밀번호 : momo12345');
      expect(c.ssid, 'cafe_momo');
      expect(c.password, 'momo12345');
    });

    test('이름표 같은 줄의 이름 뒤 장식', () {
      final c = _parser.parse('WIFI : 모모 •\nPW : abc12345');
      expect(c.ssid, '모모');
    });

    test('양쪽에 띄어 쓴 - + * 는 장식으로 본다', () {
      expect(_parser.parse('WIFI : - 모모 -\nPW : abc12345').ssid, '모모');
      expect(_parser.parse('WIFI : * 모모 *\nPW : abc12345').ssid, '모모');
      expect(_parser.parse('WIFI : + 모모 +\nPW : abc12345').ssid, '모모');
    });

    test('뗀 경우에도 원래 값은 낮은 후보로 남는다', () {
      final c = _parser.parse('WIFI\n·모모양꼬치•\nMomok123~');
      final ssids = c.candidatesOf(WifiCandidateType.ssid).toList();
      expect(ssids.first.value, '모모양꼬치');
      final original = ssids.firstWhere((e) => e.value == '모모양꼬치•');
      expect(original.score, lessThan(ssids.first.score));
      // 장식 붙은 값에서 밑줄·하이픈 변형을 만들지 않는다.
      expect(ssids.map((e) => e.value).where((v) => v.contains('_•') || v.contains('-•')), isEmpty);
    });

    test('이름표 없이 고른 이름도 원래 값을 후보로 남긴다', () {
      final c = _parser.parse('lunahouse7★\nb83kd02jq1');
      if (c.ssid != null) {
        expect(c.ssid, 'lunahouse7');
        expect(c.candidatesOf(WifiCandidateType.ssid).map((e) => e.value), contains('lunahouse7★'));
      }
    });
  });

  group('경계 보완: 붙여 쓴 기호는 보존, 원래 값은 항상 후보', () {
    // 2차 검토에서 찾은 경계. 이름에 붙여 쓴 기호는 앞뒤가 서로 달라도 장식으로 보지 않는다.
    for (final ssid in ['-Momo.', '+Momo.', '*Momo,', ',Momo+', 'Momo.']) {
      test('SSID: $ssid 그대로', () {
        expect(_parser.parse('SSID: $ssid\nPW: abc12345').ssid, ssid);
      });
    }

    // OCR은 뒤쪽 ◆를 `.` `,`로 읽는다(variants-53). 앞이 장식 전용 글자면 뒤 `.` `,`도 장식이다.
    for (final (text, expected) in [
      ('와이파이 ◆ Momo .\n비밀번호 abc12345', 'Momo'),
      ('WIFI ◆ cafe_momo .\nPW abc12345', 'cafe_momo'),
      ('WIFI : ◆ Momo .\nPW : abc12345', 'Momo'),
      ('SSID: ◆Momo.\nPW: abc12345', 'Momo'),
      ('SSID: ·Momo.\nPW: abc12345', 'Momo'),
      ('SSID: •Momo,\nPW: abc12345', 'Momo'),
    ]) {
      test('${text.split('\n').first} → $expected', () {
        expect(_parser.parse(text).ssid, expected);
      });
    }

    // ML Kit는 작은 마름모를 · • . , - +로 읽는다(docs/recognition-audit.md). 한쪽이 장식 글자면 반대쪽의 띄어 쓴
    // - + *와 , .도 장식이다. 양쪽 모두 띄어 쓴 - + *도 장식이다. 정답이 후보에서 사라지지 않게 main과 같은 1순위로 고정한다.
    for (final (text, expected, original) in [
      ('WIFI : ◆ 모모 -\nPW : abc12345', '모모', '◆ 모모 -'),
      ('SSID: ◆ 모모 -\nPW: abc12345', '모모', '◆ 모모 -'),
      ('WIFI : ◆ 모모 +\nPW : abc12345', '모모', '◆ 모모 +'),
      ('WIFI : - 모모 ◆\nPW : abc12345', '모모', '- 모모 ◆'),
      ('WIFI : , 모모 ◆\nPW : abc12345', '모모', ', 모모 ◆'),
      ('SSID: ,모모◆\nPW: abc12345', '모모', ',모모◆'),
      ('와이파이 ◆ Momo -\n비밀번호 abc12345', 'Momo', '◆ Momo -'),
      ('와이파이 , 모모 ◆\n비밀번호 abc12345', '모모', ', 모모 ◆'),
      ('WIFI : - 모모 +\nPW : abc12345', '모모', '- 모모 +'),
      ('SSID: - Momo +\nPW: abc12345', 'Momo', '- Momo +'),
      ('SSID: * Momo -\nPW: abc12345', 'Momo', '* Momo -'),
    ]) {
      test('${text.split('\n').first} → $expected, 원래 값은 ×0.8 후보', () {
        final c = _parser.parse(text);
        expect(c.ssid, expected);
        final ssids = c.candidatesOf(WifiCandidateType.ssid).toList();
        final kept = ssids.where((e) => e.value == original);
        expect(kept, hasLength(1), reason: '${ssids.map((e) => e.value)}');
        expect(kept.single.score, closeTo(ssids.first.score * 0.8, 0.001));
      });
    }

    // 붙여 쓴 진짜 기호는 앞이 장식이어도 건드리지 않는다.
    for (final (ssid, expected) in [
      ('◆모모-', '모모-'),
      ('·Momo+', 'Momo+'),
      ('★5G-', '5G-'),
      ('모모+', '모모+'),
      ('5G-', '5G-'),
      ('-Momo-', '-Momo-'),
      ('-모모◆', '-모모'),
      ('◆모모 -', '모모 -'),
      ('◆ 모모-', '모모-'),
    ]) {
      test('SSID: $ssid → $expected (붙여 쓴 기호 보존, main과 같음)', () {
        expect(_parser.parse('SSID: $ssid\nPW: abc12345').ssid, expected);
      });
    }

    test('행 앞 장식을 글머리표가 먼저 떼면 뒤 마침표는 영문 이름 끝 글자로 남는다 (main과 같음)', () {
      expect(_parser.parse('WIFI\n◆Momo.\nabc12345').ssid, 'Momo.');
    });

    test('한글 뒤 마침표는 반대쪽에 다른 기호가 있어도 뗀다', () {
      expect(_parser.parse('SSID: -모모.\nPW: abc12345').ssid, '-모모');
    });

    for (final (raw, text) in [
      for (final raw in ['✿모모✿', '◆모모◆', '★cafe_momo★', '• 모모 •', '.달빛꼬치,', '- 모모 -']) ...[
        (raw, 'SSID: $raw\nPW: abc12345'), // 같은 줄 이름표
        (raw, 'WIFI : $raw\nPW : abc12345'),
      ],
      // 다음 줄 (행 앞 장식은 글머리표 규칙이 먼저 떼므로 뒤쪽만 남은 모양)
      for (final raw in ['모모✿', '모모◆', 'cafe_momo★', '모모 •', '달빛꼬치,']) (raw, 'WIFI\n$raw\nabc12345'),
    ]) {
      test('${text.split('\n').first.startsWith('WIFI') && !text.contains(':') ? '다음 줄' : '같은 줄'} $raw: 뗀 값이 1순위, 원래 값은 ×0.8 후보', () {
        final c = _parser.parse(text);
        final ssids = c.candidatesOf(WifiCandidateType.ssid).toList();
        final top = ssids.first;
        expect(top.value, isNot(raw));
        final original = ssids.where((e) => e.value == raw);
        expect(original, hasLength(1), reason: '${ssids.map((e) => e.value)}');
        expect(original.single.score, closeTo(top.score * 0.8, 0.001));
      });
    }
  });

  group('원래 값은 어느 분기에서도 뗀 값보다 낮다', () {
    // 공유기 모양(밑줄이 섞인 두 단어 등)은 공백 든 값이 낮은 점수를 받는 분기를 탄다. 이은 값이 연락처 모양이라
    // 깎이면 공백 든 값과 그 변형끼리 1순위를 다투는데, 원래 값이 이기면 장식이 이름에 붙은 채 고쳐진다.
    for (final raw in ['✿@momo_cafe 2.4G✿', '@momo_cafe 2.4G★', '@momo_cafe 2.4G◆', '@momo_cafe 2.4G✿']) {
      for (final text in ['WIFI\n$raw\nabc12345', 'SSID\t$raw\nPW\tabc12345', '네트워크\n$raw\nabc12345']) {
        test('${text.replaceAll('\n', ' / ').replaceAll('\t', ' ⇥ ')} → @momo_cafe_2.4G', () {
          final c = _parser.parse(text);
          expect(c.ssid, '@momo_cafe_2.4G');
          final ssids = c.candidatesOf(WifiCandidateType.ssid).toList();
          final plain = ssids.firstWhere((e) => e.value == '@momo_cafe 2.4G');
          final original = ssids.firstWhere((e) => e.value == raw);
          expect(original.score, closeTo(plain.score * 0.8, 0.001));
        });
      }
    }

    for (final raw in ['✿KT F3D6✿', 'KT F3D6★', '✿Lemon House✿', 'Lemon House★', '✿momo_cafe✿', 'cafe_momo 5G★']) {
      test('$raw: 원래 값은 뗀 값의 ×0.8', () {
        final ssids = _parser.parse('WIFI\n$raw\nabc12345').candidatesOf(WifiCandidateType.ssid).toList();
        final plainValue = raw.replaceAll(RegExp('[✿★]'), '');
        final plain = ssids.firstWhere((e) => e.value == plainValue);
        final original = ssids.firstWhere((e) => e.value == raw);
        expect(original.score, closeTo(plain.score * 0.8, 0.001));
        expect(ssids.first.value, isNot(raw));
      });
    }

    test('사람이 지은 두 단어 이름: 장식 붙은 값과 그 변형은 기존 교정 후보 뒤에 온다', () {
      final ssids = _parser.parse('WIFI\n✿Lemon House✿\nabc12345').candidatesOf(WifiCandidateType.ssid).map((e) => e.value).toList();
      expect(ssids.take(3), ['Lemon House', 'Lemon_House', 'Lemon-House']);
      expect(ssids[3], '✿Lemon House✿');
    });

    test('점수가 낮아도 원래 값은 후보 목록에 남는다', () {
      final ssids = _parser.parse('ID/PW : ◆ free ◆ / abc12345').candidatesOf(WifiCandidateType.ssid).map((e) => e.value);
      expect(ssids, contains('◆ free ◆'));
    });

    test('이름표 같은 줄 원래 값에는 밑줄·하이픈 변형을 만들지 않는다 (후보로 더하는 건 원래 값 하나)', () {
      final ssids = _parser.parse('WIFI : - 모모 -\nPW : abc12345').candidatesOf(WifiCandidateType.ssid).map((e) => e.value);
      expect(ssids, ['모모', '- 모모 -']);
      final kt = _parser.parse('SSID: ✿KT F3D6✿\nPW: abc12345').candidatesOf(WifiCandidateType.ssid).map((e) => e.value);
      expect(kt.where((v) => v.contains('✿')), ['✿KT F3D6✿']);
    });
  });

  group('두 단어 공유기 이름의 교정 후보 칩', () {
    // 원래 값이 KT F3D6·KT-F3D6보다 앞서거나 뗀 값 점수가 내려가면 KT-F3D6이 칩 범위(1순위 −0.2) 밖으로 밀린다.
    for (final raw in ['★KT F3D6★', '✿KT F3D6✿']) {
      testWidgets('$raw: 칩은 기존 그대로 KT F3D6, KT-F3D6', (tester) async {
        final c = _parser.parse('WIFI\n$raw\nabc12345');
        final ssids = c.candidatesOf(WifiCandidateType.ssid).toList();
        expect(ssids.take(3).map((e) => e.value), ['KT_F3D6', 'KT F3D6', 'KT-F3D6']);
        await pumpResult(tester, c);
        expect(find.text('KT F3D6'), findsOneWidget);
        expect(find.text('KT-F3D6'), findsOneWidget);
        // 장식 붙은 값은 점수가 낮아 칩에 오르지 않는다(후보 목록에는 남는다).
        final decorated = ssids.map((e) => e.value).where((v) => v.contains(RegExp('[★✿]'))).toList();
        expect(decorated, isNotEmpty);
        for (final v in decorated) {
          expect(find.text(v), findsNothing, reason: v);
        }
      });
    }
  });

  group('이름 앞에 붙은 마침표는 뒤에 다른 기호가 있어도 뗀다', () {
    for (final (text, expected, original) in [
      ('Wi-Fi .OOO1234-, PW abc12345', 'OOO1234-', '.OOO1234-'),
      ('SSID: .Momo-\nPW: abc12345', 'Momo-', '.Momo-'),
      ('SSID: .Momo+\nPW: abc12345', 'Momo+', '.Momo+'),
      ('SSID: .Momo*\nPW: abc12345', 'Momo*', '.Momo*'),
      ('SSID: .5G-\nPW: abc12345', '5G-', '.5G-'),
      ('SSID: .Momo◆\nPW: abc12345', 'Momo', '.Momo◆'),
      ('SSID: .모모-\nPW: abc12345', '모모-', '.모모-'),
    ]) {
      test('${text.split('\n').first} → $expected, 원래 값 $original은 후보', () {
        final c = _parser.parse(text);
        expect(c.ssid, expected);
        expect(c.candidatesOf(WifiCandidateType.ssid).map((e) => e.value), contains(original));
      });
    }

    test('뒤에 기호가 없거나 앞이 다른 기호면 그대로', () {
      expect(_parser.parse('SSID: .Momo\nPW: abc12345').ssid, '.Momo');
      expect(_parser.parse('SSID: ,Momo+\nPW: abc12345').ssid, ',Momo+');
      expect(_parser.parse('SSID: -Momo.\nPW: abc12345').ssid, '-Momo.');
    });
  });

  group('진짜 글자는 그대로 둔다', () {
    test('이름 끝 느낌표', () {
      expect(_parser.parse('WIFI : 모모!\nPW : abc12345').ssid, '모모!');
    });

    test('영문 이름 끝 마침표 (한쪽만, 붙어 있음)', () {
      expect(_parser.parse('WIFI : momo_cafe.\nPW : abc12345').ssid, 'momo_cafe.');
    });

    test('이름 끝 +, 하이픈 (붙어 있음)', () {
      expect(_parser.parse('WIFI : momo_LGU+\nPW : abc12345').ssid, 'momo_LGU+');
      expect(_parser.parse('WIFI : momo-\nPW : abc12345').ssid, 'momo-');
    });

    // 검토에서 찾은 경계: 이름에 진짜 쓰이는 + - * 는 한글 뒤여도, 붙은 대칭이어도 그대로다.
    for (final ssid in ['모모+', '모모-', '모모*', '+Momo+', '-Momo-', '*Momo*', 'A-1', '5G-', 'Wi-Fi+', '모모 -', '모모 +']) {
      test('SSID: $ssid 그대로', () {
        expect(_parser.parse('SSID: $ssid\nPW: abc12345').ssid, ssid);
      });
    }

    test('이름 가운데 가운뎃점', () {
      expect(_parser.parse('WIFI : 카페·바_momo\nPW : abc12345').ssid, '카페·바_momo');
    });

    for (final pw in ['abc123~', 'abc123*', 'abc123!', 'abc123#', 'abc-1234', 'abc12345.', 'abc12345-', 'abc12345+']) {
      test('비밀번호 $pw', () {
        final c = _parser.parse('WIFI : momo_cafe\nPW : $pw');
        expect(c.ssid, 'momo_cafe');
        expect(c.password, pw);
      });
    }

    test('비밀번호 줄의 장식 모양 끝 글자도 그대로 (이름표 없는 카드)', () {
      final c = _parser.parse('WIFI\n◆모모양꼬치◆\nMomok123*');
      expect(c.ssid, '모모양꼬치');
      expect(c.password, 'Momok123*');
    });
  });
}
