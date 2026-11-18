package com.thejatech.aura.engine

import com.thejatech.aura.packet.ParsedTcpPacket
import com.thejatech.aura.packet.TcpPacketParser
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class TcpConnectionManagerTest {

    private lateinit var manager: TcpConnectionManager

    private val clientIp = byteArrayOf(10, 0, 0, 2)
    private val auraIp = byteArrayOf(10, 255.toByte(), 255.toByte(), 1)
    private val clientPort = 54321
    private val auraPort = 53

    private val ipv6Client = ByteArray(16).apply { this[15] = 2 }
    private val ipv6Aura = ByteArray(16).apply { this[15] = 1 }

    @Before
    fun setUp() {
        manager = TcpConnectionManager()
    }

    @Test
    fun testThreeWayHandshakeAndEstablished() {
        val clientIsn = 1000L
        val synPacket = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN,
                windowSize = 65535
            )
        )!!

        val result1 = manager.handlePacket(synPacket)
        assertEquals(1, result1.packetsToSend.size)
        assertEquals(0, result1.readyQueries.size)

        // Parse SYN-ACK
        val synAck = TcpPacketParser.parse(result1.packetsToSend[0])!!
        assertTrue(synAck.isSyn)
        assertTrue(synAck.isAck)
        assertEquals(clientIsn + 1, synAck.acknowledgmentNumber)

        val key = TcpConnectionManager.ConnectionKey(clientIp, clientPort, auraIp, auraPort, false)
        val conn = manager.getConnection(key)
        assertNotNull(conn)
        assertEquals(TcpConnectionManager.TcpState.SYN_RCVD, conn!!.state)

        // Duplicate SYN handling
        val dupResult = manager.handlePacket(synPacket)
        assertEquals(1, dupResult.packetsToSend.size) // Retransmitted SYN-ACK

        // Client sends ACK
        val clientAck = TcpPacketParser.parse(
            TcpPacketParser.buildAckPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn + 1,
                acknowledgmentNumber = synAck.sequenceNumber + 1
            )
        )!!

        val result2 = manager.handlePacket(clientAck)
        assertEquals(0, result2.packetsToSend.size)
        assertEquals(TcpConnectionManager.TcpState.ESTABLISHED, conn.state)
    }

    @Test
    fun testDnsQueryProcessing() {
        // Complete handshake
        val connKey = establishConnection(clientIsn = 1000L)
        val conn = manager.getConnection(connKey)!!

        val dnsQuery = "example.com query payload".toByteArray(Charsets.UTF_8)
        val framedDns = ByteArray(2 + dnsQuery.size)
        framedDns[0] = ((dnsQuery.size shr 8) and 0xFF).toByte()
        framedDns[1] = (dnsQuery.size and 0xFF).toByte()
        System.arraycopy(dnsQuery, 0, framedDns, 2, dnsQuery.size)

        val dataPacket = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = framedDns,
                psh = true
            )
        )!!

        val result = manager.handlePacket(dataPacket)
        assertEquals(1, result.readyQueries.size)
        assertArrayEquals(dnsQuery, result.readyQueries[0].dnsPayload)
        assertEquals(connKey, result.readyQueries[0].connectionKey)

        // ACK sent to client
        assertEquals(1, result.packetsToSend.size)
        val ackPacket = TcpPacketParser.parse(result.packetsToSend[0])!!
        assertTrue(ackPacket.isAck)
        assertEquals(conn.expectedSeq, ackPacket.acknowledgmentNumber)
    }

    @Test
    fun testPartialTcpStreamReads() {
        val connKey = establishConnection(clientIsn = 2000L)
        val conn = manager.getConnection(connKey)!!

        val dnsQuery = ByteArray(50) { it.toByte() }
        val framedDns = ByteArray(2 + dnsQuery.size)
        framedDns[0] = ((dnsQuery.size shr 8) and 0xFF).toByte()
        framedDns[1] = (dnsQuery.size and 0xFF).toByte()
        System.arraycopy(dnsQuery, 0, framedDns, 2, dnsQuery.size)

        // Send first chunk (length prefix + 20 bytes)
        val chunk1 = framedDns.copyOfRange(0, 22)
        val packet1 = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = chunk1
            )
        )!!

        val result1 = manager.handlePacket(packet1)
        assertEquals(0, result1.readyQueries.size) // Incomplete, no query emitted yet
        assertEquals(1, result1.packetsToSend.size) // ACK sent for first 22 bytes

        // Send second chunk (remaining 30 bytes)
        val chunk2 = framedDns.copyOfRange(22, 52)
        val packet2 = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = chunk2
            )
        )!!

        val result2 = manager.handlePacket(packet2)
        assertEquals(1, result2.readyQueries.size) // Complete message assembled
        assertArrayEquals(dnsQuery, result2.readyQueries[0].dnsPayload)
        assertEquals(1, result2.packetsToSend.size)
    }

    @Test
    fun testMultipleQueriesPipelined() {
        val connKey = establishConnection(clientIsn = 3000L)
        val conn = manager.getConnection(connKey)!!

        val q1 = "Query 1".toByteArray(Charsets.UTF_8)
        val q2 = "Query 2 Long String".toByteArray(Charsets.UTF_8)

        val stream = ByteArray(2 + q1.size + 2 + q2.size)
        var offset = 0

        stream[offset++] = ((q1.size shr 8) and 0xFF).toByte()
        stream[offset++] = (q1.size and 0xFF).toByte()
        System.arraycopy(q1, 0, stream, offset, q1.size)
        offset += q1.size

        stream[offset++] = ((q2.size shr 8) and 0xFF).toByte()
        stream[offset++] = (q2.size and 0xFF).toByte()
        System.arraycopy(q2, 0, stream, offset, q2.size)

        val packet = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = stream
            )
        )!!

        val result = manager.handlePacket(packet)
        assertEquals(2, result.readyQueries.size)
        assertArrayEquals(q1, result.readyQueries[0].dnsPayload)
        assertArrayEquals(q2, result.readyQueries[1].dnsPayload)
    }

    @Test
    fun testSendDnsResponseAndSegmentation() {
        val connKey = establishConnection(clientIsn = 4000L)
        val conn = manager.getConnection(connKey)!!

        // Small response
        val smallResponse = "DNS Response Small".toByteArray(Charsets.UTF_8)
        val packets1 = manager.sendDnsResponse(connKey, smallResponse)
        assertEquals(1, packets1.size)

        val parsed1 = TcpPacketParser.parse(packets1[0])!!
        assertTrue(parsed1.isPsh)
        assertTrue(parsed1.isAck)
        // Length prefix 2 bytes + payload
        assertEquals(2 + smallResponse.size, parsed1.payload.size)

        // Large response exceeding MSS (e.g. 2500 bytes)
        val largeResponse = ByteArray(2500) { (it % 100).toByte() }
        val packets2 = manager.sendDnsResponse(connKey, largeResponse)
        assertEquals(2, packets2.size) // 1460 bytes + (2502 - 1460) = 1042 bytes

        val parsedChunk1 = TcpPacketParser.parse(packets2[0])!!
        assertEquals(1460, parsedChunk1.payload.size)
        assertFalse(parsedChunk1.isPsh) // First chunk should not have PSH

        val parsedChunk2 = TcpPacketParser.parse(packets2[1])!!
        assertEquals(1042, parsedChunk2.payload.size)
        assertTrue(parsedChunk2.isPsh) // Final chunk has PSH
    }

    @Test
    fun testOutOfOrderSegmentBufferingAndDrain() {
        val connKey = establishConnection(clientIsn = 5000L)
        val conn = manager.getConnection(connKey)!!

        val dnsQuery = ByteArray(40) { it.toByte() }
        val framedDns = ByteArray(2 + dnsQuery.size)
        framedDns[0] = ((dnsQuery.size shr 8) and 0xFF).toByte()
        framedDns[1] = (dnsQuery.size and 0xFF).toByte()
        System.arraycopy(dnsQuery, 0, framedDns, 2, dnsQuery.size)

        val chunk1 = framedDns.copyOfRange(0, 20)
        val chunk2 = framedDns.copyOfRange(20, 42)

        val seq1 = conn.expectedSeq
        val seq2 = seq1 + 20

        // Chunk 2 arrives FIRST (out-of-order)
        val packet2 = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = seq2,
                acknowledgmentNumber = conn.localSeq,
                payload = chunk2
            )
        )!!

        val result2 = manager.handlePacket(packet2)
        assertEquals(0, result2.readyQueries.size)
        assertEquals(1, result2.packetsToSend.size)
        val dupAck = TcpPacketParser.parse(result2.packetsToSend[0])!!
        assertEquals(seq1, dupAck.acknowledgmentNumber) // Duplicate ACK for missing chunk 1

        // Chunk 1 arrives SECOND (in-order)
        val packet1 = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = seq1,
                acknowledgmentNumber = conn.localSeq,
                payload = chunk1
            )
        )!!

        val result1 = manager.handlePacket(packet1)
        assertEquals(1, result1.readyQueries.size) // Both drained and assembled
        assertArrayEquals(dnsQuery, result1.readyQueries[0].dnsPayload)
    }

    @Test
    fun testDuplicateSegmentIgnored() {
        val connKey = establishConnection(clientIsn = 6000L)
        val conn = manager.getConnection(connKey)!!

        val payload = "payload data".toByteArray(Charsets.UTF_8)
        val framed = ByteArray(2 + payload.size)
        framed[0] = 0
        framed[1] = payload.size.toByte()
        System.arraycopy(payload, 0, framed, 2, payload.size)

        val p = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = framed
            )
        )!!

        val r1 = manager.handlePacket(p)
        assertEquals(1, r1.readyQueries.size)

        // Resend identical packet
        val r2 = manager.handlePacket(p)
        assertEquals(0, r2.readyQueries.size) // No duplicate query
        assertEquals(1, r2.packetsToSend.size) // Re-sync ACK sent
    }

    @Test
    fun testSequenceNumber32BitWraparound() {
        val maxUint = 0xFFFFFFFFL

        // Sequence arithmetic tests
        assertTrue(TcpConnectionManager.SequenceNumber.lessThan(maxUint, 5L))
        assertTrue(TcpConnectionManager.SequenceNumber.greaterThan(5L, maxUint))
        assertEquals(4L, TcpConnectionManager.SequenceNumber.add(maxUint, 5L))
        assertEquals(maxUint, TcpConnectionManager.SequenceNumber.sub(5L, 6L))

        // Establish connection near 32-bit boundary
        val boundaryIsn = 0xFFFFFFFEL // 4294967294
        val connKey = establishConnection(clientIsn = boundaryIsn)
        val conn = manager.getConnection(connKey)!!

        // Expected seq is now boundaryIsn + 1 = 0xFFFFFFFFL
        assertEquals(0xFFFFFFFFL, conn.expectedSeq)

        val query = "Wraparound".toByteArray(Charsets.UTF_8)
        val framed = ByteArray(2 + query.size)
        framed[0] = 0
        framed[1] = query.size.toByte()
        System.arraycopy(query, 0, framed, 2, query.size)

        val packet = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = 0xFFFFFFFFL,
                acknowledgmentNumber = conn.localSeq,
                payload = framed
            )
        )!!

        val result = manager.handlePacket(packet)
        assertEquals(1, result.readyQueries.size)
        assertArrayEquals(query, result.readyQueries[0].dnsPayload)
        // Sequence has wrapped around past 0
        val expectedAfterWrap = (0xFFFFFFFFL + framed.size) and 0xFFFFFFFFL
        assertEquals(expectedAfterWrap, conn.expectedSeq)
    }

    @Test
    fun testTeardownFinAndRst() {
        val connKey = establishConnection(clientIsn = 7000L)
        val conn = manager.getConnection(connKey)!!

        // Client sends FIN
        val finPacket = TcpPacketParser.parse(
            TcpPacketParser.buildFinAckPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq
            )
        )!!

        val finResult = manager.handlePacket(finPacket)
        assertEquals(TcpConnectionManager.TcpState.CLOSE_WAIT, conn.state)
        assertEquals(1, finResult.packetsToSend.size) // ACK for FIN

        // Aura initiates close
        val ourFin = manager.closeConnection(connKey)
        assertNotNull(ourFin)
        assertEquals(TcpConnectionManager.TcpState.LAST_ACK, conn.state)

        // Client ACKs our FIN
        val clientAck = TcpPacketParser.parse(
            TcpPacketParser.buildAckPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq
            )
        )!!

        manager.handlePacket(clientAck)
        assertNull(manager.getConnection(connKey))

        // Reset test
        val connKey2 = establishConnection(clientIsn = 8000L)
        val rstPacket = TcpPacketParser.parse(
            TcpPacketParser.buildRstPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = 0L,
                acknowledgmentNumber = 0L
            )
        )!!

        manager.handlePacket(rstPacket)
        assertNull(manager.getConnection(connKey2))
    }

    @Test
    fun testRetransmissionAndTimeout() {
        val connKey = establishConnection(clientIsn = 9000L)
        val conn = manager.getConnection(connKey)!!
        val now = 1000000L

        manager.sendDnsResponse(connKey, "DNS Response".toByteArray(Charsets.UTF_8), now = now)
        assertEquals(1, conn.unackedSegments.size)
        val initialRto = conn.rto

        // Before RTO: no retransmission
        val r0 = manager.checkRetransmissions(now = now + initialRto - 1)
        assertEquals(0, r0.size)

        // At RTO: 1st retransmission, RTO doubles
        val r1 = manager.checkRetransmissions(now = now + initialRto)
        assertEquals(1, r1.size)
        assertEquals(1, conn.unackedSegments[0].retransmitCount)
        assertEquals(initialRto * 2, conn.rto)

        // 2nd retransmission
        val r2 = manager.checkRetransmissions(now = conn.unackedSegments[0].nextRetryTime)
        assertEquals(1, r2.size)
        assertEquals(2, conn.unackedSegments[0].retransmitCount)

        // 3rd retransmission
        val r3 = manager.checkRetransmissions(now = conn.unackedSegments[0].nextRetryTime)
        assertEquals(1, r3.size)
        assertEquals(3, conn.unackedSegments[0].retransmitCount)

        // Exceeded MAX_RETRANSMITS: sends RST and removes connection
        val r4 = manager.checkRetransmissions(now = conn.unackedSegments[0].nextRetryTime)
        assertEquals(1, r4.size)
        val rst = TcpPacketParser.parse(r4[0])!!
        assertTrue(rst.isRst)
        assertNull(manager.getConnection(connKey))
    }

    @Test
    fun testIdleTimeoutAndCapacityLimits() {
        val now = 2000000L
        val connKey = establishConnection(clientIsn = 10000L, now = now)

        // Advance past 30-second idle timeout
        val cleanupPackets = manager.cleanupIdleConnections(now = now + 31000L)
        assertEquals(1, cleanupPackets.size) // RST packet sent
        assertNull(manager.getConnection(connKey))

        // Test capacity eviction
        val smallManager = TcpConnectionManager(maxConnections = 2)
        val k1 = TcpConnectionManager.ConnectionKey(byteArrayOf(10, 0, 0, 1), 1001, auraIp, 53, false)
        val k2 = TcpConnectionManager.ConnectionKey(byteArrayOf(10, 0, 0, 2), 1002, auraIp, 53, false)
        val k3 = TcpConnectionManager.ConnectionKey(byteArrayOf(10, 0, 0, 3), 1003, auraIp, 53, false)

        val syn1 = TcpPacketParser.parse(TcpPacketParser.buildTcpPacket(false, k1.clientIp, auraIp, k1.clientPort, 53, 100L, 0L, ParsedTcpPacket.FLAG_SYN))!!
        val syn2 = TcpPacketParser.parse(TcpPacketParser.buildTcpPacket(false, k2.clientIp, auraIp, k2.clientPort, 53, 200L, 0L, ParsedTcpPacket.FLAG_SYN))!!
        val syn3 = TcpPacketParser.parse(TcpPacketParser.buildTcpPacket(false, k3.clientIp, auraIp, k3.clientPort, 53, 300L, 0L, ParsedTcpPacket.FLAG_SYN))!!

        smallManager.handlePacket(syn1, now = 100)
        smallManager.handlePacket(syn2, now = 200)
        assertEquals(2, smallManager.activeConnectionCount())

        // Third SYN arrives: evicts oldest (k1)
        smallManager.handlePacket(syn3, now = 300)
        assertEquals(2, smallManager.activeConnectionCount())
        assertNull(smallManager.getConnection(k1))
        assertNotNull(smallManager.getConnection(k2))
        assertNotNull(smallManager.getConnection(k3))
    }

    @Test
    fun testIPv6HandshakeAndDataTransfer() {
        val clientIsn = 12345L
        val synPacket = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = true,
                srcIp = ipv6Client,
                dstIp = ipv6Aura,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!

        val result1 = manager.handlePacket(synPacket)
        assertEquals(1, result1.packetsToSend.size)
        val synAck = TcpPacketParser.parse(result1.packetsToSend[0])!!
        assertTrue(synAck.isIPv6)
        assertTrue(synAck.isSyn)
        assertTrue(synAck.isAck)

        val key = TcpConnectionManager.ConnectionKey(ipv6Client, clientPort, ipv6Aura, auraPort, true)
        val conn = manager.getConnection(key)!!

        // Client ACK
        val ackPacket = TcpPacketParser.parse(
            TcpPacketParser.buildAckPacket(
                isIPv6 = true,
                srcIp = ipv6Client,
                dstIp = ipv6Aura,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn + 1,
                acknowledgmentNumber = synAck.sequenceNumber + 1
            )
        )!!
        manager.handlePacket(ackPacket)
        assertEquals(TcpConnectionManager.TcpState.ESTABLISHED, conn.state)

        // Query over IPv6
        val query = "IPv6 DNS Query".toByteArray(Charsets.UTF_8)
        val framed = ByteArray(2 + query.size)
        framed[0] = 0
        framed[1] = query.size.toByte()
        System.arraycopy(query, 0, framed, 2, query.size)

        val queryPacket = TcpPacketParser.parse(
            TcpPacketParser.buildDataPacket(
                isIPv6 = true,
                srcIp = ipv6Client,
                dstIp = ipv6Aura,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = conn.expectedSeq,
                acknowledgmentNumber = conn.localSeq,
                payload = framed
            )
        )!!

        val queryResult = manager.handlePacket(queryPacket)
        assertEquals(1, queryResult.readyQueries.size)
        assertArrayEquals(query, queryResult.readyQueries[0].dnsPayload)
        assertTrue(queryResult.readyQueries[0].connectionKey.isIPv6)
    }

    private fun establishConnection(
        clientIsn: Long,
        now: Long = System.currentTimeMillis()
    ): TcpConnectionManager.ConnectionKey {
        val synPacket = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!
        val r1 = manager.handlePacket(synPacket, now = now)
        val synAck = TcpPacketParser.parse(r1.packetsToSend[0])!!

        val ackPacket = TcpPacketParser.parse(
            TcpPacketParser.buildAckPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = clientPort,
                dstPort = auraPort,
                sequenceNumber = clientIsn + 1,
                acknowledgmentNumber = synAck.sequenceNumber + 1
            )
        )!!
        manager.handlePacket(ackPacket, now = now)

        return TcpConnectionManager.ConnectionKey(clientIp, clientPort, auraIp, auraPort, false)
    }

    @Test
    fun testStrictHalfOpenAdmissionLimit20Accepted21stRejected() {
        // Send 20 SYNs from different ports
        for (i in 0 until 20) {
            val port = 50000 + i
            val syn = TcpPacketParser.parse(
                TcpPacketParser.buildTcpPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 1000L + i,
                    acknowledgmentNumber = 0L,
                    flags = ParsedTcpPacket.FLAG_SYN
                )
            )!!
            val result = manager.handlePacket(syn)
            assertEquals("Expected SYN-ACK for connection $i", 1, result.packetsToSend.size)
            val synAck = TcpPacketParser.parse(result.packetsToSend[0])!!
            assertTrue("Expected SYN flag", synAck.isSyn)
            assertTrue("Expected ACK flag", synAck.isAck)
        }

        assertEquals(20, manager.halfOpenConnectionCount())
        assertEquals(20, manager.activeConnectionCount())

        // 21st SYN must be rejected with RST
        val syn21 = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = 50020,
                dstPort = auraPort,
                sequenceNumber = 1020L,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!
        val result21 = manager.handlePacket(syn21)
        assertEquals(1, result21.packetsToSend.size)
        val rst = TcpPacketParser.parse(result21.packetsToSend[0])!!
        assertTrue("Expected RST for 21st half-open connection", rst.isRst)
        assertEquals(20, manager.halfOpenConnectionCount())

        // Duplicate SYN retransmission for existing connection 0 does not consume capacity
        val dupSyn = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = 50000,
                dstPort = auraPort,
                sequenceNumber = 1000L,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!
        val dupResult = manager.handlePacket(dupSyn)
        assertEquals(1, dupResult.packetsToSend.size)
        val retransmittedSynAck = TcpPacketParser.parse(dupResult.packetsToSend[0])!!
        assertTrue(retransmittedSynAck.isSyn)
        assertTrue(retransmittedSynAck.isAck)
        assertEquals(20, manager.halfOpenConnectionCount())
    }

    @Test
    fun testConcurrentHalfOpenAdmissionAtomicExact20() {
        val totalAttempts = 50
        val synAckCount = java.util.concurrent.atomic.AtomicInteger(0)
        val rstCount = java.util.concurrent.atomic.AtomicInteger(0)
        val executor = java.util.concurrent.Executors.newFixedThreadPool(16)
        val countDownLatch = java.util.concurrent.CountDownLatch(totalAttempts)

        for (i in 0 until totalAttempts) {
            val port = 40000 + i
            executor.submit {
                try {
                    val syn = TcpPacketParser.parse(
                        TcpPacketParser.buildTcpPacket(
                            isIPv6 = false,
                            srcIp = clientIp,
                            dstIp = auraIp,
                            srcPort = port,
                            dstPort = auraPort,
                            sequenceNumber = 5000L + i,
                            acknowledgmentNumber = 0L,
                            flags = ParsedTcpPacket.FLAG_SYN
                        )
                    )!!
                    val result = manager.handlePacket(syn)
                    if (result.packetsToSend.isNotEmpty()) {
                        val packet = TcpPacketParser.parse(result.packetsToSend[0])!!
                        if (packet.isSyn && packet.isAck) {
                            synAckCount.incrementAndGet()
                        } else if (packet.isRst) {
                            rstCount.incrementAndGet()
                        }
                    }
                } finally {
                    countDownLatch.countDown()
                }
            }
        }

        countDownLatch.await(10, java.util.concurrent.TimeUnit.SECONDS)
        executor.shutdown()

        assertEquals("Exactly 20 connections should receive SYN-ACK", 20, synAckCount.get())
        assertEquals("Remaining 30 connections should receive RST", 30, rstCount.get())
        assertEquals("Half-open count should be strictly 20", 20, manager.halfOpenConnectionCount())
    }

    @Test
    fun testConcurrentAdmissionAndTimeoutCleanup() {
        // Admit 20 half-open connections at t=100
        for (i in 0 until 20) {
            val syn = TcpPacketParser.parse(
                TcpPacketParser.buildTcpPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = 30000 + i,
                    dstPort = auraPort,
                    sequenceNumber = 1000L + i,
                    acknowledgmentNumber = 0L,
                    flags = ParsedTcpPacket.FLAG_SYN
                )
            )!!
            manager.handlePacket(syn, now = 100)
        }
        assertEquals(20, manager.halfOpenConnectionCount())

        // Concurrent cleanup at t = 100 + HALF_OPEN_TIMEOUT_MS + 1000 while admitting new SYNs
        val executor = java.util.concurrent.Executors.newFixedThreadPool(8)
        val latch = java.util.concurrent.CountDownLatch(20)

        for (i in 0 until 10) {
            executor.submit {
                try {
                    manager.cleanupIdleConnections(now = 100 + TcpConnectionManager.HALF_OPEN_TIMEOUT_MS + 1000)
                } finally {
                    latch.countDown()
                }
            }
        }
        for (i in 0 until 10) {
            val port = 31000 + i
            executor.submit {
                try {
                    val syn = TcpPacketParser.parse(
                        TcpPacketParser.buildTcpPacket(
                            isIPv6 = false,
                            srcIp = clientIp,
                            dstIp = auraIp,
                            srcPort = port,
                            dstPort = auraPort,
                            sequenceNumber = 2000L + i,
                            acknowledgmentNumber = 0L,
                            flags = ParsedTcpPacket.FLAG_SYN
                        )
                    )!!
                    manager.handlePacket(syn, now = 100 + TcpConnectionManager.HALF_OPEN_TIMEOUT_MS + 1000)
                } finally {
                    latch.countDown()
                }
            }
        }

        latch.await(5, java.util.concurrent.TimeUnit.SECONDS)
        executor.shutdown()

        assertTrue(manager.halfOpenConnectionCount() in 0..20)
        assertTrue(manager.halfOpenConnectionCount() >= 0)
    }

    @Test
    fun testFailedInsertionReleasesReservedCapacity() {
        val port = 25000
        val syn = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = port,
                dstPort = auraPort,
                sequenceNumber = 1234L,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!

        val res1 = manager.handlePacket(syn)
        assertEquals(1, res1.packetsToSend.size)
        assertEquals(1, manager.halfOpenConnectionCount())

        // Repeat same SYN packet (key collision during creation)
        val res2 = manager.handlePacket(syn)
        assertEquals(1, res2.packetsToSend.size)
        assertEquals(1, manager.halfOpenConnectionCount())
    }

    @Test
    fun testConcurrentResetAndConnectionCreation() {
        val executor = java.util.concurrent.Executors.newFixedThreadPool(8)
        val running = java.util.concurrent.atomic.AtomicBoolean(true)
        val exceptions = java.util.concurrent.CopyOnWriteArrayList<Throwable>()

        // 4 threads creating connections
        for (t in 0 until 4) {
            executor.submit {
                var count = 0
                while (running.get() && count < 200) {
                    try {
                        val port = 10000 + (count % 1000)
                        val syn = TcpPacketParser.parse(
                            TcpPacketParser.buildTcpPacket(
                                isIPv6 = false,
                                srcIp = clientIp,
                                dstIp = auraIp,
                                srcPort = port,
                                dstPort = auraPort,
                                sequenceNumber = 100L + count,
                                acknowledgmentNumber = 0L,
                                flags = ParsedTcpPacket.FLAG_SYN
                            )
                        )!!
                        manager.handlePacket(syn)
                        count++
                    } catch (e: Throwable) {
                        exceptions.add(e)
                    }
                }
            }
        }

        // 2 threads calling reset
        for (t in 0 until 2) {
            executor.submit {
                var count = 0
                while (running.get() && count < 100) {
                    try {
                        manager.reset()
                        val halfOpen = manager.halfOpenConnectionCount()
                        assertTrue("Half open should never be negative", halfOpen >= 0)
                        count++
                        Thread.sleep(1)
                    } catch (e: Throwable) {
                        exceptions.add(e)
                    }
                }
            }
        }

        Thread.sleep(500)
        running.set(false)
        executor.shutdown()
        executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)

        assertTrue("No exceptions during concurrent reset & connection creation", exceptions.isEmpty())
        assertTrue("Half open counter never negative", manager.halfOpenConnectionCount() >= 0)

        // Post reset check
        manager.reset()
        assertEquals(0, manager.activeConnectionCount())
        assertEquals(0, manager.halfOpenConnectionCount())
    }

    @Test
    fun testConcurrentResetAndTimeoutCleanup() {
        val executor = java.util.concurrent.Executors.newFixedThreadPool(6)
        val running = java.util.concurrent.atomic.AtomicBoolean(true)
        val exceptions = java.util.concurrent.CopyOnWriteArrayList<Throwable>()

        for (t in 0 until 3) {
            executor.submit {
                var count = 0
                while (running.get() && count < 150) {
                    try {
                        manager.cleanupIdleConnections(now = System.currentTimeMillis() + 50000)
                        count++
                    } catch (e: Throwable) {
                        exceptions.add(e)
                    }
                }
            }
        }

        for (t in 0 until 3) {
            executor.submit {
                var count = 0
                while (running.get() && count < 150) {
                    try {
                        manager.reset()
                        count++
                    } catch (e: Throwable) {
                        exceptions.add(e)
                    }
                }
            }
        }

        Thread.sleep(300)
        running.set(false)
        executor.shutdown()
        executor.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)

        assertTrue("No exceptions during concurrent reset & timeout cleanup", exceptions.isEmpty())
        assertEquals(0, manager.halfOpenConnectionCount())
        assertEquals(0, manager.activeConnectionCount())
    }

    @Test
    fun testCounterEqualsActualSynRcvdCountAtAllTimes() {
        val clientCount = 15
        val synAcks = mutableListOf<ParsedTcpPacket>()

        // 1. Establish 15 half-open
        for (i in 0 until clientCount) {
            val port = 45000 + i
            val syn = TcpPacketParser.parse(
                TcpPacketParser.buildTcpPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 8000L + i,
                    acknowledgmentNumber = 0L,
                    flags = ParsedTcpPacket.FLAG_SYN
                )
            )!!
            val res = manager.handlePacket(syn)
            synAcks.add(TcpPacketParser.parse(res.packetsToSend[0])!!)
        }
        assertEquals(15, manager.halfOpenConnectionCount())

        // 2. Complete handshake for 5 connections -> halfOpenCount should decrease by 5
        for (i in 0 until 5) {
            val port = 45000 + i
            val ack = TcpPacketParser.parse(
                TcpPacketParser.buildAckPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 8001L + i,
                    acknowledgmentNumber = synAcks[i].sequenceNumber + 1
                )
            )!!
            manager.handlePacket(ack)
        }
        assertEquals(10, manager.halfOpenConnectionCount())
        assertEquals(15, manager.activeConnectionCount())

        // 3. Client RST for 3 half-open connections -> halfOpenCount should decrease by 3
        for (i in 5 until 8) {
            val port = 45000 + i
            val rst = TcpPacketParser.parse(
                TcpPacketParser.buildRstPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 8001L + i,
                    acknowledgmentNumber = 0L,
                    isAck = false
                )
            )!!
            manager.handlePacket(rst)
        }
        assertEquals(7, manager.halfOpenConnectionCount())
        assertEquals(12, manager.activeConnectionCount())

        // 4. Timeout cleanup for remaining 7 half-open connections
        manager.cleanupIdleConnections(now = System.currentTimeMillis() + TcpConnectionManager.HALF_OPEN_TIMEOUT_MS + 1000)
        assertEquals(0, manager.halfOpenConnectionCount())
        assertEquals(5, manager.activeConnectionCount()) // Only established connections remain
    }

    @Test
    fun testEstablishedConnectionCapacityRemains100() {
        val smallCapManager = TcpConnectionManager(maxConnections = 100)

        // Establish 100 connections
        for (i in 0 until 100) {
            val port = 10000 + i
            val syn = TcpPacketParser.parse(
                TcpPacketParser.buildTcpPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 1000L + i,
                    acknowledgmentNumber = 0L,
                    flags = ParsedTcpPacket.FLAG_SYN
                )
            )!!
            val r1 = smallCapManager.handlePacket(syn, now = 1000L + i)
            val synAck = TcpPacketParser.parse(r1.packetsToSend[0])!!

            val ack = TcpPacketParser.parse(
                TcpPacketParser.buildAckPacket(
                    isIPv6 = false,
                    srcIp = clientIp,
                    dstIp = auraIp,
                    srcPort = port,
                    dstPort = auraPort,
                    sequenceNumber = 1001L + i,
                    acknowledgmentNumber = synAck.sequenceNumber + 1
                )
            )!!
            smallCapManager.handlePacket(ack, now = 1000L + i)
        }

        assertEquals(100, smallCapManager.activeConnectionCount())
        assertEquals(0, smallCapManager.halfOpenConnectionCount())

        // 101st SYN arrives: evicts oldest connection
        val syn101 = TcpPacketParser.parse(
            TcpPacketParser.buildTcpPacket(
                isIPv6 = false,
                srcIp = clientIp,
                dstIp = auraIp,
                srcPort = 20000,
                dstPort = auraPort,
                sequenceNumber = 9999L,
                acknowledgmentNumber = 0L,
                flags = ParsedTcpPacket.FLAG_SYN
            )
        )!!
        val r101 = smallCapManager.handlePacket(syn101, now = 2000L)
        assertEquals(1, r101.packetsToSend.size)
        val synAck101 = TcpPacketParser.parse(r101.packetsToSend[0])!!
        assertTrue(synAck101.isSyn)
        assertTrue(synAck101.isAck)

        // Capacity capped at 100
        assertEquals(100, smallCapManager.activeConnectionCount())
        assertEquals(1, smallCapManager.halfOpenConnectionCount())
    }

    @Test
    fun testParseRejectsInvalidChecksumDroppingPacket() {
        // Establish a connection first
        val connKey = establishConnection(clientIsn = 10000L)

        // Build a valid data packet with DNS query payload
        val dnsQuery = "example.com query".toByteArray(Charsets.UTF_8)
        val framedDns = ByteArray(2 + dnsQuery.size)
        framedDns[0] = ((dnsQuery.size shr 8) and 0xFF).toByte()
        framedDns[1] = (dnsQuery.size and 0xFF).toByte()
        System.arraycopy(dnsQuery, 0, framedDns, 2, dnsQuery.size)

        // Build raw packet bytes
        val rawPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIp,
            dstIp = auraIp,
            srcPort = clientPort,
            dstPort = auraPort,
            sequenceNumber = 10000L,
            acknowledgmentNumber = 0L,
            payload = framedDns,
            psh = true
        )

        // Parse the valid packet first (should succeed)
        val validParsed = TcpPacketParser.parse(rawPacket, rawPacket.size)
        assertNotNull(validParsed)

        // Corrupt a byte in the TCP payload area (after the 20-byte TCP header)
        val tcpHeaderLen = 20
        val corruptedRaw = rawPacket.copyOf()
        corruptedRaw[tcpHeaderLen + 2] = (corruptedRaw[tcpHeaderLen + 2] + 1).toByte()

        // parse() should reject the packet because checksum no longer matches
        val corruptedParsed = TcpPacketParser.parse(corruptedRaw, corruptedRaw.size)
        assertNull(corruptedParsed)

        // Since parse() returns null, handlePacket() never receives the corrupted packet
        // and the connection state remains unchanged
        val conn = manager.getConnection(connKey)
        assertNotNull(conn)
    }
}
