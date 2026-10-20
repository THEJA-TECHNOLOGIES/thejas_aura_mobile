package com.thejatech.aura.storage

import org.junit.Assert.assertEquals
import org.junit.Test

class AuraPreferencesTest {

    @Test
    fun testPreferencesConstants() {
        assertEquals("aura_preferences", AuraPreferences.PREFS_NAME)
        assertEquals("firewall_desired_enabled", AuraPreferences.KEY_FIREWALL_DESIRED_ENABLED)
    }
}
