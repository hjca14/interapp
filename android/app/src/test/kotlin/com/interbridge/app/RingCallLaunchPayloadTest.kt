package com.interbridge.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RingCallLaunchPayloadTest {
    private val validEventId = "evt-" + "a".repeat(32)
    private val validCallId = "call-" + "c".repeat(32)
    private val validDeviceId = "ib-" + "b".repeat(32)

    private fun validPayload(
        v: String = "2",
        eventId: String = "\"$validEventId\"",
        callId: String = "\"$validCallId\"",
        deviceId: String = "\"$validDeviceId\"",
        occurredAt: String = "\"2026-01-01T00:00:00Z\"",
    ) = """{"v":$v,"event_id":$eventId,"call_id":$callId,"device_id":$deviceId,"occurred_at":$occurredAt}"""

    @Test
    fun `a well-formed RingCallIntent v2 payload is valid`() {
        assertTrue(isValidRingCallLaunchPayload(validPayload()))
    }

    @Test
    fun `null payload is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(null))
    }

    @Test
    fun `empty payload is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(""))
    }

    @Test
    fun `payload that is not JSON is invalid`() {
        assertFalse(isValidRingCallLaunchPayload("not json at all"))
    }

    @Test
    fun `arbitrary JSON object unrelated to RingCallIntent is invalid`() {
        assertFalse(isValidRingCallLaunchPayload("""{"foo":"bar"}"""))
    }

    @Test
    fun `a pre-call_id v1 payload is invalid`() {
        val v1Payload =
            """{"v":1,"event_id":"$validEventId","device_id":"$validDeviceId",""" +
                """"occurred_at":"2026-01-01T00:00:00Z"}"""
        assertFalse(isValidRingCallLaunchPayload(v1Payload))
    }

    @Test
    fun `a NOTIFICATION_ONLY tap's device-event payload never validates as a call`() {
        val deviceEventPayload = """{"v":1,"kind":"DEVICE_EVENT","device_id":"$validDeviceId"}"""
        assertFalse(isValidRingCallLaunchPayload(deviceEventPayload))
    }

    @Test
    fun `payload with an extra field beyond the v2 contract is invalid`() {
        val withExtra =
            """{"v":2,"event_id":"$validEventId","call_id":"$validCallId",""" +
                """"device_id":"$validDeviceId","occurred_at":"2026-01-01T00:00:00Z","extra":"x"}"""
        assertFalse(isValidRingCallLaunchPayload(withExtra))
    }

    @Test
    fun `payload missing a required field is invalid`() {
        val missingDeviceId =
            """{"v":2,"event_id":"$validEventId","call_id":"$validCallId",""" +
                """"occurred_at":"2026-01-01T00:00:00Z"}"""
        assertFalse(isValidRingCallLaunchPayload(missingDeviceId))
    }

    @Test
    fun `wrong contract version is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(v = "1")))
    }

    @Test
    fun `version encoded as a string instead of a number is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(v = "\"2\"")))
    }

    @Test
    fun `malformed event_id is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(eventId = "\"not-an-event-id\"")))
    }

    @Test
    fun `malformed call_id is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(callId = "\"not-a-call-id\"")))
    }

    @Test
    fun `malformed device_id is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(deviceId = "\"not-a-device-id\"")))
    }

    @Test
    fun `event_id encoded as a number instead of a string is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(eventId = "123")))
    }

    @Test
    fun `call_id encoded as a number instead of a string is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(callId = "123")))
    }

    @Test
    fun `occurred_at without a UTC Z suffix is invalid`() {
        assertFalse(
            isValidRingCallLaunchPayload(validPayload(occurredAt = "\"2026-01-01T00:00:00+00:00\"")),
        )
    }

    @Test
    fun `occurred_at that is not a parseable timestamp is invalid`() {
        assertFalse(isValidRingCallLaunchPayload(validPayload(occurredAt = "\"not-a-timestamp\"")))
    }

    @Test
    fun `an ordinary non-ring notification payload extra never validates`() {
        assertFalse(isValidRingCallLaunchPayload("some-other-notification-id"))
    }

    @Test
    fun `a legacy RING_DETECTED's derived call_id (call- plus the event_id's own 32 hex suffix, not the raw evt- prefixed event_id) validates like any other call_id`() {
        val derivedCallId = "call-" + "a".repeat(32)
        assertTrue(isValidRingCallLaunchPayload(validPayload(callId = "\"$derivedCallId\"")))
    }
}
