package com.thejatech.aura.service

import com.thejatech.aura.engine.AuraDnsEngine
import com.thejatech.aura.engine.AuraPslValidator
import com.thejatech.aura.engine.TcpConnectionManager
import com.thejatech.aura.model.ActivityRecord
import com.thejatech.aura.packet.IpPacketParser
import com.thejatech.aura.packet.ParsedDnsPacket
import com.thejatech.aura.packet.ParsedTcpPacket
import com.thejatech.aura.packet.TcpPacketParser
import com.thejatech.aura.storage.AuraPreferences
import com.thejatech.aura.storage.VpnPolicySnapshot
import java.util.concurrent.ExecutorService
import android.util.Log

/**
 * Core TUN packet router and processor for Aura DNS Firewall.
 * Discriminates incoming IPv4/IPv6 packets:
 * - Directs UDP DNS on port 53 to DNS query handler.
 * - Directs TCP DNS on port 53 to TcpConnectionManager downstream state machine.
 * - Replies with TCP RST to DoT probes on port 853 to prevent Android connection stalls.
 * - Ignores unrelated TCP/UDP traffic.
 * Integrates DNS filtering, pause/passthrough, expiry reconciliation, upstream resolution,
 * and activity logging uniformly across UDP and TCP.
 */
class AuraDnsPacketProcessor(
    val dnsEngine: AuraDnsEngine,
    val tcpConnectionManager: TcpConnectionManager = TcpConnectionManager(),
    val pslValidator: AuraPslValidator? = null,
    val policyProvider: () -> VpnPolicySnapshot,
    val onPolicyReconciled: ((VpnPolicySnapshot) -> Unit)? = null,
    val upstreamResolver: (requestDns: ByteArray) -> ByteArray?,
    val packetWriter: (ByteArray) -> Unit,
    val activityLogger: ((ActivityRecord) -> Unit)? = null,
    val executor: ExecutorService? = null
) {
    private companion object {
        const val TAG = "AuraDnsPacketProcessor"
    }

    /**
     * Inspects a raw IP packet read from TUN and dispatches it to the appropriate handler.
     * Returns true if packet was handled as DNS or probe, false if ignored.
     */
    fun processPacket(packet: ByteArray, length: Int = packet.size, now: Long = System.currentTimeMillis()): Boolean {
        if (length < 20) return false

        val version = (packet[0].toInt() shr 4) and 0x0F
        return when (version) {
            4 -> processIPv4(packet, length, now)
            6 -> processIPv6(packet, length, now)
            else -> false
        }
    }

    private fun processIPv4(packet: ByteArray, length: Int, now: Long): Boolean {
        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (length < ihl + 8) return false

        val protocol = packet[9].toInt() and 0xFF
        val dstPort = ((packet[ihl + 2].toInt() and 0xFF) shl 8) or (packet[ihl + 3].toInt() and 0xFF)

        return when {
            protocol == 17 && dstPort == 53 -> {
                val parsed = IpPacketParser.parse(packet, length)
                if (parsed != null) {
                    dispatchQuery { handleUdpDnsQuery(parsed, now) }
                    true
                } else false
            }
            protocol == 6 && dstPort == 53 -> {
                handleTcpPacket(packet, length, now)
                true
            }
            protocol == 6 && dstPort == 853 -> {
                // Reply with TCP RST to Android Private DNS probe
                val rst = IpPacketParser.buildTcpResetPacket(packet, length)
                if (rst != null) {
                    packetWriter(rst)
                }
                true
            }
            else -> false
        }
    }

    private fun processIPv6(packet: ByteArray, length: Int, now: Long): Boolean {
        if (length < 48) return false

        val nextHeader = packet[6].toInt() and 0xFF
        val dstPort = ((packet[42].toInt() and 0xFF) shl 8) or (packet[43].toInt() and 0xFF)

        return when {
            nextHeader == 17 && dstPort == 53 -> {
                val parsed = IpPacketParser.parse(packet, length)
                if (parsed != null) {
                    dispatchQuery { handleUdpDnsQuery(parsed, now) }
                    true
                } else false
            }
            nextHeader == 6 && dstPort == 53 -> {
                handleTcpPacket(packet, length, now)
                true
            }
            nextHeader == 6 && dstPort == 853 -> {
                val parsedTcp = TcpPacketParser.parse(packet, length)
                if (parsedTcp != null) {
                    val rst = TcpPacketParser.buildRstPacket(
                        isIPv6 = true,
                        srcIp = parsedTcp.destinationIp,
                        dstIp = parsedTcp.sourceIp,
                        srcPort = parsedTcp.destinationPort,
                        dstPort = parsedTcp.sourcePort,
                        sequenceNumber = parsedTcp.acknowledgmentNumber,
                        acknowledgmentNumber = parsedTcp.sequenceNumber + (if (parsedTcp.isSyn) 1L else 0L),
                        isAck = true
                    )
                    packetWriter(rst)
                }
                true
            }
            else -> false
        }
    }

    private fun handleTcpPacket(packet: ByteArray, length: Int, now: Long) {
        val parsedTcp = TcpPacketParser.parse(packet, length) ?: return
        val result = tcpConnectionManager.handlePacket(parsedTcp, now)

        for (pkt in result.packetsToSend) {
            packetWriter(pkt)
        }

        for (query in result.readyQueries) {
            dispatchQuery {
                handleTcpDnsQuery(query.connectionKey, query.dnsPayload, now)
            }
        }
    }

    private fun dispatchQuery(block: () -> Unit) {
        if (executor != null && !executor.isShutdown) {
            executor.execute(block)
        } else {
            block()
        }
    }

    private fun evaluatePolicy(now: Long): VpnPolicySnapshot {
        var policy = policyProvider()
        if (policy.isExpiredPause(now)) {
            val renewed = VpnPolicySnapshot(AuraPreferences.POLICY_ENABLED, 0L)
            onPolicyReconciled?.invoke(renewed)
            policy = renewed
        }
        return policy
    }

    fun handleUdpDnsQuery(queryPacket: ParsedDnsPacket, now: Long = System.currentTimeMillis()) {
        val question = AuraDnsEngine.parseQuestion(queryPacket.dnsPayload, 12)
        val qTypeStr = formatQueryType(question?.qType)
        val policy = evaluatePolicy(now)

        if (question != null) {
            if (policy.isPaused(now)) {
                val upstreamResp = upstreamResolver(queryPacket.dnsPayload)
                handleUdpUpstreamResult(queryPacket, upstreamResp, question.name, qTypeStr, null, isPassthrough = true)
                return
            }

            val decision = dnsEngine.evaluate(question.name, pslValidator)
            if (decision.isBlocked) {
                val blockedDns = AuraDnsEngine.createBlockedResponse(queryPacket.dnsPayload)
                if (blockedDns != null) {
                    val limitedBlocked = AuraDnsEngine.limitDnsResponseSize(
                        blockedDns,
                        queryPacket.dnsPayload,
                        isBlockedResponse = true,
                        isServFailResponse = false
                    )
                    val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, limitedBlocked)
                    packetWriter(responsePacket)

                    logActivity(
                        domain = question.name,
                        queryType = qTypeStr,
                        outcome = "blocked",
                        matchedSource = decision.matchedSource,
                        matchedRuleId = decision.matchedRule,
                        matchedCategories = decision.matchedCategories,
                        reason = decision.reason
                    )
                    return
                }
            }

            val upstreamResp = upstreamResolver(queryPacket.dnsPayload)
            handleUdpUpstreamResult(queryPacket, upstreamResp, question.name, qTypeStr, decision, isPassthrough = false)
        } else {
            val upstreamResp = upstreamResolver(queryPacket.dnsPayload)
            handleUdpUpstreamResult(queryPacket, upstreamResp, null, "UNKNOWN", null, isPassthrough = false)
        }
    }

    private fun handleUdpUpstreamResult(
        queryPacket: ParsedDnsPacket,
        upstreamResp: ByteArray?,
        domain: String?,
        queryType: String,
        decision: AuraDnsEngine.MatchDecision?,
        isPassthrough: Boolean
    ) {
        // QNAME Matching: verify upstream response question matches the original query
        if (upstreamResp != null && !AuraDnsEngine.questionsMatch(queryPacket.dnsPayload, upstreamResp)) {
            Log.w(TAG, "QNAME mismatch detected — returning SERVFAIL")
            val servFail = AuraDnsEngine.synthesizeServFailResponse(queryPacket.dnsPayload)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    queryPacket.dnsPayload,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, limited)
                packetWriter(responsePacket)
            }
            return
        }

        // DNS Rebinding Protection: reject upstream responses containing private/reserved IPs
        if (upstreamResp != null && AuraDnsEngine.hasPrivateIpAnswers(upstreamResp)) {
            Log.w(TAG, "DNS rebinding attempt detected for domain=$domain — returning SERVFAIL")
            val servFail = AuraDnsEngine.synthesizeServFailResponse(queryPacket.dnsPayload)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    queryPacket.dnsPayload,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, limited)
                packetWriter(responsePacket)
            }

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "failed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = "DNS rebinding attempt — private IP in upstream answer"
                )
            }
            return
        }

        if (upstreamResp != null) {
            val limited = AuraDnsEngine.limitDnsResponseSize(
                upstreamResp,
                queryPacket.dnsPayload,
                isBlockedResponse = false,
                isServFailResponse = false
            )
            val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, limited)
            packetWriter(responsePacket)

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "allowed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = null
                )
            }
        } else {
            val servFail = AuraDnsEngine.synthesizeServFailResponse(queryPacket.dnsPayload)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    queryPacket.dnsPayload,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, limited)
                packetWriter(responsePacket)
            }

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "failed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = "Upstream resolution failed or timed out"
                )
            }
        }
    }

    fun handleTcpDnsQuery(
        key: TcpConnectionManager.ConnectionKey,
        dnsPayload: ByteArray,
        now: Long = System.currentTimeMillis()
    ) {
        val question = AuraDnsEngine.parseQuestion(dnsPayload, 12)
        val qTypeStr = formatQueryType(question?.qType)
        val policy = evaluatePolicy(now)

        if (question != null) {
            if (policy.isPaused(now)) {
                val upstreamResp = upstreamResolver(dnsPayload)
                handleTcpUpstreamResult(key, dnsPayload, upstreamResp, question.name, qTypeStr, null, isPassthrough = true, now = now)
                return
            }

            val decision = dnsEngine.evaluate(question.name, pslValidator)
            if (decision.isBlocked) {
                val blockedDns = AuraDnsEngine.createBlockedResponse(dnsPayload)
                if (blockedDns != null) {
                    val limitedBlocked = AuraDnsEngine.limitDnsResponseSize(
                        blockedDns,
                        dnsPayload,
                        isBlockedResponse = true,
                        isServFailResponse = false
                    )
                    sendTcpDnsResponse(key, limitedBlocked, now)

                    logActivity(
                        domain = question.name,
                        queryType = qTypeStr,
                        outcome = "blocked",
                        matchedSource = decision.matchedSource,
                        matchedRuleId = decision.matchedRule,
                        matchedCategories = decision.matchedCategories,
                        reason = decision.reason
                    )
                    return
                }
            }

            val upstreamResp = upstreamResolver(dnsPayload)
            handleTcpUpstreamResult(key, dnsPayload, upstreamResp, question.name, qTypeStr, decision, isPassthrough = false, now = now)
        } else {
            val upstreamResp = upstreamResolver(dnsPayload)
            handleTcpUpstreamResult(key, dnsPayload, upstreamResp, null, "UNKNOWN", null, isPassthrough = false, now = now)
        }
    }

    private fun handleTcpUpstreamResult(
        key: TcpConnectionManager.ConnectionKey,
        requestDns: ByteArray,
        upstreamResp: ByteArray?,
        domain: String?,
        queryType: String,
        decision: AuraDnsEngine.MatchDecision?,
        isPassthrough: Boolean,
        now: Long
    ) {
        // QNAME Matching: verify upstream response question matches the original query
        if (upstreamResp != null && !AuraDnsEngine.questionsMatch(requestDns, upstreamResp)) {
            Log.w(TAG, "QNAME mismatch detected — returning SERVFAIL")
            val servFail = AuraDnsEngine.synthesizeServFailResponse(requestDns)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    requestDns,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                sendTcpDnsResponse(key, limited, now)
            }
            return
        }

        // DNS Rebinding Protection: reject upstream responses containing private/reserved IPs
        if (upstreamResp != null && AuraDnsEngine.hasPrivateIpAnswers(upstreamResp)) {
            Log.w(TAG, "DNS rebinding attempt detected for domain=$domain — returning SERVFAIL")
            val servFail = AuraDnsEngine.synthesizeServFailResponse(requestDns)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    requestDns,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                sendTcpDnsResponse(key, limited, now)
            }

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "failed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = "DNS rebinding attempt — private IP in upstream answer"
                )
            }
            return
        }

        if (upstreamResp != null) {
            val validResponse = if (upstreamResp.size > TcpConnectionManager.MAX_DNS_MESSAGE_SIZE) {
                // Truncate at the last complete DNS record boundary to avoid cutting mid-record.
                // TCP responses must not be truncated per RFC 7766, so we cap at 16KB safety limit
                // and clear the TC bit (truncation signaling is UDP-only).
                val truncation = AuraDnsEngine.truncateDnsResponse(
                    upstreamResp,
                    TcpConnectionManager.MAX_DNS_MESSAGE_SIZE,
                    isBlockedResponse = false,
                    isServFailResponse = false
                )
                var result = truncation.truncatedResponse
                // Clear TC bit (byte index 2, bit 1 = 0x02) — TCP does not use truncation signaling
                if (result.size > 2) {
                    result[2] = (result[2].toInt() and 0xFD).toByte()
                }
                result
            } else {
                upstreamResp
            }
            sendTcpDnsResponse(key, validResponse, now)

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "allowed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = null
                )
            }
        } else {
            val servFail = AuraDnsEngine.synthesizeServFailResponse(requestDns)
            if (servFail != null) {
                val limited = AuraDnsEngine.limitDnsResponseSize(
                    servFail,
                    requestDns,
                    isBlockedResponse = false,
                    isServFailResponse = true
                )
                sendTcpDnsResponse(key, limited, now)
            }

            if (domain != null) {
                logActivity(
                    domain = domain,
                    queryType = queryType,
                    outcome = "failed",
                    matchedSource = if (isPassthrough) "passthrough" else (decision?.matchedSource ?: "none"),
                    matchedRuleId = decision?.matchedRule,
                    matchedCategories = decision?.matchedCategories ?: emptyList(),
                    reason = "Upstream resolution failed or timed out"
                )
            }
        }
    }

    private fun sendTcpDnsResponse(
        key: TcpConnectionManager.ConnectionKey,
        dnsResponse: ByteArray,
        now: Long
    ) {
        val packets = tcpConnectionManager.sendDnsResponse(key, dnsResponse, now)
        for (p in packets) {
            packetWriter(p)
        }
    }

    fun checkTimers(now: Long = System.currentTimeMillis()) {
        val retransmitPackets = tcpConnectionManager.checkRetransmissions(now)
        for (pkt in retransmitPackets) {
            packetWriter(pkt)
        }

        val cleanupPackets = tcpConnectionManager.cleanupIdleConnections(now)
        for (pkt in cleanupPackets) {
            packetWriter(pkt)
        }
    }

    private fun logActivity(
        domain: String,
        queryType: String,
        outcome: String,
        matchedSource: String,
        matchedRuleId: String?,
        matchedCategories: List<String>,
        reason: String?
    ) {
        activityLogger?.invoke(
            ActivityRecord(
                domain = domain,
                queryType = queryType,
                outcome = outcome,
                matchedSource = matchedSource,
                matchedRuleId = matchedRuleId,
                matchedCategories = matchedCategories,
                reason = reason
            )
        )
    }

    private fun formatQueryType(qType: Int?): String = when (qType) {
        1 -> "A"
        28 -> "AAAA"
        5 -> "CNAME"
        15 -> "MX"
        16 -> "TXT"
        65 -> "HTTPS"
        else -> if (qType != null) "TYPE$qType" else "UNKNOWN"
    }
}
