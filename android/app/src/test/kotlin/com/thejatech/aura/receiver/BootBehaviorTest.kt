package com.thejatech.aura.receiver

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BootBehaviorTest {

    @Test
    fun testShouldStartOnBoot_WhenDesiredAndPrepared_ReturnsTrue() {
        // User turned protection ON, and VPN consent is valid -> Auto-start
        val result = BootReceiver.shouldStartOnBoot(isAutoRecoveryPermitted = true, isVpnPrepared = true)
        assertTrue(result)
    }

    @Test
    fun testShouldStartOnBoot_WhenUserTurnedOffExplicitly_ReturnsFalse() {
        // Behavioral requirement 1 & 7: Explicit OFF must remain OFF across reboot
        val result = BootReceiver.shouldStartOnBoot(isAutoRecoveryPermitted = false, isVpnPrepared = true)
        assertFalse(result)
    }

    @Test
    fun testShouldStartOnBoot_WhenConsentRevoked_ReturnsFalse() {
        // Desired is true, but system consent is missing/revoked -> Must not start
        val result = BootReceiver.shouldStartOnBoot(isAutoRecoveryPermitted = true, isVpnPrepared = false)
        assertFalse(result)
    }

    @Test
    fun testShouldStartOnBoot_WhenNeitherDesiredNorPrepared_ReturnsFalse() {
        val result = BootReceiver.shouldStartOnBoot(isAutoRecoveryPermitted = false, isVpnPrepared = false)
        assertFalse(result)
    }
}
