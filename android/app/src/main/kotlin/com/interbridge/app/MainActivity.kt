package com.interbridge.app

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterFragmentActivity() {
    private lateinit var bleProvisioningBridge: EspressifBleProvisioningBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bleProvisioningBridge = EspressifBleProvisioningBridge(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "interapp/device_timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getIdentifier") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
        // Own channel, not part of flutter_local_notifications: that plugin only
        // exposes requestFullScreenIntentPermission(), which navigates to
        // Settings whenever access is missing. Powers only SecuritySettingsPage's
        // informational status (read-only, never navigates on its own) — never a
        // dependency of whether a RING_DETECTED push requests full-screen, since
        // this handler only exists while MainActivity is alive, which a push
        // arriving through the FCM background isolate cannot guarantee. See
        // IncomingCallNotificationService.present() / full_screen_intent_access.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "interapp/full_screen_intent")
            .setMethodCallHandler { call, result ->
                if (call.method == "canUseFullScreenIntent") {
                    result.success(canUseFullScreenIntent())
                } else {
                    result.notImplemented()
                }
            }
        // Dart calls this whenever a call stops being shown (answered,
        // dismissed, RING_ENDED, or the local ring-timeout) — see
        // ring_call_lock_screen_channel.dart and
        // ringCallLockScreenIntegrationProvider (push_providers.dart). Safe
        // to call even when this launch never used the lock-screen bypass:
        // endRingCallPresentation() below only acts when the device is
        // still actually locked.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "interapp/ring_call_presentation")
            .setMethodCallHandler { call, result ->
                if (call.method == "endPresentation") {
                    endRingCallPresentation()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (::bleProvisioningBridge.isInitialized &&
            bleProvisioningBridge.onRequestPermissionsResult(requestCode, grantResults)
        ) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        if (::bleProvisioningBridge.isInitialized) bleProvisioningBridge.dispose()
        super.onDestroy()
    }

    private fun canUseFullScreenIntent(): Boolean {
        // Below Android 14 (UPSIDE_DOWN_CAKE) this was a normal, install-time
        // permission — there is no special access to check, so it is always
        // available once declared in the manifest.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return notificationManager.canUseFullScreenIntent()
    }

    // Lets the ring-call notification's full-screen intent actually draw over
    // a locked screen and wake it, per Android's documented requirement for
    // full-screen intent target activities. Scoped to only the launch whose
    // "payload" extra strictly validates as a RingCallIntent v2 payload (set
    // exclusively by IncomingCallNotificationService.present — see
    // ring_call_intent.dart and RingCallLaunchPayload.kt) so an ordinary app
    // open or an arbitrary Intent from another app (this Activity is
    // exported) never bypasses the keyguard. A NOTIFICATION_ONLY tap now
    // carries the same RingCallIntent payload shape as a call (both open the
    // same IncomingCallPage — see ring_detected_event.dart's
    // RingPresentationIntentCall.isCall doc) and so validates/bypasses the
    // same way an explicit tap deserves to; only the automatic full-screen
    // presentation itself is call-mode-only, decided entirely on the Dart
    // side before either notification kind is ever shown.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyRingCallLockScreenPresentation(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        applyRingCallLockScreenPresentation(intent)
    }

    private fun applyRingCallLockScreenPresentation(intent: Intent?) {
        val isRingCallLaunch = isValidRingCallLaunchPayload(intent?.getStringExtra("payload"))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(isRingCallLaunch)
            setTurnScreenOn(isRingCallLaunch)
        }
    }

    // Reverts the lock-screen bypass above once a call stops being shown.
    // dropShowWhenLocked() always runs so a later, unrelated locked launch
    // never inherits a stale true from this call — Android does not reset
    // setShowWhenLocked on its own between onCreate/onNewIntent calls on the
    // same Activity instance (singleTop). moveTaskToBack() only runs when the
    // keyguard is still actually engaged: if the user unlocked the device
    // while the call was up, there is no keyguard to return to, and the app
    // should simply keep showing whatever is now underneath the dismissed
    // call overlay, same as any other foreground dismissal.
    private fun endRingCallPresentation() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
        val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (keyguardManager.isKeyguardLocked) {
            moveTaskToBack(true)
        }
    }
}
