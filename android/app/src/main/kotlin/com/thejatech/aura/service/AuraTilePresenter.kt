package com.thejatech.aura.service

import android.service.quicksettings.Tile
import com.thejatech.aura.model.AuraTunnelStatus

data class TilePresentation(
    val state: Int,
    val subtitle: String,
    val isActionable: Boolean = true
)

interface TileStringResources {
    val protectedLabel: String
    val offLabel: String
    val connectingLabel: String
    val disconnectingLabel: String
    val setupNeededLabel: String
}

object AuraTilePresenter {
    /**
     * Maps the internal firewall state and permission status to the Android Quick Settings
     * Tile state and user-visible subtitle.
     */
    fun determinePresentation(
        isVpnPrepared: Boolean,
        status: AuraTunnelStatus,
        strings: TileStringResources
    ): TilePresentation {
        if (!isVpnPrepared) {
            return TilePresentation(
                state = Tile.STATE_INACTIVE,
                subtitle = strings.setupNeededLabel,
                isActionable = true
            )
        }

        return when (status) {
            AuraTunnelStatus.CONNECTED -> TilePresentation(
                state = Tile.STATE_ACTIVE,
                subtitle = strings.protectedLabel
            )
            AuraTunnelStatus.CONNECTING -> TilePresentation(
                state = Tile.STATE_INACTIVE,
                subtitle = strings.connectingLabel
            )
            AuraTunnelStatus.DISCONNECTING -> TilePresentation(
                state = Tile.STATE_ACTIVE,
                subtitle = strings.disconnectingLabel
            )
            AuraTunnelStatus.DISCONNECTED, AuraTunnelStatus.INVALID -> TilePresentation(
                state = Tile.STATE_INACTIVE,
                subtitle = strings.offLabel
            )
        }
    }
}
