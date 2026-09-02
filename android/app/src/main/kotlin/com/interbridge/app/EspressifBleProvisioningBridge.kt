package com.interbridge.app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.espressif.provisioning.DeviceConnectionEvent
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_CONNECTED
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_CONNECTION_FAILED
import com.espressif.provisioning.ESPConstants.EVENT_DEVICE_DISCONNECTED
import com.espressif.provisioning.ESPConstants.SecurityType.SECURITY_1
import com.espressif.provisioning.ESPConstants.TransportType.TRANSPORT_BLE
import com.espressif.provisioning.ESPDevice
import com.espressif.provisioning.ESPProvisionManager
import com.espressif.provisioning.listeners.BleScanListener
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
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingConnectionResult: MethodChannel.Result? = null
    private var espDevice: ESPDevice? = null
    private var scanning = false

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(this)
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

    private fun cleanupConnection() {
        stopScan()
        espDevice?.disconnectDevice()
        espDevice = null
        pendingConnectionResult = null
        candidates.clear(); handlesByAddress.clear()
    }

    fun dispose() { cleanupConnection(); eventSink = null; if (EventBus.getDefault().isRegistered(this)) EventBus.getDefault().unregister(this) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null; stopScan() }

    companion object {
        private const val METHODS = "interapp/ble_onboarding"
        private const val EVENTS = "interapp/ble_onboarding/discovery"
        private const val PREFIX = "InterBridge-"
        private const val PERMISSION_REQUEST = 4412
    }
}
