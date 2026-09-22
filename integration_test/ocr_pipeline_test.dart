// 실제 기기/에뮬레이터에서 ML Kit OCR → 행 재구성 → 가이드 영역 크롭 → Parser 전체 흐름을 검증한다.
// 카메라 대신 안내문 이미지를 그려서 파일로 저장한 뒤 인식시킨다.
//
//   flutter test integration_test -d <device-id>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/models/wifi_credential.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/image_cropper.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_extractor.dart';
import 'package:wifi_connector/features/wifi_scanner/presentation/widgets/scan_guide_overlay.dart';

const _size = Size(1200, 900);

/// [rows]의 각 항목은 한 줄. 셀이 두 개면 왼쪽/오른쪽 열에 나눠 그린다.
/// [noise]는 가이드 영역 밖(위·아래 가장자리)에 그리는 방해 문구.
Future<String> renderSign(
  List<List<String>> rows, {
  double fontSize = 60,
  List<String> noise = const [],
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & _size, Paint()..color = Colors.white);
  final style = TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.w500);

  void paint(String text, Offset offset, {double? size}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: size == null ? style : style.copyWith(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  final lineHeight = fontSize * 1.6;
  var y = (_size.height - rows.length * lineHeight) / 2;
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: row[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = row.length == 1 ? (_size.width - painter.width) / 2 : (i == 0 ? 100.0 : 620.0);
      painter.paint(canvas, Offset(x, y));
    }
    y += lineHeight;
  }
  for (var i = 0; i < noise.length; i++) {
    paint(noise[i], Offset(40, i.isEven ? 20 : _size.height - 70), size: 44);
  }

  final image = await recorder.endRecording().toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/sign_${DateTime.now().microsecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OcrService ocr;
  const extractor = WifiCredentialExtractor();

  setUpAll(() => ocr = OcrService());
  tearDownAll(() => ocr.close());

  Future<WifiCredential> recognize(String path) async {
    final results = await ocr.recognizeFileWithAllScripts(path);
    return extractor.fromOcrResults(results);
  }

  Future<void> expectSign(List<List<String>> rows, {String? ssid, String? password}) async {
    final path = await renderSign(rows);
    try {
      final credential = await recognize(path);
      expect(credential.ssid, ssid, reason: '$credential');
      expect(credential.password, password, reason: '$credential');
    } finally {
      File(path).deleteSync();
    }
  }

  testWidgets('MVP 완료 조건 안내문', (tester) async {
    await expectSign(
      [
        ['FREE WIFI'],
        ['SSID : TestCafe'],
        ['Password : Test12345'],
      ],
      ssid: 'TestCafe',
      password: 'Test12345',
    );
  });

  testWidgets('한글 라벨과 한글 SSID', (tester) async {
    await expectSign(
      [
        ['와이파이 : 카페모모'],
        ['비밀번호 : hello1234'],
      ],
      ssid: '카페모모',
      password: 'hello1234',
    );
  });

  testWidgets('라벨 열과 값 열이 떨어진 안내문', (tester) async {
    await expectSign(
      [
        ['WELCOME TO MOMO CAFE'],
        ['Wi-Fi', 'cafe_momo_5G'],
        ['Password', 'momo1234'],
      ],
      ssid: 'cafe_momo_5G',
      password: 'momo1234',
    );
  });

  testWidgets('라벨 다음 줄에 값, 대소문자/특수문자 보존', (tester) async {
    await expectSign(
      [
        ['WIFI'],
        ['MOMO_GUEST'],
        ['PASSWORD'],
        ['Coffee#2024'],
      ],
      ssid: 'MOMO_GUEST',
      password: 'Coffee#2024',
    );
  });

  testWidgets('가이드 영역 밖의 글자는 크롭으로 걸러낸다', (tester) async {
    // 가이드 밖(맨 위/맨 아래)에 다른 Wi-Fi 정보처럼 보이는 문구를 둔다.
    final path = await renderSign(
      [
        ['SSID : TestCafe'],
        ['Password : Test12345'],
      ],
      fontSize: 48,
      noise: ['STAFF ONLY  SSID : Office_5G', 'PW : staff9999  (직원용)'],
    );
    try {
      // 세로 화면(400x600)에 cover로 보여준 상태에서 앱과 같은 가이드 영역을 크롭했다고 가정.
      const view = Size(400, 600);
      final guide = ScanGuideOverlay.guideRect(view);
      final cropped = await cropImageFile(path: path, viewRect: guide, viewSize: view);
      expect(cropped, isNotNull);

      final credential = await recognize(cropped!);
      expect(credential.ssid, 'TestCafe', reason: '$credential');
      expect(credential.password, 'Test12345', reason: '$credential');
      expect(
        credential.candidates.map((c) => c.value),
        isNot(anyOf(contains('Office_5G'), contains('staff9999'))),
      );
      File(cropped).deleteSync();
    } finally {
      File(path).deleteSync();
    }
  });
}
