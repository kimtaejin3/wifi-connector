package com.kimtaejin.wifi_connector

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Flutter에서 Wi-Fi 연결 요청과 설정 화면 이동을 처리한다.
 *
 * - Android 11(API 30)+: Settings.ACTION_WIFI_ADD_NETWORKS 로 시스템 "네트워크 저장" 확인 화면을 띄운다.
 *   사용자가 승인하면 저장된 네트워크로 추가되고 OS가 연결한다.
 * - Android 10(API 29): WifiManager.addNetworkSuggestions 로 네트워크를 제안한다.
 *   처음 한 번은 사용자가 시스템 알림에서 허용해야 한다.
 * - Android 9 이하: 공식 비-deprecated API가 없어 지원하지 않는다 (Wi-Fi 설정으로 안내).
 *
 * WifiNetworkSpecifier는 인터넷용이 아닌 로컬 기기 연결 용도라 사용하지 않는다.
 * 비밀번호는 시스템 API에 전달만 하고 저장하거나 로그로 남기지 않는다.
 */
class WifiConnectorPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingConnect: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connectWifi" -> connect(
                ssid = call.argument<String>("ssid").orEmpty(),
                password = call.argument<String>("password").orEmpty(),
                result = result,
            )
            "openWifiSettings" -> {
                openWifiSettings()
                result.success(null)
            }
            "openAppSettings" -> {
                openAppSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connect(ssid: String, password: String, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null || pendingConnect != null) {
            result.success(failure("unknown"))
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(failure("unsupported"))
            return
        }

        val wifiManager = appContext.getSystemService(WifiManager::class.java)
        if (wifiManager == null) {
            result.success(failure("unsupported"))
            return
        }
        if (!wifiManager.isWifiEnabled) {
            result.success(failure("wifi_disabled"))
            return
        }

        val suggestion = buildSuggestion(ssid, password, result) ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestAddNetwork(activity, suggestion, result)
        } else {
            suggestNetwork(wifiManager, suggestion, result)
        }
    }

    /** 비밀번호가 비어 있으면 Open 네트워크, 있으면 WPA2 (WPA2/WPA3 전환 모드 AP 포함). */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun buildSuggestion(
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ): WifiNetworkSuggestion? {
        val builder = WifiNetworkSuggestion.Builder()
        try {
            builder.setSsid(ssid)
        } catch (e: IllegalArgumentException) {
            result.success(failure("invalid_ssid"))
            return null
        }
        if (password.isNotEmpty()) {
            try {
                builder.setWpa2Passphrase(password)
            } catch (e: IllegalArgumentException) {
                result.success(failure("invalid_password"))
                return null
            }
        }
        return try {
            builder.build()
        } catch (e: RuntimeException) {
            result.success(failure(if (password.isEmpty()) "invalid_ssid" else "invalid_password"))
            null
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestAddNetwork(
        activity: Activity,
        suggestion: WifiNetworkSuggestion,
        result: MethodChannel.Result,
    ) {
        val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS)
            .putParcelableArrayListExtra(Settings.EXTRA_WIFI_NETWORK_LIST, arrayListOf(suggestion))
        pendingConnect = result
        try {
            activity.startActivityForResult(intent, REQUEST_ADD_NETWORK)
        } catch (e: ActivityNotFoundException) {
            pendingConnect = null
            result.success(failure("unsupported"))
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun suggestNetwork(
        wifiManager: WifiManager,
        suggestion: WifiNetworkSuggestion,
        result: MethodChannel.Result,
    ) {
        val suggestions = listOf(suggestion)
        var status = wifiManager.addNetworkSuggestions(suggestions)
        if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_ERROR_ADD_DUPLICATE) {
            // Android 10은 같은 SSID 제안을 갱신하지 않으므로 지우고 다시 추가한다 (비밀번호 수정 반영).
            wifiManager.removeNetworkSuggestions(suggestions)
            status = wifiManager.addNetworkSuggestions(suggestions)
        }
        result.success(
            if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
                mapOf("status" to "suggested")
            } else {
                failure("unknown")
            },
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_ADD_NETWORK) return false
        val result = pendingConnect ?: return true
        pendingConnect = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(mapOf("status" to "cancelled"))
            return true
        }
        val failed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && hasAddFailure(data)
        result.success(if (failed) failure("unknown") else mapOf("status" to "requested"))
        return true
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun hasAddFailure(data: Intent?): Boolean {
        val codes = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)
            ?: return false
        return codes.any { it == Settings.ADD_WIFI_RESULT_ADD_OR_UPDATE_FAILED }
    }

    private fun openWifiSettings() {
        val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Settings.Panel.ACTION_WIFI
        } else {
            Settings.ACTION_WIFI_SETTINGS
        }
        startActivitySafely(Intent(action))
    }

    private fun openAppSettings() {
        startActivitySafely(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", appContext.packageName, null),
            ),
        )
    }

    private fun startActivitySafely(intent: Intent) {
        val activity = activityBinding?.activity
        try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        } catch (e: ActivityNotFoundException) {
            // 설정 화면이 없는 기기
        }
    }

    private fun failure(reason: String) = mapOf("status" to "failed", "reason" to reason)

    private companion object {
        const val CHANNEL = "com.kimtaejin.wifi_connector/platform"
        const val REQUEST_ADD_NETWORK = 7301
    }
}
