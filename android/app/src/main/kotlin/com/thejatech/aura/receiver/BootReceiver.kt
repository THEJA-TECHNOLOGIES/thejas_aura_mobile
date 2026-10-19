package com.thejatech.aura.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.thejatech.aura.service.AuraVpnService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Ensure periodic background blocklist sync is scheduled
            try {
                com.thejatech.aura.sync.AuraSyncManager.schedulePeriodicSync(context)
            } catch (_: Exception) {}

            // Check if VPN permission has already been prepared/granted
            val prepareIntent = VpnService.prepare(context)
            if (prepareIntent == null) {
                // Permission already granted, restart service if configured
                val vpnIntent = Intent(context, AuraVpnService::class.java).apply {
                    action = AuraVpnService.ACTION_START
                }
                try {
                    ContextCompat.startForegroundService(context, vpnIntent)
                } catch (_: Exception) {}
            }
        }
    }
}
