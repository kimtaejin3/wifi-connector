import 'dart:math' as math;
import 'dart:ui';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

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
/// 한국어 인식기 하나만 쓴다. 한국어 인식기는 한글과 라틴 문자를 모두 읽는다.
///
/// 예전에는 라틴 인식기도 함께 만들었지만, google_mlkit_text_recognition은 인식기를
/// 만든 시각(마이크로초)을 id로 쓰고 iOS·Android 모두 id로 인식기를 재사용한다.
/// 두 인식기를 연달아 만들면 id가 같아져 라틴 요청도 한국어 인식기가 처리했다
/// (실기기 로그로 확인: 두 결과가 모든 프레임에서 똑같았다). 같은 인식을 두 번 하던 셈이라
/// 실제로 쓰이던 한국어 인식기만 남겨 프레임당 인식 시간을 절반으로 줄인다.
class OcrService {
  OcrService() : _korean = TextRecognizer(script: TextRecognitionScript.korean);

  final TextRecognizer _korean;

  /// 사진 파일을 인식한다.
  ///
  /// JPEG에 EXIF 회전이 있으면 ML Kit은 글자는 똑바로 읽지만 상자는 저장된(누운) 픽셀 기준으로 준다.
  /// 그래서 방향 3·6·8은 상자를 똑바로 세워 행 구성에 넘긴다 ([uprightBox]). EXIF가 없는 파일
  /// (셔터 경로의 크롭 결과는 이미 똑바로 구워져 있다)이나 크기를 못 읽은 파일은 상자를 그대로 둔다.
  Future<List<OcrResult>> recognizeFile(String path) async {
    final frame = await _readExifFrame(path);
    return [await _recognize(_korean, TextRecognitionScript.korean, InputImage.fromFilePath(path), frame)];
  }

  /// 카메라 프리뷰 프레임 등 이미 만들어진 [InputImage]를 인식한다.
  Future<List<OcrResult>> recognizeImage(InputImage image) async =>
      [await _recognize(_korean, TextRecognitionScript.korean, image, null)];

  Future<OcrResult> _recognize(
    TextRecognizer recognizer,
    TextRecognitionScript script,
    InputImage image,
    ExifFrame? frame,
  ) async {
    final recognized = await recognizer.processImage(image);
    final lines = [
      for (final block in recognized.blocks)
        for (final line in block.lines)
          lineFromWords(
            text: line.text,
            box: line.boundingBox,
            words: [for (final e in line.elements) OcrWord(e.text, e.boundingBox)],
            chars: _charsOf(line),
            frame: frame,
          ),
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

  Future<void> close() => _korean.close();
}

/// JPEG에서 읽은 EXIF 방향과 저장된 픽셀 크기.
class ExifFrame {
  const ExifFrame(this.orientation, this.stored);

  final int orientation;
  final Size stored;
}

/// 파일의 EXIF 방향과 저장 크기를 읽는다. JPEG가 아니거나 EXIF가 없거나 크기를 못 읽으면 null
/// (그러면 상자를 바꾸지 않는다). 디코딩 없이 헤더만 읽는다.
Future<ExifFrame?> _readExifFrame(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    return exifFrameOf(bytes);
  } catch (_) {
    return null;
  }
}

/// [bytes]가 EXIF 방향(2 이상)이 있는 JPEG면 방향과 저장 크기를 돌려준다.
@visibleForTesting
ExifFrame? exifFrameOf(Uint8List bytes) {
  final decoder = img.JpegDecoder();
  if (!decoder.isValidFile(bytes)) return null;
  final info = decoder.startDecode(bytes);
  if (info == null) return null;
  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
  if (orientation == null || orientation <= 1) return null;
  if (info.width <= 0 || info.height <= 0) return null;
  return ExifFrame(orientation, Size(info.width.toDouble(), info.height.toDouble()));
}

/// 저장된(누운) 픽셀 기준의 [box]를 EXIF 방향 [orientation]으로 똑바로 세운 좌표로 바꾼다.
/// [stored]는 저장된 픽셀 크기 W×H. 변환식 (docs/recognition-audit.md 1.9):
/// - 6: `(l, t, r, b) → (H−b, l, H−t, r)` · 8: `→ (t, W−r, b, W−l)` · 3: `→ (W−r, H−b, W−l, H−t)`
///
/// 방향이 없거나 1이거나, 거울상(2·4·5·7)이거나, 크기를 모르면 [box]를 그대로 돌려준다.
Rect uprightBox(Rect box, {required int? orientation, required Size stored}) {
  final w = stored.width, h = stored.height;
  if (w <= 0 || h <= 0) return box;
  switch (orientation) {
    case 6:
      return Rect.fromLTRB(h - box.bottom, box.left, h - box.top, box.right);
    case 8:
      return Rect.fromLTRB(box.top, w - box.right, box.bottom, w - box.left);
    case 3:
      return Rect.fromLTRB(w - box.right, h - box.bottom, w - box.left, h - box.top);
    default:
      return box;
  }
}

/// 줄 상자들을 [uprightBox]로 똑바로 세운다 (글자는 그대로).
List<OcrLine> uprightLines(List<OcrLine> lines, {required int? orientation, required Size stored}) => [
      for (final l in lines)
        OcrLine(l.text, uprightBox(l.box, orientation: orientation, stored: stored), chars: l.chars),
    ];

/// 단어 상자 (ML Kit element).
class OcrWord {
  const OcrWord(this.text, this.box);

  final String text;
  final Rect box;
}

/// 단어 사이 간격이 이 줄 높이 비율보다 좁으면 보통 공백이 아니라 [gapMarker]를 넣는다.
/// 측정값(docs/recognition-audit.md 1.9): 밑줄 자리 0.03~0.05, 진짜 띄어쓰기 0.28~0.60.
const wordGapRatio = 0.12;

/// 좁은 단어 간격 표시 글자 (U+2009 THIN SPACE). OCR이 밑줄을 놓쳐 공백으로 읽은 자리일 수 있다는 표시다.
/// 파서가 값을 정리할 때 이름이면 `_`, 비밀번호면 빈 문자로 바꾼다. 결과 값에는 남지 않는다.
const gapMarker = '\u2009';

/// 단어를 이어 한 줄 글자로 만든다. 간격이 [wordGapRatio] × [lineHeight]보다 좁으면 [gapMarker],
/// 아니면 공백. 줄 높이를 모르면(0 이하) 모두 공백.
String joinWords(List<OcrWord> words, {required double lineHeight}) {
  final out = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    if (i > 0) out.write(_isNarrowGap(words[i - 1].box, words[i].box, lineHeight) ? gapMarker : ' ');
    out.write(words[i].text);
  }
  return out.toString();
}

bool _isNarrowGap(Rect a, Rect b, double lineHeight) =>
    lineHeight > 0 && b.left - a.right < lineHeight * wordGapRatio;

/// ML Kit 줄([text]·[box]·[words])로 [OcrLine]을 만든다. [frame]이 있으면 상자를 똑바로 세우고,
/// 단어 상자를 바탕으로 좁은 간격에 [gapMarker]를 넣는다. 글자를 단어로 다시 이은 것이 [text]와
/// 다르면(ML Kit이 다른 공백을 줬으면) 글자는 건드리지 않는다.
OcrLine lineFromWords({
  required String text,
  required Rect box,
  required List<OcrWord> words,
  List<OcrChar>? chars,
  ExifFrame? frame,
}) {
  Rect fix(Rect r) => frame == null ? r : uprightBox(r, orientation: frame.orientation, stored: frame.stored);
  final upBox = fix(box);
  final upWords = [for (final w in words) OcrWord(w.text, fix(w.box))];
  var lineText = text;
  var lineChars = chars;
  if (upWords.length > 1 && words.map((w) => w.text).join(' ') == text) {
    final joined = joinWords(upWords, lineHeight: upBox.height);
    if (joined != text) {
      lineText = joined;
      lineChars = lineChars == null ? null : _markGaps(lineChars, joined);
    }
  }
  return OcrLine(lineText, upBox, chars: lineChars ?? [for (final r in lineText.runes) OcrChar(String.fromCharCode(r), null)]);
}

/// 단어 사이에 넣은 공백 글자([OcrChar] ' ')를 [joined]의 같은 자리 표시 글자로 바꾼다.
List<OcrChar> _markGaps(List<OcrChar> chars, String joined) {
  final spaces = joined.runes.where((r) => r == 0x20 || r == 0x2009).length;
  if (chars.where((c) => c.text == ' ').length != spaces) return chars;
  final marks = joined.runes.where((r) => r == 0x20 || r == 0x2009).toList();
  var k = 0;
  return [for (final c in chars) c.text == ' ' ? OcrChar(String.fromCharCode(marks[k++]), c.confidence) : c];
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
