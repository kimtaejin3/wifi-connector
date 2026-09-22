import Flutter
import NetworkExtension
import UIKit

/// Flutter에서 Wi-Fi 연결 요청과 설정 화면 이동을 처리한다.
///
/// NEHotspotConfigurationManager.apply()를 호출하면 iOS가 "Wi-Fi 네트워크에 연결하겠습니까?"
/// 시스템 알림을 띄우고, 사용자가 승인해야 연결된다.
/// 비밀번호는 NEHotspotConfiguration에 전달만 하고 저장하거나 로그로 남기지 않는다.
final class WifiConnectorPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.kimtaejin.wifi_connector/platform"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WifiConnectorPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "connectWifi":
      connect(
        ssid: args?["ssid"] as? String ?? "",
        password: args?["password"] as? String ?? "",
        result: result
      )
    case "awaitConnection":
      let timeoutMs = (args?["timeoutMs"] as? NSNumber)?.intValue ?? 6000
      awaitConnection(
        ssid: args?["ssid"] as? String ?? "",
        deadline: Date().addingTimeInterval(Double(timeoutMs) / 1000),
        result: result
      )
    case "openAppSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    case "openWifiSettings":
      // iOS는 공개 API로 Wi-Fi 설정 화면에 바로 이동할 수 없다.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func connect(ssid: String, password: String, result: @escaping FlutterResult) {
    guard !ssid.isEmpty else {
      result(Self.failure("invalid_ssid"))
      return
    }

    // 비밀번호가 없으면 Open 네트워크, 있으면 WPA/WPA2/WPA3 Personal.
    let configuration = password.isEmpty
      ? NEHotspotConfiguration(ssid: ssid)
      : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
    // joinOnce = true 이면 앱이 백그라운드로 갈 때 연결이 끊긴다. 카페에서 계속 쓰도록 저장한다.
    configuration.joinOnce = false

    NEHotspotConfigurationManager.shared.apply(configuration) { error in
      DispatchQueue.main.async {
        if let error = error as NSError? {
          result(Self.map(error))
        } else {
          // apply()는 비밀번호가 틀려도 에러 없이 끝나는 경우가 있어 연결 여부는 awaitConnection에서 확인한다.
          result(["status": "requested"])
        }
      }
    }
  }

  /// 현재 연결된 SSID가 [ssid]가 될 때까지 1초 간격으로 확인한다.
  /// NEHotspotNetwork.fetchCurrent는 이 앱이 NEHotspotConfiguration으로 설정한 네트워크라면
  /// 위치 권한 없이 동작한다 (Access Wi-Fi Information entitlement 필요).
  private func awaitConnection(ssid: String, deadline: Date, result: @escaping FlutterResult) {
    NEHotspotNetwork.fetchCurrent { network in
      DispatchQueue.main.async {
        if network?.ssid == ssid {
          result(["connected": true])
        } else if Date() >= deadline {
          result(["connected": false])
        } else {
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.awaitConnection(ssid: ssid, deadline: deadline, result: result)
          }
        }
      }
    }
  }

  private static func map(_ error: NSError) -> [String: Any] {
    guard error.domain == NEHotspotConfigurationErrorDomain,
          let code = NEHotspotConfigurationError(rawValue: error.code)
    else {
      return failure("unknown")
    }
    switch code {
    case .alreadyAssociated:
      return ["status": "connected"]
    case .userDenied:
      return ["status": "cancelled"]
    case .pending:
      // 같은 요청이 아직 처리 중. 연결 여부는 awaitConnection에서 확인한다.
      return ["status": "requested"]
    case .invalidWPAPassphrase, .invalidWEPPassphrase:
      return failure("invalid_password")
    case .invalidSSID, .invalidSSIDPrefix:
      return failure("invalid_ssid")
    default:
      return failure("unknown")
    }
  }

  private static func failure(_ reason: String) -> [String: Any] {
    ["status": "failed", "reason": reason]
  }
}
