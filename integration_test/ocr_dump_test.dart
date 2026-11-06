// 안내문 이미지를 기기(보통 iOS 시뮬레이터)의 ML Kit로 읽어 원문 OCR fixture(JSON)를 만든다.
//
//   tool/ocr_dump.sh      # 보통은 이 스크립트로 실행한다 (시뮬레이터 부팅 → 이 테스트 → 개수 확인)
//
//   flutter test integration_test/ocr_dump_test.dart -d <시뮬레이터 udid> \
//     --dart-define=OCR_DUMP_IN=<이미지 폴더> --dart-define=OCR_DUMP_OUT=<fixture 폴더> \
//     [--dart-define=OCR_DUMP_ONLY=variety-01,variants-03]
//
// - 앱이 쓰는 OcrService(한국어 인식기, 같은 행 재구성)를 그대로 쓴다. 앱 코드는 바꾸지 않는다.
//   OcrService는 단어(element) 상자를 밖으로 내주지 않으므로, 같은 설정의 인식기를 한 번 더 돌려 단어 상자를
//   얻고 줄 글자가 OcrService 결과와 똑같을 때만 덧붙인다 (밑줄·자간 분석 같은 개선을 기기 없이 시험하려고).
// - 시뮬레이터 앱은 Mac 경로를 바로 읽고 쓰므로 폴더는 Mac 경로를 그대로 준다.
// - OCR_DUMP_IN/OUT이 없으면 아무것도 하지 않는다 (`flutter test integration_test`에 섞여도 무해).
// - 인식한 글자(비밀번호 포함)는 fixture 파일에만 쓴다. 화면·로그에는 이미지 이름과 개수만 남긴다.
//
// fixture 형식 (test/support/ocr_fixture.dart가 읽는다):
//   {
//     "name": "variety-01", "source": "variety-01.png", "recognizer": "...",
//     "image": {"width": 1600, "height": 1200, "exifOrientation": null},   // 저장된 픽셀 크기
//     "text": "<ML Kit 원문>", "layoutText": "<덤프 당시 layoutRows 결과>",
//     "lines": [ {"text": "...", "box": [left, top, right, bottom],
//                 "elements": [{"text": "...", "box": [...]}, ...]}, ... ]   // OcrResult.lines 순서
//   }
//   줄의 글자(OcrLine.chars)가 줄 글자와 다르면 "chars"(문자열)를 더 쓴다. 글자 신뢰도가 있으면(Android)
//   "chars"는 글자 목록, "conf"는 같은 길이의 신뢰도 목록이다.
//   상자 좌표는 ML Kit가 준 그대로다. EXIF 회전이 든 사진이면 저장된 픽셀(옆으로 누운) 기준으로 나온다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';

const _inDir = String.fromEnvironment('OCR_DUMP_IN');
const _outDir = String.fromEnvironment('OCR_DUMP_OUT');
const _only = String.fromEnvironment('OCR_DUMP_ONLY');

final _imageFile = RegExp(r'\.(png|jpe?g)$', caseSensitive: false);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('안내문 이미지 → 원문 OCR fixture', (tester) async {
    final only = {for (final n in _only.split(',')) if (n.trim().isNotEmpty) n.trim()};
    final images = Directory(_inDir)
        .listSync()
        .whereType<File>()
        .where((f) => _imageFile.hasMatch(f.path))
        .where((f) => only.isEmpty || only.contains(_nameOf(f.path)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(images, isNotEmpty, reason: '읽을 이미지가 없어요: $_inDir');
    Directory(_outDir).createSync(recursive: true);

    final ocr = OcrService();
    // 단어 상자용. OcrService와 같은 한국어 인식기.
    final words = TextRecognizer(script: TextRecognitionScript.korean);
    var withoutElements = 0;
    try {
      for (final file in images) {
        final results = await ocr.recognizeFile(file.path);
        expect(results, hasLength(1), reason: '한국어 인식기 하나의 결과만 와야 한다');
        final result = results.single;
        final recognized = await words.processImage(InputImage.fromFilePath(file.path));
        final rawLines = [for (final b in recognized.blocks) ...b.lines];
        final sameLines = rawLines.length == result.lines.length &&
            [for (var i = 0; i < rawLines.length; i++) rawLines[i].text == result.lines[i].text].every((same) => same);
        if (!sameLines) withoutElements++;
        final name = _nameOf(file.path);
        File('$_outDir/$name.json').writeAsStringSync(_fixtureJson(name, file, result, sameLines ? rawLines : null));
        // 글자는 찍지 않는다. 이름과 줄 수만.
        debugPrintSynchronously('[ocr_dump] $name: ${result.lines.length}줄${sameLines ? '' : ' (단어 상자 없음)'}');
      }
    } finally {
      await ocr.close();
      await words.close();
    }
    debugPrintSynchronously('[ocr_dump] 이미지 ${images.length}개 → $_outDir'
        '${withoutElements == 0 ? '' : ' (단어 상자를 못 붙인 이미지 $withoutElements개)'}');
  }, skip: _inDir.isEmpty || _outDir.isEmpty, timeout: const Timeout(Duration(minutes: 30)));
}

String _nameOf(String path) => path.split('/').last.replaceFirst(_imageFile, '');

List<double> _box(Rect r) => [r.left, r.top, r.right, r.bottom];

String _fixtureJson(String name, File file, OcrResult result, List<TextLine>? rawLines) {
  final bytes = file.readAsBytesSync();
  final exifOrientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
  // decodeImage는 JPEG의 EXIF 회전을 적용해 돌려주므로, 저장된 픽셀 크기로 되돌려 적는다.
  final shown = img.decodeImage(bytes);
  final sideways = exifOrientation != null && exifOrientation >= 5 && exifOrientation <= 8;
  final image = {
    'width': sideways ? shown?.height : shown?.width,
    'height': sideways ? shown?.width : shown?.height,
    'exifOrientation': exifOrientation,
  };

  String encodeLine(int index) {
    final line = result.lines[index];
    final chars = line.chars.map((c) => c.text).toList();
    final conf = line.chars.map((c) => c.confidence).toList();
    final hasConf = conf.any((c) => c != null);
    return jsonEncode({
      'text': line.text,
      'box': _box(line.box),
      // iOS는 신뢰도가 없고 글자가 줄 글자와 같아서 보통 둘 다 빠진다.
      if (hasConf) 'chars': chars else if (chars.join() != line.text) 'chars': chars.join(),
      if (hasConf) 'conf': conf,
      if (rawLines != null)
        'elements': [
          for (final e in rawLines[index].elements) {'text': e.text, 'box': _box(e.boundingBox)},
        ],
    });
  }

  // 한 줄에 OCR 한 줄씩 두어 fixture diff를 읽기 쉽게 한다.
  final head = const JsonEncoder.withIndent('  ').convert({
    'name': name,
    'source': file.path.split('/').last,
    'recognizer': 'ML Kit TextRecognizer(korean) via OcrService · ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
    'image': image,
    'text': result.text,
    'layoutText': result.layoutText,
  });
  final lines = [for (var i = 0; i < result.lines.length; i++) '    ${encodeLine(i)}'].join(',\n');
  return '${head.substring(0, head.length - 2)},\n  "lines": [\n$lines\n  ]\n}\n';
}
