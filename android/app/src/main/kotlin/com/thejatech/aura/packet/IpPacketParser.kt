package com.thejatech.aura.packet

import java.nio.ByteBuffer

data class ParsedDnsPacket(
    val isIPv6: Boolean,
    val sourceIp: ByteArray,
    val destinationIp: ByteArray,
    val sourcePort: Int,
    val destinationPort: Int,
    val dnsPayload: ByteArray
)

object IpPacketParser {

    fun parse(packet: ByteArray, length: Int): ParsedDnsPacket? {
        if (length < 28) return null // Minimum IPv4 (20) + UDP (8)
        val version = (packet[0].toInt() shr 4) and 0x0F

        return when (version) {
            4 -> parseIPv4(packet, length)
            6 -> parseIPv6(packet, length)
            else -> null
        }
    }

    private fun parseIPv4(packet: ByteArray, length: Int): ParsedDnsPacket? {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < 20 || length < ihl + 8) return null

        val totalLength = ((packet[2].toInt() and 0xFF) shl 8) or (packet[3].toInt() and 0xFF)
        if (totalLength > length) return null

        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return null // UDP only

        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)

        val srcPort = ((packet[ihl].toInt() and 0xFF) shl 8) or (packet[ihl + 1].toInt() and 0xFF)
        val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)
        val udpLength = ((packet[ihl + 4].toInt() and 0xFF) shl 8) or (packet[ihl + 5].toInt() and 0xFF)

        if (udpLength < 8 || ihl + udpLength > totalLength) return null

        val payloadOffset = ihl + 8
        val payloadLength = udpLength - 8
        val dnsPayload = packet.copyOfRange(payloadOffset, payloadOffset + payloadLength)

        return ParsedDnsPacket(
            isIPv6 = false,
            sourceIp = srcIp,
            destinationIp = dstIp,
            sourcePort = srcPort,
            destinationPort = dstPort,
            dnsPayload = dnsPayload
        )
    }

    private fun parseIPv6(packet: ByteArray, length: Int): ParsedDnsPacket? {
        if (length < 48) return null // IPv6 (40) + UDP (8)

        val payloadLength = ((packet[4].toInt() and 0xFF) shl 8) or (packet[5].toInt() and 0xFF)
        val nextHeader = packet[6].toInt() and 0xFF
        if (nextHeader != 17) return null // UDP only

        val srcIp = packet.copyOfRange(8, 24)
        val dstIp = packet.copyOfRange(24, 40)

        val udpOffset = 40
        if (length < udpOffset + 8) return null

        val srcPort = ((packet[udpOffset].toInt() and 0xFF) shl 8) or (packet[udpOffset + 1].toInt() and 0xFF)
        val dstPort = ((packet[udpOffset + 2].toInt() and 0xFF) shl 8) or (packet[udpOffset + 3].toInt() and 0xFF)
        val udpLength = ((packet[udpOffset + 4].toInt() and 0xFF) shl 8) or (packet[udpOffset + 5].toInt() and 0xFF)

        if (udpLength < 8 || udpOffset + udpLength > length) return null

        val payloadOffset = udpOffset + 8
        val dnsLength = udpLength - 8
        val dnsPayload = packet.copyOfRange(payloadOffset, payloadOffset + dnsLength)

        return ParsedDnsPacket(
            isIPv6 = true,
            sourceIp = srcIp,
            destinationIp = dstIp,
            sourcePort = srcPort,
            destinationPort = dstPort,
            dnsPayload = dnsPayload
        )
    }

    fun buildResponsePacket(request: ParsedDnsPacket, dnsResponse: ByteArray): ByteArray {
        return if (request.isIPv6) {
            buildIPv6Response(request, dnsResponse)
        } else {
            buildIPv4Response(request, dnsResponse)
        }
    }

    private fun buildIPv4Response(request: ParsedDnsPacket, dnsResponse: ByteArray): ByteArray {
        val totalLength = 20 + 8 + dnsResponse.size
        val packet = ByteArray(totalLength)

        // IP Header (20 bytes)
        packet[0] = 0x45.toByte() // IPv4, IHL = 5 (20 bytes)
        packet[1] = 0x00.toByte() // DSCP / ECN
        packet[2] = ((totalLength shr 8) and 0xFF).toByte()
        packet[3] = (totalLength and 0xFF).toByte()
        packet[4] = 0x00.toByte() // Identification
        packet[5] = 0x00.toByte()
        packet[6] = 0x40.toByte() // Flags: Don't Fragment
        packet[7] = 0x00.toByte()
        packet[8] = 64.toByte()   // TTL = 64
        packet[9] = 17.toByte()   // Protocol = UDP (17)
        packet[10] = 0x00.toByte() // Checksum placeholder
        packet[11] = 0x00.toByte()

        // Swap IP addresses
        System.arraycopy(request.destinationIp, 0, packet, 12, 4) // Source IP
        System.arraycopy(request.sourceIp, 0, packet, 16, 4)      // Destination IP

        // Calculate IPv4 Header Checksum
        val ipChecksum = computeChecksum(packet, 0, 20)
        packet[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        packet[11] = (ipChecksum and 0xFF).toByte()

        // UDP Header (8 bytes)
        val udpLength = 8 + dnsResponse.size
        packet[20] = ((request.destinationPort shr 8) and 0xFF).toByte()
        packet[21] = (request.destinationPort and 0xFF).toByte()
        packet[22] = ((request.sourcePort shr 8) and 0xFF).toByte()
        packet[23] = (request.sourcePort and 0xFF).toByte()
        packet[24] = ((udpLength shr 8) and 0xFF).toByte()
        packet[25] = (udpLength and 0xFF).toByte()
        packet[26] = 0x00.toByte() // UDP Checksum (0x0000 in IPv4 indicates no checksum)
        packet[27] = 0x00.toByte()

        // Copy DNS payload
        System.arraycopy(dnsResponse, 0, packet, 28, dnsResponse.size)

        return packet
    }

    private fun buildIPv6Response(request: ParsedDnsPacket, dnsResponse: ByteArray): ByteArray {
        val udpLength = 8 + dnsResponse.size
        val totalLength = 40 + udpLength
        val packet = ByteArray(totalLength)

        // IPv6 Header (40 bytes)
        packet[0] = 0x60.toByte() // Version 6
        packet[1] = 0x00.toByte()
        packet[2] = 0x00.toByte()
        packet[3] = 0x00.toByte()
        packet[4] = ((udpLength shr 8) and 0xFF).toByte()
        packet[5] = (udpLength and 0xFF).toByte()
        packet[6] = 17.toByte()   // Next Header = UDP (17)
        packet[7] = 64.toByte()   // Hop Limit = 64

        // Swap IPv6 addresses
        System.arraycopy(request.destinationIp, 0, packet, 8, 16)  // Source IPv6
        System.arraycopy(request.sourceIp, 0, packet, 24, 16)      // Destination IPv6

        // UDP Header (starts at 40)
        packet[40] = ((request.destinationPort shr 8) and 0xFF).toByte()
        packet[41] = (request.destinationPort and 0xFF).toByte()
        packet[42] = ((request.sourcePort shr 8) and 0xFF).toByte()
        packet[43] = (request.sourcePort and 0xFF).toByte()
        packet[44] = ((udpLength shr 8) and 0xFF).toByte()
        packet[45] = (udpLength and 0xFF).toByte()
        packet[46] = 0x00.toByte() // Placeholder for checksum
        packet[47] = 0x00.toByte()

        // Copy DNS payload
        System.arraycopy(dnsResponse, 0, packet, 48, dnsResponse.size)

        // Mandatory IPv6 UDP Checksum over Pseudo-Header + UDP packet
        val checksum = computeIPv6UdpChecksum(packet, 8, 24, 40, udpLength)
        packet[46] = ((checksum shr 8) and 0xFF).toByte()
        packet[47] = (checksum and 0xFF).toByte()

        return packet
    }

    private fun computeChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        while (i < offset + length - 1) {
            val word = ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < offset + length) {
            sum += ((data[i].toInt() and 0xFF) shl 8)
        }
        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv().toInt() and 0xFFFF)
    }

    private fun computeIPv6UdpChecksum(
        packet: ByteArray,
        srcIpOffset: Int,
        dstIpOffset: Int,
        udpOffset: Int,
        udpLength: Int
    ): Int {
        var sum = 0L

        // 1. Source IPv6 (16 bytes)
        for (i in 0 until 16 step 2) {
            sum += (((packet[srcIpOffset + i].toInt() and 0xFF) shl 8) or (packet[srcIpOffset + i + 1].toInt() and 0xFF))
        }

        // 2. Destination IPv6 (16 bytes)
        for (i in 0 until 16 step 2) {
            sum += (((packet[dstIpOffset + i].toInt() and 0xFF) shl 8) or (packet[dstIpOffset + i + 1].toInt() and 0xFF))
        }

        // 3. UDP Length (32-bit integer in pseudo-header)
        sum += (udpLength shr 16) and 0xFFFF
        sum += udpLength and 0xFFFF

        // 4. Next Header (17 = UDP)
        sum += 17

        // 5. UDP Header and Payload
        var i = udpOffset
        while (i < udpOffset + udpLength - 1) {
            val word = ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < udpOffset + udpLength) {
            sum += ((packet[i].toInt() and 0xFF) shl 8)
        }

        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        var result = (sum.inv().toInt() and 0xFFFF)
        if (result == 0) {
            result = 0xFFFF
        }
        return result
    }
}
