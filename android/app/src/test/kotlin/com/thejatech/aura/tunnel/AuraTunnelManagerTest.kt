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
    fun testMultipleListeners_ReceiveStatusUpdates() {
        var listener1Status: AuraTunnelStatus? = null
        var listener2Status: AuraTunnelStatus? = null

        val listener1: (AuraTunnelStatus) -> Unit = { listener1Status = it }
        val listener2: (AuraTunnelStatus) -> Unit = { listener2Status = it }

        manager.addStatusListener(listener1)
        manager.addStatusListener(listener2)

        // Initial replay on registration
        assertEquals(AuraTunnelStatus.DISCONNECTED, listener1Status)
        assertEquals(AuraTunnelStatus.DISCONNECTED, listener2Status)

        // Update status
        manager.updateStatus(null, AuraTunnelStatus.CONNECTED)
        assertEquals(AuraTunnelStatus.CONNECTED, listener1Status)
        assertEquals(AuraTunnelStatus.CONNECTED, listener2Status)

        // Remove listener 1
        manager.removeStatusListener(listener1)
        manager.updateStatus(null, AuraTunnelStatus.DISCONNECTED)

        // listener 1 should remain CONNECTED, listener 2 should be DISCONNECTED
        assertEquals(AuraTunnelStatus.CONNECTED, listener1Status)
        assertEquals(AuraTunnelStatus.DISCONNECTED, listener2Status)
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
