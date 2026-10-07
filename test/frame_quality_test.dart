import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/frame_quality.dart';

Uint8List image(int w, int h, int Function(int x, int y) luma, {int bpp = 1, int channel = 0}) {
  final bytes = Uint8List(w * h * bpp);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bytes[(y * w + x) * bpp + channel] = luma(x, y);
    }
  }
  return bytes;
}

void main() {
  group('lumaSharpness', () {
    const w = 120, h = 80;
    final sharp = image(w, h, (x, y) => (x ~/ 2 + y ~/ 2).isEven ? 230 : 20);
    // 같은 무늬를 흐리게 (밝기가 천천히 변함)
    final blurry = image(w, h, (x, y) => 125 + ((x % 24) - 12) * 3);
    final flat = image(w, h, (x, y) => 128);

    test('또렷한 글자 무늬가 흐린 것보다 크다', () {
      final s = lumaSharpness(sharp, width: w, height: h, bytesPerRow: w, step: 1);
      final b = lumaSharpness(blurry, width: w, height: h, bytesPerRow: w, step: 1);
      expect(s, greaterThan(b * 5));
      expect(lumaSharpness(flat, width: w, height: h, bytesPerRow: w), 0);
    });

    test('BGRA는 초록 채널을 읽는다', () {
      final bgra = image(w, h, (x, y) => (x ~/ 2 + y ~/ 2).isEven ? 230 : 20, bpp: 4, channel: 1);
      final v = lumaSharpness(bgra, width: w, height: h, bytesPerRow: w * 4, bytesPerPixel: 4, channel: 1, step: 1);
      expect(v, lumaSharpness(sharp, width: w, height: h, bytesPerRow: w, step: 1));
    });

    test('버퍼가 모자라면 0', () {
      expect(lumaSharpness(Uint8List(10), width: w, height: h, bytesPerRow: w), 0);
    });
  });

  group('SharpnessGate', () {
    final t0 = DateTime(2026);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('처음 몇 장은 무조건 인식한다', () {
      final g = SharpnessGate();
      expect(g.shouldProcess(1, now: at(0), lastProcessed: t0), isTrue);
      expect(g.shouldProcess(1, now: at(30), lastProcessed: at(0)), isTrue);
    });

    test('또렷한 프레임 뒤의 흐린 프레임은 건너뛴다', () {
      final g = SharpnessGate();
      for (var i = 0; i < 3; i++) {
        g.shouldProcess(20, now: at(i * 30), lastProcessed: at(i * 30));
      }
      expect(g.shouldProcess(5, now: at(120), lastProcessed: at(90)), isFalse);
      expect(g.shouldProcess(15, now: at(150), lastProcessed: at(90)), isTrue);
    });

    test('계속 흐려도 오래 기다리면 한 장은 인식한다', () {
      final g = SharpnessGate();
      for (var i = 0; i < 3; i++) {
        g.shouldProcess(20, now: at(i * 30), lastProcessed: at(i * 30));
      }
      expect(g.shouldProcess(5, now: at(500), lastProcessed: at(60)), isFalse);
      expect(g.shouldProcess(5, now: at(1000), lastProcessed: at(60)), isTrue);
    });

    test('무늬가 적은 새 안내문으로 바뀌면 잠시 뒤 그 안내문 기준으로 맞춘다', () {
      final g = SharpnessGate();
      for (var i = 0; i < 3; i++) {
        g.shouldProcess(20, now: at(i * 30), lastProcessed: at(i * 30));
      }
      // 1.5초가 지나 예전 최고값이 빠지면 낮은 선명도도 받아들인다
      g.shouldProcess(6, now: at(1700), lastProcessed: at(1700));
      g.shouldProcess(6, now: at(1730), lastProcessed: at(1730));
      expect(g.shouldProcess(6, now: at(1760), lastProcessed: at(1730)), isTrue);
    });
  });
}
