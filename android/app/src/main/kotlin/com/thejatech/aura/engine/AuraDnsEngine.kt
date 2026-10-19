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
                val answerBuf = ByteBuffer.allocate(10 + rdataLength)
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
