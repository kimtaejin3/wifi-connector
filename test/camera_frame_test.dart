import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/camera_frame.dart';

void main() {
  test('Android: 가로 프레임을 90도 돌리면 세로 크기', () {
    expect(uprightSize(const Size(1920, 1080), InputImageRotation.rotation90deg), const Size(1080, 1920));
    expect(uprightSize(const Size(1920, 1080), InputImageRotation.rotation270deg), const Size(1080, 1920));
  });

  test('iOS: 이미 세로로 온 프레임은 회전 없음이라 그대로', () {
    expect(uprightSize(const Size(1080, 1920), InputImageRotation.rotation0deg), const Size(1080, 1920));
  });
}
