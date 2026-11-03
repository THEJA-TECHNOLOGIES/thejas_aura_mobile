package com.thejatech.aura.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AuraPreferencesTest {

    @Test
    fun testPreferencesConstants() {
        assertEquals("aura_preferences", AuraPreferences.PREFS_NAME)
        assertEquals("firewall_desired_enabled", AuraPreferences.KEY_FIREWALL_DESIRED_ENABLED)
        assertEquals("enabled", AuraPreferences.POLICY_ENABLED)
        assertEquals("paused", AuraPreferences.POLICY_PAUSED)
        assertEquals("manually_disabled", AuraPreferences.POLICY_MANUALLY_DISABLED)
    }

    @Test
    fun testSnapshot_WhenPausedAndNotExpired_IsPausedIsTrue() {
        val futureExpiry = System.currentTimeMillis() + 60_000L
        val snapshot = VpnPolicySnapshot(AuraPreferences.POLICY_PAUSED, futureExpiry)
        assertTrue(snapshot.isPaused())
        assertEquals(AuraPreferences.POLICY_PAUSED, snapshot.mode)
        assertEquals(futureExpiry, snapshot.pauseExpiryUtcMillis)
    }

    @Test
    fun testSnapshot_WhenPausedAndExpired_IsPausedIsFalse() {
        val pastExpiry = System.currentTimeMillis() - 1_000L
        val snapshot = VpnPolicySnapshot(AuraPreferences.POLICY_PAUSED, pastExpiry)
        assertFalse(snapshot.isPaused())
    }

    @Test
    fun testSnapshot_WhenExplicitlyEnabled_IsPausedIsFalse() {
        val snapshot = VpnPolicySnapshot(AuraPreferences.POLICY_ENABLED, 0L)
        assertFalse(snapshot.isPaused())
        assertEquals(AuraPreferences.POLICY_ENABLED, snapshot.mode)
    }

    @Test
    fun testSnapshot_WhenManuallyDisabled_IsPausedIsFalse() {
        val snapshot = VpnPolicySnapshot(AuraPreferences.POLICY_MANUALLY_DISABLED, 0L)
        assertFalse(snapshot.isPaused())
        assertEquals(AuraPreferences.POLICY_MANUALLY_DISABLED, snapshot.mode)
    }
}
