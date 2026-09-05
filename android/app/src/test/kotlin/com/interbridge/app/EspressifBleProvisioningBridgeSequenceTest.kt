package com.interbridge.app

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regression guard for a real bench failure: a physical run against the
 * PR #25 firmware showed `ESPDevice.provision(...)` accept `prov-config`
 * (`wifiConfigSent` fired) and then never call back again — no
 * `wifiConfigApplied`, no terminal result — until the app's own watchdog
 * gave up. Decompiling the resolved
 * `com.github.espressif:esp-idf-provisioning-android:lib-2.1.3` AAR
 * (`ESPDevice.class`/`BLETransport.class`, `javap -c`) is what actually
 * proved the fix, not this test: `ESPDevice.provision()`'s own bytecode is
 *
 * ```
 * if (session == null || !session.isEstablished())
 *     initSession(new ResponseListener() {           // ESPDevice$5
 *         onSuccess -> sendWiFiConfig(ssid, password, listener)
 *         onFailure -> listener.createSessionFailed(e)
 *     });
 * else
 *     sendWiFiConfig(ssid, password, listener);
 * ```
 *
 * and `sendWiFiConfig`'s own response handler (`ESPDevice$10.onSuccess`)
 * unconditionally calls `applyWiFiConfig()` next, in the same callback,
 * regardless of how the session was established. `EspressifBleProvisioning
 * Bridge.establishSecurity1(...)` used to call `device.initSession(...)`
 * on its own, fully completing that SDK transaction and returning success
 * to Dart *before* the user was ever shown the Wi-Fi form — holding an
 * already-established session open across an arbitrary, user-paced UI
 * delay that `provision()`'s own designed "not yet established" branch
 * above never needs to survive, and that `BLETransport.sendConfigData()`
 * cannot recover from if a GATT operation silently fails there (it
 * discards `BluetoothGatt.writeCharacteristic(...)`'s boolean result and
 * guards the transport with an unbounded, no-timeout `Semaphore.acquire()`
 * — a known-hazardous pattern on budget Samsung BLE stacks like the
 * Galaxy A12's, per Android's own `BluetoothGatt` documentation on
 * reentrant/back-to-back GATT operations).
 *
 * This module has no Robolectric or Mockito dependency (see
 * `android/app/build.gradle.kts`'s `testImplementation`s — JUnit and
 * `org.json` only), and `ESPDevice`/`BluetoothGatt` are concrete classes
 * from a real Android/SDK stack that cannot be instantiated or mocked in a
 * plain JVM unit test here. This test therefore checks the bridge's own
 * source text for the specific method-call shape the fix requires, rather
 * than exercising real SDK/BLE behavior — a source-level regression guard,
 * not a substitute for physical validation. It fails loudly (not
 * silently) if the source file cannot be found, so it can never pass by
 * accident.
 */
class EspressifBleProvisioningBridgeSequenceTest {
    private fun bridgeSource(): String {
        val candidates = listOf(
            File("src/main/kotlin/com/interbridge/app/EspressifBleProvisioningBridge.kt"),
            File("android/app/src/main/kotlin/com/interbridge/app/EspressifBleProvisioningBridge.kt"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error(
                "EspressifBleProvisioningBridge.kt not found relative to the test working directory " +
                    "(tried: ${candidates.joinToString { it.path }})",
            )
        return file.readText()
    }

    private fun methodBody(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("method signature not found: $signature", start >= 0)
        // Bodies in this file are single top-level functions delimited by
        // brace depth - walk from the first '{' after the signature to its
        // matching close.
        val openBrace = source.indexOf('{', start)
        var depth = 0
        var i = openBrace
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(openBrace, i + 1)
                }
            }
            i++
        }
        error("unterminated method body for: $signature")
    }

    @Test
    fun `establishSecurity1 never calls the SDK's initSession`() {
        val body = methodBody(
            bridgeSource(),
            "private fun establishSecurity1(pop: String?, result: MethodChannel.Result)",
        )
        assertFalse(
            "establishSecurity1 must not call device.initSession(...) - that pre-establishes " +
                "the Security 1 session and returns control to Dart, which then waits, unbounded, " +
                "for the user to type Wi-Fi credentials before ESPDevice.provision() is ever called. " +
                "See this file's class doc for the decompiled evidence of why that stalled a real device.",
            body.contains(".initSession("),
        )
    }

    @Test
    fun `sendWifiCredentials still drives the single continuous provision() transaction`() {
        val body = methodBody(
            bridgeSource(),
            "private fun sendWifiCredentials(ssid: String?, password: String?, result: MethodChannel.Result)",
        )
        assertTrue(
            "sendWifiCredentials must call device.provision(...) - the SDK's own single " +
                "continuous transaction (session establish, if needed, through send/apply/poll)",
            body.contains(".provision("),
        )
        assertTrue(
            "sendWifiCredentials must still handle createSessionFailed - an incorrect PoP now " +
                "surfaces here (via provision()'s own internal initSession, not a separate call) " +
                "rather than in establishSecurity1",
            body.contains("createSessionFailed"),
        )
    }
}
