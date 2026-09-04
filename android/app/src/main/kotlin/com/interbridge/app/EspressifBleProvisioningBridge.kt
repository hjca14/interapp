package com.interbridge.app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.espressif.provisioning.DeviceConnectionEvent
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_CONNECTED
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_CONNECTION_FAILED
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_DISCONNECTED
import com.espressif.provisioning.ESPConstants.ProvisionFailureReason
import com.espressif.provisioning.ESPConstants.SecurityType.SECURITY_1
import com.espressif.provisioning.ESPConstants.TransportType.TRANSPORT_BLE
import com.espressif.provisioning.ESPDevice
import com.espressif.provisioning.ESPProvisionManager
import com.espressif.provisioning.listeners.BleScanListener
import com.espressif.provisioning.listeners.ProvisionListener
import com.espressif.provisioning.listeners.ResponseListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode
import java.util.UUID

/** Thin native boundary around Espressif's official Android SDK. */
class EspressifBleProvisioningBridge(
    private val activity: Activity,
    engine: FlutterEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private data class Candidate(val device: BluetoothDevice, val serviceUuid: String)

    private val manager = ESPProvisionManager.getInstance(activity.applicationContext)
    private val candidates = mutableMapOf<String, Candidate>()
    private val handlesByAddress = mutableMapOf<String, String>()
    private var eventSink: EventChannel.EventSink? = null
    private var wifiEventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingConnectionResult: MethodChannel.Result? = null
    private var espDevice: ESPDevice? = null
    private var scanning = false
    private val watchdogHandler = Handler(Looper.getMainLooper())

    /**
     * Non-null exactly while a `sendWifiCredentials` attempt is waiting on
     * *some* [ProvisionListener] callback. The official SDK can silently
     * drop a response internally — [ExecutorService.submit] discards any
     * exception thrown while parsing a `prov-config` response, so a
     * malformed/stale read from the device can leave every callback
     * (including [ProvisionListener.wifiConfigFailed]) unfired forever.
     * This watchdog is the only thing that then still ends the attempt.
     * Re-armed on every observed forward-progress callback so a
     * legitimately slow multi-poll Wi-Fi association is not killed early.
     */
    private var wifiWatchdog: Runnable? = null

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, WIFI_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { wifiEventSink = events }
                override fun onCancel(arguments: Any?) { wifiEventSink = null }
            },
        )
        EventBus.getDefault().register(this)
    }

    @Synchronized
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> checkAvailability(result)
            "startScan" -> startScan(result)
            "stopScan" -> { stopScan(); result.success(null) }
            "connect" -> connect(call.argument("transportId"), result)
            "establishSecurity1" -> establishSecurity1(call.argument("pop"), result)
            "sendWifiCredentials" -> sendWifiCredentials(
                call.argument("ssid"),
                call.argument("password"),
                result,
            )
            "disconnect" -> { cleanupConnection(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.success("unsupported"); return
        }
        val adapter = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        if (adapter == null) { result.success("unsupported"); return }
        if (!adapter.isEnabled) { result.success("bluetoothDisabled"); return }
        val permissions = requiredPermissions()
        if (permissions.all { ActivityCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED }) {
            result.success("ready"); return
        }
        if (pendingPermissionResult != null) { result.error("busy", "BLE operation already active", null); return }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, permissions, PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermissionResult?.success(if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) "ready" else "permissionDenied")
        pendingPermissionResult = null
        return true
    }

    private fun requiredPermissions(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun startScan(result: MethodChannel.Result) {
        if (scanning || pendingConnectionResult != null || espDevice != null) {
            result.error("busy", "BLE operation already active", null); return
        }
        candidates.clear(); handlesByAddress.clear(); scanning = true
        manager.searchBleEspDevices(PREFIX, object : BleScanListener {
            override fun scanStartFailed() { scanning = false; eventSink?.error("scan_failed", "Unable to start BLE discovery", null) }
            override fun onPeripheralFound(device: BluetoothDevice, scanResult: android.bluetooth.le.ScanResult) {
                val name = scanResult.scanRecord?.deviceName ?: return
                if (!name.startsWith(PREFIX)) return
                val serviceUuid = scanResult.scanRecord?.serviceUuids?.firstOrNull()?.uuid?.toString() ?: return
                val handle = handlesByAddress.getOrPut(device.address) { UUID.randomUUID().toString() }
                candidates[handle] = Candidate(device, serviceUuid)
                eventSink?.success(mapOf("transportId" to handle, "name" to name))
            }
            override fun scanCompleted() { scanning = false }
            override fun onFailure(e: Exception) { scanning = false; eventSink?.error("scan_failed", "BLE discovery failed", null) }
        })
        result.success(null)
    }

    private fun stopScan() {
        if (scanning) manager.stopBleScan()
        scanning = false
    }

    private fun connect(handle: String?, result: MethodChannel.Result) {
        stopScan()
        if (pendingConnectionResult != null || espDevice != null) { result.error("busy", "BLE operation already active", null); return }
        val candidate = candidates[handle] ?: run { result.error("not_found", "Selected BLE device is no longer available", null); return }
        pendingConnectionResult = result
        espDevice = manager.createESPDevice(TRANSPORT_BLE, SECURITY_1)
        espDevice!!.connectBLEDevice(candidate.device, candidate.serviceUuid)
    }

    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onDeviceConnectionEvent(event: DeviceConnectionEvent) {
        when (event.eventType) {
            EVENT_DEVICE_CONNECTED -> { pendingConnectionResult?.success(null); pendingConnectionResult = null }
            EVENT_DEVICE_CONNECTION_FAILED,
            EVENT_DEVICE_DISCONNECTED -> {
                pendingConnectionResult?.error("connection_failed", "Unable to connect to the selected InterBridge", null)
                pendingConnectionResult = null
                cleanupConnection()
            }
        }
    }

    private fun establishSecurity1(pop: String?, result: MethodChannel.Result) {
        val device = espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (pop.isNullOrEmpty()) { cleanupConnection(); result.error("pop_missing", "Development PoP is not configured", null); return }
        device.proofOfPossession = pop
        device.initSession(object : ResponseListener {
            override fun onSuccess(returnData: ByteArray?) { result.success(null) }
            override fun onFailure(e: Exception) { cleanupConnection(); result.error("security1_failed", "Security 1 session could not be established", null) }
        })
    }

    /**
     * Re-arms the single wifi-attempt watchdog, cancelling any previous one
     * first. Fires [WIFI_RESPONSE_TIMEOUT_MS] after the *last* observed
     * forward-progress callback (or after `provision()` itself if none has
     * fired yet) if no further [ProvisionListener] callback has arrived by
     * then — see [wifiWatchdog]'s doc for why this can genuinely happen with
     * the official SDK. Never logs/persists ssid, password, PoP, or any
     * response payload — stage names only.
     */
    private fun armWifiWatchdog() {
        cancelWifiWatchdog()
        val watchdog = Runnable {
            Log.w(TAG, "sendWifiCredentials: no SDK callback observed within timeout, ending attempt")
            wifiWatchdog = null
            cleanupConnection()
            wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "noResponse"))
        }
        wifiWatchdog = watchdog
        watchdogHandler.postDelayed(watchdog, WIFI_RESPONSE_TIMEOUT_MS)
    }

    private fun cancelWifiWatchdog() {
        wifiWatchdog?.let { watchdogHandler.removeCallbacks(it) }
        wifiWatchdog = null
    }

    /** ssid/password only ever exist as local parameters here — never stored in a field or logged. */
    private fun sendWifiCredentials(ssid: String?, password: String?, result: MethodChannel.Result) {
        val device = espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (ssid.isNullOrEmpty()) { result.error("ssid_missing", "SSID must not be empty", null); return }
        // password may legitimately be empty for an open network.
        Log.d(TAG, "sendWifiCredentials: provision() starting")
        armWifiWatchdog()
        try {
            device.provision(ssid, password ?: "", object : ProvisionListener {
                override fun createSessionFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "sendWifiCredentials: secure session unavailable (createSessionFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "sessionFailed"))
                }
                override fun wifiConfigSent() {
                    Log.d(TAG, "sendWifiCredentials: config accepted, apply requested")
                    armWifiWatchdog()
                    wifiEventSink?.success(mapOf("event" to "wifiConfigSent"))
                }
                override fun wifiConfigFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "sendWifiCredentials: config rejected (wifiConfigFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "sendFailed"))
                }
                override fun wifiConfigApplied() {
                    Log.d(TAG, "sendWifiCredentials: apply accepted, awaiting connection status")
                    armWifiWatchdog()
                    wifiEventSink?.success(mapOf("event" to "wifiConfigApplied"))
                }
                override fun wifiConfigApplyFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "sendWifiCredentials: apply rejected (wifiConfigApplyFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "applyFailed"))
                }
                override fun provisioningFailedFromDevice(reason: ProvisionFailureReason) {
                    cancelWifiWatchdog()
                    val code = wifiFailureReasonCode(reason)
                    Log.d(TAG, "sendWifiCredentials: terminal failure from device (reason=$code)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to code))
                }
                override fun deviceProvisioningSuccess() {
                    cancelWifiWatchdog()
                    Log.d(TAG, "sendWifiCredentials: terminal success (deviceProvisioningSuccess)")
                    // Deliberately does not cleanupConnection() here — Dart
                    // explicitly calls disconnect() once it has observed this
                    // event, matching connect()/establishSecurity1()'s own
                    // success paths never self-disconnecting either.
                    wifiEventSink?.success(mapOf("event" to "wifiConnected"))
                }
                override fun onProvisioningFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "sendWifiCredentials: terminal failure (onProvisioningFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "unknown"))
                }
            })
        } catch (e: Exception) {
            // An unexpected synchronous throw from the SDK itself — must
            // still end this attempt with a sanitized error instead of
            // leaving the watchdog as the only thing standing between this
            // and an infinite spinner.
            cancelWifiWatchdog()
            Log.e(TAG, "sendWifiCredentials: provision() threw synchronously")
            cleanupConnection()
            result.error("send_failed", "Unable to start Wi-Fi provisioning", null)
            return
        }
        result.success(null)
    }

    private fun cleanupConnection() {
        cancelWifiWatchdog()
        stopScan()
        espDevice?.disconnectDevice()
        espDevice = null
        pendingConnectionResult = null
        candidates.clear(); handlesByAddress.clear()
    }

    fun dispose() {
        cleanupConnection()
        eventSink = null
        wifiEventSink = null
        if (EventBus.getDefault().isRegistered(this)) EventBus.getDefault().unregister(this)
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null; stopScan() }

    companion object {
        private const val TAG = "EspressifBleProvisioningBridge"
        private const val METHODS = "interapp/ble_onboarding"
        private const val EVENTS = "interapp/ble_onboarding/discovery"
        private const val WIFI_EVENTS = "interapp/ble_onboarding/wifi"
        private const val PREFIX = "InterBridge-"
        private const val PERMISSION_REQUEST = 4412

        /**
         * Bound on how long a `sendWifiCredentials` attempt waits for the
         * *next* [ProvisionListener] callback before the bridge gives up on
         * its own — see [wifiWatchdog]. Comfortably above the SDK's own
         * internal apply-retry (2s) and status-poll (5s) intervals so a
         * legitimately slow Wi-Fi association is not cut short.
         */
        private const val WIFI_RESPONSE_TIMEOUT_MS = 25_000L
    }
}
