package com.thejatech.aura.database

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteStatement
import com.thejatech.aura.model.ActivityRecord
import org.json.JSONArray
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class AuraActivityDatabase(private val context: Context) : SQLiteOpenHelper(
    context,
    "dns_activity.sqlite",
    null,
    DATABASE_VERSION
) {
    companion object {
        const val DATABASE_VERSION = 1
        const val TABLE_DNS_ACTIVITY = "dns_activity"

        @Volatile
        private var instance: AuraActivityDatabase? = null

        fun getInstance(context: Context): AuraActivityDatabase {
            return instance ?: synchronized(this) {
                instance ?: AuraActivityDatabase(context.applicationContext).also { instance = it }
            }
        }
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.enableWriteAheadLogging()
    }

    override fun onCreate(db: SQLiteDatabase) {
        val ddl = """
            CREATE TABLE IF NOT EXISTS $TABLE_DNS_ACTIVITY (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                query_type TEXT NOT NULL,
                outcome TEXT NOT NULL,
                matched_source TEXT NOT NULL,
                matched_rule_id TEXT,
                matched_categories TEXT,
                reason TEXT,
                app_identifier TEXT,
                app_name TEXT,
                app_icon_key TEXT
            );
        """.trimIndent()
        db.execSQL(ddl)

        db.execSQL("CREATE INDEX IF NOT EXISTS idx_dns_activity_timestamp ON $TABLE_DNS_ACTIVITY(timestamp DESC);")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_dns_activity_outcome_timestamp ON $TABLE_DNS_ACTIVITY(outcome, timestamp DESC);")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_dns_activity_domain_timestamp ON $TABLE_DNS_ACTIVITY(domain, timestamp DESC);")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_dns_activity_app_timestamp ON $TABLE_DNS_ACTIVITY(app_identifier, timestamp DESC);")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Version 1 is initial
    }

    fun insertBatch(records: List<ActivityRecord>): Boolean {
        if (records.isEmpty()) return true
        val db = writableDatabase
        val sql = """
            INSERT INTO $TABLE_DNS_ACTIVITY (
                domain, timestamp, query_type, outcome,
                matched_source, matched_rule_id, matched_categories, reason,
                app_identifier, app_name, app_icon_key
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """.trimIndent()

        var stmt: SQLiteStatement? = null
        return try {
            db.beginTransaction()
            stmt = db.compileStatement(sql)
            for (record in records) {
                stmt.clearBindings()
                stmt.bindString(1, record.domain)
                stmt.bindLong(2, record.timestamp)
                stmt.bindString(3, record.queryType)
                stmt.bindString(4, record.outcome)
                stmt.bindString(5, record.matchedSource)

                if (record.matchedRuleId != null) stmt.bindString(6, record.matchedRuleId) else stmt.bindNull(6)

                if (record.matchedCategories.isNotEmpty()) {
                    val jsonArray = JSONArray(record.matchedCategories)
                    stmt.bindString(7, jsonArray.toString())
                } else {
                    stmt.bindNull(7)
                }

                if (record.reason != null) stmt.bindString(8, record.reason) else stmt.bindNull(8)
                if (record.appIdentifier != null) stmt.bindString(9, record.appIdentifier) else stmt.bindNull(9)
                if (record.appName != null) stmt.bindString(10, record.appName) else stmt.bindNull(10)
                if (record.appIconKey != null) stmt.bindString(11, record.appIconKey) else stmt.bindNull(11)

                stmt.executeInsert()
            }
            db.setTransactionSuccessful()
            true
        } catch (_: Exception) {
            false
        } finally {
            try {
                stmt?.close()
                db.endTransaction()
            } catch (_: Exception) {}
        }
    }

    fun pruneRetention(cutoffUtcMillis: Long): Int {
        val db = writableDatabase
        return db.delete(TABLE_DNS_ACTIVITY, "timestamp < ?", arrayOf(cutoffUtcMillis.toString()))
    }

    fun checkpointPassive(): Boolean {
        return try {
            val db = writableDatabase
            db.rawQuery("PRAGMA wal_checkpoint(PASSIVE);", null).use { cursor ->
                cursor.moveToFirst()
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}

class AuraActivityWriter(private val database: AuraActivityDatabase) {

    private val lock = Any()
    private val buffer = mutableListOf<ActivityRecord>()
    private var retryBatch: List<ActivityRecord>? = null
    private val maxCapacity = 500
    private val batchThreshold = 25
    private var isFlushing = false
    private var isRunning = false
    var droppedRecordCount: Int = 0
        private set

    private var executor: ScheduledExecutorService? = null

    fun start() {
        synchronized(lock) {
            if (isRunning) return
            isRunning = true
            executor = Executors.newSingleThreadScheduledExecutor { r ->
                Thread(r, "aura-activity-writer").apply { isDaemon = true }
            }
            executor?.scheduleWithFixedDelay(
                { flushPending() },
                500,
                500,
                TimeUnit.MILLISECONDS
            )
        }
    }

    fun stop() {
        synchronized(lock) {
            isRunning = false
            executor?.shutdown()
            executor = null
        }
    }

    fun enqueue(record: ActivityRecord) {
        synchronized(lock) {
            if (buffer.size >= maxCapacity) {
                // Drop oldest 100 records
                val dropCount = 100.coerceAtMost(buffer.size)
                for (i in 0 until dropCount) {
                    buffer.removeAt(0)
                }
                droppedRecordCount += dropCount
            }
            buffer.add(record)

            if (isRunning && buffer.size >= batchThreshold) {
                executor?.execute { flushPending() }
            }
        }
    }

    private fun flushPending() {
        var recordsToWrite: List<ActivityRecord> = emptyList()
        var isRetry = false

        synchronized(lock) {
            if (!isRunning || isFlushing) return
            isFlushing = true

            if (retryBatch != null) {
                recordsToWrite = retryBatch!!
                retryBatch = null
                isRetry = true
            } else if (buffer.isNotEmpty()) {
                val takeCount = batchThreshold.coerceAtMost(buffer.size)
                recordsToWrite = buffer.take(takeCount).toList()
                for (i in 0 until takeCount) {
                    buffer.removeAt(0)
                }
            }
        }

        if (recordsToWrite.isEmpty()) {
            synchronized(lock) {
                isFlushing = false
            }
            return
        }

        val success = database.insertBatch(recordsToWrite)

        synchronized(lock) {
            if (!success) {
                if (!isRetry) {
                    retryBatch = recordsToWrite
                } else {
                    droppedRecordCount += recordsToWrite.size
                }
            }
            isFlushing = false
            val hasMore = buffer.isNotEmpty() || retryBatch != null
            if (hasMore && isRunning) {
                executor?.execute { flushPending() }
            }
        }
    }

    fun flushAndClose(timeoutMillis: Long = 500L) {
        stop()
        val remaining = mutableListOf<ActivityRecord>()
        synchronized(lock) {
            retryBatch?.let { remaining.addAll(it) }
            retryBatch = null
            remaining.addAll(buffer)
            buffer.clear()
        }

        if (remaining.isNotEmpty()) {
            database.insertBatch(remaining)
        }
    }
}
