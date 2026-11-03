package com.thejatech.aura.tunnel

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.service.AuraTileService
import com.thejatech.aura.service.AuraVpnService
import com.thejatech.aura.storage.AuraPreferences
import java.util.concurrent.CopyOnWriteArrayList

class AuraTunnelManager internal constructor() {

    private val mainHandler by lazy {
        try {
            Handler(Looper.getMainLooper())
        } catch (_: Throwable) {
            null
        }
    }
    private var currentStatus: AuraTunnelStatus = AuraTunnelStatus.DISCONNECTED
    private var lastTransitionTime: Long = 0L
    private val DEBOUNCE_MS = 600L
    private val statusListeners = CopyOnWriteArrayList<(AuraTunnelStatus) -> Unit>()

    var onStatusChanged: ((AuraTunnelStatus) -> Unit)? = null
        set(value) {
            field?.let { removeStatusListener(it) }
            field = value
            value?.let { addStatusListener(it) }
        }

    fun addStatusListener(listener: (AuraTunnelStatus) -> Unit) {
        if (!statusListeners.contains(listener)) {
            statusListeners.add(listener)
        }
        val status = getStatus()
        val handler = mainHandler
        if (handler != null) {
            handler.post { listener(status) }
        } else {
            listener(status)
        }
    }

    fun removeStatusListener(listener: (AuraTunnelStatus) -> Unit) {
        statusListeners.remove(listener)
    }

    /**
     * Returns true if a connect or disconnect transition is currently active or within debounce window.
     */
    fun isTransitioning(): Boolean = synchronized(this) {
        val now = System.currentTimeMillis()
        (currentStatus == AuraTunnelStatus.CONNECTING ||
         currentStatus == AuraTunnelStatus.DISCONNECTING ||
         (now - lastTransitionTime) < DEBOUNCE_MS)
    }

    /**
     * Returns the reconciled status of the tunnel.
     * If context is provided, reconciles in-memory status against actual running service state.
     */
    fun getStatus(context: Context? = null): AuraTunnelStatus = synchronized(this) {
        if (context != null) {
            reconcileState()
        }
        currentStatus
    }

    private fun reconcileState() {
        val isServiceActive = AuraVpnService.isServiceActive
        if (isServiceActive && currentStatus != AuraTunnelStatus.CONNECTED && currentStatus != AuraTunnelStatus.DISCONNECTING) {
            currentStatus = AuraTunnelStatus.CONNECTED
        } else if (!isServiceActive && currentStatus == AuraTunnelStatus.CONNECTED) {
            currentStatus = AuraTunnelStatus.DISCONNECTED
        }
    }

    fun updateStatus(context: Context? = null, newStatus: AuraTunnelStatus) {
        synchronized(this) {
            if (currentStatus == newStatus) return
            currentStatus = newStatus
            lastTransitionTime = System.currentTimeMillis()
        }
        val handler = mainHandler
        for (listener in statusListeners) {
            if (handler != null) {
                handler.post { listener(newStatus) }
            } else {
                listener(newStatus)
            }
        }
        if (context != null) {
            AuraTileService.requestTileUpdate(context)
        }
    }

    // Overload for backward compatibility with existing calls without context
    fun updateStatus(newStatus: AuraTunnelStatus) {
        updateStatus(null, newStatus)
    }

    fun startTunnel(context: Context) {
        AuraPreferences.setPolicyEnabled(context)

        if (AuraVpnService.isServiceActive) {
            // Tunnel is already running: notify service to resume active filtering immediately
            AuraVpnService.reloadPolicy(context)
            updateStatus(context, AuraTunnelStatus.CONNECTED)
            return
        }

        synchronized(this) {
            if (currentStatus == AuraTunnelStatus.CONNECTING) {
                return
            }
            lastTransitionTime = System.currentTimeMillis()
        }

        updateStatus(context, AuraTunnelStatus.CONNECTING)

        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_START
        }
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (e: Exception) {
            updateStatus(context, AuraTunnelStatus.DISCONNECTED)
            throw e
        }
    }

    fun pauseTunnel(context: Context, durationMillis: Long) {
        val expiry = System.currentTimeMillis() + durationMillis
        AuraPreferences.setPolicyPaused(context, expiry)

        if (AuraVpnService.isServiceActive) {
            // Passthrough architecture: DO NOT STOP TUNNEL!
            // Notify service to reload policy snapshot and enter DNS passthrough mode
            AuraVpnService.reloadPolicy(context)
            updateStatus(context, AuraTunnelStatus.CONNECTED)
        } else {
            // Tunnel was not active; start it
            startTunnel(context)
        }
    }

    fun shutdownTunnel(context: Context) {
        AuraPreferences.setPolicyManuallyDisabled(context)
        stopTunnel(context)
    }

    fun stopTunnel(context: Context) {
        synchronized(this) {
            if (currentStatus == AuraTunnelStatus.DISCONNECTED || currentStatus == AuraTunnelStatus.DISCONNECTING) {
                return
            }
            lastTransitionTime = System.currentTimeMillis()
        }

        // Persist desired state
        AuraPreferences.setFirewallDesired(context, false)
        updateStatus(context, AuraTunnelStatus.DISCONNECTING)

        val intent = Intent(context, AuraVpnService::class.java).apply {
            action = AuraVpnService.ACTION_STOP
        }
        try {
            context.startService(intent)
        } catch (_: Exception) {
            updateStatus(context, AuraTunnelStatus.DISCONNECTED)
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
