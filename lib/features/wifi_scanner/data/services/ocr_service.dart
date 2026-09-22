import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  const OcrResult({required this.script, required this.text, required this.layoutText});

  final TextRecognitionScript script;

  /// ML Kit이 돌려준 원문 (블록 → 줄 순서).
  final String text;

  /// 좌표 기준으로 같은 높이의 줄을 한 행으로 묶은 텍스트. 셀 사이는 탭(`\t`).
  /// "Wi-Fi      cafe_momo" 처럼 라벨과 값이 떨어진 안내문을 파싱하기 위해 쓴다.
  final String layoutText;

  bool get isEmpty => text.trim().isEmpty;

  /// 한글이 하나라도 인식됐는지. 인식기 결과의 우선순위를 정할 때 쓴다.
  bool get hasHangul => _hangul.hasMatch(text);

  static final _hangul = RegExp(r'[가-힣]');

  // 인식 텍스트에는 비밀번호가 들어 있으므로 로그에 내용을 남기지 않는다.
  @override
  String toString() => 'OcrResult(${script.name}, ${text.length} chars)';
}

/// ML Kit 온디바이스 텍스트 인식. 이미지는 기기 밖으로 나가지 않는다.
///
/// 한국어 인식기는 한글과 라틴 문자를 모두 읽지만, 영문·숫자만 있는 안내문은
/// 라틴 전용 인식기가 `l/1/I`, `O/0` 같은 글자를 더 정확히 구분한다.
/// 그래서 두 인식기를 함께 돌리고 파서가 결과를 병합한다.
class OcrService {
  OcrService()
      : _korean = TextRecognizer(script: TextRecognitionScript.korean),
        _latin = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _korean;
  final TextRecognizer _latin;

  /// 한국어 인식기 한 번만 실행한다.
  Future<OcrResult> recognizeFile(String path) => _recognize(_korean, TextRecognitionScript.korean, path);

  /// 한국어와 라틴 인식기를 동시에 실행한다. 순서는 [한국어, 라틴].
  Future<List<OcrResult>> recognizeFileWithAllScripts(String path) => Future.wait([
        _recognize(_korean, TextRecognitionScript.korean, path),
        _recognize(_latin, TextRecognitionScript.latin, path),
      ]);

  Future<OcrResult> _recognize(TextRecognizer recognizer, TextRecognitionScript script, String path) async {
    final recognized = await recognizer.processImage(InputImage.fromFilePath(path));
    final lines = [
      for (final block in recognized.blocks)
        for (final line in block.lines) OcrLine(line.text, line.boundingBox),
    ];
    return OcrResult(script: script, text: recognized.text, layoutText: layoutRows(lines));
  }

  Future<void> close() => Future.wait([_korean.close(), _latin.close()]);
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
