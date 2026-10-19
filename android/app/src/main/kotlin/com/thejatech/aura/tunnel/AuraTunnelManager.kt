package com.thejatech.aura.tunnel

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.service.AuraVpnService

class AuraTunnelManager private constructor() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentStatus: AuraTunnelStatus = AuraTunnelStatus.DISCONNECTED

    var onStatusChanged: ((AuraTunnelStatus) -> Unit)? = null
        set(value) {
            field = value
            value?.let { cb ->
                mainHandler.post { cb(currentStatus) }
            }
        }

    fun getStatus(): AuraTunnelStatus = synchronized(this) { currentStatus }

    fun updateStatus(newStatus: AuraTunnelStatus) {
        synchronized(this) {
            if (currentStatus == newStatus) return
            currentStatus = newStatus
        }
        mainHandler.post {
            onStatusChanged?.invoke(newStatus)
        }
    }

    fun startTunnel(context: Context) {
        updateStatus(AuraTunnelStatus.CONNECTING)
        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_START
        }
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Exception) {
            updateStatus(AuraTunnelStatus.DISCONNECTED)
            throw e
        }
    }

    fun stopTunnel(context: Context) {
        updateStatus(AuraTunnelStatus.DISCONNECTING)
        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_STOP
        }
        try {
            context.startService(intent)
        } catch (_: Exception) {
            updateStatus(AuraTunnelStatus.DISCONNECTED)
        }
    }

    fun notifyRulesUpdated(context: Context) {
        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_RELOAD_RULES
        }
        try {
            context.startService(intent)
        } catch (_: Exception) {}
    }

    fun notifyCategoriesUpdated(context: Context) {
        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_RELOAD_CATEGORIES
        }
        try {
            context.startService(intent)
        } catch (_: Exception) {}
    }

    fun notifyDefaultOverridesUpdated(context: Context) {
        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_RELOAD_DEFAULT_OVERRIDES
        }
        try {
            context.startService(intent)
        } catch (_: Exception) {}
    }

    companion object {
        val shared: AuraTunnelManager by lazy { AuraTunnelManager() }
    }
}
