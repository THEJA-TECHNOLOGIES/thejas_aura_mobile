package com.thejatech.aura.packet

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

class IpPacketParserTest {

    @Test
    fun testIPv4PacketParseAndResponse() {
        val dnsPayload = byteArrayOf(0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        val packet = buildTestIPv4Packet(
            srcIp = byteArrayOf(10, 255.toByte(), 255.toByte(), 2),
            dstIp = byteArrayOf(10, 255.toByte(), 255.toByte(), 1),
            srcPort = 54321,
            dstPort = 53,
            payload = dnsPayload
        )

        val parsed = IpPacketParser.parse(packet, packet.size)
        assertNotNull(parsed)
        assertFalse(parsed!!.isIPv6)
        assertEquals(54321, parsed.sourcePort)
        assertEquals(53, parsed.destinationPort)
        assertArrayEquals(byteArrayOf(10, 255.toByte(), 255.toByte(), 2), parsed.sourceIp)
        assertArrayEquals(byteArrayOf(10, 255.toByte(), 255.toByte(), 1), parsed.destinationIp)
        assertArrayEquals(dnsPayload, parsed.dnsPayload)

        // Build response
        val dnsResponse = byteArrayOf(0x12, 0x34, 0x81.toByte(), 0x80.toByte(), 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00)
        val respPacket = IpPacketParser.buildResponsePacket(parsed, dnsResponse)

        val parsedResp = IpPacketParser.parse(respPacket, respPacket.size)
        assertNotNull(parsedResp)
        assertEquals(53, parsedResp!!.sourcePort)
        assertEquals(54321, parsedResp.destinationPort)
        assertArrayEquals(byteArrayOf(10, 255.toByte(), 255.toByte(), 1), parsedResp.sourceIp)
        assertArrayEquals(byteArrayOf(10, 255.toByte(), 255.toByte(), 2), parsedResp.destinationIp)
        assertArrayEquals(dnsResponse, parsedResp.dnsPayload)
    }

    @Test
    fun testIPv6PacketParseAndResponse() {
        val srcIp = ByteArray(16).apply { this[15] = 2 }
        val dstIp = ByteArray(16).apply { this[15] = 1 }
        val dnsPayload = byteArrayOf(0x56, 0x78, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)

        val packet = buildTestIPv6Packet(srcIp, dstIp, 54321, 53, dnsPayload)
        val parsed = IpPacketParser.parse(packet, packet.size)

        assertNotNull(parsed)
        assertTrue(parsed!!.isIPv6)
        assertEquals(54321, parsed.sourcePort)
        assertEquals(53, parsed.destinationPort)
        assertArrayEquals(srcIp, parsed.sourceIp)
        assertArrayEquals(dstIp, parsed.destinationIp)

        // Build response
        val dnsResponse = byteArrayOf(0x56, 0x78, 0x81.toByte(), 0x80.toByte(), 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00)
        val respPacket = IpPacketParser.buildResponsePacket(parsed, dnsResponse)

        val parsedResp = IpPacketParser.parse(respPacket, respPacket.size)
        assertNotNull(parsedResp)
        assertTrue(parsedResp!!.isIPv6)
        assertEquals(53, parsedResp.sourcePort)
        assertEquals(54321, parsedResp.destinationPort)
        assertArrayEquals(dstIp, parsedResp.sourceIp)
        assertArrayEquals(srcIp, parsedResp.destinationIp)
    }

    private fun buildTestIPv4Packet(
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val totalLength = 20 + 8 + payload.size
        val packet = ByteArray(totalLength)
        packet[0] = 0x45.toByte()
        packet[2] = ((totalLength shr 8) and 0xFF).toByte()
        packet[3] = (totalLength and 0xFF).toByte()
        packet[8] = 64.toByte() // TTL
        packet[9] = 17.toByte() // UDP
        System.arraycopy(srcIp, 0, packet, 12, 4)
        System.arraycopy(dstIp, 0, packet, 16, 4)

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

    private fun buildTestIPv6Packet(
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val udpLen = 8 + payload.size
        val totalLength = 40 + udpLen
        val packet = ByteArray(totalLength)
        packet[0] = 0x60.toByte()
        packet[4] = ((udpLen shr 8) and 0xFF).toByte()
        packet[5] = (udpLen and 0xFF).toByte()
        packet[6] = 17.toByte() // UDP
        packet[7] = 64.toByte() // Hop Limit

        System.arraycopy(srcIp, 0, packet, 8, 16)
        System.arraycopy(dstIp, 0, packet, 24, 16)

        packet[40] = ((srcPort shr 8) and 0xFF).toByte()
        packet[41] = (srcPort and 0xFF).toByte()
        packet[42] = ((dstPort shr 8) and 0xFF).toByte()
        packet[43] = (dstPort and 0xFF).toByte()
        packet[44] = ((udpLen shr 8) and 0xFF).toByte()
        packet[45] = (udpLen and 0xFF).toByte()
        System.arraycopy(payload, 0, packet, 48, payload.size)

        return packet
    }
}
