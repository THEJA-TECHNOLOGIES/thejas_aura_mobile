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
         * Explicit user intent (desired enabled) MUST be true, and VPN consent MUST be present.
         */
        fun shouldStartOnBoot(isFirewallDesired: Boolean, isVpnPrepared: Boolean): Boolean {
            return isFirewallDesired && isVpnPrepared
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Ensure periodic background blocklist sync is scheduled
            try {
                com.thejatech.aura.sync.AuraSyncManager.schedulePeriodicSync(context)
            } catch (_: Exception) {}

            // Behavioral requirement 1 & 7: Explicit OFF must remain OFF across device reboot.
            val isDesired = AuraPreferences.isFirewallDesired(context)
            val isPrepared = VpnService.prepare(context) == null

            if (shouldStartOnBoot(isFirewallDesired = isDesired, isVpnPrepared = isPrepared)) {
                try {
                    AuraTunnelManager.shared.startTunnel(context)
                } catch (_: Exception) {}
            }
        }
    }
}
