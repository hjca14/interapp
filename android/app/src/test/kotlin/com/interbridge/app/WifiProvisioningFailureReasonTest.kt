package com.interbridge.app

import com.espressif.provisioning.ESPConstants.ProvisionFailureReason
import org.junit.Assert.assertEquals
import org.junit.Test

class WifiProvisioningFailureReasonTest {
    @Test
    fun `AUTH_FAILED maps to authFailed`() {
        assertEquals("authFailed", wifiFailureReasonCode(ProvisionFailureReason.AUTH_FAILED))
    }

    @Test
    fun `NETWORK_NOT_FOUND maps to networkNotFound`() {
        assertEquals(
            "networkNotFound",
            wifiFailureReasonCode(ProvisionFailureReason.NETWORK_NOT_FOUND),
        )
    }

    @Test
    fun `DEVICE_DISCONNECTED maps to deviceDisconnected`() {
        assertEquals(
            "deviceDisconnected",
            wifiFailureReasonCode(ProvisionFailureReason.DEVICE_DISCONNECTED),
        )
    }

    @Test
    fun `UNKNOWN maps to unknown`() {
        assertEquals("unknown", wifiFailureReasonCode(ProvisionFailureReason.UNKNOWN))
    }
}
