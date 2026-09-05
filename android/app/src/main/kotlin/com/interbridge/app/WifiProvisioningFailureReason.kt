package com.interbridge.app

import com.espressif.provisioning.ESPConstants.ProvisionFailureReason

/**
 * Maps the Espressif SDK's device-reported Wi-Fi provisioning failure reason
 * to the sanitized string code sent to Dart over `interapp/ble_onboarding/wifi`.
 * A pure, top-level function (unlike [EspressifBleProvisioningBridge], which
 * needs a real Activity/FlutterEngine) so it is directly unit-testable.
 */
fun wifiFailureReasonCode(reason: ProvisionFailureReason): String = when (reason) {
    ProvisionFailureReason.AUTH_FAILED -> "authFailed"
    ProvisionFailureReason.NETWORK_NOT_FOUND -> "networkNotFound"
    ProvisionFailureReason.DEVICE_DISCONNECTED -> "deviceDisconnected"
    else -> "unknown"
}
