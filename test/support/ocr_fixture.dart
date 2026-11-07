// OCR fixture(test/fixtures/ocr/<이름>.json)를 앱의 OcrResult로 되살린다.
//
// fixture는 integration_test/ocr_dump_test.dart가 iOS 시뮬레이터의 ML Kit(앱과 같은 한국어 인식기)로
// 만든 원문 인식 결과다 (tool/render_signs.sh → tool/ocr_dump.sh). 형식은 ocr_dump_test.dart 머리말 참고.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';

const ocrFixtureDir = 'test/fixtures/ocr';

class OcrFixture {
  OcrFixture._({
    required this.name,
    required this.text,
    required this.dumpedLayoutText,
    required this.lines,
    required this.imageWidth,
    required this.imageHeight,
    required this.exifOrientation,
  });

  factory OcrFixture.fromJson(Map<String, dynamic> json) {
    final image = (json['image'] as Map<String, dynamic>?) ?? const {};
    // 앱의 recognizeFile과 같이: EXIF 방향이 있고 저장 크기를 알면 상자를 똑바로 세운다.
    final orientation = (image['exifOrientation'] as num?)?.toInt();
    final width = (image['width'] as num?)?.toInt();
    final height = (image['height'] as num?)?.toInt();
    final frame = (orientation != null && orientation > 1 && width != null && height != null && width > 0 && height > 0)
        ? ExifFrame(orientation, Size(width.toDouble(), height.toDouble()))
        : null;
    return OcrFixture._(
      name: json['name'] as String,
      text: json['text'] as String,
      dumpedLayoutText: json['layoutText'] as String,
      lines: [for (final l in json['lines'] as List) _line(l as Map<String, dynamic>, frame)],
      imageWidth: (image['width'] as num?)?.toInt(),
      imageHeight: (image['height'] as num?)?.toInt(),
      exifOrientation: (image['exifOrientation'] as num?)?.toInt(),
    );
  }

  static OcrFixture load(String name) =>
      OcrFixture.fromJson(jsonDecode(File('$ocrFixtureDir/$name.json').readAsStringSync()) as Map<String, dynamic>);

  /// fixture 폴더의 모든 이름 (확장자 뺀 파일 이름, 정렬).
  static List<String> names() => Directory(ocrFixtureDir)
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.json'))
      .map((n) => n.substring(0, n.length - '.json'.length))
      .toList()
    ..sort();

  final String name;

  /// ML Kit 원문 (`recognized.text`).
  final String text;

  /// 덤프할 때 앱의 layoutRows가 만든 행 재구성 텍스트. 기록용이다. 테스트는 [lines]로 지금 코드의
  /// layoutRows를 다시 돌린다 ([toOcrResult]) — 행 재구성을 고치면 fixture를 다시 뽑지 않아도 반영된다.
  final String dumpedLayoutText;

  /// 앱이 만드는 것과 같은 줄 (OcrResult.lines 순서): EXIF 회전 사진은 상자를 똑바로 세웠고
  /// (`uprightBox`), 단어 간격이 좁은 곳에는 표시 글자가 들어 있다 (`lineFromWords`).
  final List<OcrLine> lines;

  /// 저장된 픽셀 크기와 EXIF 회전 값 (EXIF가 없으면 null).
  final int? imageWidth;
  final int? imageHeight;
  final int? exifOrientation;

  /// 앱이 이 이미지를 사진 한 장으로 인식했을 때와 같은 OCR 결과 (한국어 인식기 하나).
  OcrResult toOcrResult() => OcrResult(
        script: TextRecognitionScript.korean,
        text: text,
        layoutText: layoutRows(lines),
        lines: lines,
      );

  static OcrLine _line(Map<String, dynamic> json, ExifFrame? frame) {
    final box = [for (final v in json['box'] as List) (v as num).toDouble()];
    final text = json['text'] as String;
    final chars = json['chars'];
    final conf = json['conf'] as List?;
    final words = [
      for (final e in (json['elements'] as List?) ?? const [])
        OcrWord((e as Map<String, dynamic>)['text'] as String, _rect(e['box'] as List)),
    ];
    final List<OcrChar> parsed;
    if (chars is List) {
      parsed = [
        for (var i = 0; i < chars.length; i++) OcrChar(chars[i] as String, (conf?[i] as num?)?.toDouble()),
      ];
    } else {
      // iOS: 글자 신뢰도가 없다. OcrService와 같이 글자 하나씩 신뢰도 없이 펼친다.
      parsed = [for (final r in ((chars as String?) ?? text).runes) OcrChar(String.fromCharCode(r), null)];
    }
    return lineFromWords(
      text: text,
      box: Rect.fromLTRB(box[0], box[1], box[2], box[3]),
      words: words,
      chars: parsed,
      frame: frame,
    );
  }

  static Rect _rect(List box) {
    final v = [for (final x in box) (x as num).toDouble()];
    return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  }
}
