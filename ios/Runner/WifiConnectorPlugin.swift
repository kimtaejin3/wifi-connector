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
        replaceExisting: args?["replaceExisting"] as? Bool ?? true,
        retry: args?["retry"] as? Bool ?? false,
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

  /// - replaceExisting: 이 앱이 같은 SSID로 저장한 설정을 지우고 새로 적용할지.
  ///   비밀번호가 전과 같으면 지울 필요가 없다 (apply가 기존 설정을 갱신한다).
  /// - retry: 직전 시도에서 연결을 확인하지 못한 재시도. iOS가 스캔에서 네트워크를 놓쳤거나
  ///   숨김 네트워크일 수 있으므로 이름을 지정해 직접 찾도록 hidden으로 요청한다.
  private func connect(
    ssid: String,
    password: String,
    replaceExisting: Bool,
    retry: Bool,
    result: @escaping FlutterResult
  ) {
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
    if retry {
      configuration.hidden = true
    }

    let manager = NEHotspotConfigurationManager.shared
    let apply = {
      manager.apply(configuration) { error in
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

    // 이미 그 네트워크에 붙어 있으면 아무것도 하지 않는다. 설정을 지우고 다시 적용하면
    // 연결이 잠깐 끊겼다 붙으면서 iOS가 "연결할 수 없음" 알림을 띄우기 때문이다.
    NEHotspotNetwork.fetchCurrent { current in
      if current?.ssid == ssid {
        DispatchQueue.main.async { result(["status": "connected"]) }
        return
      }
      // 비밀번호가 바뀌었을 수 있을 때만 이 앱이 저장한 옛 설정을 지우고 새로 적용한다
      // (옛 비밀번호로 붙으려다 실패하는 것을 막는다). 비밀번호가 같으면 그대로 적용한다.
      guard replaceExisting else {
        DispatchQueue.main.async(execute: apply)
        return
      }
      manager.getConfiguredSSIDs { configured in
        DispatchQueue.main.async {
          if configured.contains(ssid) {
            manager.removeConfiguration(forSSID: ssid)
            // 삭제는 비동기로 끝난다. 실제로 사라진 것을 확인한 뒤 적용해 두 요청이 겹치지 않게 한다.
            self.waitUntilRemoved(ssid: ssid, remainingChecks: 15, then: apply)
          } else {
            apply()
          }
        }
      }
    }
  }

  /// 저장된 설정 목록에서 [ssid]가 사라질 때까지 0.2초 간격으로 확인한다 (최대 3초).
  /// 끝까지 남아 있어도 더 기다리지 않고 진행한다.
  private func waitUntilRemoved(ssid: String, remainingChecks: Int, then apply: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NEHotspotConfigurationManager.shared.getConfiguredSSIDs { configured in
        DispatchQueue.main.async {
          if !configured.contains(ssid) || remainingChecks <= 1 {
            apply()
          } else {
            self.waitUntilRemoved(ssid: ssid, remainingChecks: remainingChecks - 1, then: apply)
          }
        }
      }
    }
  }

  /// 현재 연결된 SSID가 [ssid]가 될 때까지 0.5초 간격으로 확인한다.
  /// apply()는 사용자가 승인한 직후 실제 접속이 끝나기 전에 돌아오는 경우가 많아,
  /// 접속이 몇 초 늦어도 놓치지 않도록 충분히 기다리되 붙는 즉시 돌려준다.
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
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
