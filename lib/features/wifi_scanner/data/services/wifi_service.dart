import 'package:flutter/services.dart';

import '../../../../core/utils/platform_channel.dart';

enum WifiConnectStatus {
  /// OS가 연결까지 끝냈다고 알려줌 (iOS에서 이미 연결된 네트워크인 경우).
  connected,

  /// OS가 요청을 받아들였음. 실제 연결 여부는 [WifiService.awaitConnection]으로 확인한다.
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
  const WifiConnectResult(this.status, {this.failure, this.alreadySaved = false});

  const WifiConnectResult.failed(WifiConnectFailure failure)
      : this(WifiConnectStatus.failed, failure: failure);

  factory WifiConnectResult.fromMap(Map<String, Object?> map) {
    final status = WifiConnectStatus.values.asNameMap()[map['status']];
    if (status == null) return const WifiConnectResult.failed(WifiConnectFailure.unknown);
    if (status != WifiConnectStatus.failed) {
      return WifiConnectResult(status, alreadySaved: map['alreadySaved'] == true);
    }
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

  /// Android: 같은 SSID가 이미 저장돼 있어 OS가 새로 추가하지 않음.
  /// 저장된 비밀번호가 다르면 사용자가 설정에서 지워야 한다.
  final bool alreadySaved;

  bool get isSuccess =>
      status == WifiConnectStatus.connected ||
      status == WifiConnectStatus.requested ||
      status == WifiConnectStatus.suggested;

  /// OS가 원인을 밝히지 않고 실패를 돌려줬지만 실제로는 연결될 수 있는 상태.
  /// iOS는 첫 접속 시도가 늦으면 "연결할 수 없음" 알림과 함께 실패를 알린 뒤
  /// 저장된 설정으로 곧 다시 붙기도 한다. 형식 오류나 사용자 거절은 여기에 해당하지 않는다.
  bool get mayStillConnect => status == WifiConnectStatus.failed && failure == WifiConnectFailure.unknown;

  /// 요청은 성공했지만 실제 연결은 따로 확인해야 하는 상태.
  bool get needsVerification =>
      status == WifiConnectStatus.requested || status == WifiConnectStatus.suggested;
}

/// [WifiService.awaitConnection] 결과.
class WifiConnectionCheck {
  const WifiConnectionCheck({required this.connected, this.captivePortal = false});

  factory WifiConnectionCheck.fromMap(Map<String, Object?> map) => WifiConnectionCheck(
        connected: map['connected'] == true,
        captivePortal: map['captivePortal'] == true,
      );

  /// 확인할 수 없었음. 연결이 안 됐다는 뜻은 아니다.
  static const unconfirmed = WifiConnectionCheck(connected: false);

  final bool connected;

  /// 연결은 됐지만 브라우저 로그인이 필요한 네트워크 (Android에서만 감지).
  final bool captivePortal;
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
  ///
  /// iOS 전용 힌트 (Android는 무시한다):
  /// - [replaceExisting]: 이 앱이 같은 SSID로 저장해 둔 설정을 지우고 새로 적용할지.
  ///   비밀번호가 전과 같으면 false로 줘서, 지우고 다시 넣는 사이 요청이 겹쳐
  ///   "연결할 수 없음"이 뜨는 일을 피한다.
  /// - [retry]: 직전 시도에서 연결을 확인하지 못해 같은 값으로 다시 시도하는 경우.
  ///   iOS가 주변 스캔에서 네트워크를 놓쳤거나 숨김 네트워크일 수 있으므로,
  ///   이름을 지정해 직접 찾는 방식(hidden)으로 요청한다.
  Future<WifiConnectResult> connect({
    required String ssid,
    required String password,
    bool replaceExisting = true,
    bool retry = false,
  }) async {
    try {
      final result = await platformChannel.invokeMapMethod<String, Object?>(
        'connectWifi',
        {'ssid': ssid, 'password': password, 'replaceExisting': replaceExisting, 'retry': retry},
      );
      return WifiConnectResult.fromMap(result ?? const {});
    } on MissingPluginException {
      return const WifiConnectResult.failed(WifiConnectFailure.unsupported);
    } on PlatformException {
      return const WifiConnectResult.failed(WifiConnectFailure.unknown);
    }
  }

  /// 연결 요청이 받아들여진 뒤 실제로 연결됐는지 기다린다.
  ///
  /// - iOS: 앱이 설정한 네트워크의 SSID를 `NEHotspotNetwork.fetchCurrent`로 확인한다.
  /// - Android: 위치 권한 없이는 SSID를 읽을 수 없으므로, 요청 이후 새 Wi-Fi 연결이
  ///   생기는지 `ConnectivityManager` 콜백으로 감지한다.
  ///
  /// [WifiConnectionCheck.connected]가 false여도 연결이 안 됐다고 단정할 수는 없다
  /// (이미 그 네트워크에 붙어 있었거나, OS가 기존 네트워크를 유지하는 경우).
  Future<WifiConnectionCheck> awaitConnection({required String ssid, Duration? timeout}) async {
    // iOS의 apply()는 실제 접속 전에 돌아오는 경우가 많고, Android는 저장 후 OS가
    // 전환하는 데 시간이 걸린다. 둘 다 넉넉히 기다리되 붙는 즉시 끝난다.
    // iOS는 첫 시도가 실패해도 저장된 설정으로 다시 붙는 데 시간이 더 걸릴 수 있다.
    final wait = timeout ?? const Duration(seconds: 30);
    try {
      final result = await platformChannel.invokeMapMethod<String, Object?>(
        'awaitConnection',
        {'ssid': ssid, 'timeoutMs': wait.inMilliseconds},
      );
      return WifiConnectionCheck.fromMap(result ?? const {});
    } on MissingPluginException {
      return WifiConnectionCheck.unconfirmed;
    } on PlatformException {
      return WifiConnectionCheck.unconfirmed;
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
