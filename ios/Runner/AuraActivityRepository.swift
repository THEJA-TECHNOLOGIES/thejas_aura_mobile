import Foundation
import SQLite3
import os.log

public enum AuraRepositoryError: Error, LocalizedError {
    case databaseNotFound
    case schemaIncompatible(Int32)
    case busyTimeout
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "Activity database file not found in App Group container."
        case .schemaIncompatible(let v):
            return "Incompatible database schema version (\(v))."
        case .busyTimeout:
            return "Database operation timed out waiting for busy lock."
        case .queryFailed(let msg):
            return "Query execution failed: \(msg)"
        }
    }

    public var errorCode: String {
        switch self {
        case .databaseNotFound: return "DATABASE_NOT_FOUND"
        case .schemaIncompatible: return "SCHEMA_INCOMPATIBLE"
        case .busyTimeout: return "BUSY_TIMEOUT"
        case .queryFailed: return "QUERY_FAILED"
        }
    }
}

/// Native repository for reading, filtering, and aggregating DNS activity records in the Runner process.
/// Enforces deterministic ordering, stable cursor pagination, parameterized SQL, and passive WAL checkpoints.
public final class AuraActivityRepository {

    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "AuraActivityRepository")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let databaseFileName = "dns_activity.sqlite"
    public static let currentSchemaVersion: Int32 = 1

    public struct RecordItem: Equatable {
        public let id: Int64
        public let domain: String
        public let timestamp: Int64
        public let queryType: String
        public let outcome: String
        public let matchedSource: String
        public let matchedRuleId: String?
        public let matchedCategories: [String]
        public let reason: String?
        public let appIdentifier: String?
        public let appName: String?
        public let appIconKey: String?

        public func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "id": id,
                "domain": domain,
                "timestamp": timestamp,
                "queryType": queryType,
                "outcome": outcome,
                "matchedSource": matchedSource,
                "matchedCategories": matchedCategories,
                "matched_categories": matchedCategories
            ]
            if let v = matchedRuleId { dict["matchedRuleId"] = v }
            if let v = reason { dict["reason"] = v }
            if let v = appIdentifier { dict["appIdentifier"] = v }
            if let v = appName { dict["appName"] = v }
            if let v = appIconKey { dict["appIconKey"] = v }
            return dict
        }
    }

    public struct PaginatedRecords: Equatable {
        public let records: [RecordItem]
        public let nextCursorTimestamp: Int64?
        public let nextCursorId: Int64?
        public let hasMore: Bool

        public func toDictionary() -> [String: Any] {
            var dict: [String: Any] = [
                "records": records.map { $0.toDictionary() },
                "hasMore": hasMore
            ]
            if let ts = nextCursorTimestamp { dict["nextCursorTimestamp"] = ts }
            if let id = nextCursorId { dict["nextCursorId"] = id }
            return dict
        }
    }

    public struct DashboardStats: Equatable {
        public let timeWindowMillis: Int64
        public let startTime: Int64
        public let endTime: Int64
        public let totalQueries: Int64
        public let totalBlocked: Int64
        public let totalAllowed: Int64
        public let totalFailed: Int64
        public let uniqueBlockedDomains: Int64
        public let uniqueDomainsTotal: Int64

        public func toDictionary() -> [String: Any] {
            return [
                "timeWindowMillis": timeWindowMillis,
                "startTime": startTime,
                "endTime": endTime,
                "totalQueries": totalQueries,
                "totalBlocked": totalBlocked,
                "totalAllowed": totalAllowed,
                "totalFailed": totalFailed,
                "uniqueBlockedDomains": uniqueBlockedDomains,
                "uniqueDomainsTotal": uniqueDomainsTotal
            ]
        }
    }

    public struct TopBlockedDomain: Equatable {
        public let domain: String
        public let count: Int64

        public func toDictionary() -> [String: Any] {
            return [
                "domain": domain,
                "count": count
            ]
        }
    }

    private let fileURL: URL?
    private var db: OpaquePointer?
    private let lock = NSLock()
    private var isClosed = true

    public static var defaultDatabaseURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier) else {
            return nil
        }
        return containerURL.appendingPathComponent(databaseFileName)
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultDatabaseURL
    }

    deinit {
        close()
    }

    // MARK: - Lifecycle & Connection

    /// Explicitly initializes the shared activity database without needing VPN connection.
    public func initialize() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let targetURL = fileURL else {
            throw AuraRepositoryError.databaseNotFound
        }

        do {
            try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: targetURL)
        } catch let err as AuraDatabaseError {
            switch err {
            case .containerUnavailable:
                throw AuraRepositoryError.databaseNotFound
            case .schemaIncompatible(let v):
                throw AuraRepositoryError.schemaIncompatible(v)
            case .initializationFailed(let msg):
                throw AuraRepositoryError.queryFailed(msg)
            }
        }
    }

    public func open() throws {
        lock.lock()
        defer { lock.unlock() }

        guard isClosed else { return }
        guard let targetURL = fileURL else {
            throw AuraRepositoryError.databaseNotFound
        }

        // Bootstrap if not yet created or initialized
        do {
            try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: targetURL)
        } catch let err as AuraDatabaseError {
            switch err {
            case .containerUnavailable:
                throw AuraRepositoryError.databaseNotFound
            case .schemaIncompatible(let v):
                throw AuraRepositoryError.schemaIncompatible(v)
            case .initializationFailed(let msg):
                throw AuraRepositoryError.queryFailed(msg)
            }
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(targetURL.path, &handle, flags, nil)
        guard status == SQLITE_OK, let openDb = handle else {
            let errMsg = handle != nil ? String(cString: sqlite3_errmsg(handle)) : "Failed to open sqlite database"
            if handle != nil { sqlite3_close(handle) }
            throw AuraRepositoryError.queryFailed(errMsg)
        }

        // Bounded busy timeout: 250 ms
        sqlite3_busy_timeout(openDb, 250)

        // Verify user_version
        var versionStmt: OpaquePointer?
        var userVersion: Int32 = 0
        if sqlite3_prepare_v2(openDb, "PRAGMA user_version;", -1, &versionStmt, nil) == SQLITE_OK {
            if sqlite3_step(versionStmt) == SQLITE_ROW {
                userVersion = sqlite3_column_int(versionStmt, 0)
            }
        }
        sqlite3_finalize(versionStmt)

        if userVersion > Self.currentSchemaVersion {
            sqlite3_close(openDb)
            throw AuraRepositoryError.schemaIncompatible(userVersion)
        }

        self.db = openDb
        self.isClosed = false
        os_log(.info, log: Self.log, "AuraActivityRepository opened database at %{public}@", targetURL.path)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, let db = db else { return }
        sqlite3_close(db)
        self.db = nil
        self.isClosed = true
        os_log(.info, log: Self.log, "AuraActivityRepository closed database.")
    }

    /// Performs a non-blocking passive checkpoint to truncate the WAL file without exclusive locks.
    /// Checkpoints are owned strictly by Runner.
    @discardableResult
    public func checkpointPassive() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isClosed, let db = db else { return false }
        var logSize: Int32 = 0
        var checkpointed: Int32 = 0
        let status = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, &logSize, &checkpointed)
        return status == SQLITE_OK
    }

    // MARK: - Cursor-Based Activity Query

    /// Fetches a paginated slice of activity records ordered deterministically by timestamp DESC, id DESC.
    public func queryActivity(
        limit: Int = 25,
        cursorTimestamp: Int64? = nil,
        cursorId: Int64? = nil,
        outcome: String? = nil,
        searchDomain: String? = nil,
        startTime: Int64? = nil,
        endTime: Int64? = nil
    ) throws -> PaginatedRecords {
        try ensureOpen()

        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw AuraRepositoryError.databaseNotFound }

        let clampedLimit = max(1, min(100, limit))
        let queryLimit = clampedLimit + 1 // Fetch 1 extra to determine hasMore deterministically

        var sql = """
        SELECT id, domain, timestamp, query_type, outcome, matched_source,
               matched_rule_id, matched_categories, reason, app_identifier,
               app_name, app_icon_key
        FROM dns_activity
        WHERE 1=1
        """

        var bindParams: [Any] = []

        // Cursor filter: (timestamp < :cursorTimestamp OR (timestamp = :cursorTimestamp AND id < :cursorId))
        if let cTs = cursorTimestamp, let cId = cursorId {
            sql += " AND (timestamp < ? OR (timestamp = ? AND id < ?))"
            bindParams.append(cTs)
            bindParams.append(cTs)
            bindParams.append(cId)
        }

        // Outcome filter
        if let out = outcome?.lowercased(), !out.isEmpty, out != "all" {
            sql += " AND outcome = ?"
            bindParams.append(out)
        }

        // Search domain filter (normalized with literal LIKE semantics)
        if let search = searchDomain?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !search.isEmpty {
            sql += " AND domain LIKE ? ESCAPE '\\'"
            let escaped = search
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            bindParams.append("%\(escaped)%")
        }

        // Time range filter (UTC Unix ms)
        if let start = startTime {
            sql += " AND timestamp >= ?"
            bindParams.append(start)
        }
        if let end = endTime {
            sql += " AND timestamp <= ?"
            bindParams.append(end)
        }

        // Deterministic ordering & limit
        sql += " ORDER BY timestamp DESC, id DESC LIMIT ?;"
        bindParams.append(Int32(queryLimit))

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let preparedStmt = stmt else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw AuraRepositoryError.queryFailed(errMsg)
        }
        defer { sqlite3_finalize(preparedStmt) }

        // Bind parameters safely
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, param) in bindParams.enumerated() {
            let bindIdx = Int32(index + 1)
            if let intVal = param as? Int64 {
                sqlite3_bind_int64(preparedStmt, bindIdx, intVal)
            } else if let int32Val = param as? Int32 {
                sqlite3_bind_int(preparedStmt, bindIdx, int32Val)
            } else if let strVal = param as? String {
                sqlite3_bind_text(preparedStmt, bindIdx, (strVal as NSString).utf8String, -1, transient)
            }
        }

        var results: [RecordItem] = []
        while sqlite3_step(preparedStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(preparedStmt, 0)
            let domain = String(cString: sqlite3_column_text(preparedStmt, 1))
            let timestamp = sqlite3_column_int64(preparedStmt, 2)
            let queryType = String(cString: sqlite3_column_text(preparedStmt, 3))
            let outcome = String(cString: sqlite3_column_text(preparedStmt, 4))
            let matchedSource = String(cString: sqlite3_column_text(preparedStmt, 5))

            var matchedRuleId: String? = nil
            if let txt = sqlite3_column_text(preparedStmt, 6) {
                matchedRuleId = String(cString: txt)
            }

            var categories: [String] = []
            if let catText = sqlite3_column_text(preparedStmt, 7) {
                let raw = String(cString: catText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    if raw.hasPrefix("["),
                       let catData = raw.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: catData) as? [String] {
                        categories = parsed.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    } else {
                        categories = raw.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
                            .filter { !$0.isEmpty }
                    }
                }
            }

            var reason: String? = nil
            if let txt = sqlite3_column_text(preparedStmt, 8) {
                reason = String(cString: txt)
            }

            var appIdentifier: String? = nil
            if let txt = sqlite3_column_text(preparedStmt, 9) {
                appIdentifier = String(cString: txt)
            }

            var appName: String? = nil
            if let txt = sqlite3_column_text(preparedStmt, 10) {
                appName = String(cString: txt)
            }

            var appIconKey: String? = nil
            if let txt = sqlite3_column_text(preparedStmt, 11) {
                appIconKey = String(cString: txt)
            }

            results.append(RecordItem(
                id: id,
                domain: domain,
                timestamp: timestamp,
                queryType: queryType,
                outcome: outcome,
                matchedSource: matchedSource,
                matchedRuleId: matchedRuleId,
                matchedCategories: categories,
                reason: reason,
                appIdentifier: appIdentifier,
                appName: appName,
                appIconKey: appIconKey
            ))
        }

        let hasMore = results.count > clampedLimit
        if hasMore {
            results.removeLast()
        }

        let nextCursorTimestamp = hasMore ? results.last?.timestamp : nil
        let nextCursorId = hasMore ? results.last?.id : nil

        return PaginatedRecords(
            records: results,
            nextCursorTimestamp: nextCursorTimestamp,
            nextCursorId: nextCursorId,
            hasMore: hasMore
        )
    }

    // MARK: - Dashboard Aggregates

    /// Computes dashboard statistical totals and distinct counts for a given time window.
    public func getDashboardStats(
        timeWindowMillis: Int64 = 86_400_000,
        currentTimeMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> DashboardStats {
        try ensureOpen()

        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw AuraRepositoryError.databaseNotFound }

        let isAllTime = timeWindowMillis <= 0
        let endTime = currentTimeMillis
        let startTime = isAllTime ? 0 : (endTime - timeWindowMillis)

        let sql = isAllTime ? """
        SELECT 
            COUNT(*) AS total_queries,
            COUNT(CASE WHEN outcome = 'blocked' THEN 1 END) AS total_blocked,
            COUNT(CASE WHEN outcome = 'allowed' THEN 1 END) AS total_allowed,
            COUNT(CASE WHEN outcome = 'failed' THEN 1 END) AS total_failed,
            COUNT(DISTINCT CASE WHEN outcome = 'blocked' THEN domain END) AS unique_blocked_domains,
            COUNT(DISTINCT domain) AS unique_domains_total
        FROM dns_activity;
        """ : """
        SELECT 
            COUNT(*) AS total_queries,
            COUNT(CASE WHEN outcome = 'blocked' THEN 1 END) AS total_blocked,
            COUNT(CASE WHEN outcome = 'allowed' THEN 1 END) AS total_allowed,
            COUNT(CASE WHEN outcome = 'failed' THEN 1 END) AS total_failed,
            COUNT(DISTINCT CASE WHEN outcome = 'blocked' THEN domain END) AS unique_blocked_domains,
            COUNT(DISTINCT domain) AS unique_domains_total
        FROM dns_activity
        WHERE timestamp >= ? AND timestamp <= ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let preparedStmt = stmt else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw AuraRepositoryError.queryFailed(errMsg)
        }
        defer { sqlite3_finalize(preparedStmt) }

        if !isAllTime {
            sqlite3_bind_int64(preparedStmt, 1, startTime)
            sqlite3_bind_int64(preparedStmt, 2, endTime)
        }

        var totalQueries: Int64 = 0
        var totalBlocked: Int64 = 0
        var totalAllowed: Int64 = 0
        var totalFailed: Int64 = 0
        var uniqueBlockedDomains: Int64 = 0
        var uniqueDomainsTotal: Int64 = 0

        if sqlite3_step(preparedStmt) == SQLITE_ROW {
            totalQueries = sqlite3_column_int64(preparedStmt, 0)
            totalBlocked = sqlite3_column_int64(preparedStmt, 1)
            totalAllowed = sqlite3_column_int64(preparedStmt, 2)
            totalFailed = sqlite3_column_int64(preparedStmt, 3)
            uniqueBlockedDomains = sqlite3_column_int64(preparedStmt, 4)
            uniqueDomainsTotal = sqlite3_column_int64(preparedStmt, 5)
        }

        return DashboardStats(
            timeWindowMillis: timeWindowMillis,
            startTime: startTime,
            endTime: endTime,
            totalQueries: totalQueries,
            totalBlocked: totalBlocked,
            totalAllowed: totalAllowed,
            totalFailed: totalFailed,
            uniqueBlockedDomains: uniqueBlockedDomains,
            uniqueDomainsTotal: uniqueDomainsTotal
        )
    }

    // MARK: - Frequently Blocked Domains

    /// Returns the top blocked domains ordered by block count descending.
    public func getTopBlockedDomains(
        limit: Int = 5,
        timeWindowMillis: Int64? = nil,
        currentTimeMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> [TopBlockedDomain] {
        try ensureOpen()

        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw AuraRepositoryError.databaseNotFound }

        let clampedLimit = max(1, min(50, limit))

        var sql = """
        SELECT domain, COUNT(*) AS block_count
        FROM dns_activity
        WHERE outcome = 'blocked'
        """

        if timeWindowMillis != nil {
            sql += " AND timestamp >= ? AND timestamp <= ?"
        }

        sql += " GROUP BY domain ORDER BY block_count DESC, domain ASC LIMIT ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let preparedStmt = stmt else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw AuraRepositoryError.queryFailed(errMsg)
        }
        defer { sqlite3_finalize(preparedStmt) }

        var bindIdx: Int32 = 1
        if let window = timeWindowMillis {
            let startTime = currentTimeMillis - window
            sqlite3_bind_int64(preparedStmt, bindIdx, startTime)
            bindIdx += 1
            sqlite3_bind_int64(preparedStmt, bindIdx, currentTimeMillis)
            bindIdx += 1
        }
        sqlite3_bind_int(preparedStmt, bindIdx, Int32(clampedLimit))

        var results: [TopBlockedDomain] = []
        while sqlite3_step(preparedStmt) == SQLITE_ROW {
            let domain = String(cString: sqlite3_column_text(preparedStmt, 0))
            let count = sqlite3_column_int64(preparedStmt, 1)
            results.append(TopBlockedDomain(domain: domain, count: count))
        }

        return results
    }

    public func getDailyBlockedActivity(startTime: Int64, endTime: Int64) throws -> [[String: Any]] {
        try ensureOpen()

        lock.lock()
        defer { lock.unlock() }

        guard let db = db else { throw AuraRepositoryError.databaseNotFound }

        let sql = """
        SELECT 
            strftime('%Y-%m-%d', timestamp / 1000, 'unixepoch', 'localtime') AS day,
            COUNT(*) AS blocked_count
        FROM dns_activity
        WHERE outcome = 'blocked' AND timestamp >= ? AND timestamp <= ?
        GROUP BY day
        ORDER BY day ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let preparedStmt = statement else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            throw AuraRepositoryError.queryFailed(errMsg)
        }
        defer { sqlite3_finalize(preparedStmt) }

        sqlite3_bind_int64(preparedStmt, 1, startTime)
        sqlite3_bind_int64(preparedStmt, 2, endTime)

        var results: [[String: Any]] = []
        while sqlite3_step(preparedStmt) == SQLITE_ROW {
            if let dayCStr = sqlite3_column_text(preparedStmt, 0) {
                let day = String(cString: dayCStr)
                let count = sqlite3_column_int64(preparedStmt, 1)
                results.append(["day": day, "count": count])
            }
        }
        return results
    }

    // MARK: - Helper

    private func ensureOpen() throws {
        if isClosed {
            try open()
        }
    }
}
