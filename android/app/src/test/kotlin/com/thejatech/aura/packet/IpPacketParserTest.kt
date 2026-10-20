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

    @Test
    fun testBuildTcpResetPacket() {
        val srcIp = byteArrayOf(10, 255.toByte(), 255.toByte(), 2)
        val dstIp = byteArrayOf(10, 255.toByte(), 255.toByte(), 1)
        val srcPort = 45678
        val dstPort = 853 // DoT probe

        // Build 40-byte IPv4 TCP SYN packet
        val synPacket = ByteArray(40)
        synPacket[0] = 0x45.toByte() // IPv4, IHL = 5 (20 bytes)
        synPacket[2] = 0.toByte()
        synPacket[3] = 40.toByte() // Total length 40
        synPacket[8] = 64.toByte() // TTL 64
        synPacket[9] = 6.toByte()  // Protocol TCP (6)
        System.arraycopy(srcIp, 0, synPacket, 12, 4)
        System.arraycopy(dstIp, 0, synPacket, 16, 4)

        // TCP header
        synPacket[20] = ((srcPort shr 8) and 0xFF).toByte()
        synPacket[21] = (srcPort and 0xFF).toByte()
        synPacket[22] = ((dstPort shr 8) and 0xFF).toByte()
        synPacket[23] = (dstPort and 0xFF).toByte()
        // SeqNum = 1000 (0x000003E8)
        synPacket[24] = 0.toByte()
        synPacket[25] = 0.toByte()
        synPacket[26] = 0x03.toByte()
        synPacket[27] = 0xE8.toByte()
        synPacket[32] = 0x50.toByte() // Offset 5 (20 bytes)
        synPacket[33] = 0x02.toByte() // SYN flag

        val rst = IpPacketParser.buildTcpResetPacket(synPacket, synPacket.size)
        assertNotNull(rst)
        assertEquals(40, rst!!.size)
        assertEquals(0x45.toByte(), rst[0])
        assertEquals(6.toByte(), rst[9]) // Protocol TCP

        // Verify swapped IP
        val rstSrcIp = rst.copyOfRange(12, 16)
        val rstDstIp = rst.copyOfRange(16, 20)
        assertArrayEquals(dstIp, rstSrcIp)
        assertArrayEquals(srcIp, rstDstIp)

        // Verify swapped Ports
        val rstSrcPort = ((rst[20].toInt() and 0xFF) shl 8) or (rst[21].toInt() and 0xFF)
        val rstDstPort = ((rst[22].toInt() and 0xFF) shl 8) or (rst[23].toInt() and 0xFF)
        assertEquals(853, rstSrcPort)
        assertEquals(45678, rstDstPort)

        // Verify RST+ACK flags (0x14)
        assertEquals(0x14.toByte(), rst[33])

        // Verify Ack = SeqNum + 1 = 1001 (0x000003E9)
        assertEquals(0.toByte(), rst[28])
        assertEquals(0.toByte(), rst[29])
        assertEquals(0x03.toByte(), rst[30])
        assertEquals(0xE9.toByte(), rst[31])
    }
}
