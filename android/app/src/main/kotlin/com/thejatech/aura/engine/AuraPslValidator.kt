package com.thejatech.aura.engine

import android.content.Context
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress

sealed class AuraDomainValidationError(val code: String, override val message: String) : Exception(message) {
    class EmptyDomain : AuraDomainValidationError("EMPTY_DOMAIN", "Domain name cannot be empty.")
    class SingleLabelDomain(val domain: String) : AuraDomainValidationError(
        "SINGLE_LABEL_DOMAIN",
        "Domain '$domain' is a top-level domain without a registrable name."
    )
    class PublicSuffix(val domain: String) : AuraDomainValidationError(
        "PUBLIC_SUFFIX",
        "Domain '$domain' is a public suffix (TLD or registry suffix) and cannot be blocked as a whole."
    )
    class InvalidCharacters(val domain: String) : AuraDomainValidationError(
        "INVALID_CHARACTERS",
        "Domain '$domain' contains invalid characters."
    )
    class IpAddress(val domain: String) : AuraDomainValidationError(
        "IP_ADDRESS",
        "IP address '$domain' cannot be used as a domain firewall rule."
    )
}

class AuraPslValidator(rulesContent: String) {

    private val exactRules: Set<String>
    private val wildcardRules: Set<String>
    private val exceptionRules: Set<String>

    init {
        val exacts = mutableSetOf<String>()
        val wildcards = mutableSetOf<String>()
        val exceptions = mutableSetOf<String>()

        rulesContent.lineSequence().forEach { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("//") || trimmed.startsWith("#")) {
                return@forEach
            }
            val lower = trimmed.lowercase()
            when {
                lower.startsWith("!") -> exceptions.add(lower.drop(1))
                lower.startsWith("*.") -> wildcards.add(lower.drop(2))
                else -> exacts.add(lower)
            }
        }

        exactRules = exacts
        wildcardRules = wildcards
        exceptionRules = exceptions
    }

    fun getPublicSuffix(domain: String): String {
        val cleaned = domain.trim().trim('.').lowercase()
        val labels = cleaned.split('.')
        if (labels.isEmpty() || cleaned.isEmpty()) return cleaned

        val candidates = mutableListOf<String>()
        for (i in labels.indices) {
            candidates.add(labels.subList(i, labels.size).joinToString("."))
        }

        // 1. Check Exception rules (!city.kobe.jp)
        for (candidate in candidates) {
            if (exceptionRules.contains(candidate)) {
                val candidateLabels = candidate.split('.')
                return if (candidateLabels.size > 1) {
                    candidateLabels.drop(1).joinToString(".")
                } else {
                    ""
                }
            }
        }

        // 2. Check Wildcard and Exact rules; pick matching rule with most labels
        var bestSuffix: String? = null
        var bestLabelCount = -1

        for (candidate in candidates) {
            val candidateLabels = candidate.split('.')
            val count = candidateLabels.size

            if (count >= 2) {
                val parent = candidateLabels.drop(1).joinToString(".")
                if (wildcardRules.contains(parent)) {
                    if (count > bestLabelCount) {
                        bestSuffix = candidate
                        bestLabelCount = count
                    }
                }
            }

            if (exactRules.contains(candidate)) {
                if (count > bestLabelCount) {
                    bestSuffix = candidate
                    bestLabelCount = count
                }
            }
        }

        if (bestSuffix != null) {
            return bestSuffix
        }

        // Fallback: rightmost label (TLD)
        return labels.lastOrNull() ?: cleaned
    }

    fun isPublicSuffix(domain: String): Boolean {
        val cleaned = domain.trim().trim('.').lowercase()
        if (cleaned.isEmpty()) return false
        val suffix = getPublicSuffix(cleaned)
        return cleaned == suffix
    }

    fun registrableDomain(domain: String): String? {
        val cleaned = domain.trim().trim('.').lowercase()
        val labels = cleaned.split('.')
        if (labels.size < 2) return null

        val suffix = getPublicSuffix(cleaned)
        if (cleaned == suffix) return null

        val suffixLabels = suffix.split('.')
        if (labels.size <= suffixLabels.size) return null

        val registrableIndex = labels.size - suffixLabels.size - 1
        return labels.subList(registrableIndex, labels.size).joinToString(".")
    }

    fun validateRuleDomain(rawDomain: String): String {
        val trimmed = rawDomain.trim()
        if (trimmed.isEmpty()) {
            throw AuraDomainValidationError.EmptyDomain()
        }

        if (isIPAddress(trimmed)) {
            throw AuraDomainValidationError.IpAddress(trimmed)
        }

        var domain = trimmed.lowercase()

        // Strip scheme, paths, ports, trailing dots
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

        if (domain.isEmpty()) {
            throw AuraDomainValidationError.EmptyDomain()
        }

        if (isIPAddress(domain)) {
            throw AuraDomainValidationError.IpAddress(domain)
        }

        if (domain.length > 253) {
            throw AuraDomainValidationError.InvalidCharacters(domain)
        }

        val labels = domain.split('.')
        if (labels.size < 2) {
            throw AuraDomainValidationError.SingleLabelDomain(domain)
        }

        for (label in labels) {
            if (label.isEmpty() || label.length > 63 || label.startsWith('-') || label.endsWith('-')) {
                throw AuraDomainValidationError.InvalidCharacters(domain)
            }
            for (ch in label) {
                val isAlpha = (ch in 'a'..'z') || (ch in '0'..'9') || (ch == '-')
                if (!isAlpha) {
                    throw AuraDomainValidationError.InvalidCharacters(domain)
                }
            }
        }

        val tld = labels.last()
        if (tld.all { it in '0'..'9' }) {
            throw AuraDomainValidationError.IpAddress(domain)
        }

        if (isPublicSuffix(domain)) {
            throw AuraDomainValidationError.PublicSuffix(domain)
        }

        return domain
    }

    companion object {
        @Volatile
        private var instance: AuraPslValidator? = null

        fun getInstance(context: Context): AuraPslValidator {
            return instance ?: synchronized(this) {
                instance ?: loadFromAssets(context).also { instance = it }
            }
        }

        private fun loadFromAssets(context: Context): AuraPslValidator {
            return try {
                context.assets.open("public_suffix_list.dat").use { stream ->
                    BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { reader ->
                        AuraPslValidator(reader.readText())
                    }
                }
            } catch (e: Exception) {
                AuraPslValidator(FALLBACK_RULES)
            }
        }

        fun isIPAddress(raw: String): Boolean {
            val clean = raw.trim().trim('[', ']')
            if (clean.isEmpty()) return false
            return try {
                val addr = InetAddress.getByName(clean)
                addr.hostAddress == clean || clean.contains(":")
            } catch (_: Exception) {
                false
            }
        }

        private const val FALLBACK_RULES = """
com
org
net
edu
gov
mil
io
co.uk
gov.uk
ac.uk
"""
    }
}
