import 'package:flutter/services.dart';

import '../../../../core/utils/platform_channel.dart';

enum WifiConnectStatus {
  /// 연결까지 확인됨 (iOS에서 현재 SSID로 검증된 경우).
  connected,

  /// OS가 요청을 받아들였지만 실제 연결 여부는 확인할 수 없음.
  requested,

  /// Android 10: 네트워크 제안으로 등록됨. 사용자가 알림에서 허용해야 연결된다.
  suggested,

  /// 사용자가 OS 확인 화면에서 거절함.
  cancelled,

  failed,
}

enum WifiConnectFailure {
  invalidPassword,
  invalidSsid,
  wifiDisabled,
  unsupported,
  unknown,
}

class WifiConnectResult {
  const WifiConnectResult(this.status, [this.failure]);

  const WifiConnectResult.failed(WifiConnectFailure failure)
      : this(WifiConnectStatus.failed, failure);

  factory WifiConnectResult.fromMap(Map<String, Object?> map) {
    final status = WifiConnectStatus.values.asNameMap()[map['status']];
    if (status == null) return const WifiConnectResult.failed(WifiConnectFailure.unknown);
    if (status != WifiConnectStatus.failed) return WifiConnectResult(status);
    final failure = switch (map['reason']) {
      'invalid_password' => WifiConnectFailure.invalidPassword,
      'invalid_ssid' => WifiConnectFailure.invalidSsid,
      'wifi_disabled' => WifiConnectFailure.wifiDisabled,
      'unsupported' => WifiConnectFailure.unsupported,
      _ => WifiConnectFailure.unknown,
    };
    return WifiConnectResult.failed(failure);
  }

  final WifiConnectStatus status;
  final WifiConnectFailure? failure;

  bool get isSuccess =>
      status == WifiConnectStatus.connected ||
      status == WifiConnectStatus.requested ||
      status == WifiConnectStatus.suggested;
}

/// OS 공식 Wi-Fi API로 연결을 요청한다.
///
/// - Android 11+: `Settings.ACTION_WIFI_ADD_NETWORKS` (시스템 저장 확인 화면)
/// - Android 10: `WifiManager.addNetworkSuggestions`
/// - iOS: `NEHotspotConfigurationManager.apply` (시스템 연결 확인 알림)
///
/// 비밀번호는 네이티브로 전달만 하고 저장하거나 로그로 남기지 않는다.
class WifiService {
  const WifiService();

  /// [password]가 비어 있으면 공개(Open) 네트워크로 연결한다.
  Future<WifiConnectResult> connect({required String ssid, required String password}) async {
    try {
      final result = await platformChannel.invokeMapMethod<String, Object?>(
        'connectWifi',
        {'ssid': ssid, 'password': password},
      );
      return WifiConnectResult.fromMap(result ?? const {});
    } on MissingPluginException {
      return const WifiConnectResult.failed(WifiConnectFailure.unsupported);
    } on PlatformException {
      return const WifiConnectResult.failed(WifiConnectFailure.unknown);
    }
  }

  /// Wi-Fi 설정 화면(Android 패널)을 연다. iOS는 앱에서 Wi-Fi 설정으로 이동할 수 없다.
  Future<void> openWifiSettings() async {
    try {
      await platformChannel.invokeMethod<void>('openWifiSettings');
    } on PlatformException {
      // 무시
    } on MissingPluginException {
      // 무시
    }
  }
}
