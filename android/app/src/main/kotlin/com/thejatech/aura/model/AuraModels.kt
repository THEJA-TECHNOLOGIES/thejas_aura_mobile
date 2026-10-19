package com.thejatech.aura.model

import org.json.JSONArray
import org.json.JSONObject

enum class AuraTunnelStatus(val rawValue: String) {
    DISCONNECTED("disconnected"),
    CONNECTING("connecting"),
    CONNECTED("connected"),
    DISCONNECTING("disconnecting"),
    INVALID("invalid");

    companion object {
        fun fromString(raw: String): AuraTunnelStatus =
            values().firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: INVALID
    }
}

data class AuraRuleItem(
    val id: String,
    val domain: String,
    val isEnabled: Boolean = true,
    val isBlocked: Boolean = true
) {
    fun toDictionary(): Map<String, Any> = mapOf(
        "id" to id,
        "domain" to domain,
        "isEnabled" to isEnabled,
        "isBlocked" to isBlocked
    )

    fun toJsonObject(): JSONObject = JSONObject().apply {
        put("id", id)
        put("domain", domain)
        put("isEnabled", isEnabled)
        put("isBlocked", isBlocked)
    }

    companion object {
        fun fromDictionary(map: Map<*, *>): AuraRuleItem? {
            val domain = map["domain"] as? String ?: return null
            val id = (map["id"] as? String)?.takeIf { it.isNotBlank() } ?: domain
            val isEnabled = (map["isEnabled"] as? Boolean) ?: true
            val isBlocked = (map["isBlocked"] as? Boolean) ?: true
            return AuraRuleItem(id = id, domain = domain, isEnabled = isEnabled, isBlocked = isBlocked)
        }

        fun fromJsonObject(json: JSONObject): AuraRuleItem? {
            val domain = json.optString("domain") ?: return null
            if (domain.isBlank()) return null
            val id = json.optString("id").takeIf { !it.isNullOrBlank() } ?: domain
            val isEnabled = json.optBoolean("isEnabled", true)
            val isBlocked = json.optBoolean("isBlocked", true)
            return AuraRuleItem(id = id, domain = domain, isEnabled = isEnabled, isBlocked = isBlocked)
        }
    }
}

data class ActivityRecord(
    val id: Long? = null,
    val domain: String,
    val timestamp: Long = System.currentTimeMillis(),
    val queryType: String = "A",
    val outcome: String, // "blocked", "allowed", "failed"
    val matchedSource: String, // "default", "custom", "allowlist", "none"
    val matchedRuleId: String? = null,
    val matchedCategories: List<String> = emptyList(),
    val reason: String? = null,
    val appIdentifier: String? = null,
    val appName: String? = null,
    val appIconKey: String? = null
) {
    fun toDictionary(): Map<String, Any?> {
        val dict = mutableMapOf<String, Any?>(
            "id" to (id ?: 0L),
            "domain" to domain,
            "timestamp" to timestamp,
            "queryType" to queryType,
            "outcome" to outcome,
            "matchedSource" to matchedSource,
            "matchedCategories" to matchedCategories
        )
        if (matchedRuleId != null) dict["matchedRuleId"] = matchedRuleId
        if (reason != null) dict["reason"] = reason
        if (appIdentifier != null) dict["appIdentifier"] = appIdentifier
        if (appName != null) dict["appName"] = appName
        if (appIconKey != null) dict["appIconKey"] = appIconKey
        return dict
    }
}

data class PaginatedActivityResult(
    val records: List<ActivityRecord>,
    val nextCursorTimestamp: Long?,
    val nextCursorId: Long?,
    val hasMore: Boolean
) {
    fun toDictionary(): Map<String, Any?> {
        val dict = mutableMapOf<String, Any?>(
            "records" to records.map { it.toDictionary() },
            "hasMore" to hasMore
        )
        if (nextCursorTimestamp != null) dict["nextCursorTimestamp"] = nextCursorTimestamp
        if (nextCursorId != null) dict["nextCursorId"] = nextCursorId
        return dict
    }
}

data class DashboardStatsData(
    val timeWindowMillis: Long,
    val startTime: Long,
    val endTime: Long,
    val totalQueries: Long,
    val totalBlocked: Long,
    val totalAllowed: Long,
    val totalFailed: Long,
    val uniqueBlockedDomains: Long,
    val uniqueDomainsTotal: Long
) {
    fun toDictionary(): Map<String, Any> = mapOf(
        "timeWindowMillis" to timeWindowMillis,
        "startTime" to startTime,
        "endTime" to endTime,
        "totalQueries" to totalQueries,
        "totalBlocked" to totalBlocked,
        "totalAllowed" to totalAllowed,
        "totalFailed" to totalFailed,
        "uniqueBlockedDomains" to uniqueBlockedDomains,
        "uniqueDomainsTotal" to uniqueDomainsTotal
    )
}

data class TopBlockedDomainItem(
    val domain: String,
    val count: Long
) {
    fun toDictionary(): Map<String, Any> = mapOf(
        "domain" to domain,
        "count" to count
    )
}
