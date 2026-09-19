import 'dart:convert';

/// 연결 요청 전에 OS API가 거부할 입력을 미리 걸러낸다.
///
/// Android `WifiNetworkSuggestion.Builder`와 iOS `NEHotspotConfiguration` 모두
/// SSID는 최대 32바이트, WPA 비밀번호는 8~63자의 ASCII 문자만 허용한다.
abstract final class WifiInputValidator {
  static String? ssidError(String ssid) {
    if (ssid.isEmpty) return 'Wi-Fi 이름을 입력해주세요.';
    if (utf8.encode(ssid).length > 32) return 'Wi-Fi 이름이 너무 길어요. (최대 32바이트)';
    return null;
  }

  /// 빈 비밀번호는 공개(Open) 네트워크로 보고 허용한다.
  static String? passwordError(String password) {
    if (password.isEmpty) return null;
    if (!_printableAscii.hasMatch(password)) {
      return '비밀번호에는 영문, 숫자, 특수문자만 쓸 수 있어요.';
    }
    if (password.length < 8) return 'Wi-Fi 비밀번호는 8자 이상이에요. 다시 확인해주세요.';
    if (password.length > 63) return '비밀번호가 너무 길어요. (최대 63자)';
    return null;
  }

  static final _printableAscii = RegExp(r'^[\x20-\x7E]+$');
}
