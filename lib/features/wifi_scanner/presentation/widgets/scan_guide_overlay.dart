import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 카메라 프리뷰 위에 안내문을 맞출 영역을 표시한다. 영역 밖은 어둡게 처리.
class ScanGuideOverlay extends StatelessWidget {
  const ScanGuideOverlay({super.key, this.processing = false, this.reading = false});

  /// 인식 중이면 영역 안에 진행 표시를 띄운다.
  final bool processing;

  /// 실시간 인식이 글자를 읽는 중 (아직 결과가 안정되지 않음).
  final bool reading;

  /// 화면 크기에 맞춘 정사각형 가이드 영역. 촬영 버튼 공간을 위해 중앙보다 약간 위.
  static Rect guideRect(Size size) {
    final side = math.min(math.min(size.width * 0.84, size.height * 0.5), 420.0);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: side,
      height: side,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final rect = guideRect(constraints.biggest);
      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GuidePainter(rect))),
          Positioned(
            left: 24,
            right: 24,
            bottom: constraints.maxHeight - rect.top + 28,
            child: Text(
              processing
                  ? 'Wi-Fi 정보를 찾고 있어요'
                  : reading
                      ? '글자를 읽고 있어요\n잠시 그대로 비춰주세요'
                      : 'Wi-Fi 안내문을\n영역 안에 맞춰주세요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.35,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ),
          if (processing)
            Positioned.fromRect(
              rect: rect,
              child: const Center(
                child: SizedBox.square(
                  dimension: 36,
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.rect);

  final Rect rect;

  static const _radius = Radius.circular(20);

  @override
  void paint(Canvas canvas, Size size) {
    final guide = RRect.fromRectAndRadius(rect, _radius);
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(guide)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      guide,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => oldDelegate.rect != rect;
}
