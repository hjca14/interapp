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
     * Defers every `ProvisionListener` callback's Flutter/GATT/`Handler`
     * work to [watchdogHandler] instead of running it on the SDK's own
     * callback stack — see [sendWifiCredentials] for why, and this class's
     * own doc for the single-attempt/no-stale-revival guarantee it provides.
     */
    private val wifiAttempts = WifiAttemptDispatcher(poster = watchdogHandler::post)

    /**
     * Non-null exactly while a `sendWifiCredentials` attempt is waiting on
     * *some* [ProvisionListener] callback. A secondary UX safety net, not a
     * fix: a bench run showed `wifiConfigSent()` fire and then no further
     * SDK callback at all, so whatever the actual cause turns out to be,
     * the UI must never be left on a spinner with no way out. Fires
     * [WIFI_RESPONSE_TIMEOUT_MS] after the *last* observed forward-progress
     * callback, ends the attempt with a recoverable, retryable error, and
     * disconnects. Re-armed on every observed forward-progress callback so
     * a legitimately slow multi-poll Wi-Fi association is not killed early.
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
     * call will use — does not itself open a Security 1 session or perform
     * any BLE transaction. `ESPDevice.provision(ssid, password, listener)`
     * is the SDK's own single continuous transaction for session-establish
     * through apply/poll (decompiled `ESPDevice.class`, confirmed as of
     * `com.github.espressif:esp-idf-provisioning-android:lib-2.1.3`): it
     * calls `initSession()` itself when `session == null`, and
     * `sendWiFiConfig()`'s own response handler unconditionally calls
     * `applyWiFiConfig()` next in the same callback. A first bench attempt
     * that pre-established the session here, then let Dart hold it open
     * across an arbitrary, user-paced UI delay before calling
     * [sendWifiCredentials], did not complete the flow; not calling
     * `initSession()` here follows the SDK's own supported request/response
     * cycle instead, but a later bench run showed this alone does not
     * resolve the stall either — see `docs/PHASE_3_ROADMAP.md` for the
     * current state of that investigation, and [sendWifiCredentials] for
     * what changed after that run. An incorrect PoP is reported via
     * `provision()`'s own `createSessionFailed` callback once the user
     * submits Wi-Fi credentials, not here — this method only ever fails on
     * a missing PoP or no BLE connection, both purely local checks. Kept as
     * its own bridge/Dart call so the app can still show a "preparing
     * secure connection" step between BLE connect and the Wi-Fi form — it
     * does not itself complete a real SDK transaction, so the UI must not
     * claim the session is already established at this point.
     */
    private fun establishSecurity1(pop: String?, result: MethodChannel.Result) {
        espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (pop.isNullOrEmpty()) { cleanupConnection(); result.error("pop_missing", "Development PoP is not configured", null); return }
        espDevice!!.proofOfPossession = pop
        result.success(null)
    }

    /**
     * Re-arms the *secondary UX safety net*, cancelling any previous one
     * first — a bounded, recoverable fallback, not a diagnosis. Any time it
     * actually fires, that means no further [ProvisionListener] callback
     * arrived at all after the last observed one — a fact this must
     * surface, not paper over: it logs `terminal timeout` precisely because
     * the timeout itself is not a normal outcome. Fires
     * [WIFI_RESPONSE_TIMEOUT_MS] after the *last* observed forward-progress
     * delivery (or after `provision()` itself if none has arrived yet),
     * ends the attempt with a recoverable error, and disconnects — the same
     * retry path (reconnect from scratch) every other failure in this
     * method already uses. Runs on [watchdogHandler], the same poster
     * [wifiAttempts] delivers through, so it is naturally ordered against
     * them; still checks [WifiAttemptDispatcher.isActive] itself in case a
     * delivery for this same attempt is already queued ahead of it. Never
     * logs/persists ssid, password, PoP, or any response payload.
     */
    private fun armWifiWatchdog(attemptId: Int) {
        cancelWifiWatchdog()
        val watchdog = Runnable {
            wifiWatchdog = null
            if (wifiAttempts.isActive(attemptId)) {
                Log.w(TAG, "terminal timeout")
                wifiAttempts.endAttempt(attemptId)
                cleanupConnection()
                wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to "noResponse"))
            }
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
     * already-connected device — see [establishSecurity1]'s doc for why
     * this is where Security 1 itself actually runs. No GATT, protobuf, or
     * endpoint of our own, no Security 0 fallback.
     *
     * A bench run showed `wifiConfigSent()` fire (`credentials accepted by
     * SDK`) and then nothing further at all — no `wifiConfigApplied`, no
     * failure, nothing but the watchdog's own timeout 25s later. Decompiled
     * `ESPDevice$10.onSuccess` (the response handler `sendWiFiConfig()`
     * registers) calls `provisionListener.wifiConfigSent()` and then, on the
     * same call stack and only if that callback returns normally, calls
     * `applyWiFiConfig()` next — so every `ProvisionListener` override below
     * is now strictly minimal: it does no Flutter/GATT work and lets no
     * exception escape, deferring everything to [wifiAttempts] instead of
     * risking being the reason that next call is never reached. This has
     * not yet been confirmed as the actual cause of the stall — it is
     * consistent with where the log stops, not proven by it; see
     * `docs/PHASE_3_ROADMAP.md`. Log markers are the sanitized bench
     * vocabulary for this call: "provision invoked", "credentials accepted
     * by SDK", "sdk wifiConfigSent returned", "apply progression
     * scheduled", "wifi applying", "wifi connected", "wifi rejected",
     * "terminal timeout" — never SSID, password, PoP, BLE payload bytes,
     * MAC address, or UUIDs.
     */
    private fun sendWifiCredentials(ssid: String?, password: String?, result: MethodChannel.Result) {
        val device = espDevice ?: run { result.error("not_connected", "No BLE connection", null); return }
        if (ssid.isNullOrEmpty()) { result.error("ssid_missing", "SSID must not be empty", null); return }
        // password may legitimately be empty for an open network.
        val attemptId = wifiAttempts.beginAttempt()
        Log.d(TAG, "provision invoked")
        armWifiWatchdog(attemptId)
        try {
            device.provision(ssid, password ?: "", object : ProvisionListener {
                // Every override below is intentionally minimal — see this
                // method's doc. sdkCallback() guarantees no exception ever
                // escapes back into the SDK's own callback stack.
                override fun createSessionFailed(e: Exception) = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi rejected (createSessionFailed)")
                        failAttempt(attemptId, "sessionFailed")
                    }
                }
                override fun wifiConfigSent() = sdkCallback {
                    Log.d(TAG, "credentials accepted by SDK")
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "apply progression scheduled")
                        armWifiWatchdog(attemptId)
                        wifiEventSink?.success(mapOf("event" to "wifiConfigSent"))
                    }
                    Log.d(TAG, "sdk wifiConfigSent returned")
                }
                override fun wifiConfigFailed(e: Exception) = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi rejected (wifiConfigFailed)")
                        failAttempt(attemptId, "sendFailed")
                    }
                }
                override fun wifiConfigApplied() = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi applying")
                        armWifiWatchdog(attemptId)
                        wifiEventSink?.success(mapOf("event" to "wifiConfigApplied"))
                    }
                }
                override fun wifiConfigApplyFailed(e: Exception) = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi rejected (wifiConfigApplyFailed)")
                        failAttempt(attemptId, "applyFailed")
                    }
                }
                override fun provisioningFailedFromDevice(reason: ProvisionFailureReason) = sdkCallback {
                    val code = wifiFailureReasonCode(reason)
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi rejected (provisioningFailedFromDevice, reason=$code)")
                        failAttempt(attemptId, code)
                    }
                }
                override fun deviceProvisioningSuccess() = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi connected")
                        wifiAttempts.endAttempt(attemptId)
                        cancelWifiWatchdog()
                        // Deliberately does not cleanupConnection() here —
                        // Dart explicitly calls disconnect() once it has
                        // observed this event, matching connect()/
                        // establishSecurity1()'s own success paths never
                        // self-disconnecting either.
                        wifiEventSink?.success(mapOf("event" to "wifiConnected"))
                    }
                }
                override fun onProvisioningFailed(e: Exception) = sdkCallback {
                    wifiAttempts.deliver(attemptId) {
                        Log.d(TAG, "wifi rejected (onProvisioningFailed)")
                        failAttempt(attemptId, "unknown")
                    }
                }
            })
        } catch (e: Exception) {
            // An unexpected synchronous throw from the SDK itself, on our
            // own calling thread (not the SDK's callback stack) — must
            // still end this attempt with a sanitized error instead of
            // leaving the watchdog as the only thing standing between this
            // and an infinite spinner.
            wifiAttempts.endAttempt(attemptId)
            cancelWifiWatchdog()
            Log.e(TAG, "wifi rejected (provision() threw synchronously)")
            cleanupConnection()
            result.error("send_failed", "Unable to start Wi-Fi provisioning", null)
            return
        }
        result.success(null)
    }

    /**
     * Runs [body], guaranteeing no exception escapes back into the SDK's
     * own `ProvisionListener` callback stack — see [sendWifiCredentials].
     */
    private inline fun sdkCallback(body: () -> Unit) {
        try {
            body()
        } catch (t: Throwable) {
            Log.e(TAG, "wifi rejected (ProvisionListener callback threw)")
        }
    }

    /** Ends [attemptId], cancels the watchdog, disconnects, and reports [reason] to Dart. */
    private fun failAttempt(attemptId: Int, reason: String) {
        wifiAttempts.endAttempt(attemptId)
        cancelWifiWatchdog()
        cleanupConnection()
        wifiEventSink?.success(mapOf("event" to "wifiFailed", "reason" to reason))
    }

    private fun cleanupConnection() {
        wifiAttempts.endActiveAttempt()
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
