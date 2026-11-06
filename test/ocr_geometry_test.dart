import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'support/ocr_fixture.dart';

void main() {
  exifFixtureTests();
  group('uprightBox: EXIF 회전 좌표 바로 세우기', () {
    // 저장 크기 W×H = 1500×1200 (옆으로 누운 픽셀 기준)
    const stored = Size(1500, 1200);

    test('방향 6: 시계 방향으로 90도 돌려 세운다', () {
      final box = uprightBox(const Rect.fromLTRB(100, 200, 160, 500), orientation: 6, stored: stored);
      expect(box, const Rect.fromLTRB(1200 - 500, 100, 1200 - 200, 160));
    });

    test('방향 8: 반시계 방향으로 90도 돌려 세운다', () {
      final box = uprightBox(const Rect.fromLTRB(100, 200, 160, 500), orientation: 8, stored: stored);
      expect(box, const Rect.fromLTRB(200, 1500 - 160, 500, 1500 - 100));
    });

    test('방향 3: 180도 돌린다', () {
      final box = uprightBox(const Rect.fromLTRB(100, 200, 160, 500), orientation: 3, stored: stored);
      expect(box, const Rect.fromLTRB(1500 - 160, 1200 - 500, 1500 - 100, 1200 - 200));
    });

    test('EXIF가 없거나 1이면 상자를 바꾸지 않는다 (크롭 결과를 두 번 돌리면 망가진다)', () {
      const box = Rect.fromLTRB(100, 200, 160, 500);
      expect(uprightBox(box, orientation: null, stored: stored), box);
      expect(uprightBox(box, orientation: 1, stored: stored), box);
    });

    test('거울상(2·4·5·7)이나 알 수 없는 방향은 건드리지 않는다', () {
      const box = Rect.fromLTRB(100, 200, 160, 500);
      for (final o in [2, 4, 5, 7, 0, 9]) {
        expect(uprightBox(box, orientation: o, stored: stored), box, reason: '방향 $o');
      }
    });

    test('저장 크기를 모르면(0 이하) 바꾸지 않는다', () {
      const box = Rect.fromLTRB(100, 200, 160, 500);
      expect(uprightBox(box, orientation: 6, stored: Size.zero), box);
    });

    test('방향 6·8·3 세로로 누운 두 줄이 위→아래 한 칸씩 두 행이 된다', () {
      // 원본(똑바른) 1200x1500 이미지: 위 줄 "WIFI", 아래 줄 "ABC"
      // 방향 8 저장(1500×1200)에서는 위 줄이 오른쪽, 아래 줄이 왼쪽에 세로로 긴 상자.
      final lines = [
        OcrLine('WIFI', const Rect.fromLTRB(1100, 400, 1140, 600)),
        OcrLine('ABC', const Rect.fromLTRB(500, 400, 540, 600)),
      ];
      final fixed = uprightLines(lines, orientation: 8, stored: const Size(1500, 1200));
      expect(layoutRows(fixed), 'WIFI\nABC');
    });
  });

  group('exifFrameOf: JPEG에서 방향과 저장 크기 읽기', () {
    Uint8List jpeg({int? orientation}) {
      final image = img.Image(width: 40, height: 30);
      if (orientation != null) image.exif.imageIfd.orientation = orientation;
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('방향 6 JPEG는 방향과 저장된 크기(회전 전)를 돌려준다', () {
      final frame = exifFrameOf(jpeg(orientation: 6));
      expect(frame?.orientation, 6);
      expect(frame?.stored, const Size(40, 30));
    });

    test('EXIF가 없는 JPEG(셔터 경로의 크롭 결과)는 null이라 상자를 바꾸지 않는다', () {
      expect(exifFrameOf(jpeg()), isNull);
      expect(exifFrameOf(jpeg(orientation: 1)), isNull);
    });

    test('JPEG가 아니면 null', () {
      expect(exifFrameOf(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('단어 간격 표시 글자', () {
    OcrWord w(String t, double l, double r) => OcrWord(t, Rect.fromLTRB(l, 0, r, 50));

    test('줄 높이의 0.12배보다 좁은 간격에는 표시 글자를 넣는다', () {
      // 줄 높이 50 → 문턱 6px. 간격 2px
      final text = joinWords([w('Lumi', 0, 100), w('Cafe', 102, 200)], lineHeight: 50);
      expect(text, 'Lumi${gapMarker}Cafe');
    });

    test('진짜 띄어쓰기(0.3배 이상)는 보통 공백이다', () {
      final text = joinWords([w('Momo', 0, 100), w('Coffee', 130, 250)], lineHeight: 50);
      expect(text, 'Momo Coffee');
    });

    test('줄 높이를 모르면 모두 보통 공백이다', () {
      expect(joinWords([w('a', 0, 10), w('b', 11, 20)], lineHeight: 0), 'a b');
    });

    test('가로로 겹치거나 순서가 뒤집힌 단어도 보통 공백이 아닌 표시 글자(간격 0 이하)', () {
      expect(joinWords([w('a', 0, 10), w('b', 9, 20)], lineHeight: 50), 'a${gapMarker}b');
    });
  });
}

void exifFixtureTests() {
  group('EXIF 회전 사진 fixture: 원본과 같은 행 구조', () {
    final photos = OcrFixture.names().where((n) => n.startsWith('photo-') && RegExp(r'-exif\d$').hasMatch(n)).toList();

    test('EXIF 사진 fixture가 10장 있다', () => expect(photos.length, 10));

    for (final name in photos) {
      test('$name의 layoutText는 원본 fixture와 같은 행 구조다 (행 수·행별 칸 수)', () {
        final source = name.substring('photo-'.length).replaceFirst(RegExp(r'-exif\d$'), '');
        final photo = OcrFixture.load(name).toOcrResult().layoutText;
        final original = OcrFixture.load(source).toOcrResult().layoutText;
        // 회전 사진은 픽셀이 달라 OCR이 글자를 조금 다르게 읽을 수 있다 (예: "SSID:" ↔ "SSID :"). 행 구조만 비교한다.
        List<int> shape(String t) => [for (final row in t.split('\n')) row.split('\t').length];
        expect(shape(photo), shape(original), reason: '회전 사진:\n$photo\n원본:\n$original');
      });
    }
  });
}
