package com.thejatech.aura.packet

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpPacketParserTest {

    private val ipv4Client = byteArrayOf(10, 0, 0, 2)
    private val ipv4Server = byteArrayOf(10, 255.toByte(), 255.toByte(), 1)
    private val ipv6Client = ByteArray(16).apply { this[15] = 2 }
    private val ipv6Server = ByteArray(16).apply { this[15] = 1 }

    @Test
    fun testBuildAndParseIPv4SynPacket() {
        val synPacket = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = ipv4Client,
            dstIp = ipv4Server,
            srcPort = 54321,
            dstPort = 53,
            sequenceNumber = 100000L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN,
            windowSize = 65535
        )

        val parsed = TcpPacketParser.parse(synPacket, synPacket.size)
        assertNotNull(parsed)
        parsed!!
        assertFalse(parsed.isIPv6)
        assertArrayEquals(ipv4Client, parsed.sourceIp)
        assertArrayEquals(ipv4Server, parsed.destinationIp)
        assertEquals(54321, parsed.sourcePort)
        assertEquals(53, parsed.destinationPort)
        assertEquals(100000L, parsed.sequenceNumber)
        assertEquals(0L, parsed.acknowledgmentNumber)
        assertTrue(parsed.isSyn)
        assertFalse(parsed.isAck)
        assertFalse(parsed.isFin)
        assertFalse(parsed.isRst)
        assertEquals(65535, parsed.windowSize)
        assertEquals(0, parsed.payload.size)

        assertTrue(TcpPacketParser.verifyChecksum(synPacket))
    }

    @Test
    fun testBuildAndParseIPv4DataPacket() {
        val payload = "DNS TCP Query Data".toByteArray(Charsets.UTF_8)
        val dataPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = false,
            srcIp = ipv4Client,
            dstIp = ipv4Server,
            srcPort = 54321,
            dstPort = 53,
            sequenceNumber = 100001L,
            acknowledgmentNumber = 200001L,
            payload = payload,
            windowSize = 32768,
            psh = true
        )

        val parsed = TcpPacketParser.parse(dataPacket, dataPacket.size)
        assertNotNull(parsed)
        parsed!!
        assertFalse(parsed.isIPv6)
        assertEquals(54321, parsed.sourcePort)
        assertEquals(53, parsed.destinationPort)
        assertEquals(100001L, parsed.sequenceNumber)
        assertEquals(200001L, parsed.acknowledgmentNumber)
        assertTrue(parsed.isAck)
        assertTrue(parsed.isPsh)
        assertFalse(parsed.isSyn)
        assertEquals(32768, parsed.windowSize)
        assertArrayEquals(payload, parsed.payload)

        assertTrue(TcpPacketParser.verifyChecksum(dataPacket))
    }

    @Test
    fun testBuildAndParseIPv6SynAckPacket() {
        val synAckPacket = TcpPacketParser.buildSynAckPacket(
            isIPv6 = true,
            srcIp = ipv6Server,
            dstIp = ipv6Client,
            srcPort = 53,
            dstPort = 49152,
            sequenceNumber = 500000L,
            acknowledgmentNumber = 100001L,
            windowSize = 65535,
            mss = 1440
        )

        val parsed = TcpPacketParser.parse(synAckPacket, synAckPacket.size)
        assertNotNull(parsed)
        parsed!!
        assertTrue(parsed.isIPv6)
        assertArrayEquals(ipv6Server, parsed.sourceIp)
        assertArrayEquals(ipv6Client, parsed.destinationIp)
        assertEquals(53, parsed.sourcePort)
        assertEquals(49152, parsed.destinationPort)
        assertEquals(500000L, parsed.sequenceNumber)
        assertEquals(100001L, parsed.acknowledgmentNumber)
        assertTrue(parsed.isSyn)
        assertTrue(parsed.isAck)
        assertEquals(6, parsed.dataOffset) // 20 TCP header + 4 MSS option = 24 bytes = 6 words
        assertEquals(4, parsed.options.size)
        assertEquals(0x02.toByte(), parsed.options[0]) // Option kind = MSS
        assertEquals(0x04.toByte(), parsed.options[1]) // Option length = 4

        assertTrue(TcpPacketParser.verifyChecksum(synAckPacket))
    }

    @Test
    fun testBuildAndParseIPv6DataPacket() {
        val payload = ByteArray(256) { it.toByte() }
        val dataPacket = TcpPacketParser.buildDataPacket(
            isIPv6 = true,
            srcIp = ipv6Server,
            dstIp = ipv6Client,
            srcPort = 53,
            dstPort = 49152,
            sequenceNumber = 500001L,
            acknowledgmentNumber = 100050L,
            payload = payload,
            windowSize = 65535,
            psh = false
        )

        val parsed = TcpPacketParser.parse(dataPacket, dataPacket.size)
        assertNotNull(parsed)
        parsed!!
        assertTrue(parsed.isIPv6)
        assertTrue(parsed.isAck)
        assertFalse(parsed.isPsh)
        assertArrayEquals(payload, parsed.payload)

        assertTrue(TcpPacketParser.verifyChecksum(dataPacket))
    }

    @Test
    fun testBuildFinAckAndRstPackets() {
        val finAck = TcpPacketParser.buildFinAckPacket(
            isIPv6 = false,
            srcIp = ipv4Server,
            dstIp = ipv4Client,
            srcPort = 53,
            dstPort = 54321,
            sequenceNumber = 3000L,
            acknowledgmentNumber = 4000L
        )
        val parsedFin = TcpPacketParser.parse(finAck, finAck.size)
        assertNotNull(parsedFin)
        assertTrue(parsedFin!!.isFin)
        assertTrue(parsedFin.isAck)
        assertTrue(TcpPacketParser.verifyChecksum(finAck))

        val rst = TcpPacketParser.buildRstPacket(
            isIPv6 = false,
            srcIp = ipv4Server,
            dstIp = ipv4Client,
            srcPort = 53,
            dstPort = 54321,
            sequenceNumber = 3001L,
            acknowledgmentNumber = 4001L,
            isAck = true
        )
        val parsedRst = TcpPacketParser.parse(rst, rst.size)
        assertNotNull(parsedRst)
        assertTrue(parsedRst!!.isRst)
        assertTrue(parsedRst.isAck)
        assertTrue(TcpPacketParser.verifyChecksum(rst))
    }

    @Test
    fun testRejectMalformedAndNonTcpPackets() {
        // Less than minimum size
        assertNull(TcpPacketParser.parse(ByteArray(20), 20))

        // Wrong IP version
        val badVersion = ByteArray(40)
        badVersion[0] = 0x25.toByte()
        assertNull(TcpPacketParser.parse(badVersion, badVersion.size))

        // UDP packet (protocol 17 instead of 6)
        val udpPacket = ByteArray(40)
        udpPacket[0] = 0x45.toByte()
        udpPacket[2] = 0x00
        udpPacket[3] = 40
        udpPacket[9] = 17.toByte()
        assertNull(TcpPacketParser.parse(udpPacket, udpPacket.size))

        // Truncated packet length
        val validPacket = TcpPacketParser.buildAckPacket(
            isIPv6 = false,
            srcIp = ipv4Client,
            dstIp = ipv4Server,
            srcPort = 1234,
            dstPort = 53,
            sequenceNumber = 1L,
            acknowledgmentNumber = 2L
        )
        assertNull(TcpPacketParser.parse(validPacket, 30)) // Pass smaller length than header

        // Checksum verification fails when bytes are corrupted
        val corrupted = validPacket.copyOf()
        corrupted[30] = (corrupted[30] + 1).toByte()
        assertFalse(TcpPacketParser.verifyChecksum(corrupted))
    }

    @Test
    fun testParseRejectsInvalidChecksum() {
        // Build a valid packet, then corrupt a byte in the payload area
        val validPacket = TcpPacketParser.buildAckPacket(
            isIPv6 = false,
            srcIp = ipv4Client,
            dstIp = ipv4Server,
            srcPort = 1234,
            dstPort = 53,
            sequenceNumber = 1L,
            acknowledgmentNumber = 2L
        )

        // Corrupt a byte in the payload (after the TCP header)
        val corrupted = validPacket.copyOf()
        val tcpHeaderLen = 20
        corrupted[tcpHeaderLen] = (corrupted[tcpHeaderLen] + 1).toByte()

        // parse() should reject the packet because the checksum no longer matches
        assertNull(TcpPacketParser.parse(corrupted, corrupted.size))
    }

    @Test
    fun testParseAcceptsValidChecksum() {
        val synPacket = TcpPacketParser.buildTcpPacket(
            isIPv6 = false,
            srcIp = ipv4Client,
            dstIp = ipv4Server,
            srcPort = 54321,
            dstPort = 53,
            sequenceNumber = 100000L,
            acknowledgmentNumber = 0L,
            flags = ParsedTcpPacket.FLAG_SYN,
            windowSize = 65535
        )

        // Valid checksum: parse should succeed
        assertNotNull(TcpPacketParser.parse(synPacket, synPacket.size))
    }
}
