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
     * *some* [ProvisionListener] callback. A secondary UX safety net only —
     * see [establishSecurity1] for the actual SDK-call-sequence fix for the
     * stall a real bench run observed, and [armWifiWatchdog] for why this
     * must never be described as that fix. The UI must never be left on a
     * spinner with no way out regardless, so every attempt still gets a
     * bounded deadline and a recoverable, retryable error. Re-armed on every
     * observed forward-progress callback so a legitimately slow multi-poll
     * Wi-Fi association is not killed early.
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

    /**
     * Configures the Proof-of-Possession the *upcoming* [sendWifiCredentials]
     * call will use — it deliberately does not itself open a Security 1
     * session or perform any BLE transaction.
     *
     * A real bench run against the PR #25 firmware showed the SDK accept
     * `prov-config` (`wifiConfigSent` fired — `credentials accepted by SDK`)
     * and then never call back again; the app-level watchdog was the only
     * thing that ever ended the attempt. Decompiling the resolved
     * `com.github.espressif:esp-idf-provisioning-android:lib-2.1.3` AAR
     * (`ESPDevice.class`, `javap -c`) found the actual cause: this method
     * used to call `device.initSession(...)` here, on its own, and only
     * *after* it fully completed did the bridge return success to Dart —
     * which then showed the Wi-Fi form and waited, unbounded, for the user
     * to type SSID/password. `ESPDevice.provision(ssid, password, listener)`
     * is the SDK's own single continuous transaction for the rest of the
     * flow: its bytecode is
     * ```
     * if (session == null || !session.isEstablished()) initSession(new ResponseListener() {
     *     onSuccess -> sendWiFiConfig(ssid, password, listener)   // ESPDevice$5
     *     onFailure -> listener.createSessionFailed(e)
     * }); else sendWiFiConfig(ssid, password, listener);
     * ```
     * and `sendWiFiConfig`'s own response handler (`ESPDevice$10.onSuccess`)
     * unconditionally calls `applyWiFiConfig()` next in the same callback —
     * so nothing about *that* chaining was ever under this bridge's control,
     * and nothing about it changes here. What changes is which entry point
     * we call: by pre-establishing the session ourselves and letting Dart
     * hold it open across an arbitrary, user-paced UI delay, we sat outside
     * `provision()`'s own supported request/response cycle for that whole
     * interval — a window `BLETransport.sendConfigData()` cannot recover
     * from if a GATT operation silently fails there (it calls
     * `bluetoothGatt.writeCharacteristic(...)` and discards the boolean
     * result, and guards the transport with an unbounded, no-timeout
     * `Semaphore.acquire()`; Android's own docs and long-standing BLE stack
     * behavior, particularly on budget Samsung chipsets like the Galaxy
     * A12's, document `writeCharacteristic`/`readCharacteristic` returning
     * `false` or silently not calling back when issued after the GATT
     * client has sat idle). `provision()` is the officially-supported way
     * to run session-establish through apply/poll as one uninterrupted
     * transaction; not calling `initSession()` here at all is what lets
     * [sendWifiCredentials] reach it fresh, with `session == null`, every
     * time. An incorrect PoP is therefore now reported via `provision()`'s
     * own `createSessionFailed` callback (already handled below) once the
     * user submits Wi-Fi credentials, not here — this method only ever
     * fails on a missing PoP or no BLE connection, both purely local
     * checks. Kept as its own bridge/Dart call (rather than merged into
     * [sendWifiCredentials]) so the app can still show its "securing
     * connection" step as an observable UI phase between BLE connect and
     * the Wi-Fi form, per the required UX — it just no longer gates that
     * step on a real, separately-completed SDK transaction.
     */
    private fun establishSecurity1(pop: String?, result: MethodChannel.Result) {
        espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (pop.isNullOrEmpty()) { cleanupConnection(); result.error("pop_missing", "Development PoP is not configured", null); return }
        espDevice!!.proofOfPossession = pop
        result.success(null)
    }

    /**
     * Re-arms the *secondary UX safety net*, cancelling any previous one
     * first. This is a bounded, recoverable fallback — never the fix for
     * the stall a real bench run observed (see [establishSecurity1] for the
     * SDK-call-sequence fix that addresses that directly, and never claim
     * this watchdog does). Any time it actually fires, that means the SDK
     * produced no further [ProvisionListener] callback at all after the
     * last observed one — a fact this must surface, not paper over: it logs
     * `terminal timeout` precisely because the timeout itself is not a
     * normal outcome. It exists purely so a real device — for whatever
     * reason, on any future attempt this specific fix does not cover
     * either — never leaves the UI stuck on a spinner with no way out:
     * fires [WIFI_RESPONSE_TIMEOUT_MS] after the *last* observed
     * forward-progress callback (or after `provision()` itself if none has
     * fired yet, which now includes the SDK's own internal session
     * establishment — see [establishSecurity1]), ends the attempt with a
     * recoverable error, and disconnects — the same retry path (reconnect
     * from scratch) every other failure in this method already uses. Never
     * logs/persists ssid, password, PoP, or any response payload — stage
     * names only.
     */
    private fun armWifiWatchdog() {
        cancelWifiWatchdog()
        val watchdog = Runnable {
            Log.w(TAG, "terminal timeout")
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

    /**
     * ssid/password only ever exist as local parameters here — never stored
     * in a field or logged. Calls the official SDK's `ESPDevice.provision`
     * exactly as documented for manual SSID/password entry, on the
     * already-connected device. Since [establishSecurity1] no longer calls
     * `initSession()` itself, `session` is `null` here, so this `provision()`
     * call is where the SDK establishes Security 1 *and* sends/applies the
     * Wi-Fi config *and* polls for the result — one continuous transaction,
     * exactly as `ESPDevice.provision`'s own bytecode is written to do (see
     * [establishSecurity1]'s doc comment for the decompiled proof). No GATT,
     * protobuf, or endpoint of our own, no Security 0 fallback. Log markers
     * below are the sanitized bench vocabulary for this call: "provision
     * invoked", "credentials accepted by SDK", "wifi applying", "wifi
     * connected", "wifi rejected", "terminal timeout" — never SSID,
     * password, PoP, BLE payload bytes, MAC address, or UUIDs.
     */
    private fun sendWifiCredentials(ssid: String?, password: String?, result: MethodChannel.Result) {
        val device = espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (ssid.isNullOrEmpty()) { result.error("ssid_missing", "SSID must not be empty", null); return }
        // password may legitimately be empty for an open network.
        Log.d(TAG, "provision invoked")
        armWifiWatchdog()
        try {
            device.provision(ssid, password ?: "", object : ProvisionListener {
                override fun createSessionFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "wifi rejected (createSessionFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "sessionFailed"))
                }
                override fun wifiConfigSent() {
                    Log.d(TAG, "credentials accepted by SDK")
                    armWifiWatchdog()
                    wifiEventSink?.success(mapOf("event" to "wifiConfigSent"))
                }
                override fun wifiConfigFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "wifi rejected (wifiConfigFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "sendFailed"))
                }
                override fun wifiConfigApplied() {
                    Log.d(TAG, "wifi applying")
                    armWifiWatchdog()
                    wifiEventSink?.success(mapOf("event" to "wifiConfigApplied"))
                }
                override fun wifiConfigApplyFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "wifi rejected (wifiConfigApplyFailed)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "applyFailed"))
                }
                override fun provisioningFailedFromDevice(reason: ProvisionFailureReason) {
                    cancelWifiWatchdog()
                    val code = wifiFailureReasonCode(reason)
                    Log.d(TAG, "wifi rejected (provisioningFailedFromDevice, reason=$code)")
                    cleanupConnection()
                    wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to code))
                }
                override fun deviceProvisioningSuccess() {
                    cancelWifiWatchdog()
                    Log.d(TAG, "wifi connected")
                    // Deliberately does not cleanupConnection() here — Dart
                    // explicitly calls disconnect() once it has observed this
                    // event, matching connect()/establishSecurity1()'s own
                    // success paths never self-disconnecting either.
                    wifiEventSink?.success(mapOf("event" to "wifiConnected"))
                }
                override fun onProvisioningFailed(e: Exception) {
                    cancelWifiWatchdog()
                    Log.d(TAG, "wifi rejected (onProvisioningFailed)")
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
            Log.e(TAG, "wifi rejected (provision() threw synchronously)")
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
         * its own — see [wifiWatchdog]. Since [establishSecurity1] no longer
         * pre-establishes the session, the *first* window also covers the
         * SDK's own internal Security 1 handshake (`initSession()`, now run
         * as part of this same `provision()` call) before any callback has
         * fired — comfortably above that plus the SDK's own internal
         * apply-retry (2s) and status-poll (5s) intervals so a legitimately
         * slow handshake or Wi-Fi association is not cut short.
         */
        private const val WIFI_RESPONSE_TIMEOUT_MS = 25_000L
    }
}
