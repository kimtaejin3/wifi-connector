import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/image_cropper.dart';

void main() {
  test('화면과 이미지 비율이 같으면 단순 배율', () {
    final rect = mapCoverRectToImage(
      viewRect: const Rect.fromLTRB(100, 200, 300, 400),
      viewSize: const Size(400, 800),
      imageSize: const Size(1080, 2160),
      margin: 0,
    );
    expect(rect, const Rect.fromLTRB(270, 540, 810, 1080));
  });

  test('cover로 잘려 나간 가로 여백을 보정한다', () {
    // 이미지(1000x1500)가 화면(400x800)을 세로 기준으로 채우므로 좌우가 잘린다.
    final rect = mapCoverRectToImage(
      viewRect: const Rect.fromLTRB(0, 0, 400, 800),
      viewSize: const Size(400, 800),
      imageSize: const Size(1000, 1500),
      margin: 0,
    );
    // scale = 800/1500, 화면 밖으로 밀려난 가로 = 1000*scale - 400 = 133.3 → 좌우 66.7
    expect(rect.left, closeTo(125, 0.5));
    expect(rect.right, closeTo(875, 0.5));
    expect(rect.top, closeTo(0, 0.01));
    expect(rect.bottom, closeTo(1500, 0.01));
  });

  test('여백을 더하되 이미지 밖으로는 나가지 않는다', () {
    final rect = mapCoverRectToImage(
      viewRect: const Rect.fromLTRB(0, 0, 400, 400),
      viewSize: const Size(400, 800),
      imageSize: const Size(400, 800),
      margin: 0.1,
    );
    expect(rect, const Rect.fromLTRB(0, 0, 400, 440));
  });

  test('점 변환: 화면 중앙은 이미지 중앙', () {
    final p = mapCoverPointToImage(
      const Offset(200, 400),
      viewSize: const Size(400, 800),
      imageSize: const Size(1000, 1500),
    );
    expect(p.dx, closeTo(500, 0.01));
    expect(p.dy, closeTo(750, 0.01));
  });
}
