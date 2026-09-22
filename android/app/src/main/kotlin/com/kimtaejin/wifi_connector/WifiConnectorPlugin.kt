package com.kimtaejin.wifi_connector

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.Handler
import android.os.Looper
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
 * 연결 확인: 위치 권한 없이는 현재 SSID를 읽을 수 없으므로, 요청 전에 ConnectivityManager
 * 콜백을 등록해 두고 승인 뒤에 "새로" 생기는 Wi-Fi 연결을 감지한다 (awaitConnection).
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
    private var watcher: ConnectionWatcher? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stopWatcher()
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
            "awaitConnection" -> awaitConnection(
                timeoutMs = (call.argument<Number>("timeoutMs") ?: 20_000).toLong(),
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

    // -----------------------------------------------------------------------------------------
    // 연결 요청

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

        // 승인 화면이 떠 있는 동안 현재 네트워크들을 파악해 두어야 승인 뒤의 "새 연결"을 구분할 수 있다.
        startWatcher()

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
            stopWatcher()
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
        if (status == WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
            watcher?.arm()
            result.success(mapOf("status" to "suggested"))
        } else {
            stopWatcher()
            result.success(failure("unknown"))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_ADD_NETWORK) return false
        val result = pendingConnect ?: return true
        pendingConnect = null

        if (resultCode != Activity.RESULT_OK) {
            stopWatcher()
            result.success(mapOf("status" to "cancelled"))
            return true
        }
        val codes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) resultCodes(data) else emptyList()
        if (codes.any { it == Settings.ADD_WIFI_RESULT_ADD_OR_UPDATE_FAILED }) {
            stopWatcher()
            result.success(failure("unknown"))
            return true
        }
        watcher?.arm()
        result.success(
            mapOf(
                "status" to "requested",
                "alreadySaved" to codes.any { it == Settings.ADD_WIFI_RESULT_ALREADY_EXISTS },
            ),
        )
        return true
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun resultCodes(data: Intent?): List<Int> =
        data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST) ?: emptyList()

    // -----------------------------------------------------------------------------------------
    // 연결 확인

    private fun awaitConnection(timeoutMs: Long, result: MethodChannel.Result) {
        val w = watcher
        if (w == null || !w.armed) {
            result.success(mapOf("connected" to false))
            return
        }
        w.await(timeoutMs) { connected, captivePortal ->
            stopWatcher()
            result.success(mapOf("connected" to connected, "captivePortal" to captivePortal))
        }
    }

    private fun startWatcher() {
        stopWatcher()
        val cm = appContext.getSystemService(ConnectivityManager::class.java) ?: return
        watcher = ConnectionWatcher(cm, mainHandler).also { it.start() }
    }

    private fun stopWatcher() {
        watcher?.stop()
        watcher = null
    }

    /**
     * 요청 전에 등록해 지금 붙어 있는 Wi-Fi 네트워크를 기억하고(known), 승인 뒤(armed)에
     * 그 밖의 Wi-Fi 네트워크가 생기면 연결된 것으로 본다.
     *
     * 위치 권한 없이는 SSID를 읽을 수 없으므로 기본 게이트웨이 주소로 네트워크를 구분한다.
     * 저장 직후 OS가 기존 네트워크를 끊었다 다시 붙이는 경우(Network 객체는 새로 생긴다)를
     * 새 연결로 오인하지 않기 위해서다. 게이트웨이가 우연히 같은 다른 AP는 "확인 못 함"이 된다.
     */
    private class ConnectionWatcher(
        private val cm: ConnectivityManager,
        private val handler: Handler,
    ) : ConnectivityManager.NetworkCallback() {
        private val known = mutableSetOf<Network>()
        private val knownGateways = mutableSetOf<String>()
        private val captive = mutableMapOf<Network, Boolean>()
        private var registered = false
        private var newNetwork: Network? = null
        private var listener: ((Boolean, Boolean) -> Unit)? = null
        private var timeout: Runnable? = null
        private var settle: Runnable? = null

        @Volatile
        var armed = false
            private set

        fun start() {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            try {
                cm.registerNetworkCallback(request, this)
                registered = true
            } catch (e: RuntimeException) {
                // 콜백 등록 한도 초과 등. 확인 없이 진행한다.
            }
        }

        fun arm() {
            armed = true
        }

        fun await(timeoutMs: Long, onDone: (connected: Boolean, captivePortal: Boolean) -> Unit) {
            handler.post {
                listener = onDone
                if (newNetwork != null && settle == null) {
                    finish(true)
                    return@post
                }
                timeout = Runnable { finish(false) }.also { handler.postDelayed(it, timeoutMs) }
            }
        }

        fun stop() {
            timeout?.let { handler.removeCallbacks(it) }
            settle?.let { handler.removeCallbacks(it) }
            timeout = null
            settle = null
            listener = null
            if (registered) {
                registered = false
                try {
                    cm.unregisterNetworkCallback(this)
                } catch (e: IllegalArgumentException) {
                    // 이미 해제됨
                }
            }
        }

        /** main thread에서만 호출. */
        private fun finish(connected: Boolean) {
            timeout?.let { handler.removeCallbacks(it) }
            settle?.let { handler.removeCallbacks(it) }
            timeout = null
            settle = null
            val done = listener ?: return
            listener = null
            done(connected, connected && (newNetwork?.let { captive[it] } ?: false))
        }

        override fun onAvailable(network: Network) {
            if (!armed) known.add(network)
        }

        override fun onLost(network: Network) {
            known.remove(network)
            captive.remove(network)
        }

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            captive[network] = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
            if (!armed) {
                known.add(network)
                return
            }
            // 새 네트워크의 인터넷/캡티브 포털 판정이 끝나면 더 기다리지 않는다.
            if (network == newNetwork &&
                (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ||
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL))
            ) {
                handler.post { if (settle != null) finish(true) }
            }
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            val gateways = gatewaysOf(linkProperties)
            if (!armed || network in known) {
                known.add(network)
                knownGateways.addAll(gateways)
                return
            }
            if (newNetwork != null) return
            if (gateways.isNotEmpty() && gateways.any { it in knownGateways }) {
                // 같은 게이트웨이 = 기존 네트워크에 다시 붙은 것
                known.add(network)
                return
            }
            newNetwork = network
            handler.post {
                if (listener == null) return@post
                // 캡티브 포털 여부는 연결 직후 probe가 끝나야 알 수 있어 잠시 기다린다.
                settle = Runnable { finish(true) }.also { handler.postDelayed(it, SETTLE_MS) }
            }
        }

        private fun gatewaysOf(linkProperties: LinkProperties): Set<String> =
            linkProperties.routes
                .filter { it.isDefaultRoute }
                .mapNotNull { it.gateway?.hostAddress }
                .toSet()

        private companion object {
            const val SETTLE_MS = 2_500L
        }
    }

    // -----------------------------------------------------------------------------------------
    // 설정 화면

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
