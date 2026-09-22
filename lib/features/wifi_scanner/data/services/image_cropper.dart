import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 화면에 `BoxFit.cover`로 채워 보여준 프리뷰 위의 영역([viewRect])을
/// 실제 촬영 이미지([imageSize]) 좌표로 옮긴다.
///
/// [margin]은 영역 크기에 대한 비율로, 안내문이 가이드보다 살짝 크게 찍혀도
/// 글자가 잘리지 않도록 사방으로 넓힌다. 결과는 이미지 안으로 잘라낸다.
Rect mapCoverRectToImage({
  required Rect viewRect,
  required Size viewSize,
  required Size imageSize,
  double margin = 0.08,
}) {
  final expanded = Rect.fromLTRB(
    viewRect.left - viewRect.width * margin,
    viewRect.top - viewRect.height * margin,
    viewRect.right + viewRect.width * margin,
    viewRect.bottom + viewRect.height * margin,
  );
  final topLeft = mapCoverPointToImage(expanded.topLeft, viewSize: viewSize, imageSize: imageSize);
  final bottomRight =
      mapCoverPointToImage(expanded.bottomRight, viewSize: viewSize, imageSize: imageSize);
  return Rect.fromPoints(topLeft, bottomRight).intersect(Offset.zero & imageSize);
}

/// `BoxFit.cover`로 보여준 화면 위의 점을 원본 이미지 좌표로 옮긴다. 이미지 밖은 잘라내지 않는다.
Offset mapCoverPointToImage(Offset viewPoint, {required Size viewSize, required Size imageSize}) {
  final scale = math.max(viewSize.width / imageSize.width, viewSize.height / imageSize.height);
  final offsetX = (imageSize.width * scale - viewSize.width) / 2;
  final offsetY = (imageSize.height * scale - viewSize.height) / 2;
  return Offset((viewPoint.dx + offsetX) / scale, (viewPoint.dy + offsetY) / scale);
}

/// 촬영 파일에서 가이드 영역만 잘라 새 JPEG 파일로 저장하고 경로를 돌려준다.
///
/// 디코딩과 인코딩은 별도 isolate에서 실행한다. 실패하면 null을 돌려주므로
/// 호출 쪽에서 원본으로 계속 진행할 수 있다.
Future<String?> cropImageFile({
  required String path,
  required Rect viewRect,
  required Size viewSize,
}) {
  return compute(_cropWorker, _CropArgs(path, viewRect, viewSize));
}

class _CropArgs {
  const _CropArgs(this.path, this.viewRect, this.viewSize);

  final String path;
  final Rect viewRect;
  final Size viewSize;
}

Future<String?> _cropWorker(_CropArgs args) async {
  final bytes = await File(args.path).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // EXIF 회전 정보를 픽셀에 반영해 화면에 보인 방향과 맞춘다.
  final upright = img.bakeOrientation(decoded);
  final rect = mapCoverRectToImage(
    viewRect: args.viewRect,
    viewSize: args.viewSize,
    imageSize: Size(upright.width.toDouble(), upright.height.toDouble()),
  );
  if (rect.width < 32 || rect.height < 32) return null;

  final cropped = img.copyCrop(
    upright,
    x: rect.left.round(),
    y: rect.top.round(),
    width: rect.width.round(),
    height: rect.height.round(),
  );
  final outPath = '${args.path}.crop.jpg';
  await File(outPath).writeAsBytes(img.encodeJpg(cropped, quality: 92));
  return outPath;
}
