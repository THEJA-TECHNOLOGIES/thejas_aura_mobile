import Foundation
import SQLite3
import os.log

/// Data model representing a recorded DNS activity event.
public struct ActivityRecord: Equatable {
    public let id: Int64?
    public let domain: String
    public let timestamp: Int64 // UTC Unix milliseconds
    public let queryType: String // e.g. "A", "AAAA", "HTTPS"
    public let outcome: String // "blocked", "allowed", "failed"
    public let matchedSource: String // "default", "custom", "allowlist", "none"
    public let matchedRuleId: String? // matching domain rule or category ID
    public let matchedCategories: [String] // matching category names
    public let reason: String?
    public let appIdentifier: String?
    public let appName: String?
    public let appIconKey: String?

    public init(
        id: Int64? = nil,
        domain: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        queryType: String = "A",
        outcome: String,
        matchedSource: String,
        matchedRuleId: String? = nil,
        matchedCategories: [String] = [],
        reason: String? = nil,
        appIdentifier: String? = nil,
        appName: String? = nil,
        appIconKey: String? = nil
    ) {
        self.id = id
        self.domain = AuraDNSEngine.normalizeDomain(domain)
        self.timestamp = timestamp
        self.queryType = queryType.uppercased()
        self.outcome = outcome.lowercased()
        self.matchedSource = matchedSource.lowercased()
        self.matchedRuleId = matchedRuleId
        self.matchedCategories = matchedCategories.sorted()
        self.reason = reason
        self.appIdentifier = appIdentifier
        self.appName = appName
        self.appIconKey = appIconKey
    }
}

public enum AuraDatabaseError: LocalizedError {
    case containerUnavailable
    case initializationFailed(String)
    case schemaIncompatible(Int32)

    public var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "Activity database file not found in App Group container."
        case .initializationFailed(let msg):
            return "Failed to initialize activity database: \(msg)"
        case .schemaIncompatible(let v):
            return "Incompatible database schema version (\(v))."
        }
    }

    public var errorCode: String {
        switch self {
        case .containerUnavailable: return "DATABASE_NOT_FOUND"
        case .initializationFailed: return "INIT_FAILED"
        case .schemaIncompatible: return "SCHEMA_INCOMPATIBLE"
        }
    }
}

/// Native SQLite database repository for Theja's Aura DNS activity history.
/// Manages schema versioning, WAL mode, bounded busy timeout, and thread-safe batch transactions.
public final class AuraActivityDatabase {

    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "AuraActivityDatabase")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let databaseFileName = "dns_activity.sqlite"
    public static let currentSchemaVersion: Int32 = 1

    private static let bootstrapLock = NSLock()

    private var db: OpaquePointer?
    private let dbLock = NSLock()
    private var isClosed = true

    public static var defaultDatabaseURL: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier) else {
            return nil
        }
        return containerURL.appendingPathComponent(databaseFileName)
    }

    private let fileURL: URL?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultDatabaseURL
    }

    deinit {
        close()
    }

    // MARK: - Lifecycle & Initialization

    /// Ensures the shared App Group SQLite database and its schema are initialized idempotently.
    /// Creates parent directories, sets file protection, enables WAL mode, and initializes tables/indexes.
    @discardableResult
    public static func bootstrapSharedDatabase(fileURL: URL? = nil) throws -> URL {
        bootstrapLock.lock()
        defer { bootstrapLock.unlock() }

        guard let targetURL = fileURL ?? defaultDatabaseURL else {
            os_log(.error, log: Self.log, "Failed to resolve database file URL in App Group container")
            throw AuraDatabaseError.containerUnavailable
        }

        // 1. Ensure parent directory exists
        let directoryURL = targetURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            os_log(.error, log: Self.log, "Failed to create directory at %{public}@: %{public}@", directoryURL.path, error.localizedDescription)
            throw AuraDatabaseError.initializationFailed("Failed to create directory: \(error.localizedDescription)")
        }

        // 2. Open SQLite handle with CREATE flag
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        var dbHandle: OpaquePointer?
        let status = sqlite3_open_v2(targetURL.path, &dbHandle, flags, nil)
        guard status == SQLITE_OK, let db = dbHandle else {
            let errMsg = dbHandle != nil ? String(cString: sqlite3_errmsg(dbHandle)) : "Failed to open sqlite database"
            if dbHandle != nil { sqlite3_close(dbHandle) }
            os_log(.error, log: Self.log, "sqlite3_open_v2 bootstrap failed at %{public}@: %{public}@", targetURL.path, errMsg)
            throw AuraDatabaseError.initializationFailed(errMsg)
        }
        defer { sqlite3_close(db) }

        // 3. Set file protection for shared App Group background access
        try? FileManager.default.setAttributes([
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ], ofItemAtPath: targetURL.path)

        // 4. Bounded busy timeout: 250 ms
        sqlite3_busy_timeout(db, 250)

        // 5. Pragmas for WAL mode and synchronous = NORMAL
        _ = sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)

        // 6. Inspect schema version
        var versionStmt: OpaquePointer?
        var userVersion: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &versionStmt, nil) == SQLITE_OK {
            if sqlite3_step(versionStmt) == SQLITE_ROW {
                userVersion = sqlite3_column_int(versionStmt, 0)
            }
        }
        sqlite3_finalize(versionStmt)

        if userVersion > currentSchemaVersion {
            os_log(
                .error,
                log: Self.log,
                "Incompatible database schema: user_version %{public}d > supported version %{public}d",
                userVersion,
                currentSchemaVersion
            )
            throw AuraDatabaseError.schemaIncompatible(userVersion)
        }

        if userVersion == 0 {
            let ddl = """
            CREATE TABLE IF NOT EXISTS dns_activity (
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

            CREATE INDEX IF NOT EXISTS idx_dns_activity_timestamp 
                ON dns_activity(timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_outcome_timestamp 
                ON dns_activity(outcome, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_domain_timestamp 
                ON dns_activity(domain, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_app_timestamp 
                ON dns_activity(app_identifier, timestamp DESC);
            """

            var errMsg: UnsafeMutablePointer<CChar>?
            let res = sqlite3_exec(db, ddl, nil, nil, &errMsg)
            if res != SQLITE_OK {
                let errString = errMsg != nil ? String(cString: errMsg!) : "Unknown DDL error"
                sqlite3_free(errMsg)
                os_log(.error, log: Self.log, "Schema creation failed: %{public}s", errString)
                throw AuraDatabaseError.initializationFailed("Schema creation failed: \(errString)")
            }

            _ = sqlite3_exec(db, "PRAGMA user_version = \(currentSchemaVersion);", nil, nil, nil)
            os_log(.info, log: Self.log, "Initialized new activity database schema version %{public}d", currentSchemaVersion)
        }

        return targetURL
    }

    public func open() -> Bool {
        dbLock.lock()
        defer { dbLock.unlock() }

        guard isClosed else { return true }
        guard let targetURL = fileURL else {
            os_log(.error, log: Self.log, "Failed to resolve database file URL in App Group container")
            return false
        }

        do {
            try Self.bootstrapSharedDatabase(fileURL: targetURL)
        } catch {
            os_log(.error, log: Self.log, "Database bootstrap failed at %{public}@: %{public}@", targetURL.path, error.localizedDescription)
            return false
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(targetURL.path, &db, flags, nil)
        guard status == SQLITE_OK, let db = db else {
            let errMsg = String(cString: sqlite3_errmsg(self.db))
            os_log(.error, log: Self.log, "sqlite3_open_v2 failed at %{public}@: %{public}@", targetURL.path, errMsg)
            self.db = nil
            return false
        }

        // Configure WAL mode, normal synchronous, and bounded busy timeout (250 ms)
        sqlite3_busy_timeout(db, 250)
        executePragma("PRAGMA journal_mode = WAL;")
        executePragma("PRAGMA synchronous = NORMAL;")

        let initialized = initializeSchema(db)
        if !initialized {
            os_log(.error, log: Self.log, "Database schema initialization/version check failed at %{public}@", targetURL.path)
            sqlite3_close(db)
            self.db = nil
            return false
        }

        isClosed = false
        os_log(.info, log: Self.log, "Opened activity database at %{public}@ (WAL mode, version %{public}d)", targetURL.path, Self.currentSchemaVersion)
        return true
    }

    public func close() {
        dbLock.lock()
        defer { dbLock.unlock() }

        guard !isClosed, let db = db else { return }
        sqlite3_close(db)
        self.db = nil
        self.isClosed = true
        os_log(.info, log: Self.log, "Closed activity database.")
    }

    private func executePragma(_ sql: String) {
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                os_log(.error, log: Self.log, "PRAGMA failed (%{public}@): %{public}s", sql, err)
                sqlite3_free(errMsg)
            }
        }
    }

    private func initializeSchema(_ db: OpaquePointer) -> Bool {
        // 1. Check user_version
        var versionStmt: OpaquePointer?
        var userVersion: Int32 = 0
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &versionStmt, nil) == SQLITE_OK {
            if sqlite3_step(versionStmt) == SQLITE_ROW {
                userVersion = sqlite3_column_int(versionStmt, 0)
            }
        }
        sqlite3_finalize(versionStmt)

        if userVersion > Self.currentSchemaVersion {
            os_log(
                .error,
                log: Self.log,
                "Incompatible database schema: user_version %{public}d > supported version %{public}d",
                userVersion,
                Self.currentSchemaVersion
            )
            return false
        }

        if userVersion == 0 {
            // Fresh database: initialize schema version 1
            let ddl = """
            CREATE TABLE IF NOT EXISTS dns_activity (
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

            CREATE INDEX IF NOT EXISTS idx_dns_activity_timestamp 
                ON dns_activity(timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_outcome_timestamp 
                ON dns_activity(outcome, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_domain_timestamp 
                ON dns_activity(domain, timestamp DESC);

            CREATE INDEX IF NOT EXISTS idx_dns_activity_app_timestamp 
                ON dns_activity(app_identifier, timestamp DESC);
            """

            var errMsg: UnsafeMutablePointer<CChar>?
            let res = sqlite3_exec(db, ddl, nil, nil, &errMsg)
            if res != SQLITE_OK {
                if let err = errMsg {
                    os_log(.error, log: Self.log, "Schema creation failed: %{public}s", err)
                    sqlite3_free(errMsg)
                }
                return false
            }

            executePragma("PRAGMA user_version = \(Self.currentSchemaVersion);")
            os_log(.info, log: Self.log, "Initialized new activity database schema version %{public}d", Self.currentSchemaVersion)
        }

        return true
    }

    // MARK: - Batch Insert (Atomic, Parameterized)

    public func insertBatch(_ records: [ActivityRecord]) -> Bool {
        guard !records.isEmpty else { return true }

        dbLock.lock()
        defer { dbLock.unlock() }

        guard !isClosed, let db = db else {
            os_log(.error, log: Self.log, "Cannot insert batch: database is not open")
            return false
        }

        // Begin immediate transaction to acquire write lock
        if sqlite3_exec(db, "BEGIN IMMEDIATE;", nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            os_log(.error, log: Self.log, "BEGIN IMMEDIATE failed: %{public}@", errMsg)
            return false
        }

        let sql = """
        INSERT INTO dns_activity (
            domain, timestamp, query_type, outcome,
            matched_source, matched_rule_id, matched_categories, reason,
            app_identifier, app_name, app_icon_key
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for record in records {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            // 1. domain
            sqlite3_bind_text(stmt, 1, (record.domain as NSString).utf8String, -1, transient)
            // 2. timestamp
            sqlite3_bind_int64(stmt, 2, record.timestamp)
            // 3. query_type
            sqlite3_bind_text(stmt, 3, (record.queryType as NSString).utf8String, -1, transient)
            // 4. outcome
            sqlite3_bind_text(stmt, 4, (record.outcome as NSString).utf8String, -1, transient)
            // 5. matched_source
            sqlite3_bind_text(stmt, 5, (record.matchedSource as NSString).utf8String, -1, transient)

            // 6. matched_rule_id (nullable)
            if let ruleId = record.matchedRuleId {
                sqlite3_bind_text(stmt, 6, (ruleId as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            // 7. matched_categories (nullable JSON string)
            if !record.matchedCategories.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: record.matchedCategories),
               let jsonStr = String(data: data, encoding: .utf8) {
                sqlite3_bind_text(stmt, 7, (jsonStr as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 7)
            }

            // 8. reason (nullable)
            if let reason = record.reason {
                sqlite3_bind_text(stmt, 8, (reason as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 8)
            }

            // 9. app_identifier (nullable)
            if let appId = record.appIdentifier {
                sqlite3_bind_text(stmt, 9, (appId as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 9)
            }

            // 10. app_name (nullable)
            if let appName = record.appName {
                sqlite3_bind_text(stmt, 10, (appName as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 10)
            }

            // 11. app_icon_key (nullable)
            if let iconKey = record.appIconKey {
                sqlite3_bind_text(stmt, 11, (iconKey as NSString).utf8String, -1, transient)
            } else {
                sqlite3_bind_null(stmt, 11)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                let errMsg = String(cString: sqlite3_errmsg(db))
                os_log(.error, log: Self.log, "sqlite3_step failed on record insert: %{public}@", errMsg)
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                return false
            }
        }

        if sqlite3_exec(db, "COMMIT;", nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            os_log(.error, log: Self.log, "COMMIT failed: %{public}@", errMsg)
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }

        return true
    }

    // MARK: - Query & Maintenance APIs

    /// Returns the total count of records in the database.
    public func countTotal() -> Int {
        dbLock.lock()
        defer { dbLock.unlock() }

        guard !isClosed, let db = db else { return 0 }
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM dns_activity;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return count
    }

    /// Queries bounded activity records ordered by timestamp descending.
    public func queryRecords(limit: Int = 50, offset: Int = 0, outcomeFilter: String? = nil) -> [ActivityRecord] {
        dbLock.lock()
        defer { dbLock.unlock() }

        guard !isClosed, let db = db else { return [] }

        var sql = "SELECT id, domain, timestamp, query_type, outcome, matched_source, matched_rule_id, matched_categories, reason, app_identifier, app_name, app_icon_key FROM dns_activity"
        if let filter = outcomeFilter, !filter.isEmpty {
            sql += " WHERE outcome = '\(filter.lowercased())'"
        }
        sql += " ORDER BY timestamp DESC LIMIT \(limit) OFFSET \(offset);"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [ActivityRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let domain = String(cString: sqlite3_column_text(stmt, 1))
            let timestamp = sqlite3_column_int64(stmt, 2)
            let queryType = String(cString: sqlite3_column_text(stmt, 3))
            let outcome = String(cString: sqlite3_column_text(stmt, 4))
            let matchedSource = String(cString: sqlite3_column_text(stmt, 5))

            var matchedRuleId: String? = nil
            if let ruleText = sqlite3_column_text(stmt, 6) {
                matchedRuleId = String(cString: ruleText)
            }

            var categories: [String] = []
            if let catText = sqlite3_column_text(stmt, 7),
               let catData = String(cString: catText).data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: catData) as? [String] {
                categories = parsed
            }

            var reason: String? = nil
            if let reasonText = sqlite3_column_text(stmt, 8) {
                reason = String(cString: reasonText)
            }

            var appIdentifier: String? = nil
            if let appText = sqlite3_column_text(stmt, 9) {
                appIdentifier = String(cString: appText)
            }

            var appName: String? = nil
            if let nameText = sqlite3_column_text(stmt, 10) {
                appName = String(cString: nameText)
            }

            var appIconKey: String? = nil
            if let iconText = sqlite3_column_text(stmt, 11) {
                appIconKey = String(cString: iconText)
            }

            let record = ActivityRecord(
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
            )
            results.append(record)
        }

        return results
    }

    /// Prunes activity history records older than the specified cutoff timestamp.
    /// Returns the count of deleted rows.
    @discardableResult
    public func pruneRetention(cutoffUtcMillis: Int64) -> Int {
        dbLock.lock()
        defer { dbLock.unlock() }

        guard !isClosed, let db = db else { return 0 }

        var stmt: OpaquePointer?
        let sql = "DELETE FROM dns_activity WHERE timestamp < ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, cutoffUtcMillis)

        if sqlite3_step(stmt) == SQLITE_DONE {
            let changes = Int(sqlite3_changes(db))
            os_log(.info, log: Self.log, "Retention prune deleted %{public}ld records older than timestamp %{public}lld", changes, cutoffUtcMillis)
            return changes
        } else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            os_log(.error, log: Self.log, "Retention prune failed: %{public}@", errMsg)
            return 0
        }
    }


}

// MARK: - Asynchronous Bounded Activity Queue & Writer

/// High-throughput, thread-safe asynchronous activity writer.
/// Guarantees:
/// 1. Zero DNS blocking: Enqueue operations are non-blocking.
/// 2. Bounded memory: Hard limit of 500 records; drops oldest 100 on overflow.
/// 3. Batched transactions: Flushes every 25 records or 500 ms.
/// 4. Graceful shutdown: Flushes buffer within 500 ms budget respecting 250 ms busy timeout.
/// 5. Bounded retry: Retries failed batches at most once; never duplicates records.
public final class AuraActivityWriter {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraActivityWriter")

    private let database: AuraActivityDatabase
    private let queue = DispatchQueue(label: "com.thejatech.aura.activityWriter", qos: .utility)
    private let lock = NSLock()

    private var buffer: [ActivityRecord] = []
    private var retryBatch: [ActivityRecord]? = nil
    private let maxCapacity = 500
    private let batchThreshold = 25
    private var timer: DispatchSourceTimer?
    private var isFlushing = false
    private var isRunning = false
    private(set) public var droppedRecordCount: Int = 0

    public init(database: AuraActivityDatabase) {
        self.database = database
    }

    deinit {
        stop()
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }
        isRunning = true

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        t.setEventHandler { [weak self] in
            self?.flushPending()
        }
        t.resume()
        self.timer = t
        os_log(.info, log: Self.log, "Activity writer started (500ms flush timer, max capacity %{public}d)", maxCapacity)
    }

    public func stop() {
        lock.lock()
        if let t = timer {
            t.cancel()
            self.timer = nil
        }
        isRunning = false
        lock.unlock()
    }

    /// Enqueues an activity record non-blockingly from the DNS processing thread.
    public func enqueue(_ record: ActivityRecord) {
        lock.lock()
        defer { lock.unlock() }

        // Bounded overflow protection: if buffer reaches 500, drop oldest 100
        if buffer.count >= maxCapacity {
            buffer.removeFirst(100)
            droppedRecordCount += 100
            os_log(
                .error,
                log: Self.log,
                "Activity queue reached capacity (%{public}d); dropped 100 oldest records (total dropped: %{public}d)",
                maxCapacity,
                droppedRecordCount
            )
        }

        buffer.append(record)

        // Trigger immediate async flush if running and batch threshold reached
        if isRunning && buffer.count >= batchThreshold {
            queue.async { [weak self] in
                self?.flushPending()
            }
        }
    }

    /// Flushes pending records onto the background serial queue.
    private func flushPending() {
        var recordsToWrite: [ActivityRecord] = []
        var isRetry = false

        lock.lock()
        guard isRunning, !isFlushing else {
            lock.unlock()
            return
        }
        isFlushing = true

        if let retry = retryBatch {
            recordsToWrite = retry
            retryBatch = nil
            isRetry = true
        } else if !buffer.isEmpty {
            recordsToWrite = Array(buffer.prefix(batchThreshold))
            buffer.removeFirst(recordsToWrite.count)
        }
        lock.unlock()

        guard !recordsToWrite.isEmpty else {
            lock.lock()
            isFlushing = false
            lock.unlock()
            return
        }

        // Execute batch write inside SQLite transaction (bounded 250ms busy timeout)
        let success = database.insertBatch(recordsToWrite)

        lock.lock()
        if !success {
            if !isRetry {
                // Bounded retry: queue for exactly ONE retry attempt
                retryBatch = recordsToWrite
                os_log(.error, log: Self.log, "Batch insert of %{public}ld records failed; scheduled for 1 retry", recordsToWrite.count)
            } else {
                // Already retried once; drop batch to prevent indefinite retry stalls
                droppedRecordCount += recordsToWrite.count
                os_log(.error, log: Self.log, "Retry insert failed; dropped %{public}ld records (total dropped: %{public}d)", recordsToWrite.count, droppedRecordCount)
            }
        }
        isFlushing = false

        // If there are still items remaining in the buffer, schedule next batch immediately
        let hasMore = !buffer.isEmpty || retryBatch != nil
        lock.unlock()

        if hasMore {
            queue.async { [weak self] in
                self?.flushPending()
            }
        }
    }

    /// Flushes all pending in-memory records during graceful shutdown within the specified timeout.
    public func flushAndClose(timeout: TimeInterval = 0.5) {
        stop()

        var remaining: [ActivityRecord] = []
        lock.lock()
        if let retry = retryBatch {
            remaining.append(contentsOf: retry)
            retryBatch = nil
        }
        remaining.append(contentsOf: buffer)
        buffer.removeAll()
        lock.unlock()

        guard !remaining.isEmpty else {
            database.close()
            return
        }

        os_log(.info, log: Self.log, "Shutdown flush: committing %{public}ld pending records within %{public}.2fs deadline...", remaining.count, timeout)
        let group = DispatchGroup()
        group.enter()

        queue.async { [weak self] in
            _ = self?.database.insertBatch(remaining)
            self?.database.close()
            group.leave()
        }

        let waitResult = group.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            os_log(.error, log: Self.log, "Shutdown flush timed out after %{public}.2fs; closing database", timeout)
            database.close()
        } else {
            os_log(.info, log: Self.log, "Shutdown flush completed successfully.")
        }
    }
}
