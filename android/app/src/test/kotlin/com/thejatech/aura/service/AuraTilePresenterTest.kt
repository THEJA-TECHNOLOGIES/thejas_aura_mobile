package com.thejatech.aura.service

import android.service.quicksettings.Tile
import com.thejatech.aura.model.AuraTunnelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AuraTilePresenterTest {

    private lateinit var fakeStrings: TileStringResources

    @Before
    fun setUp() {
        fakeStrings = object : TileStringResources {
            override val protectedLabel: String = "Protected"
            override val offLabel: String = "Off"
            override val connectingLabel: String = "Connecting…"
            override val disconnectingLabel: String = "Disconnecting…"
            override val setupNeededLabel: String = "Tap to set up"
        }
    }

    @Test
    fun testPresentation_ConsentMissing_ReturnsInactiveWithSetupNeeded() {
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = false,
            status = AuraTunnelStatus.DISCONNECTED,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_INACTIVE, presentation.state)
        assertEquals("Tap to set up", presentation.subtitle)
        assertTrue(presentation.isActionable)
    }

    @Test
    fun testPresentation_Connected_ReturnsActiveWithProtected() {
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = true,
            status = AuraTunnelStatus.CONNECTED,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_ACTIVE, presentation.state)
        assertEquals("Protected", presentation.subtitle)
    }

    @Test
    fun testPresentation_Connecting_ReturnsInactiveWithConnecting() {
        // Requirement 3: A start request must not immediately display ON; wait for the service's actual CONNECTED status.
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = true,
            status = AuraTunnelStatus.CONNECTING,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_INACTIVE, presentation.state)
        assertEquals("Connecting…", presentation.subtitle)
    }

    @Test
    fun testPresentation_Disconnecting_ReturnsActiveWithDisconnecting() {
        // Requirement 4: A stop request must update the tile after the service has actually stopped.
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = true,
            status = AuraTunnelStatus.DISCONNECTING,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_ACTIVE, presentation.state)
        assertEquals("Disconnecting…", presentation.subtitle)
    }

    @Test
    fun testPresentation_Disconnected_ReturnsInactiveWithOff() {
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = true,
            status = AuraTunnelStatus.DISCONNECTED,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_INACTIVE, presentation.state)
        assertEquals("Off", presentation.subtitle)
    }

    @Test
    fun testPresentation_Invalid_ReturnsInactiveWithOff() {
        val presentation = AuraTilePresenter.determinePresentation(
            isVpnPrepared = true,
            status = AuraTunnelStatus.INVALID,
            strings = fakeStrings
        )

        assertEquals(Tile.STATE_INACTIVE, presentation.state)
        assertEquals("Off", presentation.subtitle)
    }
}
