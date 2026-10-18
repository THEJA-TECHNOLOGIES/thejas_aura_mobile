import XCTest
import SQLite3
@testable import Runner

final class AuraDatabaseTests: XCTestCase {

    var tempDirectory: URL!
    var testDatabaseURL: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraDatabaseTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        testDatabaseURL = tempDirectory.appendingPathComponent("dns_activity.sqlite")
    }

    override func tearDown() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Fresh Bootstrap Tests

    func testBootstrapCreatesDatabaseAndSchemaOnFreshFile() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDatabaseURL.path))

        let bootstrappedURL = try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: testDatabaseURL)
        XCTAssertEqual(bootstrappedURL.path, testDatabaseURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDatabaseURL.path))

        // Open sqlite handle directly to inspect low-level schema and pragmas
        var db: OpaquePointer?
        let openStatus = sqlite3_open_v2(testDatabaseURL.path, &db, SQLITE_OPEN_READONLY, nil)
        XCTAssertEqual(openStatus, SQLITE_OK)
        defer { if let db = db { sqlite3_close(db) } }

        // 1. Verify WAL journal mode
        var journalStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &journalStmt, nil) == SQLITE_OK {
            if sqlite3_step(journalStmt) == SQLITE_ROW {
                let mode = String(cString: sqlite3_column_text(journalStmt, 0)).lowercased()
                XCTAssertEqual(mode, "wal")
            } else {
                XCTFail("Failed to step journal_mode PRAGMA")
            }
        }
        sqlite3_finalize(journalStmt)

        // 2. Verify schema user_version is 1
        var versionStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &versionStmt, nil) == SQLITE_OK {
            if sqlite3_step(versionStmt) == SQLITE_ROW {
                let version = sqlite3_column_int(versionStmt, 0)
                XCTAssertEqual(version, AuraActivityDatabase.currentSchemaVersion)
            } else {
                XCTFail("Failed to step user_version PRAGMA")
            }
        }
        sqlite3_finalize(versionStmt)

        // 3. Verify dns_activity table exists
        var tableStmt: OpaquePointer?
        let checkTableSQL = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='dns_activity';"
        if sqlite3_prepare_v2(db, checkTableSQL, -1, &tableStmt, nil) == SQLITE_OK {
            if sqlite3_step(tableStmt) == SQLITE_ROW {
                let tableCount = sqlite3_column_int(tableStmt, 0)
                XCTAssertEqual(tableCount, 1)
            }
        }
        sqlite3_finalize(tableStmt)

        // 4. Verify the 4 required indexes exist
        let expectedIndexes = [
            "idx_dns_activity_timestamp",
            "idx_dns_activity_outcome_timestamp",
            "idx_dns_activity_domain_timestamp",
            "idx_dns_activity_app_timestamp"
        ]

        for indexName in expectedIndexes {
            var indexStmt: OpaquePointer?
            let checkIndexSQL = "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='\(indexName)';"
            if sqlite3_prepare_v2(db, checkIndexSQL, -1, &indexStmt, nil) == SQLITE_OK {
                if sqlite3_step(indexStmt) == SQLITE_ROW {
                    let indexCount = sqlite3_column_int(indexStmt, 0)
                    XCTAssertEqual(indexCount, 1, "Index \(indexName) must exist")
                }
            }
            sqlite3_finalize(indexStmt)
        }
    }

    // MARK: - Idempotency & Data Preservation

    func testBootstrapIsIdempotentAndPreservesExistingData() throws {
        // First bootstrap
        try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: testDatabaseURL)

        // Insert a record directly
        let insertSQL = """
        INSERT INTO dns_activity (domain, timestamp, query_type, outcome, matched_source, matched_rule_id, matched_categories)
        VALUES ('tracker.example.com', 1700000000000, 'A', 'blocked', 'default', 'cat-ads', '["Advertising"]');
        """
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(testDatabaseURL.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // Second bootstrap invocation must NOT clear or corrupt data
        try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: testDatabaseURL)

        // Reopen and verify record is preserved
        var verifyDb: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(testDatabaseURL.path, &verifyDb, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let verifyDb = verifyDb { sqlite3_close(verifyDb) } }

        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(verifyDb, "SELECT count(*), domain, outcome FROM dns_activity;", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                let count = sqlite3_column_int(countStmt, 0)
                let domain = String(cString: sqlite3_column_text(countStmt, 1))
                let outcome = String(cString: sqlite3_column_text(countStmt, 2))

                XCTAssertEqual(count, 1)
                XCTAssertEqual(domain, "tracker.example.com")
                XCTAssertEqual(outcome, "blocked")
            } else {
                XCTFail("Failed to step select count")
            }
        }
        sqlite3_finalize(countStmt)
    }

    // MARK: - Incompatible Schema Version

    func testBootstrapRejectsFutureIncompatibleSchema() throws {
        try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: testDatabaseURL)

        // Artificially bump user_version to 99
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(testDatabaseURL.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA user_version = 99;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        XCTAssertThrowsError(try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: testDatabaseURL)) { error in
            guard let dbError = error as? AuraDatabaseError else {
                XCTFail("Expected AuraDatabaseError, got \(error)")
                return
            }
            if case .schemaIncompatible(let version) = dbError {
                XCTAssertEqual(version, 99)
            } else {
                XCTFail("Expected schemaIncompatible, got \(dbError)")
            }
        }
    }

    // MARK: - Thread Safety & Concurrency

    func testConcurrentBootstrapCallsAreThreadSafe() {
        let iterations = 10
        let expectation = self.expectation(description: "Concurrent bootstrap")
        expectation.expectedFulfillmentCount = iterations

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            do {
                _ = try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: self.testDatabaseURL)
            } catch {
                XCTFail("Concurrent bootstrap failed with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)

        // Verify valid database state after concurrent boots
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(testDatabaseURL.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let db = db { sqlite3_close(db) } }

        var versionStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &versionStmt, nil) == SQLITE_OK {
            if sqlite3_step(versionStmt) == SQLITE_ROW {
                let version = sqlite3_column_int(versionStmt, 0)
                XCTAssertEqual(version, 1)
            }
        }
        sqlite3_finalize(versionStmt)
    }

    // MARK: - AuraActivityRepository Queries on Fresh Bootstrapped Database

    func testAuraActivityRepositoryOnEmptyDatabase() throws {
        let repository = AuraActivityRepository(fileURL: testDatabaseURL)

        // Explicitly initialize database from repository
        try repository.initialize()

        // Open repository
        try repository.open()

        // 1. Dashboard stats on empty database
        let stats = try repository.getDashboardStats(timeWindowMillis: 86400000)
        XCTAssertEqual(stats.totalQueries, 0)
        XCTAssertEqual(stats.totalBlocked, 0)
        XCTAssertEqual(stats.totalAllowed, 0)
        XCTAssertEqual(stats.uniqueDomainsTotal, 0)
        XCTAssertEqual(stats.uniqueBlockedDomains, 0)

        // 2. Activity list on empty database
        let activity = try repository.queryActivity(limit: 25)
        XCTAssertTrue(activity.records.isEmpty)
        XCTAssertFalse(activity.hasMore)

        // 3. Top blocked domains on empty database
        let topBlocked = try repository.getTopBlockedDomains(limit: 5)
        XCTAssertTrue(topBlocked.isEmpty)

        repository.close()
    }

    // MARK: - AuraActivityRepository Queries with Data

    func testAuraActivityRepositoryWithData() throws {
        let dbWriter = AuraActivityDatabase(fileURL: testDatabaseURL)
        XCTAssertTrue(dbWriter.open())

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let records = [
            ActivityRecord(
                domain: "ads.example.com",
                timestamp: now - 1000,
                queryType: "A",
                outcome: "blocked",
                matchedSource: "default",
                matchedRuleId: "cat-ads",
                matchedCategories: ["Advertising"]
            ),
            ActivityRecord(
                domain: "ads.example.com",
                timestamp: now - 500,
                queryType: "AAAA",
                outcome: "blocked",
                matchedSource: "default",
                matchedRuleId: "cat-ads",
                matchedCategories: ["Advertising"]
            ),
            ActivityRecord(
                domain: "news.example.com",
                timestamp: now,
                queryType: "A",
                outcome: "allowed",
                matchedSource: "none"
            )
        ]

        let writeSuccess = dbWriter.insertBatch(records)
        XCTAssertTrue(writeSuccess)
        dbWriter.close()

        // Open repository to read back
        let repository = AuraActivityRepository(fileURL: testDatabaseURL)
        try repository.open()

        let stats = try repository.getDashboardStats(timeWindowMillis: 86400000)
        XCTAssertEqual(stats.totalQueries, 3)
        XCTAssertEqual(stats.totalBlocked, 2)
        XCTAssertEqual(stats.totalAllowed, 1)
        XCTAssertEqual(stats.uniqueDomainsTotal, 2) // ads.example.com and news.example.com
        XCTAssertEqual(stats.uniqueBlockedDomains, 1) // ads.example.com

        let activity = try repository.queryActivity(limit: 10)
        XCTAssertEqual(activity.records.count, 3)
        XCTAssertFalse(activity.hasMore)
        XCTAssertEqual(activity.records[0].domain, "news.example.com")
        XCTAssertEqual(activity.records[1].domain, "ads.example.com")

        let topBlocked = try repository.getTopBlockedDomains(limit: 5)
        XCTAssertEqual(topBlocked.count, 1)
        XCTAssertEqual(topBlocked[0].domain, "ads.example.com")
        XCTAssertEqual(topBlocked[0].count, 2)

        repository.close()
    }

    func testDashboardStatsAllTimeQueryAndRepeatedDomains() throws {
        let dbWriter = AuraActivityDatabase(fileURL: testDatabaseURL)
        XCTAssertTrue(dbWriter.open())

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let records = [
            // google.com x 3 (2 blocked, 1 allowed)
            ActivityRecord(domain: "google.com", timestamp: now - 5000, queryType: "A", outcome: "blocked", matchedSource: "custom"),
            ActivityRecord(domain: "google.com", timestamp: now - 4000, queryType: "A", outcome: "blocked", matchedSource: "custom"),
            ActivityRecord(domain: "google.com", timestamp: now - 3000, queryType: "AAAA", outcome: "allowed", matchedSource: "none"),
            // youtube.com x 2 (2 blocked)
            ActivityRecord(domain: "youtube.com", timestamp: now - 2000, queryType: "A", outcome: "blocked", matchedSource: "custom"),
            ActivityRecord(domain: "youtube.com", timestamp: now - 1000, queryType: "A", outcome: "blocked", matchedSource: "custom"),
            // example.com x 1 (1 allowed)
            ActivityRecord(domain: "example.com", timestamp: now, queryType: "A", outcome: "allowed", matchedSource: "none")
        ]

        let writeSuccess = dbWriter.insertBatch(records)
        XCTAssertTrue(writeSuccess)
        dbWriter.close()

        let repository = AuraActivityRepository(fileURL: testDatabaseURL)
        try repository.open()

        // All-time query with timeWindowMillis: 0 (no date restriction)
        let allTimeStats = try repository.getDashboardStats(timeWindowMillis: 0)

        // All-Time Logs counts all 6 records, including repeated requests
        XCTAssertEqual(allTimeStats.totalQueries, 6)
        // Unique domains counts distinct domain values (google.com, youtube.com, example.com)
        XCTAssertEqual(allTimeStats.uniqueDomainsTotal, 3)
        // Blocked counts
        XCTAssertEqual(allTimeStats.totalBlocked, 4)
        XCTAssertEqual(allTimeStats.uniqueBlockedDomains, 2)
        XCTAssertEqual(allTimeStats.totalAllowed, 2)

        repository.close()
    }
}
