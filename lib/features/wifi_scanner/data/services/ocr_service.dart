import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/utils/text_normalizer.dart';

class OcrResult {
  const OcrResult({
    required this.script,
    required this.text,
    required this.layoutText,
    this.lines = const [],
  });

  final TextRecognitionScript script;

  /// 줄별 글자와 신뢰도. 값의 어느 글자가 불확실한지 찾는 데 쓴다.
  final List<OcrLine> lines;

  /// ML Kit이 돌려준 원문 (블록 → 줄 순서).
  final String text;

  /// 좌표 기준으로 같은 높이의 줄을 한 행으로 묶은 텍스트. 셀 사이는 탭(`\t`).
  /// "Wi-Fi      cafe_momo" 처럼 라벨과 값이 떨어진 안내문을 파싱하기 위해 쓴다.
  final String layoutText;

  /// [lines]만으로 결과를 다시 만든다 (가이드 영역 밖의 줄을 걸러낼 때).
  OcrResult withLines(List<OcrLine> newLines) => OcrResult(
        script: script,
        text: newLines.map((l) => l.text).join('\n'),
        layoutText: layoutRows(newLines),
        lines: newLines,
      );

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
  Future<OcrResult> recognizeFile(String path) =>
      _recognize(_korean, TextRecognitionScript.korean, InputImage.fromFilePath(path));

  /// 한국어와 라틴 인식기를 동시에 실행한다. 순서는 [한국어, 라틴].
  Future<List<OcrResult>> recognizeFileWithAllScripts(String path) =>
      _recognizeAll(InputImage.fromFilePath(path));

  /// 카메라 프리뷰 프레임 등 이미 만들어진 [InputImage]를 인식한다.
  Future<List<OcrResult>> recognizeImage(InputImage image) => _recognizeAll(image);

  Future<List<OcrResult>> _recognizeAll(InputImage image) => Future.wait([
        _recognize(_korean, TextRecognitionScript.korean, image),
        _recognize(_latin, TextRecognitionScript.latin, image),
      ]);

  Future<OcrResult> _recognize(
    TextRecognizer recognizer,
    TextRecognitionScript script,
    InputImage image,
  ) async {
    final recognized = await recognizer.processImage(image);
    final lines = [
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrLine(line.text, line.boundingBox, chars: _charsOf(line)),
    ];
    return OcrResult(
      script: script,
      text: recognized.text,
      layoutText: layoutRows(lines),
      lines: lines,
    );
  }

  /// 줄을 글자 단위로 펼친다. Android는 글자(symbol)마다 신뢰도를 주고, iOS는 주지 않는다.
  static List<OcrChar> _charsOf(TextLine line) {
    final chars = <OcrChar>[];
    for (var i = 0; i < line.elements.length; i++) {
      final element = line.elements[i];
      if (i > 0) chars.add(const OcrChar(' ', null));
      if (element.symbols.isEmpty) {
        for (final rune in element.text.runes) {
          chars.add(OcrChar(String.fromCharCode(rune), element.confidence));
        }
      } else {
        for (final symbol in element.symbols) {
          chars.add(OcrChar(symbol.text, symbol.confidence));
        }
      }
    }
    return chars;
  }

  Future<void> close() => Future.wait([_korean.close(), _latin.close()]);
}

class OcrLine {
  const OcrLine(this.text, this.box, {this.chars = const []});

  final String text;
  final Rect box;
  final List<OcrChar> chars;
}

class OcrChar {
  const OcrChar(this.text, this.confidence);

  final String text;

  /// 0~1. 인식기가 주지 않으면 null.
  final double? confidence;
}

/// 인식기가 기호를 이 글자들로 읽었다면 정규화 결과(`-`, `0`, `@` …)도 확신할 수 없다.
const _ambiguousSymbols = {'ㅡ', '一', 'ー', 'ㅣ', '丨', '〇', '○', '井', '©'};

/// [value]가 인식된 줄 안에서 어느 글자로 읽혔는지 찾아, 신뢰도가 [threshold] 미만이거나
/// 기호 오인식을 되돌린 글자의 위치(문자열 인덱스)를 돌려준다.
/// 파서가 공백을 `_`/`-`로 바꾼 값도 원래 줄과 맞춰 본다.
Set<int> uncertainCharIndexes(
  String value,
  List<OcrLine> lines, {
  double threshold = 0.65,
}) {
  if (value.isEmpty) return const {};
  final probes = {value, value.replaceAll('_', ' '), value.replaceAll('-', ' ')};
  for (final line in lines) {
    if (line.chars.isEmpty) continue;
    final text = StringBuffer();
    final uncertain = <bool>[];
    for (final c in line.chars) {
      final ambiguous = (c.confidence ?? 1.0) < threshold || _ambiguousSymbols.contains(c.text);
      // 파서와 같은 정규화를 거쳐야 값과 글자가 1:1로 맞는다.
      for (final rune in normalizeOcrText(c.text).runes) {
        text.writeCharCode(rune);
        uncertain.add(ambiguous);
      }
    }
    final lineText = text.toString();
    for (final probe in probes) {
      if (probe.length != value.length) continue;
      final start = lineText.indexOf(probe);
      if (start < 0) continue;
      return {for (var i = 0; i < value.length; i++) if (uncertain[start + i]) i};
    }
  }
  return const {};
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
