import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// 프리뷰 프레임 가운데 영역의 선명도. 손떨림이나 초점 이동으로 흐려진 프레임을 거르는 데 쓴다.
///
/// iOS는 BGRA8888(초록 채널을 밝기로 쓴다), Android는 NV21(첫 평면이 밝기).
double frameSharpness(CameraImage image) {
  if (image.planes.isEmpty) return 0;
  final plane = image.planes.first;
  final ios = Platform.isIOS;
  return lumaSharpness(
    plane.bytes,
    width: image.width,
    height: image.height,
    bytesPerRow: plane.bytesPerRow,
    bytesPerPixel: ios ? 4 : 1,
    channel: ios ? 1 : 0,
  );
}

/// 이웃한 픽셀끼리의 밝기 차이 평균. 글자 가장자리가 또렷할수록 크다.
///
/// 회전과 상관없이 프레임 가운데 절반 영역만, 몇 픽셀 간격으로 듬성듬성 본다.
/// 가이드 영역이 화면 가운데에 있으므로 회전을 계산하지 않아도 안내문이 이 안에 들어온다.
double lumaSharpness(
  Uint8List bytes, {
  required int width,
  required int height,
  required int bytesPerRow,
  int bytesPerPixel = 1,
  int channel = 0,
  int step = 6,
}) {
  final x0 = width ~/ 4;
  final x1 = width * 3 ~/ 4;
  final y0 = height ~/ 4;
  final y1 = height * 3 ~/ 4;
  if (x1 - x0 < 2 || y1 - y0 < 2) return 0;

  int at(int x, int y) => bytes[y * bytesPerRow + x * bytesPerPixel + channel];
  final last = (y1 - 1) * bytesPerRow + (x1 - 1) * bytesPerPixel + channel;
  if (last >= bytes.length) return 0;

  var sum = 0;
  var count = 0;
  for (var y = y0; y < y1 - 1; y += step) {
    for (var x = x0; x < x1 - 1; x += step) {
      final p = at(x, y);
      sum += (at(x + 1, y) - p).abs() + (at(x, y + 1) - p).abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

/// 최근 프레임 중 가장 선명했던 것과 비교해 눈에 띄게 흐린 프레임은 인식하지 않는다.
///
/// 흐린 프레임은 글자를 다르게 읽어 다수결을 흔든다. 절대 기준은 안내문마다 달라서
/// (무늬 없는 종이와 빽빽한 안내문의 선명도가 다르다) 최근 [window] 동안의 최고값을 기준으로 삼는다.
/// 계속 흐려도 [maxWait]가 지나면 한 장은 인식해서 결과가 멈추지 않게 한다.
class SharpnessGate {
  SharpnessGate({
    this.window = const Duration(milliseconds: 1500),
    this.ratio = 0.45,
    this.maxWait = const Duration(milliseconds: 900),
  });

  final Duration window;
  final double ratio;
  final Duration maxWait;

  final List<(DateTime, double)> _samples = [];

  /// [sharpness]인 프레임을 인식할지. [lastProcessed]는 마지막으로 인식한 시각.
  bool shouldProcess(double sharpness, {required DateTime now, required DateTime lastProcessed}) {
    _samples
      ..add((now, sharpness))
      ..removeWhere((s) => now.difference(s.$1) > window);
    if (_samples.length < 3) return true;
    if (now.difference(lastProcessed) >= maxWait) return true;
    final best = _samples.map((s) => s.$2).reduce(math.max);
    return sharpness >= best * ratio;
  }

  void clear() => _samples.clear();
}
