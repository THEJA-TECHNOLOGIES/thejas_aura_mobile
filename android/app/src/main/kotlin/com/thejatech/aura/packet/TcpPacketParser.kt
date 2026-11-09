package com.thejatech.aura.packet

data class ParsedTcpPacket(
    val isIPv6: Boolean,
    val sourceIp: ByteArray,
    val destinationIp: ByteArray,
    val sourcePort: Int,
    val destinationPort: Int,
    val sequenceNumber: Long,
    val acknowledgmentNumber: Long,
    val dataOffset: Int, // Header length in 32-bit words (>= 5)
    val flags: Int,
    val windowSize: Int,
    val checksum: Int,
    val urgentPointer: Int,
    val options: ByteArray = ByteArray(0),
    val payload: ByteArray = ByteArray(0)
) {
    val isFin: Boolean get() = (flags and FLAG_FIN) != 0
    val isSyn: Boolean get() = (flags and FLAG_SYN) != 0
    val isRst: Boolean get() = (flags and FLAG_RST) != 0
    val isPsh: Boolean get() = (flags and FLAG_PSH) != 0
    val isAck: Boolean get() = (flags and FLAG_ACK) != 0
    val isUrg: Boolean get() = (flags and FLAG_URG) != 0
    val isEce: Boolean get() = (flags and FLAG_ECE) != 0
    val isCwr: Boolean get() = (flags and FLAG_CWR) != 0

    val tcpHeaderLength: Int get() = dataOffset * 4

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ParsedTcpPacket) return false
        return isIPv6 == other.isIPv6 &&
                sourcePort == other.sourcePort &&
                destinationPort == other.destinationPort &&
                sequenceNumber == other.sequenceNumber &&
                acknowledgmentNumber == other.acknowledgmentNumber &&
                dataOffset == other.dataOffset &&
                flags == other.flags &&
                windowSize == other.windowSize &&
                checksum == other.checksum &&
                urgentPointer == other.urgentPointer &&
                sourceIp.contentEquals(other.sourceIp) &&
                destinationIp.contentEquals(other.destinationIp) &&
                options.contentEquals(other.options) &&
                payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = (if (isIPv6) 1 else 0)
        result = 31 * result + sourceIp.contentHashCode()
        result = 31 * result + destinationIp.contentHashCode()
        result = 31 * result + sourcePort
        result = 31 * result + destinationPort
        result = 31 * result + sequenceNumber.hashCode()
        result = 31 * result + acknowledgmentNumber.hashCode()
        result = 31 * result + dataOffset
        result = 31 * result + flags
        result = 31 * result + windowSize
        result = 31 * result + checksum
        result = 31 * result + urgentPointer
        result = 31 * result + options.contentHashCode()
        result = 31 * result + payload.contentHashCode()
        return result
    }

    companion object {
        const val FLAG_FIN = 0x01
        const val FLAG_SYN = 0x02
        const val FLAG_RST = 0x04
        const val FLAG_PSH = 0x08
        const val FLAG_ACK = 0x10
        const val FLAG_URG = 0x20
        const val FLAG_ECE = 0x40
        const val FLAG_CWR = 0x80
    }
}

object TcpPacketParser {

    private const val PROTOCOL_TCP = 6
    private const val MIN_IPV4_HEADER_LEN = 20
    private const val IPV6_HEADER_LEN = 40
    private const val MIN_TCP_HEADER_LEN = 20

    /**
     * Parses an IPv4 or IPv6 TCP packet from raw bytes.
     * Returns null if packet is invalid, truncated, or not TCP.
     */
    fun parse(packet: ByteArray, length: Int = packet.size): ParsedTcpPacket? {
        if (length < MIN_IPV4_HEADER_LEN + MIN_TCP_HEADER_LEN) return null
        val version = (packet[0].toInt() shr 4) and 0x0F

        return when (version) {
            4 -> parseIPv4(packet, length)
            6 -> parseIPv6(packet, length)
            else -> null
        }
    }

    private fun parseIPv4(packet: ByteArray, length: Int): ParsedTcpPacket? {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < MIN_IPV4_HEADER_LEN || length < ihl + MIN_TCP_HEADER_LEN) return null

        val totalLength = ((packet[2].toInt() and 0xFF) shl 8) or (packet[3].toInt() and 0xFF)
        if (totalLength > length || totalLength < ihl + MIN_TCP_HEADER_LEN) return null

        val protocol = packet[9].toInt() and 0xFF
        if (protocol != PROTOCOL_TCP) return null

        val srcIp = packet.copyOfRange(12, 16)
        val dstIp = packet.copyOfRange(16, 20)

        // Verify TCP checksum before accepting the segment
        if (!verifyChecksum(packet, totalLength)) {
            return null
        }

        return parseTcpSegment(
            packet = packet,
            isIPv6 = false,
            srcIp = srcIp,
            dstIp = dstIp,
            tcpOffset = ihl,
            totalPacketLength = totalLength
        )
    }

    private fun parseIPv6(packet: ByteArray, length: Int): ParsedTcpPacket? {
        if (length < IPV6_HEADER_LEN + MIN_TCP_HEADER_LEN) return null

        val payloadLength = ((packet[4].toInt() and 0xFF) shl 8) or (packet[5].toInt() and 0xFF)
        val totalLength = IPV6_HEADER_LEN + payloadLength
        if (totalLength > length || payloadLength < MIN_TCP_HEADER_LEN) return null

        val nextHeader = packet[6].toInt() and 0xFF
        if (nextHeader != PROTOCOL_TCP) return null

        val srcIp = packet.copyOfRange(8, 24)
        val dstIp = packet.copyOfRange(24, 40)

        // Verify TCP checksum before accepting the segment
        if (!verifyChecksum(packet, totalLength)) {
            return null
        }

        return parseTcpSegment(
            packet = packet,
            isIPv6 = true,
            srcIp = srcIp,
            dstIp = dstIp,
            tcpOffset = IPV6_HEADER_LEN,
            totalPacketLength = totalLength
        )
    }

    private fun parseTcpSegment(
        packet: ByteArray,
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        tcpOffset: Int,
        totalPacketLength: Int
    ): ParsedTcpPacket? {
        val srcPort = ((packet[tcpOffset].toInt() and 0xFF) shl 8) or
                (packet[tcpOffset + 1].toInt() and 0xFF)
        val dstPort = ((packet[tcpOffset + 2].toInt() and 0xFF) shl 8) or
                (packet[tcpOffset + 3].toInt() and 0xFF)

        val seqNum = ((packet[tcpOffset + 4].toLong() and 0xFF) shl 24) or
                ((packet[tcpOffset + 5].toLong() and 0xFF) shl 16) or
                ((packet[tcpOffset + 6].toLong() and 0xFF) shl 8) or
                (packet[tcpOffset + 7].toLong() and 0xFF)

        val ackNum = ((packet[tcpOffset + 8].toLong() and 0xFF) shl 24) or
                ((packet[tcpOffset + 9].toLong() and 0xFF) shl 16) or
                ((packet[tcpOffset + 10].toLong() and 0xFF) shl 8) or
                (packet[tcpOffset + 11].toLong() and 0xFF)

        val dataOffset = (packet[tcpOffset + 12].toInt() shr 4) and 0x0F
        if (dataOffset < 5) return null
        val tcpHeaderLength = dataOffset * 4

        if (tcpOffset + tcpHeaderLength > totalPacketLength) return null

        val flags = packet[tcpOffset + 13].toInt() and 0xFF
        val windowSize = ((packet[tcpOffset + 14].toInt() and 0xFF) shl 8) or
                (packet[tcpOffset + 15].toInt() and 0xFF)
        val checksum = ((packet[tcpOffset + 16].toInt() and 0xFF) shl 8) or
                (packet[tcpOffset + 17].toInt() and 0xFF)
        val urgentPointer = ((packet[tcpOffset + 18].toInt() and 0xFF) shl 8) or
                (packet[tcpOffset + 19].toInt() and 0xFF)

        val optionsLength = tcpHeaderLength - MIN_TCP_HEADER_LEN
        val options = if (optionsLength > 0) {
            packet.copyOfRange(tcpOffset + MIN_TCP_HEADER_LEN, tcpOffset + tcpHeaderLength)
        } else {
            ByteArray(0)
        }

        val payloadOffset = tcpOffset + tcpHeaderLength
        val payloadLength = totalPacketLength - payloadOffset
        val payload = if (payloadLength > 0) {
            packet.copyOfRange(payloadOffset, totalPacketLength)
        } else {
            ByteArray(0)
        }

        return ParsedTcpPacket(
            isIPv6 = isIPv6,
            sourceIp = srcIp,
            destinationIp = dstIp,
            sourcePort = srcPort,
            destinationPort = dstPort,
            sequenceNumber = seqNum,
            acknowledgmentNumber = ackNum,
            dataOffset = dataOffset,
            flags = flags,
            windowSize = windowSize,
            checksum = checksum,
            urgentPointer = urgentPointer,
            options = options,
            payload = payload
        )
    }

    /**
     * Builds a full raw IP/TCP packet (IPv4 or IPv6) with appropriate headers and checksums.
     */
    fun buildTcpPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long,
        flags: Int,
        windowSize: Int = 65535,
        payload: ByteArray = ByteArray(0),
        options: ByteArray = ByteArray(0)
    ): ByteArray {
        val paddedOptionsLength = if (options.isNotEmpty()) {
            val rem = options.size % 4
            if (rem == 0) options.size else options.size + (4 - rem)
        } else {
            0
        }
        val tcpHeaderLength = MIN_TCP_HEADER_LEN + paddedOptionsLength
        val dataOffset = tcpHeaderLength / 4

        val ipHeaderLength = if (isIPv6) IPV6_HEADER_LEN else MIN_IPV4_HEADER_LEN
        val tcpSegmentLength = tcpHeaderLength + payload.size
        val totalLength = ipHeaderLength + tcpSegmentLength

        val packet = ByteArray(totalLength)

        if (isIPv6) {
            buildIPv6Header(packet, srcIp, dstIp, tcpSegmentLength)
        } else {
            buildIPv4Header(packet, srcIp, dstIp, totalLength)
        }

        // TCP Header starts at ipHeaderLength
        val tcpOffset = ipHeaderLength
        packet[tcpOffset] = ((srcPort shr 8) and 0xFF).toByte()
        packet[tcpOffset + 1] = (srcPort and 0xFF).toByte()
        packet[tcpOffset + 2] = ((dstPort shr 8) and 0xFF).toByte()
        packet[tcpOffset + 3] = (dstPort and 0xFF).toByte()

        // Sequence number (32-bit)
        packet[tcpOffset + 4] = ((sequenceNumber shr 24) and 0xFF).toByte()
        packet[tcpOffset + 5] = ((sequenceNumber shr 16) and 0xFF).toByte()
        packet[tcpOffset + 6] = ((sequenceNumber shr 8) and 0xFF).toByte()
        packet[tcpOffset + 7] = (sequenceNumber and 0xFF).toByte()

        // Acknowledgment number (32-bit)
        packet[tcpOffset + 8] = ((acknowledgmentNumber shr 24) and 0xFF).toByte()
        packet[tcpOffset + 9] = ((acknowledgmentNumber shr 16) and 0xFF).toByte()
        packet[tcpOffset + 10] = ((acknowledgmentNumber shr 8) and 0xFF).toByte()
        packet[tcpOffset + 11] = (acknowledgmentNumber and 0xFF).toByte()

        // Data Offset and reserved bits
        packet[tcpOffset + 12] = ((dataOffset shl 4) and 0xF0).toByte()

        // Flags
        packet[tcpOffset + 13] = (flags and 0xFF).toByte()

        // Window size
        packet[tcpOffset + 14] = ((windowSize shr 8) and 0xFF).toByte()
        packet[tcpOffset + 15] = (windowSize and 0xFF).toByte()

        // Checksum placeholder
        packet[tcpOffset + 16] = 0x00.toByte()
        packet[tcpOffset + 17] = 0x00.toByte()

        // Urgent pointer
        packet[tcpOffset + 18] = 0x00.toByte()
        packet[tcpOffset + 19] = 0x00.toByte()

        // Options
        if (options.isNotEmpty()) {
            System.arraycopy(options, 0, packet, tcpOffset + MIN_TCP_HEADER_LEN, options.size)
            // Zero-pad if needed
            for (i in options.size until paddedOptionsLength) {
                packet[tcpOffset + MIN_TCP_HEADER_LEN + i] = 0x00.toByte()
            }
        }

        // Payload
        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, packet, tcpOffset + tcpHeaderLength, payload.size)
        }

        // Compute TCP Checksum
        val tcpChecksum = computeTcpChecksum(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            packet = packet,
            tcpOffset = tcpOffset,
            tcpLength = tcpSegmentLength
        )
        packet[tcpOffset + 16] = ((tcpChecksum shr 8) and 0xFF).toByte()
        packet[tcpOffset + 17] = (tcpChecksum and 0xFF).toByte()

        return packet
    }

    private fun buildIPv4Header(packet: ByteArray, srcIp: ByteArray, dstIp: ByteArray, totalLength: Int) {
        packet[0] = 0x45.toByte() // IPv4, IHL = 5 (20 bytes)
        packet[1] = 0x00.toByte() // DSCP / ECN
        packet[2] = ((totalLength shr 8) and 0xFF).toByte()
        packet[3] = (totalLength and 0xFF).toByte()
        packet[4] = 0x00.toByte() // Identification
        packet[5] = 0x00.toByte()
        packet[6] = 0x40.toByte() // Don't Fragment flag
        packet[7] = 0x00.toByte()
        packet[8] = 64.toByte()   // TTL = 64
        packet[9] = PROTOCOL_TCP.toByte()
        packet[10] = 0x00.toByte() // Checksum placeholder
        packet[11] = 0x00.toByte()

        System.arraycopy(srcIp, 0, packet, 12, 4)
        System.arraycopy(dstIp, 0, packet, 16, 4)

        val ipChecksum = computeIpv4HeaderChecksum(packet, 0, MIN_IPV4_HEADER_LEN)
        packet[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        packet[11] = (ipChecksum and 0xFF).toByte()
    }

    private fun buildIPv6Header(packet: ByteArray, srcIp: ByteArray, dstIp: ByteArray, tcpSegmentLength: Int) {
        packet[0] = 0x60.toByte() // Version 6
        packet[1] = 0x00.toByte()
        packet[2] = 0x00.toByte()
        packet[3] = 0x00.toByte()
        packet[4] = ((tcpSegmentLength shr 8) and 0xFF).toByte()
        packet[5] = (tcpSegmentLength and 0xFF).toByte()
        packet[6] = PROTOCOL_TCP.toByte()
        packet[7] = 64.toByte() // Hop Limit = 64

        System.arraycopy(srcIp, 0, packet, 8, 16)
        System.arraycopy(dstIp, 0, packet, 24, 16)
    }

    fun computeIpv4HeaderChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        val end = offset + length
        while (i < end - 1) {
            val word = ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8)
        }
        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv().toInt() and 0xFFFF)
    }

    fun computeTcpChecksum(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        packet: ByteArray,
        tcpOffset: Int,
        tcpLength: Int
    ): Int {
        return if (isIPv6) {
            computeIPv6TcpChecksum(srcIp, dstIp, packet, tcpOffset, tcpLength)
        } else {
            computeIPv4TcpChecksum(srcIp, dstIp, packet, tcpOffset, tcpLength)
        }
    }

    private fun computeIPv4TcpChecksum(
        srcIp: ByteArray,
        dstIp: ByteArray,
        packet: ByteArray,
        tcpOffset: Int,
        tcpLength: Int
    ): Int {
        var sum = 0L

        // IPv4 Pseudo-Header
        // 1. Source IP (4 bytes = 2 words)
        sum += ((srcIp[0].toInt() and 0xFF) shl 8) or (srcIp[1].toInt() and 0xFF)
        sum += ((srcIp[2].toInt() and 0xFF) shl 8) or (srcIp[3].toInt() and 0xFF)

        // 2. Destination IP (4 bytes = 2 words)
        sum += ((dstIp[0].toInt() and 0xFF) shl 8) or (dstIp[1].toInt() and 0xFF)
        sum += ((dstIp[2].toInt() and 0xFF) shl 8) or (dstIp[3].toInt() and 0xFF)

        // 3. Zero + Protocol (6)
        sum += PROTOCOL_TCP

        // 4. TCP Length
        sum += tcpLength

        // 5. TCP Header + Payload
        var i = tcpOffset
        val end = tcpOffset + tcpLength
        while (i < end - 1) {
            val word = ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < end) {
            sum += ((packet[i].toInt() and 0xFF) shl 8)
        }

        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        return (sum.inv().toInt() and 0xFFFF)
    }

    private fun computeIPv6TcpChecksum(
        srcIp: ByteArray,
        dstIp: ByteArray,
        packet: ByteArray,
        tcpOffset: Int,
        tcpLength: Int
    ): Int {
        var sum = 0L

        // IPv6 Pseudo-Header
        // 1. Source IPv6 (16 bytes = 8 words)
        for (i in 0 until 16 step 2) {
            sum += ((srcIp[i].toInt() and 0xFF) shl 8) or (srcIp[i + 1].toInt() and 0xFF)
        }

        // 2. Destination IPv6 (16 bytes = 8 words)
        for (i in 0 until 16 step 2) {
            sum += ((dstIp[i].toInt() and 0xFF) shl 8) or (dstIp[i + 1].toInt() and 0xFF)
        }

        // 3. TCP Length (32-bit word in pseudo-header)
        sum += (tcpLength shr 16) and 0xFFFF
        sum += tcpLength and 0xFFFF

        // 4. Next Header (6 = TCP)
        sum += PROTOCOL_TCP

        // 5. TCP Header + Payload
        var i = tcpOffset
        val end = tcpOffset + tcpLength
        while (i < end - 1) {
            val word = ((packet[i].toInt() and 0xFF) shl 8) or (packet[i + 1].toInt() and 0xFF)
            sum += word
            i += 2
        }
        if (i < end) {
            sum += ((packet[i].toInt() and 0xFF) shl 8)
        }

        while ((sum shr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        return (sum.inv().toInt() and 0xFFFF)
    }

    /**
     * Verifies the TCP checksum of a packet.
     * Returns true if the checksum field matches the computed checksum.
     */
    fun verifyChecksum(packet: ByteArray, length: Int = packet.size): Boolean {
        if (length < MIN_IPV4_HEADER_LEN + MIN_TCP_HEADER_LEN) return false
        val version = (packet[0].toInt() shr 4) and 0x0F
        return when (version) {
            4 -> {
                val ihl = (packet[0].toInt() and 0x0F) * 4
                if (ihl < MIN_IPV4_HEADER_LEN || length < ihl + MIN_TCP_HEADER_LEN) return false
                val totalLength = ((packet[2].toInt() and 0xFF) shl 8) or (packet[3].toInt() and 0xFF)
                if (totalLength > length || totalLength < ihl + MIN_TCP_HEADER_LEN) return false
                val protocol = packet[9].toInt() and 0xFF
                if (protocol != PROTOCOL_TCP) return false

                val srcIp = packet.copyOfRange(12, 16)
                val dstIp = packet.copyOfRange(16, 20)
                val tcpLength = totalLength - ihl
                val currentChecksum = ((packet[ihl + 16].toInt() and 0xFF) shl 8) or (packet[ihl + 17].toInt() and 0xFF)

                // Temporarily zero checksum to recompute
                val packetCopy = packet.copyOf(totalLength)
                packetCopy[ihl + 16] = 0
                packetCopy[ihl + 17] = 0

                val computed = computeIPv4TcpChecksum(srcIp, dstIp, packetCopy, ihl, tcpLength)
                computed == currentChecksum
            }
            6 -> {
                if (length < IPV6_HEADER_LEN + MIN_TCP_HEADER_LEN) return false
                val payloadLength = ((packet[4].toInt() and 0xFF) shl 8) or (packet[5].toInt() and 0xFF)
                val totalLength = IPV6_HEADER_LEN + payloadLength
                if (totalLength > length || payloadLength < MIN_TCP_HEADER_LEN) return false
                val nextHeader = packet[6].toInt() and 0xFF
                if (nextHeader != PROTOCOL_TCP) return false

                val srcIp = packet.copyOfRange(8, 24)
                val dstIp = packet.copyOfRange(24, 40)
                val currentChecksum = ((packet[IPV6_HEADER_LEN + 16].toInt() and 0xFF) shl 8) or
                        (packet[IPV6_HEADER_LEN + 17].toInt() and 0xFF)

                val packetCopy = packet.copyOf(totalLength)
                packetCopy[IPV6_HEADER_LEN + 16] = 0
                packetCopy[IPV6_HEADER_LEN + 17] = 0

                val computed = computeIPv6TcpChecksum(srcIp, dstIp, packetCopy, IPV6_HEADER_LEN, payloadLength)
                computed == currentChecksum
            }
            else -> false
        }
    }

    /**
     * Builds a TCP SYN-ACK packet, including the MSS option (RFC 793 / 1122).
     */
    fun buildSynAckPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long,
        windowSize: Int = 65535,
        mss: Int = if (isIPv6) 1440 else 1460
    ): ByteArray {
        val mssOption = byteArrayOf(
            0x02, 0x04,
            ((mss shr 8) and 0xFF).toByte(),
            (mss and 0xFF).toByte()
        )
        return buildTcpPacket(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            sequenceNumber = sequenceNumber,
            acknowledgmentNumber = acknowledgmentNumber,
            flags = ParsedTcpPacket.FLAG_SYN or ParsedTcpPacket.FLAG_ACK,
            windowSize = windowSize,
            payload = ByteArray(0),
            options = mssOption
        )
    }

    /**
     * Builds a TCP ACK packet.
     */
    fun buildAckPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long,
        windowSize: Int = 65535
    ): ByteArray {
        return buildTcpPacket(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            sequenceNumber = sequenceNumber,
            acknowledgmentNumber = acknowledgmentNumber,
            flags = ParsedTcpPacket.FLAG_ACK,
            windowSize = windowSize,
            payload = ByteArray(0)
        )
    }

    /**
     * Builds a TCP Data packet with ACK (and optionally PSH).
     */
    fun buildDataPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long,
        payload: ByteArray,
        windowSize: Int = 65535,
        psh: Boolean = true
    ): ByteArray {
        val flags = if (psh) {
            ParsedTcpPacket.FLAG_PSH or ParsedTcpPacket.FLAG_ACK
        } else {
            ParsedTcpPacket.FLAG_ACK
        }
        return buildTcpPacket(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            sequenceNumber = sequenceNumber,
            acknowledgmentNumber = acknowledgmentNumber,
            flags = flags,
            windowSize = windowSize,
            payload = payload
        )
    }

    /**
     * Builds a TCP FIN-ACK packet.
     */
    fun buildFinAckPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long,
        windowSize: Int = 65535
    ): ByteArray {
        return buildTcpPacket(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            sequenceNumber = sequenceNumber,
            acknowledgmentNumber = acknowledgmentNumber,
            flags = ParsedTcpPacket.FLAG_FIN or ParsedTcpPacket.FLAG_ACK,
            windowSize = windowSize,
            payload = ByteArray(0)
        )
    }

    /**
     * Builds a TCP RST packet (with ACK if ackNumber > 0).
     */
    fun buildRstPacket(
        isIPv6: Boolean,
        srcIp: ByteArray,
        dstIp: ByteArray,
        srcPort: Int,
        dstPort: Int,
        sequenceNumber: Long,
        acknowledgmentNumber: Long = 0L,
        isAck: Boolean = false
    ): ByteArray {
        val flags = if (isAck) {
            ParsedTcpPacket.FLAG_RST or ParsedTcpPacket.FLAG_ACK
        } else {
            ParsedTcpPacket.FLAG_RST
        }
        return buildTcpPacket(
            isIPv6 = isIPv6,
            srcIp = srcIp,
            dstIp = dstIp,
            srcPort = srcPort,
            dstPort = dstPort,
            sequenceNumber = sequenceNumber,
            acknowledgmentNumber = acknowledgmentNumber,
            flags = flags,
            windowSize = 0,
            payload = ByteArray(0)
        )
    }
}
