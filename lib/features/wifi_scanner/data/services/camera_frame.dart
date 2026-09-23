import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// 카메라 컨트롤러를 만들 때 쓸 프레임 형식. ML Kit이 변환 없이 받는 형식이다.
ImageFormatGroup get mlKitImageFormatGroup =>
    Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21;

const _deviceRotations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// 프리뷰 프레임을 ML Kit 입력으로 바꾼다. 형식이 맞지 않으면 null.
///
/// Android는 NV21 단일 평면, iOS는 BGRA8888. 회전은 센서 방향과 기기 방향으로 계산한다.
InputImage? inputImageFromFrame(CameraImage image, CameraController controller) {
  if (image.planes.isEmpty) return null;
  final rotation = frameRotation(controller);
  if (rotation == null) return null;
  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

InputImageRotation? frameRotation(CameraController controller) {
  final sensor = controller.description.sensorOrientation;
  if (Platform.isIOS) return InputImageRotationValue.fromRawValue(sensor);
  final device = _deviceRotations[controller.value.deviceOrientation] ?? 0;
  final degrees = controller.description.lensDirection == CameraLensDirection.front
      ? (sensor + device) % 360
      : (sensor - device + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees);
}

/// 회전을 반영한(화면에 보이는 방향의) 프레임 크기.
Size uprightFrameSize(CameraImage image, InputImageRotation rotation) {
  final rotated =
      rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;
  return rotated
      ? Size(image.height.toDouble(), image.width.toDouble())
      : Size(image.width.toDouble(), image.height.toDouble());
}
