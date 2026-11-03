package com.thejatech.aura.storage

import android.content.Context
import android.content.SharedPreferences

/**
 * Single source of truth for persistent user intent regarding the Aura Firewall state.
 */
object AuraPreferences {
    const val PREFS_NAME = "aura_preferences"
    const val KEY_FIREWALL_DESIRED_ENABLED = "firewall_desired_enabled"
    const val KEY_AUTO_RESTART_ENABLED = "auto_restart_enabled"
    const val KEY_LOG_RETENTION_DAYS = "log_retention_days"
    const val DEFAULT_RETENTION_DAYS = 30

    // Authoritative VPN Policy Modes
    const val POLICY_ENABLED = "enabled"
    const val POLICY_PAUSED = "paused"
    const val POLICY_MANUALLY_DISABLED = "manually_disabled"

    const val KEY_VPN_POLICY_MODE = "vpn_policy_mode"
    const val KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS = "vpn_pause_expiry_utc_millis"
    const val KEY_SYSTEM_ALWAYS_ON = "system_always_on"
    const val KEY_SYSTEM_LOCKDOWN = "system_lockdown"

    fun getPreferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Retrieves the authoritative user intent policy mode.
     */
    fun getPolicyMode(context: Context): String {
        return try {
            val prefs = getPreferences(context)
            val mode = prefs.getString(KEY_VPN_POLICY_MODE, null)
            if (mode == POLICY_PAUSED) {
                val expiry = prefs.getLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, 0L)
                val now = System.currentTimeMillis()
                if (expiry > 0L && now >= expiry) {
                    setPolicyEnabled(context)
                    return POLICY_ENABLED
                }
                return POLICY_PAUSED
            } else if (mode != null) {
                mode
            } else {
                if (isFirewallDesired(context)) POLICY_ENABLED else POLICY_MANUALLY_DISABLED
            }
        } catch (_: Exception) {
            POLICY_MANUALLY_DISABLED
        }
    }

    /**
     * Retrieves the absolute UTC timestamp (millis) when the temporary pause expires.
     */
    fun getPauseExpiryMillis(context: Context): Long {
        return try {
            getPreferences(context).getLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, 0L)
        } catch (_: Exception) {
            0L
        }
    }

    /**
     * Sets the policy to explicitly ENABLED.
     * Clears any active pause expiry and marks firewall desired.
     */
    fun setPolicyEnabled(context: Context) {
        try {
            getPreferences(context)
                .edit()
                .putString(KEY_VPN_POLICY_MODE, POLICY_ENABLED)
                .putLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, 0L)
                .putBoolean(KEY_FIREWALL_DESIRED_ENABLED, true)
                .apply()
        } catch (_: Exception) {}
    }

    /**
     * Sets the policy to TEMPORARILY PAUSED until [expiryUtcMillis].
     * In passthrough mode, the tunnel remains active with firewall desired set to true.
     */
    fun setPolicyPaused(context: Context, expiryUtcMillis: Long) {
        try {
            getPreferences(context)
                .edit()
                .putString(KEY_VPN_POLICY_MODE, POLICY_PAUSED)
                .putLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, expiryUtcMillis)
                .putBoolean(KEY_FIREWALL_DESIRED_ENABLED, true)
                .apply()
        } catch (_: Exception) {}
    }

    /**
     * Returns a thread-safe policy snapshot, reconciling any expired pause.
     */
    fun getPolicySnapshot(context: Context): VpnPolicySnapshot {
        return try {
            val prefs = getPreferences(context)
            val mode = prefs.getString(KEY_VPN_POLICY_MODE, null)
            val expiry = prefs.getLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, 0L)
            val now = System.currentTimeMillis()
            if (mode == POLICY_PAUSED && expiry > 0L && now >= expiry) {
                setPolicyEnabled(context)
                VpnPolicySnapshot(POLICY_ENABLED, 0L)
            } else {
                val resolvedMode = mode ?: if (isFirewallDesired(context)) POLICY_ENABLED else POLICY_MANUALLY_DISABLED
                VpnPolicySnapshot(resolvedMode, expiry)
            }
        } catch (_: Exception) {
            VpnPolicySnapshot(POLICY_MANUALLY_DISABLED, 0L)
        }
    }

    /**
     * Sets the policy to MANUALLY DISABLED ("Turn Off Until I Turn It On").
     * Clears pause expiry and suppresses firewall desired state.
     */
    fun setPolicyManuallyDisabled(context: Context) {
        try {
            getPreferences(context)
                .edit()
                .putString(KEY_VPN_POLICY_MODE, POLICY_MANUALLY_DISABLED)
                .putLong(KEY_VPN_PAUSE_EXPIRY_UTC_MILLIS, 0L)
                .putBoolean(KEY_FIREWALL_DESIRED_ENABLED, false)
                .apply()
        } catch (_: Exception) {}
    }

    /**
     * Returns true if application-managed auto-recovery / auto-start is permitted under
     * the authoritative persisted policy.
     * - If manually disabled: false.
     * - If paused and now < expiry: false (suppress auto-reconnect).
     * - If paused and now >= expiry: true (pause has expired, auto-reconnect allowed).
     * - If enabled: true.
     */
    fun isAutoRecoveryPermitted(context: Context): Boolean {
        return try {
            when (getPolicyMode(context)) {
                POLICY_MANUALLY_DISABLED -> false
                POLICY_PAUSED -> {
                    val expiry = getPauseExpiryMillis(context)
                    val now = System.currentTimeMillis()
                    now >= expiry
                }
                POLICY_ENABLED -> true
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }

    fun isSystemAlwaysOn(context: Context): Boolean {
        return try {
            getPreferences(context).getBoolean(KEY_SYSTEM_ALWAYS_ON, false)
        } catch (_: Exception) {
            false
        }
    }

    fun setSystemAlwaysOn(context: Context, active: Boolean) {
        try {
            getPreferences(context).edit().putBoolean(KEY_SYSTEM_ALWAYS_ON, active).apply()
        } catch (_: Exception) {}
    }

    fun isSystemLockdown(context: Context): Boolean {
        return try {
            getPreferences(context).getBoolean(KEY_SYSTEM_LOCKDOWN, false)
        } catch (_: Exception) {
            false
        }
    }

    fun setSystemLockdown(context: Context, active: Boolean) {
        try {
            getPreferences(context).edit().putBoolean(KEY_SYSTEM_LOCKDOWN, active).apply()
        } catch (_: Exception) {}
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

    /**
     * Checks if auto-restart on boot or unexpected termination is enabled.
     * Default is true.
     */
    fun isAutoRestartEnabled(context: Context): Boolean {
        return try {
            val prefs = getPreferences(context)
            if (prefs.contains(KEY_AUTO_RESTART_ENABLED)) {
                prefs.getBoolean(KEY_AUTO_RESTART_ENABLED, true)
            } else if (prefs.contains("vpn_auto_restart_enabled")) {
                prefs.getBoolean("vpn_auto_restart_enabled", true)
            } else {
                true
            }
        } catch (_: Exception) {
            true
        }
    }

    /**
     * Persists the auto-restart preference.
     * Consolidates both keys safely for backwards compatibility.
     */
    fun setAutoRestartEnabled(context: Context, enabled: Boolean) {
        try {
            getPreferences(context)
                .edit()
                .putBoolean(KEY_AUTO_RESTART_ENABLED, enabled)
                .putBoolean("vpn_auto_restart_enabled", enabled)
                .apply()
        } catch (_: Exception) {}
    }

    /**
     * Retrieves the configured log retention period in days (7 or 30).
     * Defaults to 30 days if not set or invalid.
     */
    fun getRetentionDays(context: Context): Int {
        return try {
            val days = getPreferences(context).getInt(KEY_LOG_RETENTION_DAYS, DEFAULT_RETENTION_DAYS)
            if (days == 7 || days == 30) days else DEFAULT_RETENTION_DAYS
        } catch (_: Exception) {
            DEFAULT_RETENTION_DAYS
        }
    }

    /**
     * Persists the configured log retention period in days (7 or 30).
     */
    fun setRetentionDays(context: Context, days: Int) {
        if (days != 7 && days != 30) return
        try {
            getPreferences(context)
                .edit()
                .putInt(KEY_LOG_RETENTION_DAYS, days)
                .apply()
        } catch (_: Exception) {}
    }
}

/**
 * Immutable thread-safe snapshot of the current VPN policy.
 */
data class VpnPolicySnapshot(
    val mode: String,
    val pauseExpiryUtcMillis: Long
) {
    fun isPaused(now: Long = System.currentTimeMillis()): Boolean {
        return mode == AuraPreferences.POLICY_PAUSED && now < pauseExpiryUtcMillis
    }

    fun isExpiredPause(now: Long = System.currentTimeMillis()): Boolean {
        return mode == AuraPreferences.POLICY_PAUSED && now >= pauseExpiryUtcMillis
    }
}

