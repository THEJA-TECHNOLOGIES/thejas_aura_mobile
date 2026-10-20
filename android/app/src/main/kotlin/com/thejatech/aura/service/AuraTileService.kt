package com.thejatech.aura.service

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi
import com.thejatech.aura.R
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.theja_aura.MainActivity
import com.thejatech.aura.tunnel.AuraTunnelManager

@RequiresApi(Build.VERSION_CODES.N)
class AuraTileService : TileService() {

    companion object {
        private const val TAG = "AuraTileService"

        fun requestTileUpdate(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    requestListeningState(
                        context.applicationContext,
                        ComponentName(context.applicationContext, AuraTileService::class.java)
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to request tile update: ${e.message}")
                }
            }
        }
    }

    private val stringResources by lazy {
        object : TileStringResources {
            override val protectedLabel: String
                get() = getString(R.string.qs_tile_subtitle_protected)
            override val offLabel: String
                get() = getString(R.string.qs_tile_subtitle_off)
            override val connectingLabel: String
                get() = getString(R.string.qs_tile_subtitle_connecting)
            override val disconnectingLabel: String
                get() = getString(R.string.qs_tile_subtitle_disconnecting)
            override val setupNeededLabel: String
                get() = getString(R.string.qs_tile_subtitle_setup_needed)
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        // Behavioral requirement 6: Rapid taps must not create competing start/stop operations.
        if (AuraTunnelManager.shared.isTransitioning()) {
            Log.d(TAG, "Tile clicked while transition is active, ignoring rapid tap")
            return
        }

        val isVpnPrepared = VpnService.prepare(this) == null
        val currentStatus = AuraTunnelManager.shared.getStatus(this)

        if (currentStatus == AuraTunnelStatus.CONNECTED) {
            AuraTunnelManager.shared.stopTunnel(this)
            updateTileState()
        } else {
            if (!isVpnPrepared) {
                // Behavioral requirement 5: Missing consent must open existing consent flow through MainActivity
                openConsentFlow()
            } else {
                try {
                    AuraTunnelManager.shared.startTunnel(this)
                    updateTileState()
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start tunnel from tile: ${e.message}")
                    updateTileState()
                }
            }
        }
    }

    private fun openConsentFlow() {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_REQUEST_VPN_CONSENT, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val isVpnPrepared = VpnService.prepare(this) == null
        val currentStatus = AuraTunnelManager.shared.getStatus(this)

        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = isVpnPrepared,
            status = currentStatus,
            strings = stringResources
        )

        tile.state = presentation.state
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_firewall)
        tile.label = getString(R.string.qs_tile_label)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = presentation.subtitle
        }

        tile.updateTile()
    }
}
