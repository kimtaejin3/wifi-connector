import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  const OcrResult({required this.text, required this.layoutText});

  /// ML Kit이 돌려준 원문 (블록 → 줄 순서).
  final String text;

  /// 좌표 기준으로 같은 높이의 줄을 한 행으로 묶은 텍스트. 셀 사이는 탭(`\t`).
  /// "Wi-Fi      cafe_momo" 처럼 라벨과 값이 떨어진 안내문을 파싱하기 위해 쓴다.
  final String layoutText;

  bool get isEmpty => text.trim().isEmpty;

  // 인식 텍스트에는 비밀번호가 들어 있으므로 로그에 내용을 남기지 않는다.
  @override
  String toString() => 'OcrResult(${text.length} chars)';
}

/// ML Kit 온디바이스 텍스트 인식. 이미지는 기기 밖으로 나가지 않는다.
///
/// 한국어 인식기는 한글과 라틴 문자를 모두 인식한다.
class OcrService {
  OcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.korean);

  final TextRecognizer _recognizer;

  Future<OcrResult> recognizeFile(String path) async {
    final recognized = await _recognizer.processImage(InputImage.fromFilePath(path));
    final lines = [
      for (final block in recognized.blocks)
        for (final line in block.lines) OcrLine(line.text, line.boundingBox),
    ];
    return OcrResult(text: recognized.text, layoutText: layoutRows(lines));
  }

  Future<void> close() => _recognizer.close();
}

class OcrLine {
  const OcrLine(this.text, this.box);

  final String text;
  final Rect box;
}

/// 세로 위치가 겹치는 줄끼리 한 행으로 묶고, 행 안에서는 왼쪽부터 탭으로 잇는다.
@visibleForTesting
String layoutRows(List<OcrLine> lines) {
  final sorted = lines.where((l) => l.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));

  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    if (rows.isNotEmpty && _isSameRow(rows.last, line)) {
      rows.last.add(line);
    } else {
      rows.add([line]);
    }
  }

  return rows.map((row) {
    row.sort((a, b) => a.box.left.compareTo(b.box.left));
    return row.map((l) => l.text.trim()).join('\t');
  }).join('\n');
}

bool _isSameRow(List<OcrLine> row, OcrLine line) {
  final rowCenter = row.map((l) => l.box.center.dy).reduce((a, b) => a + b) / row.length;
  final rowHeight = row.map((l) => l.box.height).reduce(math.min);
  final height = math.min(rowHeight, line.box.height);
  return (line.box.center.dy - rowCenter).abs() < height * 0.5;
}
