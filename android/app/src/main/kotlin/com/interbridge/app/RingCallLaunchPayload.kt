package com.interbridge.app

import java.time.Instant
import org.json.JSONException
import org.json.JSONObject

private val EVENT_ID_PATTERN = Regex("^evt-[0-9a-f]{32}$")
private val CALL_ID_PATTERN = Regex("^call-[0-9a-f]{32}$")
private val DEVICE_ID_PATTERN = Regex("^ib-[0-9a-f]{32}$")
private val RING_CALL_INTENT_KEYS =
    setOf("v", "event_id", "call_id", "device_id", "occurred_at")

/**
 * Strictly validates that [payload] matches the minimal `RingCallIntent` v2
 * format produced by `IncomingCallNotificationService.present()` (see
 * `RingCallIntent.serialize()`/`tryRestore()` in ring_call_intent.dart) —
 * an arbitrary `payload` launch extra must never be trusted as a real
 * interphone call. `MainActivity` is exported, so this extra can originate
 * from any launcher Intent, not only ours.
 *
 * Checks structure and types only — exact key set, `v == 2`, `event_id`/
 * `call_id`/`device_id` matching the backend's id formats, and
 * `occurred_at` a parseable UTC instant — not freshness or authorization. It
 * only gates the cosmetic lock-screen presentation
 * ([android.app.Activity.setShowWhenLocked]/
 * [android.app.Activity.setTurnScreenOn]); real authorization and
 * Atender/Dispensar stay entirely inside `IncomingCallPage`. A
 * `NOTIFICATION_ONLY` tap's payload (`DeviceEventNotificationIntent`, a
 * different shape entirely — see device_event_notification_intent.dart)
 * never matches this and so never grants the lock-screen bypass either.
 *
 * Never throws and never logs [payload] — any malformed or unexpected input
 * simply resolves to `false`.
 */
fun isValidRingCallLaunchPayload(payload: String?): Boolean {
    if (payload.isNullOrEmpty()) return false
    return try {
        val json = JSONObject(payload)
        if (json.length() != RING_CALL_INTENT_KEYS.size) return false
        if (json.keys().asSequence().toSet() != RING_CALL_INTENT_KEYS) return false

        if (!isVersionTwo(json.opt("v"))) return false

        val eventId = json.opt("event_id")
        if (eventId !is String || !EVENT_ID_PATTERN.matches(eventId)) return false

        val callId = json.opt("call_id")
        if (callId !is String || !CALL_ID_PATTERN.matches(callId)) return false

        val deviceId = json.opt("device_id")
        if (deviceId !is String || !DEVICE_ID_PATTERN.matches(deviceId)) return false

        val occurredAt = json.opt("occurred_at")
        if (occurredAt !is String || !occurredAt.endsWith("Z")) return false
        Instant.parse(occurredAt)

        true
    } catch (e: JSONException) {
        false
    } catch (e: java.time.format.DateTimeParseException) {
        false
    } catch (e: java.time.DateTimeException) {
        false
    }
}

private fun isVersionTwo(value: Any?): Boolean = when (value) {
    is Int -> value == 2
    is Long -> value == 2L
    else -> false
}
