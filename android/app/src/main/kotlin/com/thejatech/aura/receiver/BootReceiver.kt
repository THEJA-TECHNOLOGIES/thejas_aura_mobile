package com.thejatech.aura.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.thejatech.aura.storage.AuraPreferences
import com.thejatech.aura.tunnel.AuraTunnelManager

class BootReceiver : BroadcastReceiver() {

    companion object {
        /**
         * Evaluates whether the VPN should be automatically started upon boot completion.
         * Explicit user policy MUST permit recovery, VPN consent MUST be present,
         * and auto-restart setting MUST be enabled.
         */
        fun shouldStartOnBoot(
            isAutoRecoveryPermitted: Boolean,
            isVpnPrepared: Boolean,
            isAutoRestartEnabled: Boolean = true
        ): Boolean {
            return isAutoRecoveryPermitted && isVpnPrepared && isAutoRestartEnabled
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Ensure periodic background blocklist sync is scheduled
            try {
                com.thejatech.aura.sync.AuraSyncManager.schedulePeriodicSync(context)
            } catch (_: Exception) {}

            // Check authoritative policy
            val isAutoRecoveryAllowed = AuraPreferences.isAutoRecoveryPermitted(context)
            val isPrepared = VpnService.prepare(context) == null
            val isAutoRestart = AuraPreferences.isAutoRestartEnabled(context)
            val policyMode = AuraPreferences.getPolicyMode(context)

            if (policyMode == AuraPreferences.POLICY_PAUSED && !isAutoRecoveryAllowed) {
                // Device rebooted during an active pause: preserve the original expiry timestamp
                // and reschedule the pause expiry worker for the remaining duration.
                val remainingMillis = AuraPreferences.getPauseExpiryMillis(context) - System.currentTimeMillis()
                if (remainingMillis > 0) {
                    com.thejatech.aura.service.VpnPauseWorker.schedulePauseExpiry(context, remainingMillis)
                }
            }

            if (shouldStartOnBoot(
                    isAutoRecoveryPermitted = isAutoRecoveryAllowed,
                    isVpnPrepared = isPrepared,
                    isAutoRestartEnabled = isAutoRestart
                )
            ) {
                try {
                    AuraTunnelManager.shared.startTunnel(context)
                } catch (_: Exception) {}
            }
        }
    }
}
