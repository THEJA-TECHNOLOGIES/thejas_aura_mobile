package com.thejatech.aura.storage

import android.content.Context
import android.content.SharedPreferences

/**
 * Single source of truth for persistent user intent regarding the Aura Firewall state.
 */
object AuraPreferences {
    const val PREFS_NAME = "aura_preferences"
    const val KEY_FIREWALL_DESIRED_ENABLED = "firewall_desired_enabled"

    fun getPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Checks if the user explicitly wants the firewall protection to be enabled.
     * Default is false (explicit opt-in required).
     */
    fun isFirewallDesired(context: Context): Boolean {
        return try {
            getPreferences(context).getBoolean(KEY_FIREWALL_DESIRED_ENABLED, false)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Persists the user's explicit intent to enable or disable the firewall protection.
     */
    fun setFirewallDesired(context: Context, desired: Boolean) {
        try {
            getPreferences(context)
                .edit()
                .putBoolean(KEY_FIREWALL_DESIRED_ENABLED, desired)
                .apply()
        } catch (_: Exception) {}
    }
}
