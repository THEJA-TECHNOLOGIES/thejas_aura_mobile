package com.thejatech.aura.database

import android.content.Context
import com.thejatech.aura.model.ActivityRecord
import com.thejatech.aura.model.DashboardStatsData
import com.thejatech.aura.model.PaginatedActivityResult
import com.thejatech.aura.model.TopBlockedDomainItem
import org.json.JSONArray

class AuraActivityRepository(private val context: Context) {

    private val dbHelper = AuraActivityDatabase.getInstance(context)

    fun initialize() {
        dbHelper.writableDatabase
    }

    fun queryActivity(
        limit: Int = 25,
        cursorTimestamp: Long? = null,
        cursorId: Long? = null,
        outcome: String? = null,
        searchDomain: String? = null,
        startTime: Long? = null,
        endTime: Long? = null
    ): PaginatedActivityResult {
        val clampedLimit = limit.coerceIn(1, 100)
        val queryLimit = clampedLimit + 1

        val sb = StringBuilder("""
            SELECT id, domain, timestamp, query_type, outcome, matched_source,
                   matched_rule_id, matched_categories, reason, app_identifier,
                   app_name, app_icon_key
            FROM ${AuraActivityDatabase.TABLE_DNS_ACTIVITY}
            WHERE 1=1
        """.trimIndent())

        val args = mutableListOf<String>()

        if (cursorTimestamp != null && cursorId != null) {
            sb.append(" AND (timestamp < ? OR (timestamp = ? AND id < ?))")
            args.add(cursorTimestamp.toString())
            args.add(cursorTimestamp.toString())
            args.add(cursorId.toString())
        }

        if (!outcome.isNullOrBlank() && !outcome.equals("all", ignoreCase = true)) {
            sb.append(" AND outcome = ?")
            args.add(outcome.lowercase())
        }

        if (!searchDomain.isNullOrBlank()) {
            val trimmed = searchDomain.trim().lowercase()
            val escaped = trimmed
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_")
            sb.append(" AND domain LIKE ? ESCAPE '\\'")
            args.add("%$escaped%")
        }

        if (startTime != null) {
            sb.append(" AND timestamp >= ?")
            args.add(startTime.toString())
        }

        if (endTime != null) {
            sb.append(" AND timestamp <= ?")
            args.add(endTime.toString())
        }

        sb.append(" ORDER BY timestamp DESC, id DESC LIMIT ?")
        args.add(queryLimit.toString())

        val records = mutableListOf<ActivityRecord>()
        val db = dbHelper.readableDatabase

        db.rawQuery(sb.toString(), args.toTypedArray()).use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val domain = cursor.getString(1)
                val timestamp = cursor.getLong(2)
                val queryType = cursor.getString(3)
                val outcomeVal = cursor.getString(4)
                val matchedSource = cursor.getString(5)
                val matchedRuleId = if (!cursor.isNull(6)) cursor.getString(6) else null

                val categories = mutableListOf<String>()
                if (!cursor.isNull(7)) {
                    try {
                        val array = JSONArray(cursor.getString(7))
                        for (i in 0 until array.length()) {
                            categories.add(array.getString(i))
                        }
                    } catch (_: Exception) {}
                }

                val reason = if (!cursor.isNull(8)) cursor.getString(8) else null
                val appIdentifier = if (!cursor.isNull(9)) cursor.getString(9) else null
                val appName = if (!cursor.isNull(10)) cursor.getString(10) else null
                val appIconKey = if (!cursor.isNull(11)) cursor.getString(11) else null

                records.add(
                    ActivityRecord(
                        id = id,
                        domain = domain,
                        timestamp = timestamp,
                        queryType = queryType,
                        outcome = outcomeVal,
                        matchedSource = matchedSource,
                        matchedRuleId = matchedRuleId,
                        matchedCategories = categories,
                        reason = reason,
                        appIdentifier = appIdentifier,
                        appName = appName,
                        appIconKey = appIconKey
                    )
                )
            }
        }

        val hasMore = records.size > clampedLimit
        if (hasMore) {
            records.removeAt(records.size - 1)
        }

        val nextCursorTimestamp = if (hasMore) records.lastOrNull()?.timestamp else null
        val nextCursorId = if (hasMore) records.lastOrNull()?.id else null

        return PaginatedActivityResult(
            records = records,
            nextCursorTimestamp = nextCursorTimestamp,
            nextCursorId = nextCursorId,
            hasMore = hasMore
        )
    }

    fun getDashboardStats(
        timeWindowMillis: Long = 86_400_000L,
        currentTimeMillis: Long = System.currentTimeMillis()
    ): DashboardStatsData {
        val isAllTime = timeWindowMillis <= 0
        val endTime = currentTimeMillis
        val startTime = if (isAllTime) 0L else (endTime - timeWindowMillis)

        val sql = if (isAllTime) {
            """
                SELECT 
                    COUNT(*) AS total_queries,
                    COUNT(CASE WHEN outcome = 'blocked' THEN 1 END) AS total_blocked,
                    COUNT(CASE WHEN outcome = 'allowed' THEN 1 END) AS total_allowed,
                    COUNT(CASE WHEN outcome = 'failed' THEN 1 END) AS total_failed,
                    COUNT(DISTINCT CASE WHEN outcome = 'blocked' THEN domain END) AS unique_blocked_domains,
                    COUNT(DISTINCT domain) AS unique_domains_total
                FROM ${AuraActivityDatabase.TABLE_DNS_ACTIVITY};
            """.trimIndent()
        } else {
            """
                SELECT 
                    COUNT(*) AS total_queries,
                    COUNT(CASE WHEN outcome = 'blocked' THEN 1 END) AS total_blocked,
                    COUNT(CASE WHEN outcome = 'allowed' THEN 1 END) AS total_allowed,
                    COUNT(CASE WHEN outcome = 'failed' THEN 1 END) AS total_failed,
                    COUNT(DISTINCT CASE WHEN outcome = 'blocked' THEN domain END) AS unique_blocked_domains,
                    COUNT(DISTINCT domain) AS unique_domains_total
                FROM ${AuraActivityDatabase.TABLE_DNS_ACTIVITY}
                WHERE timestamp >= ? AND timestamp <= ?;
            """.trimIndent()
        }

        val args = if (isAllTime) emptyArray() else arrayOf(startTime.toString(), endTime.toString())
        val db = dbHelper.readableDatabase

        var totalQueries = 0L
        var totalBlocked = 0L
        var totalAllowed = 0L
        var totalFailed = 0L
        var uniqueBlockedDomains = 0L
        var uniqueDomainsTotal = 0L

        db.rawQuery(sql, args).use { cursor ->
            if (cursor.moveToFirst()) {
                totalQueries = cursor.getLong(0)
                totalBlocked = cursor.getLong(1)
                totalAllowed = cursor.getLong(2)
                totalFailed = cursor.getLong(3)
                uniqueBlockedDomains = cursor.getLong(4)
                uniqueDomainsTotal = cursor.getLong(5)
            }
        }

        return DashboardStatsData(
            timeWindowMillis = timeWindowMillis,
            startTime = startTime,
            endTime = endTime,
            totalQueries = totalQueries,
            totalBlocked = totalBlocked,
            totalAllowed = totalAllowed,
            totalFailed = totalFailed,
            uniqueBlockedDomains = uniqueBlockedDomains,
            uniqueDomainsTotal = uniqueDomainsTotal
        )
    }

    fun getTopBlockedDomains(
        limit: Int = 5,
        timeWindowMillis: Long? = null,
        currentTimeMillis: Long = System.currentTimeMillis()
    ): List<TopBlockedDomainItem> {
        val clampedLimit = limit.coerceIn(1, 50)
        val sb = StringBuilder("""
            SELECT domain, COUNT(*) AS block_count
            FROM ${AuraActivityDatabase.TABLE_DNS_ACTIVITY}
            WHERE outcome = 'blocked'
        """.trimIndent())

        val args = mutableListOf<String>()

        if (timeWindowMillis != null && timeWindowMillis > 0) {
            val startTime = currentTimeMillis - timeWindowMillis
            sb.append(" AND timestamp >= ? AND timestamp <= ?")
            args.add(startTime.toString())
            args.add(currentTimeMillis.toString())
        }

        sb.append(" GROUP BY domain ORDER BY block_count DESC, domain ASC LIMIT ?")
        args.add(clampedLimit.toString())

        val results = mutableListOf<TopBlockedDomainItem>()
        val db = dbHelper.readableDatabase

        db.rawQuery(sb.toString(), args.toTypedArray()).use { cursor ->
            while (cursor.moveToNext()) {
                results.add(
                    TopBlockedDomainItem(
                        domain = cursor.getString(0),
                        count = cursor.getLong(1)
                    )
                )
            }
        }

        return results
    }

    fun checkpointPassive(): Boolean {
        return dbHelper.checkpointPassive()
    }
}
