package com.thejatech.aura.tunnel

import com.thejatech.aura.model.AuraTunnelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AuraTunnelManagerTest {

    private lateinit var manager: AuraTunnelManager

    @Before
    fun setUp() {
        manager = AuraTunnelManager()
    }

    @Test
    fun testInitialStatus_IsDisconnected() {
        assertEquals(AuraTunnelStatus.DISCONNECTED, manager.getStatus())
    }

    @Test
    fun testUpdateStatus_NotifiesCallback() {
        var observedStatus: AuraTunnelStatus? = null
        manager.onStatusChanged = { status ->
            observedStatus = status
        }

        manager.updateStatus(null, AuraTunnelStatus.CONNECTED)

        assertEquals(AuraTunnelStatus.CONNECTED, manager.getStatus())
        assertEquals(AuraTunnelStatus.CONNECTED, observedStatus)
    }

    @Test
    fun testIsTransitioning_DuringConnectingAndDisconnecting() {
        manager.updateStatus(null, AuraTunnelStatus.CONNECTING)
        assertTrue(manager.isTransitioning())

        manager.updateStatus(null, AuraTunnelStatus.DISCONNECTING)
        assertTrue(manager.isTransitioning())
    }

    @Test
    fun testDebounce_PreventsRapidReentry() {
        manager.updateStatus(null, AuraTunnelStatus.CONNECTED)
        // Immediately after status change, debounce window is active
        assertTrue(manager.isTransitioning())

        // Simulate wait beyond 650ms debounce
        Thread.sleep(650)
        assertFalse(manager.isTransitioning())
    }
}
