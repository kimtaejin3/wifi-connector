import 'package:flutter/services.dart';

/// Android(MainActivity) / iOS(AppDelegate)에 직접 구현한 네이티브 기능 채널.
///
/// - `connectWifi` {ssid, password} → {status, reason?}
/// - `openWifiSettings` (Android 전용)
/// - `openAppSettings`
const platformChannel = MethodChannel('com.kimtaejin.wifi_connector/platform');

/// 앱의 시스템 설정 화면(권한 설정)을 연다.
Future<void> openAppSettings() async {
  try {
    await platformChannel.invokeMethod<void>('openAppSettings');
  } on PlatformException {
    // 설정 화면을 열 수 없는 기기에서는 조용히 무시한다.
  } on MissingPluginException {
    // 지원하지 않는 플랫폼
  }
}
