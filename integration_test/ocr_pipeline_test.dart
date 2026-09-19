// 실제 기기/에뮬레이터에서 ML Kit OCR → 행 재구성 → Parser 전체 흐름을 검증한다.
// 카메라 대신 안내문 이미지를 그려서 파일로 저장한 뒤 인식시킨다.
//
//   flutter test integration_test -d <device-id>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wifi_connector/features/wifi_scanner/data/services/ocr_service.dart';
import 'package:wifi_connector/features/wifi_scanner/domain/services/wifi_credential_parser.dart';

const _size = Size(1200, 900);

/// [rows]의 각 항목은 한 줄. 셀이 두 개면 왼쪽/오른쪽 열에 나눠 그린다.
Future<String> renderSign(List<List<String>> rows, {double fontSize = 60}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & _size, Paint()..color = Colors.white);
  final style = TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.w500);

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

  final image = await recorder.endRecording().toImage(_size.width.toInt(), _size.height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/sign_${DateTime.now().microsecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OcrService ocr;
  const parser = WifiCredentialParser();

  setUpAll(() => ocr = OcrService());
  tearDownAll(() => ocr.close());

  Future<void> expectSign(List<List<String>> rows, {String? ssid, String? password}) async {
    final path = await renderSign(rows);
    try {
      final result = await ocr.recognizeFile(path);
      var credential = parser.parse(result.layoutText);
      if (credential.isEmpty) credential = parser.parse(result.text);
      final reason = 'OCR layout:\n${result.layoutText}\n---\n$credential';
      expect(credential.ssid, ssid, reason: reason);
      expect(credential.password, password, reason: reason);
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
}
