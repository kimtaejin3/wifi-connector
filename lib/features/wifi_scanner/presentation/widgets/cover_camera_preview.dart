import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// 프리뷰를 비율을 유지한 채 화면 전체를 채우도록 확대한다.
class CoverCameraPreview extends StatelessWidget {
  const CoverCameraPreview({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    // previewSize는 가로 기준이므로 세로 화면에서는 너비/높이를 뒤집는다.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
