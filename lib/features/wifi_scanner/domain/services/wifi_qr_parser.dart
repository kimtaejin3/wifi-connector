/// Wi-Fi QR 코드 내용. 표준 형식은 `WIFI:T:WPA;S:ssid;P:password;H:true;;`.
class WifiQr {
  const WifiQr({required this.ssid, required this.password, this.hidden = false, this.security});

  final String ssid;

  /// 공개 네트워크(`T:nopass`)면 빈 문자열.
  final String password;
  final bool hidden;

  /// `WPA`, `WEP`, `nopass` 등 원문 그대로.
  final String? security;
}

/// `WIFI:` 문자열을 파싱한다. Wi-Fi QR이 아니거나 SSID가 없으면 null.
///
/// 값 안의 `;`, `,`, `:`, `\`는 `\`로 이스케이프된다.
WifiQr? parseWifiQr(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (!text.toUpperCase().startsWith('WIFI:')) return null;

  final fields = <String, String>{};
  final buffer = StringBuffer();
  String? key;
  var i = 5;
  while (i < text.length) {
    final ch = text[i];
    if (ch == '\\' && i + 1 < text.length) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (key == null && ch == ':') {
      key = buffer.toString().trim().toUpperCase();
      buffer.clear();
    } else if (ch == ';') {
      if (key != null) fields[key] = buffer.toString();
      key = null;
      buffer.clear();
    } else {
      buffer.write(ch);
    }
    i++;
  }
  if (key != null && buffer.isNotEmpty) fields[key] = buffer.toString();

  final ssid = fields['S'];
  if (ssid == null || ssid.isEmpty) return null;
  final security = fields['T'];
  final open = security != null && security.toLowerCase() == 'nopass';
  return WifiQr(
    ssid: ssid,
    password: open ? '' : (fields['P'] ?? ''),
    hidden: (fields['H'] ?? '').toLowerCase() == 'true',
    security: security,
  );
}
