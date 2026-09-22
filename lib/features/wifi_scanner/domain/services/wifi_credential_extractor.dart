import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/models/wifi_credential.dart';
import '../../data/services/ocr_service.dart';
import 'wifi_credential_parser.dart';

/// 여러 인식기의 OCR 결과를 파서에 넘겨 하나의 [WifiCredential]로 만든다.
class WifiCredentialExtractor {
  const WifiCredentialExtractor({this.parser = const WifiCredentialParser()});

  final WifiCredentialParser parser;

  /// 한글이 보이면 한국어 인식기 결과를, 아니면 라틴 인식기 결과를 우선한다.
  /// 좌표 기반 행 재구성 텍스트로 먼저 시도하고, 아무것도 못 찾으면 원문으로 다시 시도한다.
  WifiCredential fromOcrResults(List<OcrResult> results) {
    final ordered = [...results]..sort((a, b) => _priority(a, results).compareTo(_priority(b, results)));
    final fromLayout = parser.merge([for (final r in ordered) parser.parse(r.layoutText)]);
    if (!fromLayout.isEmpty) return fromLayout;
    return parser.merge([for (final r in ordered) parser.parse(r.text)]);
  }

  static int _priority(OcrResult r, List<OcrResult> all) {
    final anyHangul = all.any((o) => o.hasHangul);
    final preferred = anyHangul ? TextRecognitionScript.korean : TextRecognitionScript.latin;
    return r.script == preferred ? 0 : 1;
  }
}
