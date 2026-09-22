/// OCR이 자주 만들어내는 비ASCII 변형을 되돌린다.
///
/// WPA 비밀번호는 ASCII만 허용되므로, 전각 문자나 특수 대시/따옴표는 안내문의
/// 글꼴 때문에 생긴 오인식일 뿐 실제 값일 수 없다. 이 변환은 뜻이 하나로
/// 정해지는 문자만 다루고, 대소문자나 특수문자 자체는 바꾸지 않는다.
String normalizeOcrText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    // 전각 ASCII (！ ～ ) → 반각
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFF01 + 0x21);
      continue;
    }
    switch (rune) {
      case 0x3000: // 전각 공백
      case 0x00A0: // NBSP
        buffer.write(' ');
      case 0x200B: // zero width space
      case 0x200C:
      case 0x200D:
      case 0xFEFF:
        break;
      case 0x2010: // ‐ hyphen
      case 0x2011: // ‑ non-breaking hyphen
      case 0x2012: // ‒ figure dash
      case 0x2013: // – en dash
      case 0x2014: // — em dash
      case 0x2015: // ― horizontal bar
      case 0x2212: // − minus sign
        buffer.write('-');
      case 0x2018: // ‘
      case 0x2019: // ’
      case 0x02BC: // ʼ
        buffer.write("'");
      case 0x201C: // “
      case 0x201D: // ”
        buffer.write('"');
      case 0x2026: // …
        buffer.write('...');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
