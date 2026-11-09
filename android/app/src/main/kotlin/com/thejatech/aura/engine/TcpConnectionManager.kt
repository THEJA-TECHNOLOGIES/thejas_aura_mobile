package com.thejatech.aura.engine

import com.thejatech.aura.packet.ParsedTcpPacket
import com.thejatech.aura.packet.TcpPacketParser
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.locks.ReentrantReadWriteLock

/**
 * Manages client-initiated TCP connections for DNS-over-TCP in the Aura VPN service.
 * Implements TCP state machine (RFC 793), sequence and ACK tracking with 32-bit circular
 * arithmetic, retransmission with RFC 6298 RTO algorithm, out-of-order segment buffering,
 * DNS-over-TCP stream framing (RFC 1035 / RFC 7766), and connection lifecycle bounds.
 */
class TcpConnectionManager(
    private val maxConnections: Int = MAX_CONNECTIONS,
    private val idleTimeoutMs: Long = IDLE_TIMEOUT_MS
) {

    enum class TcpState {
        CLOSED,
        SYN_RCVD,
        ESTABLISHED,
        CLOSE_WAIT,
        LAST_ACK,
        FIN_WAIT_1,
        FIN_WAIT_2,
        CLOSING,
        TIME_WAIT
    }

    data class ConnectionKey(
        val clientIp: ByteArray,
        val clientPort: Int,
        val auraIp: ByteArray,
        val auraPort: Int,
        val isIPv6: Boolean
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is ConnectionKey) return false
            return clientPort == other.clientPort &&
                    auraPort == other.auraPort &&
                    isIPv6 == other.isIPv6 &&
                    clientIp.contentEquals(other.clientIp) &&
                    auraIp.contentEquals(other.auraIp)
        }

        override fun hashCode(): Int {
            var result = (if (isIPv6) 1 else 0)
            result = 31 * result + clientIp.contentHashCode()
            result = 31 * result + clientPort
            result = 31 * result + auraIp.contentHashCode()
            result = 31 * result + auraPort
            return result
        }

        override fun toString(): String {
            val cIp = if (isIPv6) formatIpv6(clientIp) else formatIpv4(clientIp)
            val aIp = if (isIPv6) formatIpv6(auraIp) else formatIpv4(auraIp)
            return "$cIp:$clientPort -> $aIp:$auraPort"
        }

        private fun formatIpv4(bytes: ByteArray): String =
            bytes.joinToString(".") { (it.toInt() and 0xFF).toString() }

        private fun formatIpv6(bytes: ByteArray): String {
            val parts = mutableListOf<String>()
            for (i in 0 until 16 step 2) {
                val word = ((bytes[i].toInt() and 0xFF) shl 8) or (bytes[i + 1].toInt() and 0xFF)
                parts.add(word.toString(16))
            }
            return parts.joinToString(":")
        }
    }

    data class DnsQueryPacket(
        val connectionKey: ConnectionKey,
        val dnsPayload: ByteArray
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is DnsQueryPacket) return false
            return connectionKey == other.connectionKey && dnsPayload.contentEquals(other.dnsPayload)
        }

        override fun hashCode(): Int {
            return 31 * connectionKey.hashCode() + dnsPayload.contentHashCode()
        }
    }

    data class TcpProcessingResult(
        val packetsToSend: List<ByteArray> = emptyList(),
        val readyQueries: List<DnsQueryPacket> = emptyList()
    )

    data class SentSegment(
        val seq: Long,
        val endSeq: Long,
        val packet: ByteArray,
        val sendTime: Long,
        var retransmitCount: Int = 0,
        var nextRetryTime: Long = 0L
    )

    data class BufferedSegment(
        val seq: Long,
        val data: ByteArray
    )

    class TcpConnection(
        val key: ConnectionKey,
        var state: TcpState = TcpState.CLOSED,
        var localSeq: Long = 0L,
        var remoteSeq: Long = 0L,
        var expectedSeq: Long = 0L,
        var remoteAck: Long = 0L,
        val localWindow: Int = 65535,
        var remoteWindow: Int = 65535,
        var lastActivity: Long = System.currentTimeMillis(),
        var rto: Long = INITIAL_RTO,
        var srtt: Long = 0L,
        var rttvar: Long = 0L,
        var receiveBuffer: ByteArray = ByteArray(0),
        val outOfOrderSegments: MutableList<BufferedSegment> = mutableListOf(),
        val unackedSegments: MutableList<SentSegment> = mutableListOf()
    ) {
        val lock = Any()
    }

    object SequenceNumber {
        fun add(seq: Long, count: Long): Long = (seq + count) and 0xFFFFFFFFL
        fun sub(a: Long, b: Long): Long = (a - b) and 0xFFFFFFFFL

        /**
         * Returns true if a < b in 32-bit modular sequence arithmetic.
         */
        fun lessThan(a: Long, b: Long): Boolean = ((a - b).toInt()) < 0

        fun lessThanOrEqual(a: Long, b: Long): Boolean = ((a - b).toInt()) <= 0

        fun greaterThan(a: Long, b: Long): Boolean = ((a - b).toInt()) > 0

        fun greaterThanOrEqual(a: Long, b: Long): Boolean = ((a - b).toInt()) >= 0
    }

    private val connections = ConcurrentHashMap<ConnectionKey, TcpConnection>()
    private val random = SecureRandom()
    private val halfOpenCount = AtomicInteger(0)
    private val admissionLock = Any()
    private val lifecycleLock = ReentrantReadWriteLock()

    private fun decrementHalfOpen() {
        halfOpenCount.updateAndGet { count -> maxOf(0, count - 1) }
    }

    /**
     * Process an incoming raw TCP packet parsed by TcpPacketParser.
     */
    fun handlePacket(
        packet: ParsedTcpPacket,
        now: Long = System.currentTimeMillis()
    ): TcpProcessingResult {
        lifecycleLock.readLock().lock()
        try {
            val key = ConnectionKey(
                clientIp = packet.sourceIp,
                clientPort = packet.sourcePort,
                auraIp = packet.destinationIp,
                auraPort = packet.destinationPort,
                isIPv6 = packet.isIPv6
            )

            // Handle RST flag immediately
            if (packet.isRst) {
                connections.remove(key)?.let { removedConn ->
                    if (removedConn.state == TcpState.SYN_RCVD) {
                        decrementHalfOpen()
                    }
                }
                return TcpProcessingResult()
            }

            var conn = connections[key]

            if (conn == null) {
                // No existing connection
                if (packet.isSyn && !packet.isAck) {
                    // Client is initiating a connection with SYN
                    conn = createConnection(key, packet, now)
                    if (conn == null) {
                        // Check if connection was created concurrently by a racing thread
                        val concurrentConn = connections[key]
                        if (concurrentConn != null) {
                            conn = concurrentConn
                        } else {
                            // Resource exhaustion: reply with RST
                            val rstPacket = TcpPacketParser.buildRstPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = 0L,
                                acknowledgmentNumber = SequenceNumber.add(packet.sequenceNumber, 1L),
                                isAck = true
                            )
                            return TcpProcessingResult(packetsToSend = listOf(rstPacket))
                        }
                    }

                    if (conn != null && conn.state == TcpState.SYN_RCVD) {
                        synchronized(conn.lock) {
                            val synAckPacket = TcpPacketParser.buildSynAckPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = conn.localSeq,
                                acknowledgmentNumber = conn.expectedSeq,
                                windowSize = conn.localWindow,
                                mss = if (key.isIPv6) MSS_IPV6 else MSS_IPV4
                            )

                            if (conn.unackedSegments.isEmpty()) {
                                conn.unackedSegments.add(
                                    SentSegment(
                                        seq = conn.localSeq,
                                        endSeq = SequenceNumber.add(conn.localSeq, 1L),
                                        packet = synAckPacket,
                                        sendTime = now,
                                        retransmitCount = 0,
                                        nextRetryTime = now + conn.rto
                                    )
                                )
                            }

                            return TcpProcessingResult(packetsToSend = listOf(synAckPacket))
                        }
                    }
                } else {
                    // Non-SYN packet for non-existent connection: reply with RST
                    val rstPacket = if (packet.isAck) {
                        TcpPacketParser.buildRstPacket(
                            isIPv6 = key.isIPv6,
                            srcIp = key.auraIp,
                            dstIp = key.clientIp,
                            srcPort = key.auraPort,
                            dstPort = key.clientPort,
                            sequenceNumber = packet.acknowledgmentNumber,
                            acknowledgmentNumber = 0L,
                            isAck = false
                        )
                    } else {
                        val payloadLen = packet.payload.size.toLong()
                        val ackNum = SequenceNumber.add(packet.sequenceNumber, if (payloadLen > 0) payloadLen else 1L)
                        TcpPacketParser.buildRstPacket(
                            isIPv6 = key.isIPv6,
                            srcIp = key.auraIp,
                            dstIp = key.clientIp,
                            srcPort = key.auraPort,
                            dstPort = key.clientPort,
                            sequenceNumber = 0L,
                            acknowledgmentNumber = ackNum,
                            isAck = true
                        )
                    }
                    return TcpProcessingResult(packetsToSend = listOf(rstPacket))
                }
            }

            // Connection exists: handle state machine under connection lock
            synchronized(conn.lock) {
                conn.lastActivity = now
                conn.remoteWindow = packet.windowSize

                val packetsToSend = mutableListOf<ByteArray>()
                val readyQueries = mutableListOf<DnsQueryPacket>()

                when (conn.state) {
                    TcpState.SYN_RCVD -> {
                        if (packet.isSyn) {
                            // Duplicate SYN from client: retransmit SYN-ACK
                            val synAck = conn.unackedSegments.firstOrNull()?.packet
                            if (synAck != null) {
                                packetsToSend.add(synAck)
                            }
                        } else if (packet.isAck) {
                            val expectedAck = SequenceNumber.add(conn.localSeq, 1L)
                            if (packet.acknowledgmentNumber == expectedAck) {
                                // Handshake complete
                                conn.localSeq = expectedAck
                                conn.remoteAck = packet.acknowledgmentNumber
                                conn.unackedSegments.clear()
                                conn.state = TcpState.ESTABLISHED
                                decrementHalfOpen()

                                // If 3rd handshake packet also contains data, process it
                                if (packet.payload.isNotEmpty() || packet.isFin) {
                                    processEstablishedData(conn, packet, now, packetsToSend, readyQueries)
                                }
                            }
                        }
                    }

                    TcpState.ESTABLISHED -> {
                        processEstablishedData(conn, packet, now, packetsToSend, readyQueries)
                    }

                    TcpState.CLOSE_WAIT -> {
                        // Client already sent FIN; ACK any retransmitted client FIN or duplicate data
                        if (packet.payload.isNotEmpty() || packet.isFin) {
                            val ackPacket = TcpPacketParser.buildAckPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = conn.localSeq,
                                acknowledgmentNumber = conn.expectedSeq,
                                windowSize = conn.localWindow
                            )
                            packetsToSend.add(ackPacket)
                        }
                    }

                    TcpState.LAST_ACK -> {
                        if (packet.isAck && packet.acknowledgmentNumber == conn.localSeq) {
                            conn.state = TcpState.CLOSED
                            connections.remove(key)?.let { removedConn ->
                                if (removedConn.state == TcpState.SYN_RCVD) {
                                    decrementHalfOpen()
                                }
                            }
                        }
                    }

                    TcpState.FIN_WAIT_1 -> {
                        if (packet.isAck && packet.acknowledgmentNumber == conn.localSeq) {
                            conn.state = TcpState.FIN_WAIT_2
                        }
                        if (packet.isFin) {
                            conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, 1L)
                            val ackPacket = TcpPacketParser.buildAckPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = conn.localSeq,
                                acknowledgmentNumber = conn.expectedSeq,
                                windowSize = conn.localWindow
                            )
                            packetsToSend.add(ackPacket)
                            conn.state = if (conn.state == TcpState.FIN_WAIT_2) TcpState.TIME_WAIT else TcpState.CLOSING
                        }
                    }

                    TcpState.FIN_WAIT_2 -> {
                        if (packet.isFin) {
                            conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, 1L)
                            val ackPacket = TcpPacketParser.buildAckPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = conn.localSeq,
                                acknowledgmentNumber = conn.expectedSeq,
                                windowSize = conn.localWindow
                            )
                            packetsToSend.add(ackPacket)
                            conn.state = TcpState.TIME_WAIT
                        }
                    }

                    TcpState.CLOSING -> {
                        if (packet.isAck && packet.acknowledgmentNumber == conn.localSeq) {
                            conn.state = TcpState.TIME_WAIT
                        }
                    }

                    TcpState.TIME_WAIT, TcpState.CLOSED -> {
                        // Ignored or handled during cleanup
                    }
                }

                return TcpProcessingResult(packetsToSend = packetsToSend, readyQueries = readyQueries)
            }
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    private fun processEstablishedData(
        conn: TcpConnection,
        packet: ParsedTcpPacket,
        now: Long,
        packetsToSend: MutableList<ByteArray>,
        readyQueries: MutableList<DnsQueryPacket>
    ) {
        val key = conn.key

        // 1. Process client ACK
        if (packet.isAck) {
            handleIncomingAck(conn, packet.acknowledgmentNumber, now)
        }

        var shouldSendAck = false
        val payload = packet.payload
        val seq = packet.sequenceNumber

        // 2. Process payload sequence number
        if (payload.isNotEmpty()) {
            if (seq == conn.expectedSeq) {
                // In-order segment
                appendPayload(conn, payload)
                conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, payload.size.toLong())

                // Check buffered out-of-order segments to see if they can now be stitched in
                drainOutOfOrderSegments(conn)

                shouldSendAck = true
            } else if (SequenceNumber.lessThan(seq, conn.expectedSeq)) {
                // Old / duplicate data from client
                val overlap = SequenceNumber.sub(conn.expectedSeq, seq).toInt()
                if (overlap < payload.size) {
                    val remainingNewData = payload.copyOfRange(overlap, payload.size)
                    appendPayload(conn, remainingNewData)
                    conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, remainingNewData.size.toLong())
                    drainOutOfOrderSegments(conn)
                }
                // Send duplicate ACK to re-sync client
                shouldSendAck = true
            } else {
                // Out-of-order segment (future sequence number)
                bufferOutOfOrderSegment(conn, seq, payload)
                // Fast retransmit / duplicate ACK trigger
                shouldSendAck = true
            }
        }

        // 3. Process FIN flag
        if (packet.isFin) {
            // Client FIN consumes 1 sequence number
            if (seq == conn.expectedSeq || SequenceNumber.lessThan(seq, conn.expectedSeq)) {
                conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, 1L)
                conn.state = TcpState.CLOSE_WAIT
                shouldSendAck = true
            }
        }

        // 4. Extract framed DNS queries from accumulated stream
        val dnsQueries = extractFramedDnsQueries(conn)
        for (q in dnsQueries) {
            readyQueries.add(DnsQueryPacket(key, q))
        }

        // 5. Send ACK if data or FIN arrived
        if (shouldSendAck) {
            val ackPacket = TcpPacketParser.buildAckPacket(
                isIPv6 = key.isIPv6,
                srcIp = key.auraIp,
                dstIp = key.clientIp,
                srcPort = key.auraPort,
                dstPort = key.clientPort,
                sequenceNumber = conn.localSeq,
                acknowledgmentNumber = conn.expectedSeq,
                windowSize = conn.localWindow
            )
            packetsToSend.add(ackPacket)
        }
    }

    private fun handleIncomingAck(conn: TcpConnection, ack: Long, now: Long) {
        if (SequenceNumber.lessThanOrEqual(ack, conn.remoteAck) ||
            SequenceNumber.greaterThan(ack, conn.localSeq)
        ) {
            return
        }

        val iterator = conn.unackedSegments.iterator()
        while (iterator.hasNext()) {
            val seg = iterator.next()
            if (SequenceNumber.lessThanOrEqual(seg.endSeq, ack)) {
                if (seg.retransmitCount == 0) {
                    val sampleRtt = now - seg.sendTime
                    updateRto(conn, sampleRtt)
                }
                iterator.remove()
            }
        }
        conn.remoteAck = ack
    }

    private fun appendPayload(conn: TcpConnection, payload: ByteArray) {
        if (conn.receiveBuffer.size + payload.size > MAX_RECEIVE_BUFFER_SIZE) {
            // Buffer overflow protection: enforce cap
            return
        }
        val newBuf = ByteArray(conn.receiveBuffer.size + payload.size)
        System.arraycopy(conn.receiveBuffer, 0, newBuf, 0, conn.receiveBuffer.size)
        System.arraycopy(payload, 0, newBuf, conn.receiveBuffer.size, payload.size)
        conn.receiveBuffer = newBuf
    }

    private fun bufferOutOfOrderSegment(conn: TcpConnection, seq: Long, data: ByteArray) {
        if (conn.outOfOrderSegments.size >= MAX_OUT_OF_ORDER_SEGMENTS) {
            return
        }
        // Avoid duplicate entry in buffer
        if (conn.outOfOrderSegments.none { it.seq == seq }) {
            conn.outOfOrderSegments.add(BufferedSegment(seq, data))
        }
    }

    private fun drainOutOfOrderSegments(conn: TcpConnection) {
        var progress = true
        while (progress && conn.outOfOrderSegments.isNotEmpty()) {
            progress = false
            val matchingIndex = conn.outOfOrderSegments.indexOfFirst { it.seq == conn.expectedSeq }
            if (matchingIndex >= 0) {
                val seg = conn.outOfOrderSegments.removeAt(matchingIndex)
                appendPayload(conn, seg.data)
                conn.expectedSeq = SequenceNumber.add(conn.expectedSeq, seg.data.size.toLong())
                progress = true
            }
        }
    }

    private fun extractFramedDnsQueries(conn: TcpConnection): List<ByteArray> {
        val queries = mutableListOf<ByteArray>()
        var offset = 0
        val buf = conn.receiveBuffer

        while (buf.size - offset >= 2) {
            val len = ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)
            if (len > MAX_DNS_MESSAGE_SIZE) {
                // Safety limit exceeded: terminate connection to prevent DoS
                conn.state = TcpState.CLOSED
                connections.remove(conn.key)?.let { removedConn ->
                    if (removedConn.state == TcpState.SYN_RCVD) {
                        decrementHalfOpen()
                    }
                }
                return emptyList()
            }

            if (buf.size - offset >= 2 + len) {
                val queryBytes = buf.copyOfRange(offset + 2, offset + 2 + len)
                queries.add(queryBytes)
                offset += 2 + len
            } else {
                // Incomplete message; await further segments
                break
            }
        }

        if (offset > 0) {
            conn.receiveBuffer = if (offset < buf.size) {
                buf.copyOfRange(offset, buf.size)
            } else {
                ByteArray(0)
            }
        }

        return queries
    }

    /**
     * Packages a DNS response with 2-byte RFC 1035 framing, segments it according to MSS,
     * tracks unacknowledged segments for retransmission, and generates raw IP/TCP packets.
     */
    fun sendDnsResponse(
        key: ConnectionKey,
        dnsResponse: ByteArray,
        now: Long = System.currentTimeMillis()
    ): List<ByteArray> {
        lifecycleLock.readLock().lock()
        try {
            val conn = connections[key] ?: return emptyList()

            synchronized(conn.lock) {
                if (conn.state != TcpState.ESTABLISHED && conn.state != TcpState.CLOSE_WAIT) {
                    return emptyList()
                }

                val framed = ByteArray(2 + dnsResponse.size)
                framed[0] = ((dnsResponse.size shr 8) and 0xFF).toByte()
                framed[1] = (dnsResponse.size and 0xFF).toByte()
                System.arraycopy(dnsResponse, 0, framed, 2, dnsResponse.size)

                val mss = if (key.isIPv6) MSS_IPV6 else MSS_IPV4
                val packets = mutableListOf<ByteArray>()
                var offset = 0

                while (offset < framed.size) {
                    val chunkSize = minOf(mss, framed.size - offset)
                    val chunk = framed.copyOfRange(offset, offset + chunkSize)
                    val isLast = (offset + chunkSize >= framed.size)

                    val packet = TcpPacketParser.buildDataPacket(
                        isIPv6 = key.isIPv6,
                        srcIp = key.auraIp,
                        dstIp = key.clientIp,
                        srcPort = key.auraPort,
                        dstPort = key.clientPort,
                        sequenceNumber = conn.localSeq,
                        acknowledgmentNumber = conn.expectedSeq,
                        payload = chunk,
                        windowSize = conn.localWindow,
                        psh = isLast
                    )

                    val nextSeq = SequenceNumber.add(conn.localSeq, chunkSize.toLong())
                    conn.unackedSegments.add(
                        SentSegment(
                            seq = conn.localSeq,
                            endSeq = nextSeq,
                            packet = packet,
                            sendTime = now,
                            retransmitCount = 0,
                            nextRetryTime = now + conn.rto
                        )
                    )

                    conn.localSeq = nextSeq
                    packets.add(packet)
                    offset += chunkSize
                }

                conn.lastActivity = now
                return packets
            }
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    /**
     * Checks unacknowledged segments across all active connections and triggers retransmissions
     * or connection resets when max retransmissions are exceeded (RFC 6298).
     */
    fun checkRetransmissions(now: Long = System.currentTimeMillis()): List<ByteArray> {
        lifecycleLock.readLock().lock()
        try {
            val packetsToSend = mutableListOf<ByteArray>()
            val failedKeys = mutableListOf<ConnectionKey>()

            for ((key, conn) in connections) {
                synchronized(conn.lock) {
                    val iterator = conn.unackedSegments.iterator()
                    while (iterator.hasNext()) {
                        val seg = iterator.next()
                        if (now >= seg.nextRetryTime) {
                            if (seg.retransmitCount < MAX_RETRANSMITS) {
                                seg.retransmitCount++
                                conn.rto = minOf(MAX_RTO, conn.rto * 2)
                                seg.nextRetryTime = now + conn.rto
                                packetsToSend.add(seg.packet)
                            } else {
                                // Max retransmits reached: reset connection
                                failedKeys.add(key)
                                val rstPacket = TcpPacketParser.buildRstPacket(
                                    isIPv6 = key.isIPv6,
                                    srcIp = key.auraIp,
                                    dstIp = key.clientIp,
                                    srcPort = key.auraPort,
                                    dstPort = key.clientPort,
                                    sequenceNumber = conn.localSeq,
                                    acknowledgmentNumber = conn.expectedSeq,
                                    isAck = true
                                )
                                packetsToSend.add(rstPacket)
                                break
                            }
                        }
                    }
                }
            }

            for (k in failedKeys) {
                connections.remove(k)?.let { removedConn ->
                    if (removedConn.state == TcpState.SYN_RCVD) {
                        decrementHalfOpen()
                    }
                }
            }

            return packetsToSend
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    /**
     * Scans and cleans up connections that have exceeded the idle timeout.
     */
    fun cleanupIdleConnections(now: Long = System.currentTimeMillis()): List<ByteArray> {
        lifecycleLock.readLock().lock()
        try {
            val packetsToSend = mutableListOf<ByteArray>()
            val expiredKeys = mutableListOf<ConnectionKey>()

            for ((key, conn) in connections) {
                synchronized(conn.lock) {
                    val isHalfOpen = conn.state == TcpState.SYN_RCVD
                    val timeout = if (isHalfOpen) HALF_OPEN_TIMEOUT_MS else idleTimeoutMs

                    if (now - conn.lastActivity > timeout) {
                        expiredKeys.add(key)
                        if (conn.state == TcpState.ESTABLISHED || conn.state == TcpState.CLOSE_WAIT) {
                            val rstPacket = TcpPacketParser.buildRstPacket(
                                isIPv6 = key.isIPv6,
                                srcIp = key.auraIp,
                                dstIp = key.clientIp,
                                srcPort = key.auraPort,
                                dstPort = key.clientPort,
                                sequenceNumber = conn.localSeq,
                                acknowledgmentNumber = conn.expectedSeq,
                                isAck = true
                            )
                            packetsToSend.add(rstPacket)
                        }
                    }
                }
            }

            for (k in expiredKeys) {
                connections.remove(k)?.let { removedConn ->
                    if (removedConn.state == TcpState.SYN_RCVD) {
                        decrementHalfOpen()
                    }
                }
            }

            return packetsToSend
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    /**
     * Gracefully initiate close of an active connection by sending FIN-ACK.
     */
    fun closeConnection(key: ConnectionKey): ByteArray? {
        lifecycleLock.readLock().lock()
        try {
            val conn = connections[key] ?: return null
            synchronized(conn.lock) {
                if (conn.state == TcpState.CLOSED) return null

                val finPacket = TcpPacketParser.buildFinAckPacket(
                    isIPv6 = key.isIPv6,
                    srcIp = key.auraIp,
                    dstIp = key.clientIp,
                    srcPort = key.auraPort,
                    dstPort = key.clientPort,
                    sequenceNumber = conn.localSeq,
                    acknowledgmentNumber = conn.expectedSeq,
                    windowSize = conn.localWindow
                )

                conn.localSeq = SequenceNumber.add(conn.localSeq, 1L)
                conn.state = if (conn.state == TcpState.CLOSE_WAIT) TcpState.LAST_ACK else TcpState.FIN_WAIT_1
                return finPacket
            }
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    fun getConnection(key: ConnectionKey): TcpConnection? = connections[key]

    fun activeConnectionCount(): Int {
        lifecycleLock.readLock().lock()
        try {
            return connections.size
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    fun halfOpenConnectionCount(): Int {
        lifecycleLock.readLock().lock()
        try {
            return halfOpenCount.get()
        } finally {
            lifecycleLock.readLock().unlock()
        }
    }

    fun reset() {
        lifecycleLock.writeLock().lock()
        try {
            synchronized(admissionLock) {
                connections.clear()
                halfOpenCount.set(0)
            }
        } finally {
            lifecycleLock.writeLock().unlock()
        }
    }

    private fun createConnection(
        key: ConnectionKey,
        synPacket: ParsedTcpPacket,
        now: Long
    ): TcpConnection? {
        synchronized(admissionLock) {
            // Check if connection already exists (duplicate SYN in race)
            if (connections.containsKey(key)) {
                return null
            }

            // Check half-open limit (max 20)
            if (halfOpenCount.get() >= MAX_HALF_OPEN_CONNECTIONS) {
                return null
            }

            // Check established connection limit and evict if necessary
            if (connections.size >= maxConnections) {
                evictOldestConnection(now)
                if (connections.size >= maxConnections) {
                    return null
                }
            }

            // Atomically reserve capacity before insertion
            halfOpenCount.incrementAndGet()

            val isn = (random.nextInt().toLong() and 0xFFFFFFFFL)
            val initialExpectedSeq = SequenceNumber.add(synPacket.sequenceNumber, 1L)

            val conn = TcpConnection(
                key = key,
                state = TcpState.SYN_RCVD,
                localSeq = isn,
                remoteSeq = synPacket.sequenceNumber,
                expectedSeq = initialExpectedSeq,
                remoteAck = 0L,
                localWindow = 65535,
                remoteWindow = synPacket.windowSize,
                lastActivity = now,
                rto = INITIAL_RTO
            )

            // Insert under admissionLock
            val existing = connections.putIfAbsent(key, conn)
            if (existing != null) {
                // Collision: rollback reservation
                decrementHalfOpen()
                return null
            }

            return conn
        }
    }

    private fun evictOldestConnection(now: Long) {
        // First, try to evict expired half-open connections
        var evicted = false
        for ((key, conn) in connections) {
            synchronized(conn.lock) {
                if (conn.state == TcpState.SYN_RCVD && now - conn.lastActivity > HALF_OPEN_TIMEOUT_MS) {
                    connections.remove(key)?.let { removedConn ->
                        if (removedConn.state == TcpState.SYN_RCVD) {
                            decrementHalfOpen()
                        }
                    }
                    evicted = true
                    return
                }
            }
        }

        // Then, try to evict any expired connections
        for ((key, conn) in connections) {
            synchronized(conn.lock) {
                if (now - conn.lastActivity > idleTimeoutMs) {
                    connections.remove(key)?.let { removedConn ->
                        if (removedConn.state == TcpState.SYN_RCVD) {
                            decrementHalfOpen()
                        }
                    }
                    evicted = true
                    return
                }
            }
        }

        // Finally, evict the oldest connection (prefer half-open)
        var oldestHalfOpenKey: ConnectionKey? = null
        var oldestHalfOpenActivity = Long.MAX_VALUE
        var oldestKey: ConnectionKey? = null
        var oldestActivity = Long.MAX_VALUE

        for ((key, conn) in connections) {
            if (conn.state == TcpState.SYN_RCVD) {
                if (conn.lastActivity < oldestHalfOpenActivity) {
                    oldestHalfOpenActivity = conn.lastActivity
                    oldestHalfOpenKey = key
                }
            } else {
                if (conn.lastActivity < oldestActivity) {
                    oldestActivity = conn.lastActivity
                    oldestKey = key
                }
            }
        }

        // Prefer evicting half-open connections
        val keyToEvict = oldestHalfOpenKey ?: oldestKey
        keyToEvict?.let { connections.remove(it)?.let { removedConn ->
            if (removedConn.state == TcpState.SYN_RCVD) {
                decrementHalfOpen()
            }
        }}
    }

    /**
     * Updates RTO using the standard RFC 6298 algorithm:
     * First RTT measurement:
     *   SRTT = R, RTTVAR = R / 2, RTO = SRTT + max(G, 4 * RTTVAR)
     * Subsequent RTT measurements:
     *   RTTVAR = (1 - BETA) * RTTVAR + BETA * |SRTT - R|
     *   SRTT = (1 - ALPHA) * SRTT + ALPHA * R
     *   RTO = SRTT + 4 * RTTVAR
     */
    private fun updateRto(conn: TcpConnection, rtt: Long) {
        if (conn.srtt == 0L) {
            conn.srtt = rtt
            conn.rttvar = rtt / 2
        } else {
            val err = kotlin.math.abs(conn.srtt - rtt)
            conn.rttvar = ((1.0 - BETA) * conn.rttvar + BETA * err).toLong()
            conn.srtt = ((1.0 - ALPHA) * conn.srtt + ALPHA * rtt).toLong()
        }
        conn.rto = (conn.srtt + 4 * conn.rttvar).coerceIn(MIN_RTO, MAX_RTO)
    }

    companion object {
        const val MAX_CONNECTIONS = 100
        const val MAX_HALF_OPEN_CONNECTIONS = 20
        const val IDLE_TIMEOUT_MS = 30000L // 30 seconds
        const val HALF_OPEN_TIMEOUT_MS = 10000L // 10 seconds for half-open connections
        const val MAX_RETRANSMITS = 3
        const val INITIAL_RTO = 1000L // 1000 ms (1.0s) per RFC 6298 Section 2.1
        const val MIN_RTO = 200L // 200 ms (Linux TCP_RTO_MIN for low-latency interfaces)
        const val MAX_RTO = 60000L // 60 seconds
        const val MSS_IPV4 = 1460
        const val MSS_IPV6 = 1440
        const val MAX_RECEIVE_BUFFER_SIZE = 64 * 1024 // 64 KB
        const val MAX_OUT_OF_ORDER_SEGMENTS = 16
        const val MAX_DNS_MESSAGE_SIZE = 16384 // 16 KB safety limit

        private const val ALPHA = 0.125 // 1/8
        private const val BETA = 0.25   // 1/4
    }
}