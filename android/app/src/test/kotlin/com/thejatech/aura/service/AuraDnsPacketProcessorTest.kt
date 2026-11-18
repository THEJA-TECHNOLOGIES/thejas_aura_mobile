package com.thejatech.aura.service

import com.thejatech.aura.engine.AuraDnsEngine
import com.thejatech.aura.engine.AuraPslValidator
import com.thejatech.aura.engine.TcpConnectionManager
import com.thejatech.aura.model.ActivityRecord
import com.thejatech.aura.model.AuraRuleItem
import com.thejatech.aura.packet.ParsedTcpPacket
import com.thejatech.aura.packet.TcpPacketParser
import com.thejatech.aura.storage.AuraPreferences
import com.thejatech.aura.storage.VpnPolicySnapshot
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class AuraDnsPacketProcessorTest {

    private lateinit var dnsEngine: AuraDnsEngine
    private lateinit var tcpConnectionManager: TcpConnectionManager
    private lateinit var pslValidator: AuraPslValidator
    private lateinit var processor: AuraDnsPacketProcessor

    private val writtenPackets = mutableListOf<ByteArray>()
    private val loggedRecords = mutableListOf<ActivityRecord>()
    private var currentPolicy = VpnPolicySnapshot(AuraPreferences.POLICY_ENABLED, 0L)
    private var reconciledPolicy: VpnPolicySnapshot? = null

    private val clientIpv4 = byteArrayOf(10, 0, 0, 2)
    private val auraIpv4 = byteArrayOf(10, 255.toByte(), 255.toByte(), 1)
    private val clientIpv6 = ByteArray(16).apply { this[15] = 2 }
    private val auraIpv6 = ByteArray(16).apply { this[15] = 1 }
    private val clientPort = 54321
    private val dnsPort = 53

    @Before
    fun setUp() {
        dnsEngine = AuraDnsEngine()
        tcpConnectionManager = TcpConnectionManager()
        pslValidator = AuraPslValidator("""
            com
            org
            net
        """.trimIndent())
        writtenPackets.clear()
        loggedRecords.clear()
        currentPolicy = VpnPolicySnapshot(AuraPreferences.POLICY_ENABLED, 0L)
        reconciledPolicy = null

        processor = AuraDnsPacketProcessor(
            dnsEngine = dnsEngine,
            tcpConnectionManager = tcpConnectionManager,
            pslValidator = pslValidator,
            policyProvider = { currentPolicy },
            onPolicyReconciled = { reconciled ->
                reconciledPolicy = reconciled
                currentPolicy = reconciled
            },
            upstreamResolver = { requestDns ->
                // Default upstream returns synthetic answer echoing request ID
                createSyntheticResponse(requestDns)
            },
            packetWriter = { packet ->
                writtenPackets.add(packet)
            },
            activityLogger = { record ->
                loggedRecords.add(record)
            },
            executor = null // Synchronous execution for unit tests
        )
    }

    @Test
    fun testTcpDnsSynHandshakeAndEstablished() {
        val syn = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 1000L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN
        )

        val handled = processor.processPacket(syn, syn.size)
        assertTrue(handled)
        assertEquals(1, writtenPackets.size)

        val synAck = TcpPacketParser.parse(writtenPackets[0])!!
        assertTrue(synAck.isSyn)
        assertTrue(synAck.isAck)
        assertEquals(1001L, synAck.acknowledgmentNumber)

        val key = TcpConnectionManager.ConnectionKey(clientIpv4, clientPort, auraIpv4, dnsPort, false)
        val conn = tcpConnectionManager.getConnection(key)
        assertNotNull(conn)
        assertEquals(TcpConnectionManager.TcpState.SYN_RCVD, conn!!.state)

        // Client ACKs
        val clientAck = TcpPacketParser.buildAckPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 1001L,
            acknowledgmentNumber = synAck.sequenceNumber + 1L
        )
        processor.processPacket(clientAck, clientAck.size)
        assertEquals(TcpConnectionManager.TcpState.ESTABLISHED, conn.state)
    }

    @Test
    fun testTcpDnsBlockedDomainResponse() {
        dnsEngine.setRules(
            listOf(AuraRuleItem(id = "blocked.com", domain = "blocked.com", isEnabled = true, isBlocked = true))
        )

        val connKey = completeTcpHandshake(clientIsn = 2000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val query = createQueryPacket("blocked.com", 1, txId = 0x1234)
        val framed = frameDns(query)

        val queryPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = framed
        )

        processor.processPacket(queryPacket, queryPacket.size)

        // Should receive TCP ACK and TCP Data packet containing blocked DNS response
        assertTrue(writtenPackets.isNotEmpty())
        val dataPacket = writtenPackets.firstOrNull {
            val p = TcpPacketParser.parse(it)
            p != null && p.payload.isNotEmpty()
        }
        assertNotNull("Must receive TCP packet with payload", dataPacket)

        val parsedData = TcpPacketParser.parse(dataPacket!!)!!
        assertTrue(parsedData.payload.size >= 2)
        val dnsLength = ((parsedData.payload[0].toInt() and 0xFF) shl 8) or (parsedData.payload[1].toInt() and 0xFF)
        val dnsResp = parsedData.payload.copyOfRange(2, 2 + dnsLength)

        val header = AuraDnsEngine.parseHeader(dnsResp)!!
        assertEquals(0x1234, header.id)
        assertEquals(0x8180, header.flags) // Response, NoError
        assertEquals(1, header.anCount)

        // Activity record
        assertEquals(1, loggedRecords.size)
        assertEquals("blocked.com", loggedRecords[0].domain)
        assertEquals("blocked", loggedRecords[0].outcome)
    }

    @Test
    fun testTcpDnsAllowedDomainResolution() {
        val connKey = completeTcpHandshake(clientIsn = 3000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val query = createQueryPacket("allowed.com", 1, txId = 0x5678)
        val framed = frameDns(query)

        val queryPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = framed
        )

        processor.processPacket(queryPacket, queryPacket.size)

        val dataPacket = writtenPackets.firstOrNull {
            val p = TcpPacketParser.parse(it)
            p != null && p.payload.isNotEmpty()
        }
        assertNotNull(dataPacket)

        val parsedData = TcpPacketParser.parse(dataPacket!!)!!
        val dnsLength = ((parsedData.payload[0].toInt() and 0xFF) shl 8) or (parsedData.payload[1].toInt() and 0xFF)
        val dnsResp = parsedData.payload.copyOfRange(2, 2 + dnsLength)
        val header = AuraDnsEngine.parseHeader(dnsResp)!!
        assertEquals(0x5678, header.id)

        assertEquals(1, loggedRecords.size)
        assertEquals("allowed.com", loggedRecords[0].domain)
        assertEquals("allowed", loggedRecords[0].outcome)
    }

    @Test
    fun testMultipleQueriesOverOneTcpConnection() {
        val connKey = completeTcpHandshake(clientIsn = 4000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        // Query 1
        val q1 = createQueryPacket("site1.com", 1, txId = 0x1111)
        val p1 = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(q1)
        )
        processor.processPacket(p1, p1.size)

        // Query 2
        val q2 = createQueryPacket("site2.com", 1, txId = 0x2222)
        val p2 = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(q2)
        )
        processor.processPacket(p2, p2.size)

        assertEquals(2, loggedRecords.size)
        assertEquals("site1.com", loggedRecords[0].domain)
        assertEquals("site2.com", loggedRecords[1].domain)
    }

    @Test
    fun testMultipleQueriesPipelinedInSinglePacket() {
        val connKey = completeTcpHandshake(clientIsn = 5000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val q1 = frameDns(createQueryPacket("pipe1.com", 1, txId = 0x3333))
        val q2 = frameDns(createQueryPacket("pipe2.com", 1, txId = 0x4444))
        val combined = q1 + q2

        val packet = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = combined
        )
        processor.processPacket(packet, packet.size)

        assertEquals(2, loggedRecords.size)
        assertEquals("pipe1.com", loggedRecords[0].domain)
        assertEquals("pipe2.com", loggedRecords[1].domain)
    }

    @Test
    fun testSegmentedTcpDnsResponse() {
        val connKey = completeTcpHandshake(clientIsn = 6000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        // Configure upstream to return large 2500-byte DNS response with matching question section
        processor = AuraDnsPacketProcessor(
            dnsEngine = dnsEngine,
            tcpConnectionManager = tcpConnectionManager,
            pslValidator = pslValidator,
            policyProvider = { currentPolicy },
            upstreamResolver = { requestDns ->
                val base = createSyntheticResponse(requestDns)
                // Pad to 2500 bytes with additional answer records
                val padded = ByteArray(2500)
                System.arraycopy(base, 0, padded, 0, base.size.coerceAtMost(2500))
                padded
            },
            packetWriter = { writtenPackets.add(it) }
        )

        val query = createQueryPacket("large.com", 1, txId = 0x7777)
        val p = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(query)
        )
        processor.processPacket(p, p.size)

        // Should receive multiple segments
        val dataPackets = writtenPackets.filter {
            val parsed = TcpPacketParser.parse(it)
            parsed != null && parsed.payload.isNotEmpty()
        }
        assertEquals(2, dataPackets.size) // 1460 + 1042
    }

    @Test
    fun testRetransmissionDuringActiveConnection() {
        val now = 1000000L
        val connKey = completeTcpHandshake(clientIsn = 7000L, now = now)
        writtenPackets.clear()

        val query = createQueryPacket("retrans.com", 1, txId = 0x8888)
        val p = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 7001L,
            acknowledgmentNumber = 1L,
            payload = frameDns(query)
        )
        processor.processPacket(p, p.size, now = now)
        writtenPackets.clear()

        // Advance by RTO (1000ms)
        processor.checkTimers(now = now + 1000L)
        assertTrue("Must retransmit unacknowledged segment", writtenPackets.isNotEmpty())
    }

    @Test
    fun testDuplicatePacketHandling() {
        val connKey = completeTcpHandshake(clientIsn = 8000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val query = createQueryPacket("dup.com", 1, txId = 0x9999)
        val p = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(query)
        )
        processor.processPacket(p, p.size)
        assertEquals(1, loggedRecords.size)

        // Resend identical packet
        processor.processPacket(p, p.size)
        assertEquals("Duplicate packet must not trigger duplicate DNS resolution", 1, loggedRecords.size)
    }

    @Test
    fun testTeardownFinAndRst() {
        val connKey = completeTcpHandshake(clientIsn = 9000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        // Client FIN
        val fin = TcpPacketParser.buildFinAckPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq
        )
        processor.processPacket(fin, fin.size)
        assertEquals(TcpConnectionManager.TcpState.CLOSE_WAIT, conn.state)
        assertTrue(writtenPackets.isNotEmpty()) // ACK for FIN

        // Client RST
        val rst = TcpPacketParser.buildRstPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 0L,
            acknowledgmentNumber = 0L
        )
        processor.processPacket(rst, rst.size)
        assertNull(tcpConnectionManager.getConnection(connKey))
    }

    @Test
    fun testIPv6TcpDnsHandling() {
        // SYN
        val syn = TcpPacketParser.buildTcpPacket(
            isIPv6 = true,
            srcIp = clientIpv6,
            dstIp = auraIpv6,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 12000L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN
        )
        processor.processPacket(syn, syn.size)
        val synAck = TcpPacketParser.parse(writtenPackets[0])!!
        assertTrue(synAck.isIPv6)

        // ACK
        val ack = TcpPacketParser.buildAckPacket(
            isIPv6 = true,
            srcIp = clientIpv6,
            dstIp = auraIpv6,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 12001L,
            acknowledgmentNumber = synAck.sequenceNumber + 1L
        )
        processor.processPacket(ack, ack.size)
        writtenPackets.clear()

        // Query
        val query = createQueryPacket("ipv6.com", 28, txId = 0xAAAA)
        val qPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = true,
            srcIp = clientIpv6,
            dstIp = auraIpv6,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = 12001L,
            acknowledgmentNumber = synAck.sequenceNumber + 1L,
            payload = frameDns(query)
        )
        processor.processPacket(qPacket, qPacket.size)

        assertEquals(1, loggedRecords.size)
        assertEquals("ipv6.com", loggedRecords[0].domain)
        assertEquals("AAAA", loggedRecords[0].queryType)
    }

    @Test
    fun testPausePassthrough() {
        dnsEngine.setRules(
            listOf(AuraRuleItem(id = "pauseblock.com", domain = "pauseblock.com", isEnabled = true, isBlocked = true))
        )
        // Policy is PAUSED
        currentPolicy = VpnPolicySnapshot(AuraPreferences.POLICY_PAUSED, System.currentTimeMillis() + 60000L)

        val connKey = completeTcpHandshake(clientIsn = 13000L)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val query = createQueryPacket("pauseblock.com", 1, txId = 0xBBBB)
        val p = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(query)
        )
        processor.processPacket(p, p.size)

        // Must be allowed via passthrough
        assertEquals(1, loggedRecords.size)
        assertEquals("pauseblock.com", loggedRecords[0].domain)
        assertEquals("allowed", loggedRecords[0].outcome)
        assertEquals("passthrough", loggedRecords[0].matchedSource)
    }

    @Test
    fun testPauseExpiryAndResumedFiltering() {
        dnsEngine.setRules(
            listOf(AuraRuleItem(id = "expiredblock.com", domain = "expiredblock.com", isEnabled = true, isBlocked = true))
        )
        val now = 2000000L
        // Pause expired 1 second ago
        currentPolicy = VpnPolicySnapshot(AuraPreferences.POLICY_PAUSED, now - 1000L)

        val connKey = completeTcpHandshake(clientIsn = 14000L, now = now)
        val conn = tcpConnectionManager.getConnection(connKey)!!
        writtenPackets.clear()

        val query = createQueryPacket("expiredblock.com", 1, txId = 0xCCCC)
        val p = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = conn.expectedSeq,
            acknowledgmentNumber = conn.localSeq,
            payload = frameDns(query)
        )
        processor.processPacket(p, p.size, now = now)

        // Policy should have reconciled to ENABLED
        assertNotNull(reconciledPolicy)
        assertEquals(AuraPreferences.POLICY_ENABLED, reconciledPolicy!!.mode)

        // Domain must be blocked
        assertEquals(1, loggedRecords.size)
        assertEquals("expiredblock.com", loggedRecords[0].domain)
        assertEquals("blocked", loggedRecords[0].outcome)
    }

    @Test
    fun testUnrelatedTcpTrafficIgnored() {
        // Port 80 (HTTP)
        val httpPacket = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = 12345,
            dstPort = 80,
            sequenceNumber = 100L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN
        )
        val handled = processor.processPacket(httpPacket, httpPacket.size)
        assertFalse("Unrelated TCP traffic on port 80 must be ignored", handled)
        assertEquals(0, writtenPackets.size)
    }

    @Test
    fun testPrivateDnsPort853ReceivesRst() {
        val dotPacket = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = 12345,
            dstPort = 853,
            sequenceNumber = 100L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN
        )
        val handled = processor.processPacket(dotPacket, dotPacket.size)
        assertTrue(handled)
        assertEquals(1, writtenPackets.size)

        val rst = TcpPacketParser.parse(writtenPackets[0])!!
        assertTrue(rst.isRst)
        assertTrue(rst.isAck)
    }

    @Test
    fun testExistingUdpDnsBehaviorUnchanged() {
        val query = createQueryPacket("udp.com", 1, txId = 0xDDDD)
        val udpPacket = buildTestUdpPacket(clientIpv4, auraIpv4, 54321, 53, query)

        val handled = processor.processPacket(udpPacket, udpPacket.size)
        assertTrue(handled)
        assertEquals(1, writtenPackets.size)

        val parsedUdp = com.thejatech.aura.packet.IpPacketParser.parse(writtenPackets[0], writtenPackets[0].size)
        assertNotNull(parsedUdp)
        val respHeader = AuraDnsEngine.parseHeader(parsedUdp!!.dnsPayload)!!
        assertEquals(0xDDDD, respHeader.id)

        assertEquals(1, loggedRecords.size)
        assertEquals("udp.com", loggedRecords[0].domain)
        assertEquals("allowed", loggedRecords[0].outcome)
    }

    // Helper functions

    private fun completeTcpHandshake(
        clientIsn: Long,
        now: Long = System.currentTimeMillis()
    ): TcpConnectionManager.ConnectionKey {
        val syn = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = clientIsn,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN
        )
        processor.processPacket(syn, syn.size, now = now)
        val synAck = TcpPacketParser.parse(writtenPackets.last())!!

        val ack = TcpPacketParser.buildAckPacket(
            isIPv6 = false,
            srcIp = clientIpv4,
            dstIp = auraIpv4,
            srcPort = clientPort,
            dstPort = dnsPort,
            sequenceNumber = clientIsn + 1L,
            acknowledgmentNumber = synAck.sequenceNumber + 1L
        )
        processor.processPacket(ack, ack.size, now = now)

        return TcpConnectionManager.ConnectionKey(clientIpv4, clientPort, auraIpv4, dnsPort, false)
    }

    private fun frameDns(dnsPayload: ByteArray): ByteArray {
        val out = ByteArray(2 + dnsPayload.size)
        out[0] = ((dnsPayload.size shr 8) and 0xFF).toByte()
        out[1] = (dnsPayload.size and 0xFF).toByte()
        System.arraycopy(dnsPayload, 0, out, 2, dnsPayload.size)
        return out
    }

    private fun createQueryPacket(name: String, qType: Int, txId: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val header = ByteBuffer.allocate(12)
        header.putShort(txId.toShort())
        header.putShort(0x0100.toShort())
        header.putShort(1.toShort())
        header.putShort(0.toShort())
        header.putShort(0.toShort())
        header.putShort(0.toShort())
        out.write(header.array())

        for (label in name.split('.')) {
            val bytes = label.toByteArray(Charsets.UTF_8)
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(0)

        val tail = ByteBuffer.allocate(4)
        tail.putShort(qType.toShort())
        tail.putShort(1.toShort())
        out.write(tail.array())

        return out.toByteArray()
    }

    private fun createSyntheticResponse(requestDns: ByteArray): ByteArray {
        val resp = requestDns.copyOf()
        if (resp.size >= 4) {
            resp[2] = 0x81.toByte() // Response, RD
            resp[3] = 0x80.toByte() // RA, NoError
        }
        return resp
    }

    private fun buildTestUdpPacket(srcIp: ByteArray, dstIp: ByteArray, srcPort: Int, dstPort: Int, payload: ByteArray): ByteArray {
        val totalLen = 20 + 8 + payload.size
        val packet = ByteArray(totalLen)
        packet[0] = 0x45.toByte()
        packet[2] = ((totalLen shr 8) and 0xFF).toByte()
        packet[3] = (totalLen and 0xFF).toByte()
        packet[6] = 0x40.toByte()
        packet[8] = 64.toByte()
        packet[9] = 17.toByte() // UDP
        System.arraycopy(srcIp, 0, packet, 12, 4)
        System.arraycopy(dstIp, 0, packet, 16, 4)

        // UDP header
        val udpLen = 8 + payload.size
        packet[20] = ((srcPort shr 8) and 0xFF).toByte()
        packet[21] = (srcPort and 0xFF).toByte()
        packet[22] = ((dstPort shr 8) and 0xFF).toByte()
        packet[23] = (dstPort and 0xFF).toByte()
        packet[24] = ((udpLen shr 8) and 0xFF).toByte()
        packet[25] = (udpLen and 0xFF).toByte()
        System.arraycopy(payload, 0, packet, 28, payload.size)
        return packet
    }
}
