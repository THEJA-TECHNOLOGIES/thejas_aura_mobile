package com.thejatech.aura.engine

import com.thejatech.aura.model.AuraRuleItem
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class AuraDnsEngine {

    data class MatchDecision(
        val isBlocked: Boolean,
        val matchedSource: String, // "allowlist", "custom", "default", "none"
        val matchedRule: String?,
        val matchedCategories: List<String>,
        val reason: String
    ) {
        companion object {
            fun allowedByAllowlist(rule: String, categories: List<String> = emptyList()): MatchDecision = MatchDecision(
                isBlocked = false,
                matchedSource = "allowlist",
                matchedRule = rule,
                matchedCategories = categories,
                reason = "Allowed by custom allowlist rule: $rule"
            )

            fun allowedDefault(domain: String, categories: List<String> = emptyList()): MatchDecision = MatchDecision(
                isBlocked = false,
                matchedSource = "none",
                matchedRule = null,
                matchedCategories = categories,
                reason = "Permitted domain"
            )

            fun blockedByCustom(rule: String, categories: List<String> = emptyList()): MatchDecision {
                val catStr = if (categories.isEmpty()) "" else " (also matches: ${categories.joinToString(", ")})"
                return MatchDecision(
                    isBlocked = true,
                    matchedSource = "custom",
                    matchedRule = rule,
                    matchedCategories = categories,
                    reason = "Blocked by custom rule: $rule$catStr"
                )
            }

            fun blockedByDefault(categories: List<String>, matchedDomain: String): MatchDecision = MatchDecision(
                isBlocked = true,
                matchedSource = "default",
                matchedRule = matchedDomain,
                matchedCategories = categories,
                reason = "Blocked by ${categories.joinToString(", ")}"
            )
        }
    }

    private var rules: Map<String, AuraRuleItem> = emptyMap()
    private var categories: Map<String, Set<String>> = emptyMap()
    private var categoryPreferences: Map<String, Boolean> = emptyMap()
    private var disabledDefaultDomains: Set<String> = emptySet()
    private val lock = Any()

    fun setRules(newRules: List<AuraRuleItem>) {
        synchronized(lock) {
            val map = mutableMapOf<String, AuraRuleItem>()
            for (rule in newRules) {
                val normalized = normalizeDomain(rule.domain)
                if (normalized.isNotEmpty()) {
                    map[normalized] = rule.copy(domain = normalized)
                }
            }
            rules = map
        }
    }

    fun setCategories(newCategories: Map<String, Set<String>>) {
        synchronized(lock) {
            categories = newCategories
        }
    }

    fun setCategoryPreferences(prefs: Map<String, Boolean>) {
        synchronized(lock) {
            categoryPreferences = prefs
        }
    }

    fun setDisabledDefaultDomains(domains: Set<String>) {
        synchronized(lock) {
            disabledDefaultDomains = domains
        }
    }

    private fun isCategoryEnabled(catName: String, prefs: Map<String, Boolean>): Boolean {
        prefs[catName]?.let { return it }
        val normTarget = catName.lowercase().replace("_", "").replace(" ", "").replace("-", "")
        for ((key, value) in prefs) {
            val normKey = key.lowercase().replace("_", "").replace(" ", "").replace("-", "")
            if (normKey == normTarget) {
                return value
            }
        }
        return true
    }

    fun evaluate(domain: String, pslValidator: AuraPslValidator? = null): MatchDecision {
        val target = normalizeDomain(domain)
        if (target.isEmpty()) {
            return MatchDecision.allowedDefault("")
        }

        val currentRules: Map<String, AuraRuleItem>
        val currentCategories: Map<String, Set<String>>
        val currentPrefs: Map<String, Boolean>
        val currentDisabled: Set<String>

        synchronized(lock) {
            currentRules = rules
            currentCategories = categories
            currentPrefs = categoryPreferences
            currentDisabled = disabledDefaultDomains
        }

        val candidates = generateCandidateSuffixes(target, pslValidator)
        if (candidates.isEmpty()) {
            return MatchDecision.allowedDefault(target)
        }

        // 1. Check Custom Allowlist (highest precedence)
        var matchedAllowRule: String? = null
        for (candidate in candidates) {
            val rule = currentRules[candidate]
            if (rule != null && rule.isEnabled && !rule.isBlocked) {
                matchedAllowRule = candidate
                break
            }
        }

        // 2. Check Custom Blocklist
        var matchedCustomBlock: String? = null
        for (candidate in candidates) {
            val rule = currentRules[candidate]
            if (rule != null && rule.isEnabled && rule.isBlocked) {
                matchedCustomBlock = candidate
                break
            }
        }

        // Check matching categories across all candidates
        val matchingEnabledCategories = mutableSetOf<String>()
        val allMatchingCategories = mutableSetOf<String>()
        var firstCategoryMatchedDomain: String? = null

        for ((catName, domainSet) in currentCategories) {
            val isEnabled = isCategoryEnabled(catName, currentPrefs)
            for (candidate in candidates) {
                if (domainSet.contains(candidate)) {
                    allMatchingCategories.add(catName)
                    if (isEnabled && !currentDisabled.contains(candidate)) {
                        matchingEnabledCategories.add(catName)
                        if (firstCategoryMatchedDomain == null) {
                            firstCategoryMatchedDomain = candidate
                        }
                    }
                    break
                }
            }
        }

        val sortedEnabledCategories = matchingEnabledCategories.sorted()
        val sortedAllCategories = allMatchingCategories.sorted()
        val recordCategories = if (sortedEnabledCategories.isNotEmpty()) sortedEnabledCategories else sortedAllCategories

        if (matchedAllowRule != null) {
            return MatchDecision.allowedByAllowlist(matchedAllowRule, recordCategories)
        }

        if (matchedCustomBlock != null) {
            return MatchDecision.blockedByCustom(matchedCustomBlock, recordCategories)
        }

        // 3. Check Default Categories
        if (sortedEnabledCategories.isNotEmpty()) {
            val matchedDomain = firstCategoryMatchedDomain ?: target
            return MatchDecision.blockedByDefault(sortedEnabledCategories, matchedDomain)
        }

        // 4. Default Allow
        return MatchDecision.allowedDefault(target, recordCategories)
    }

    data class DnsHeader(
        val id: Int,
        val flags: Int,
        val qdCount: Int,
        val anCount: Int,
        val nsCount: Int,
        val arCount: Int
    )

    data class DnsQuestion(
        val name: String,
        val qType: Int,
        val qClass: Int,
        val rawLength: Int
    )

    companion object {
        // =========================================================================
        // Private helper functions (must be defined first)
        // =========================================================================

        /**
         * Parses a DNS name from the packet, handling compression pointers.
         * Returns the new offset after the name.
         */
        private fun parseDnsName(data: ByteArray, offset: Int): Pair<Int, Boolean>? {
            var current = offset
            var jumped = false

            while (current < data.size) {
                val length = data[current].toInt() and 0xFF
                if (length == 0) {
                    return Pair(current + 1, jumped)
                }
                if ((length and 0xC0) == 0xC0) {
                    // Compression pointer
                    if (current + 1 >= data.size) return null
                    jumped = true
                    return Pair(current + 2, true)
                }
                if (current + 1 + length > data.size) return null
                current += 1 + length
            }
            return null
        }

        /**
         * Skips the specified number of resource records in the packet.
         * Returns the offset after the skipped records.
         */
        private fun skipResourceRecords(data: ByteArray, offset: Int, count: Int): Int {
            var current = offset
            repeat(count) {
                val nameResult = parseDnsName(data, current)
                if (nameResult == null) return current
                current = nameResult.first
                if (current + 10 > data.size) return current // TYPE+CLASS+TTL+RDLENGTH
                val rdlength = ((data[current + 8].toInt() and 0xFF) shl 8) or (data[current + 9].toInt() and 0xFF)
                current += 10 + rdlength
            }
            return current
        }

        // =========================================================================
        // EDNS0 Parsing and DNS Response Truncation
        // =========================================================================

        /**
         * Result of EDNS0 parsing from a DNS query.
         */
        data class Edns0Info(
            /** The advertised UDP payload size from the OPT record, or 512 if no OPT record. */
            val udpPayloadSize: Int,
            /** Whether an OPT record was found in the additional section. */
            val hasOptRecord: Boolean
        ) {
            companion object {
                val DEFAULT_UDP_PAYLOAD = 512
                val MIN_UDP_PAYLOAD = 512
                // Conservative operational cap to avoid fragmentation (IPv6 min MTU 1280 - 48 IP/UDP headers = 1232)
                val OPERATIONAL_CAP = 1232
            }
        }

        /**
         * Result of DNS response truncation.
         */
        data class TruncationResult(
            val truncatedResponse: ByteArray,
            val wasTruncated: Boolean
        )

        /**
         * Parses the EDNS0 OPT record from a DNS query to extract the client's advertised
         * UDP payload size. If no OPT record is present, returns the default of 512 bytes.
         *
         * @param queryDns The original DNS query packet
         * @return Edns0Info containing the UDP payload size and whether an OPT record was found
         */
        fun parseEdns0Info(queryDns: ByteArray): Edns0Info {
            return try {
                val header = parseHeader(queryDns) ?: return Edns0Info(Edns0Info.DEFAULT_UDP_PAYLOAD, false)
                if (header.qdCount == 0) return Edns0Info(Edns0Info.DEFAULT_UDP_PAYLOAD, false)

                // Parse question section to find where additional section starts
                val question = parseQuestion(queryDns, 12) ?: return Edns0Info(Edns0Info.DEFAULT_UDP_PAYLOAD, false)
                var current = 12 + question.rawLength

                // Skip answer, authority sections
                var remaining = header.anCount + header.nsCount
                current = skipResourceRecords(queryDns, current, remaining)

                // Now at additional section - look for OPT record (TYPE=41)
                var optPayloadSize: Int? = null
                var hasOptRecord = false

                var arCount = header.arCount
                var loopCurrent = current
                while (arCount > 0 && loopCurrent < queryDns.size) {
                    arCount--

                    // Parse record name (skip it)
                    val nameResult = parseDnsName(queryDns, loopCurrent)
                    if (nameResult == null) break
                    loopCurrent = nameResult.first

                    if (loopCurrent + 8 > queryDns.size) break // TYPE(2) + CLASS(2) + TTL(4) + RDLENGTH(2) = 10 minimum

                    val rtype = ((queryDns[loopCurrent].toInt() and 0xFF) shl 8) or (queryDns[loopCurrent + 1].toInt() and 0xFF)
                    val rclass = ((queryDns[loopCurrent + 2].toInt() and 0xFF) shl 8) or (queryDns[loopCurrent + 3].toInt() and 0xFF)

                    loopCurrent += 8 // Skip TYPE, CLASS, TTL

                    if (loopCurrent + 2 > queryDns.size) break
                    val rdlength = ((queryDns[loopCurrent].toInt() and 0xFF) shl 8) or (queryDns[loopCurrent + 1].toInt() and 0xFF)
                    loopCurrent += 2

                    if (rtype == 41 && rclass >= Edns0Info.MIN_UDP_PAYLOAD) { // TYPE=41 (OPT), CLASS = UDP payload size
                        // hasOptRecord = true
                        // OPT record RDATA format: options (variable length)
                        // The CLASS field in OPT record IS the UDP payload size
                        optPayloadSize = rclass
                    }

                    if (loopCurrent + rdlength > queryDns.size) break
                    loopCurrent += rdlength
                }
                current = loopCurrent

                val payloadSize = optPayloadSize?.coerceIn(Edns0Info.MIN_UDP_PAYLOAD, Edns0Info.OPERATIONAL_CAP)
                    ?: Edns0Info.DEFAULT_UDP_PAYLOAD

                Edns0Info(payloadSize, hasOptRecord)
            } catch (e: Exception) {
                Edns0Info(Edns0Info.DEFAULT_UDP_PAYLOAD, false)
            }
        }

        /**
         * Calculates the effective UDP response limit based on EDNS0 info and MTU constraints.
         */
        fun calculateEffectiveUdpLimit(edns0Info: Edns0Info): Int {
            // The effective limit is the minimum of:
            // 1. Client's advertised UDP payload size (from EDNS0)
            // 2. Operational cap (1232 bytes for IPv6-safe unfragmented)
            // 3. Path MTU estimate minus IP/UDP headers (conservative: 1500 - 28 = 1472 for IPv4)
            return edns0Info.udpPayloadSize.coerceAtMost(Edns0Info.OPERATIONAL_CAP)
        }

        /**
         * Truncates a DNS response to fit within the specified UDP payload limit.
         * Preserves header, question section, and complete resource records only.
         * Sets TC bit and updates section counts appropriately.
         *
         * @param responseDns The complete DNS response to potentially truncate
         * @param maxUdpPayload Maximum UDP payload size in bytes
         * @param isBlockedResponse Whether this is a locally synthesized blocked response
         * @param isServFailResponse Whether this is a locally synthesized SERVFAIL response
         * @return TruncationResult with the (possibly truncated) response and whether truncation occurred
         */
        fun truncateDnsResponse(
            responseDns: ByteArray,
            maxUdpPayload: Int,
            isBlockedResponse: Boolean = false,
            isServFailResponse: Boolean = false
        ): TruncationResult {
            if (responseDns.size <= maxUdpPayload) {
                return TruncationResult(responseDns, false)
            }

            return try {
                val header = parseHeader(responseDns) ?: return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                if (header.qdCount == 0) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)

                val question = parseQuestion(responseDns, 12) ?: return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                var current = 12 + question.rawLength

                // Parse all resource records, tracking their boundaries
                data class RecordBoundary(
                    val section: Int, // 0=answer, 1=authority, 2=additional
                    val startOffset: Int,
                    val endOffset: Int,
                    val recordSize: Int,
                    val isOptRecord: Boolean
                )

                val records = mutableListOf<RecordBoundary>()
                val sectionCounts = intArrayOf(header.anCount, header.nsCount, header.arCount)

                for (section in 0..2) {
                    var sectionCount = sectionCounts[section]
                    while (sectionCount > 0) {
                        sectionCount--
                        if (current >= responseDns.size) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)

                        val recordStart = current
                        val nameResult = parseDnsName(responseDns, current)
                        if (nameResult == null) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                        current = nameResult.first

                        if (current + 10 > responseDns.size) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                        val rtype = ((responseDns[current].toInt() and 0xFF) shl 8) or (responseDns[current + 1].toInt() and 0xFF)
                        val rclass = ((responseDns[current + 2].toInt() and 0xFF) shl 8) or (responseDns[current + 3].toInt() and 0xFF)
                        current += 8 // Skip TYPE, CLASS, TTL
                        if (current + 2 > responseDns.size) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                        val rdlength = ((responseDns[current].toInt() and 0xFF) shl 8) or (responseDns[current + 1].toInt() and 0xFF)
                        current += 2

                        val isOpt = rtype == 41
                        if (current + rdlength > responseDns.size) return TruncationResult(responseDns.copyOf(maxUdpPayload), true)
                        current += rdlength

                        records.add(RecordBoundary(section, recordStart, current, current - recordStart, isOpt))
                    }
                }

                // Determine which records fit within the limit
                val headerSize = 12
                val questionSize = question.rawLength
                val fixedOverhead = headerSize + questionSize

                var includedRecords = mutableListOf<RecordBoundary>()
                var currentSize = fixedOverhead

                for (record in records) {
                    if (currentSize + record.recordSize > maxUdpPayload) {
                        break
                    }
                    currentSize += record.recordSize
                    includedRecords.add(record)
                }

                // If we can't even fit the header + question, return minimal response
                if (fixedOverhead > maxUdpPayload) {
                    // Return minimal SERVFAIL
                    return TruncationResult(synthesizeServFailResponse(ByteArray(responseDns.size))?.copyOf(maxUdpPayload) ?: responseDns.copyOf(maxUdpPayload), true)
                }

                // Build truncated response
                val output = ByteArrayOutputStream()
                output.write(responseDns, 0, headerSize) // Header (will update counts later)
                output.write(responseDns, 12, questionSize) // Question

                // Write included records
                for (record in includedRecords) {
                    output.write(responseDns, record.startOffset, record.recordSize)
                }

                var truncated = output.toByteArray()

                // Update header: counts and TC bit
                if (truncated.size >= 12) {
                    // Update ANCOUNT, NSCOUNT, ARCOUNT
                    val anCount = includedRecords.count { it.section == 0 }
                    val nsCount = includedRecords.count { it.section == 1 }
                    val arCount = includedRecords.count { it.section == 2 }

                    // Update header counts (bytes 4-11)
                    val anCountBytes = ByteBuffer.allocate(2).putShort(anCount.toShort()).array()
                    val nsCountBytes = ByteBuffer.allocate(2).putShort(nsCount.toShort()).array()
                    val arCountBytes = ByteBuffer.allocate(2).putShort(arCount.toShort()).array()

                    truncated[4] = anCountBytes[0]
                    truncated[5] = anCountBytes[1]
                    truncated[6] = nsCountBytes[0]
                    truncated[7] = nsCountBytes[1]
                    truncated[10] = arCountBytes[0]
                    truncated[11] = arCountBytes[1]

                    // Set TC bit (bit 1 of flags byte at index 2)
                    truncated[2] = (truncated[2].toInt() or 0x02).toByte()
                }

                TruncationResult(truncated, true)
            } catch (e: Exception) {
                TruncationResult(responseDns.copyOf(maxUdpPayload), true)
            }
        }

        /**
         * Applies size-limiting to a DNS response before sending downstream.
         * Handles both upstream responses and locally synthesized responses.
         */
        fun limitDnsResponseSize(
            responseDns: ByteArray,
            queryDns: ByteArray,
            isBlockedResponse: Boolean = false,
            isServFailResponse: Boolean = false
        ): ByteArray {
            val edns0Info = parseEdns0Info(queryDns)
            val maxUdpPayload = calculateEffectiveUdpLimit(edns0Info)
            val result = truncateDnsResponse(responseDns, maxUdpPayload, isBlockedResponse, isServFailResponse)
            return result.truncatedResponse
        }

        fun normalizeDomain(raw: String): String {
            var domain = raw.trim().lowercase()
            val schemeIdx = domain.indexOf("://")
            if (schemeIdx >= 0) {
                domain = domain.substring(schemeIdx + 3)
            }
            val slashIdx = domain.indexOf('/')
            if (slashIdx >= 0) {
                domain = domain.substring(0, slashIdx)
            }
            val colonIdx = domain.indexOf(':')
            if (colonIdx >= 0) {
                domain = domain.substring(0, colonIdx)
            }
            while (domain.endsWith('.')) {
                domain = domain.dropLast(1)
            }
            return domain
        }

        fun generateCandidateSuffixes(domain: String, pslValidator: AuraPslValidator? = null): List<String> {
            val normalized = normalizeDomain(domain)
            if (normalized.isEmpty()) return emptyList()

            val parts = normalized.split('.')
            if (parts.size < 2) return emptyList()

            val candidates = mutableListOf<String>()
            for (i in parts.indices) {
                val candidate = parts.subList(i, parts.size).joinToString(".")
                if (pslValidator == null || !pslValidator.isPublicSuffix(candidate)) {
                    candidates.add(candidate)
                }
            }
            return candidates
        }

        fun parseHeader(data: ByteArray): DnsHeader? {
            if (data.size < 12) return null
            val buffer = ByteBuffer.wrap(data)
            val id = buffer.short.toInt() and 0xFFFF
            val flags = buffer.short.toInt() and 0xFFFF
            val qdCount = buffer.short.toInt() and 0xFFFF
            val anCount = buffer.short.toInt() and 0xFFFF
            val nsCount = buffer.short.toInt() and 0xFFFF
            val arCount = buffer.short.toInt() and 0xFFFF
            return DnsHeader(id, flags, qdCount, anCount, nsCount, arCount)
        }

        fun parseQuestion(data: ByteArray, offset: Int = 12): DnsQuestion? {
            if (data.size <= offset) return null
            var current = offset
            val domainParts = mutableListOf<String>()

            while (current < data.size) {
                val length = data[current].toInt() and 0xFF
                if (length == 0) {
                    current++
                    break
                }
                if ((length and 0xC0) == 0xC0) {
                    current += 2
                    break
                }
                current++
                if (current + length > data.size) return null
                val label = String(data, current, length, Charsets.UTF_8)
                domainParts.add(label)
                current += length
            }

            if (current + 4 > data.size) return null
            val buffer = ByteBuffer.wrap(data, current, 4)
            val qType = buffer.short.toInt() and 0xFFFF
            val qClass = buffer.short.toInt() and 0xFFFF

            val fullName = domainParts.joinToString(".")
            return DnsQuestion(fullName, qType, qClass, (current + 4) - offset)
        }

        fun createBlockedResponse(requestData: ByteArray): ByteArray? {
            val header = parseHeader(requestData) ?: return null
            if (header.qdCount == 0) return null
            val question = parseQuestion(requestData, 12) ?: return null

            val isA = question.qType == 1
            val isAaaa = question.qType == 28

            val out = ByteArrayOutputStream()

            // 1. Header (12 bytes)
            val headerBuf = ByteBuffer.allocate(12)
            headerBuf.putShort(header.id.toShort()) // Preserve original Transaction ID
            headerBuf.putShort(0x8180.toShort())    // Response, NoError, Recursion Available
            headerBuf.putShort(1.toShort())         // QDCOUNT = 1
            headerBuf.putShort((if (isA || isAaaa) 1 else 0).toShort()) // ANCOUNT = 1 for A/AAAA, 0 for NODATA
            headerBuf.putShort(0.toShort())         // NSCOUNT = 0
            headerBuf.putShort(0.toShort())         // ARCOUNT = 0
            out.write(headerBuf.array())

            // 2. Question section (copied verbatim from request)
            out.write(requestData, 12, question.rawLength)

            // 3. Answer Section: only generated for A and AAAA sinkholes
            if (isA || isAaaa) {
                val rdataLength = if (isAaaa) 16 else 4
                val answerBuf = ByteBuffer.allocate(12 + rdataLength)
                answerBuf.putShort(0xC00C.toShort())         // Name pointer to offset 12 (0xC00C)
                answerBuf.putShort(question.qType.toShort()) // TYPE matches original question type
                answerBuf.putShort(1.toShort())              // CLASS IN (1)
                answerBuf.putInt(300)                        // TTL 300s
                answerBuf.putShort(rdataLength.toShort())    // RDLENGTH
                answerBuf.put(ByteArray(rdataLength))        // 0.0.0.0 or ::
                out.write(answerBuf.array())
            }

            return out.toByteArray()
        }

        fun synthesizeBlockedResponse(requestData: ByteArray): ByteArray? = createBlockedResponse(requestData)

        fun synthesizeServFailResponse(requestData: ByteArray): ByteArray? {
            val header = parseHeader(requestData) ?: return null
            val question = if (header.qdCount > 0) parseQuestion(requestData, 12) else null

            val out = ByteArrayOutputStream()

            val headerBuf = ByteBuffer.allocate(12)
            headerBuf.putShort(header.id.toShort()) // Preserve original Transaction ID
            headerBuf.putShort(0x8182.toShort())    // Response, ServFail (RCODE 2)
            headerBuf.putShort((if (question != null) 1 else 0).toShort()) // QDCOUNT
            headerBuf.putShort(0.toShort())         // ANCOUNT = 0
            headerBuf.putShort(0.toShort())         // NSCOUNT = 0
            headerBuf.putShort(0.toShort())         // ARCOUNT = 0
            out.write(headerBuf.array())

            if (question != null) {
                out.write(requestData, 12, question.rawLength)
            }

            return out.toByteArray()
        }
    }
}
