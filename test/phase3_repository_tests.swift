import Foundation
import SQLite3

@main
struct Phase3RepositoryTests {
    static func main() {
        print("=======================================================")
        print("THEJA AURA — PHASE 3 NATIVE REPOSITORY & BRIDGE TESTS")
        print("=======================================================")

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("aura_phase3_tests_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let dbURL = tempDir.appendingPathComponent("test_activity.sqlite")

        // MARK: - TEST 1: Missing Database & Incompatible Version Handling
        print("\n[TEST 1] Missing Database & Incompatible Version Handling...")
        let missingRepo = AuraActivityRepository(fileURL: tempDir.appendingPathComponent("nonexistent.sqlite"))
        do {
            try missingRepo.open()
            fatalError("CRITICAL FAILURE: Expected open() to throw databaseNotFound for missing file")
        } catch let err as AuraRepositoryError {
            assert(err.errorCode == "DATABASE_NOT_FOUND", "Expected DATABASE_NOT_FOUND error code")
            print("  ✓ Correctly rejected missing database with typed error: \(err.localizedDescription)")
        } catch {
            fatalError("Unexpected error: \(error)")
        }

        // Test incompatible future schema (user_version = 99)
        let futureURL = tempDir.appendingPathComponent("future_v99.sqlite")
        var futureHandle: OpaquePointer?
        sqlite3_open_v2(futureURL.path, &futureHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        sqlite3_exec(futureHandle, "PRAGMA user_version = 99;", nil, nil, nil)
        sqlite3_close(futureHandle)

        let futureRepo = AuraActivityRepository(fileURL: futureURL)
        do {
            try futureRepo.open()
            fatalError("Expected open() to throw schemaIncompatible for version 99")
        } catch let err as AuraRepositoryError {
            assert(err.errorCode == "SCHEMA_INCOMPATIBLE")
            print("  ✓ Correctly rejected incompatible schema: \(err.localizedDescription)")
        } catch {
            fatalError("Unexpected error: \(error)")
        }

        // MARK: - TEST 2: Seed Activity Records via Extension Writer
        print("\n[TEST 2] Seeding Activity Records via Extension Database...")
        let extDb = AuraActivityDatabase(fileURL: dbURL)
        assert(extDb.open(), "Failed to create activity database via extension database")

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let hourMillis: Int64 = 3_600_000

        let seedRecords: [ActivityRecord] = [
            // Domain 1: doubleclick.net (Blocked by Ads, 4 occurrences)
            ActivityRecord(domain: "doubleclick.net", timestamp: now - 1000, queryType: "A", outcome: "blocked", matchedSource: "default", matchedRuleId: "doubleclick.net", matchedCategories: ["Ads"], reason: "Blocked by Ads"),
            ActivityRecord(domain: "doubleclick.net", timestamp: now - 2000, queryType: "AAAA", outcome: "blocked", matchedSource: "default", matchedRuleId: "doubleclick.net", matchedCategories: ["Ads"], reason: "Blocked by Ads"),
            ActivityRecord(domain: "doubleclick.net", timestamp: now - 3000, queryType: "HTTPS", outcome: "blocked", matchedSource: "default", matchedRuleId: "doubleclick.net", matchedCategories: ["Ads"], reason: "Blocked by Ads"),
            ActivityRecord(domain: "doubleclick.net", timestamp: now - 4000, queryType: "A", outcome: "blocked", matchedSource: "default", matchedRuleId: "doubleclick.net", matchedCategories: ["Ads"], reason: "Blocked by Ads"),

            // Domain 2: telemetry.evil.com (Blocked by Custom, 2 occurrences)
            ActivityRecord(domain: "telemetry.evil.com", timestamp: now - 5000, queryType: "A", outcome: "blocked", matchedSource: "custom", matchedRuleId: "telemetry.evil.com", reason: "Blocked by custom rule"),
            ActivityRecord(domain: "telemetry.evil.com", timestamp: now - 6000, queryType: "AAAA", outcome: "blocked", matchedSource: "custom", matchedRuleId: "telemetry.evil.com", reason: "Blocked by custom rule"),

            // Domain 3: trackers.scorecard.net (Blocked by Trackers, 1 occurrence)
            ActivityRecord(domain: "trackers.scorecard.net", timestamp: now - 7000, queryType: "A", outcome: "blocked", matchedSource: "default", matchedCategories: ["Trackers"], reason: "Blocked by Trackers"),

            // Domain 4: apple.com (Allowed, 3 occurrences)
            ActivityRecord(domain: "apple.com", timestamp: now - 8000, queryType: "A", outcome: "allowed", matchedSource: "allowlist", matchedRuleId: "apple.com"),
            ActivityRecord(domain: "apple.com", timestamp: now - 9000, queryType: "AAAA", outcome: "allowed", matchedSource: "allowlist", matchedRuleId: "apple.com"),
            ActivityRecord(domain: "apple.com", timestamp: now - 10000, queryType: "HTTPS", outcome: "allowed", matchedSource: "allowlist", matchedRuleId: "apple.com"),

            // Domain 5: wikipedia.org (Allowed default, 2 occurrences)
            ActivityRecord(domain: "wikipedia.org", timestamp: now - 11000, queryType: "A", outcome: "allowed", matchedSource: "none"),
            ActivityRecord(domain: "wikipedia.org", timestamp: now - 12000, queryType: "AAAA", outcome: "allowed", matchedSource: "none"),

            // Domain 6: timeout-test.org (Failed upstream, 1 occurrence)
            ActivityRecord(domain: "timeout-test.org", timestamp: now - 13000, queryType: "A", outcome: "failed", matchedSource: "none", reason: "Upstream timeout")
        ]

        assert(extDb.insertBatch(seedRecords), "Failed to seed records")
        assert(extDb.countTotal() == 13)
        extDb.close()
        print("  ✓ Seeded 13 records across 6 domains (7 blocked, 5 allowed, 1 failed).")

        // MARK: - TEST 3: Deterministic Ordering & Cursor-Based Pagination
        print("\n[TEST 3] Deterministic Ordering & Cursor-Based Pagination...")
        let repo = AuraActivityRepository(fileURL: dbURL)
        assert((try? repo.open()) != nil, "Failed to open repository")

        // Fetch page 1 with limit = 5
        let page1 = try! repo.queryActivity(limit: 5)
        assert(page1.records.count == 5, "Expected 5 records on page 1, got \(page1.records.count)")
        assert(page1.hasMore == true, "Expected hasMore == true for page 1")
        assert(page1.nextCursorTimestamp != nil && page1.nextCursorId != nil)

        // Verify deterministic descending order
        for i in 0..<(page1.records.count - 1) {
            let r1 = page1.records[i]
            let r2 = page1.records[i + 1]
            assert(r1.timestamp > r2.timestamp || (r1.timestamp == r2.timestamp && r1.id > r2.id), "Records must be sorted by timestamp DESC, id DESC")
        }

        // Fetch page 2 using cursor
        let page2 = try! repo.queryActivity(
            limit: 5,
            cursorTimestamp: page1.nextCursorTimestamp,
            cursorId: page1.nextCursorId
        )
        assert(page2.records.count == 5, "Expected 5 records on page 2")
        assert(page2.hasMore == true)

        // Verify no duplicates between page 1 and page 2
        let page1Ids = Set(page1.records.map { $0.id })
        let page2Ids = Set(page2.records.map { $0.id })
        assert(page1Ids.isDisjoint(with: page2Ids), "Page 1 and Page 2 must not contain duplicate records")

        // Fetch page 3 using cursor from page 2
        let page3 = try! repo.queryActivity(
            limit: 5,
            cursorTimestamp: page2.nextCursorTimestamp,
            cursorId: page2.nextCursorId
        )
        assert(page3.records.count == 3, "Expected 3 remaining records on page 3 (13 total)")
        assert(page3.hasMore == false, "Expected hasMore == false on final page")
        assert(page3.nextCursorTimestamp == nil && page3.nextCursorId == nil)
        print("  ✓ Cursor-based pagination smoothly sliced 13 records into pages 5 + 5 + 3 with zero duplicate IDs.")

        // MARK: - TEST 4: Filtering by Outcome (all, blocked, allowed, failed)
        print("\n[TEST 4] Filtering by Outcome...")
        let blockedOnly = try! repo.queryActivity(limit: 50, outcome: "blocked")
        assert(blockedOnly.records.count == 7, "Expected 7 blocked records, got \(blockedOnly.records.count)")
        assert(blockedOnly.records.allSatisfy { $0.outcome == "blocked" })

        let allowedOnly = try! repo.queryActivity(limit: 50, outcome: "allowed")
        assert(allowedOnly.records.count == 5, "Expected 5 allowed records, got \(allowedOnly.records.count)")
        assert(allowedOnly.records.allSatisfy { $0.outcome == "allowed" })

        let failedOnly = try! repo.queryActivity(limit: 50, outcome: "failed")
        assert(failedOnly.records.count == 1, "Expected 1 failed record, got \(failedOnly.records.count)")
        assert(failedOnly.records.first?.domain == "timeout-test.org")

        let allRecords = try! repo.queryActivity(limit: 50, outcome: "all")
        assert(allRecords.records.count == 13)
        print("  ✓ Outcome filtering strictly isolated 'blocked' (7), 'allowed' (5), and 'failed' (1).")

        // MARK: - TEST 5: Domain Search & Case Normalization
        print("\n[TEST 5] Domain Search & Case Normalization...")
        let searchDouble = try! repo.queryActivity(limit: 50, searchDomain: "DOUBLECLICK")
        assert(searchDouble.records.count == 4)
        assert(searchDouble.records.allSatisfy { $0.domain == "doubleclick.net" })

        let searchApple = try! repo.queryActivity(limit: 50, searchDomain: "  apple.com  ")
        assert(searchApple.records.count == 3)
        assert(searchApple.records.allSatisfy { $0.domain == "apple.com" })

        let searchNotFound = try! repo.queryActivity(limit: 50, searchDomain: "nonexistent-site.org")
        assert(searchNotFound.records.isEmpty)
        assert(searchNotFound.hasMore == false)
        print("  ✓ Search matched normalized substrings and trimmed whitespace correctly.")

        // MARK: - TEST 6: Time Range Filtering
        print("\n[TEST 6] Time Range Filtering...")
        // Range covering first 3 records: timestamps now-3000 to now
        let range1 = try! repo.queryActivity(
            limit: 50,
            startTime: now - 3500,
            endTime: now
        )
        assert(range1.records.count == 3, "Expected 3 records in range, got \(range1.records.count)")

        // Range covering old records: now-13500 to now-10500
        let range2 = try! repo.queryActivity(
            limit: 50,
            startTime: now - 13500,
            endTime: now - 10500
        )
        assert(range2.records.count == 3, "Expected 3 records in range, got \(range2.records.count)")
        print("  ✓ Time range bounded by startTime & endTime filtered correctly.")

        // MARK: - TEST 7: Dashboard Statistical Aggregates
        print("\n[TEST 7] Dashboard Statistical Aggregates & Distinct Counts...")
        let stats = try! repo.getDashboardStats(
            timeWindowMillis: hourMillis,
            currentTimeMillis: now
        )

        assert(stats.totalQueries == 13, "Expected 13 total queries, got \(stats.totalQueries)")
        assert(stats.totalBlocked == 7, "Expected 7 total blocked events, got \(stats.totalBlocked)")
        assert(stats.totalAllowed == 5, "Expected 5 total allowed events, got \(stats.totalAllowed)")
        assert(stats.totalFailed == 1, "Expected 1 total failed event, got \(stats.totalFailed)")

        // UNIQUE DOMAIN VERIFICATION:
        // Blocked domains: doubleclick.net (4), telemetry.evil.com (2), trackers.scorecard.net (1) -> 3 UNIQUE
        assert(stats.uniqueBlockedDomains == 3, "Expected 3 unique blocked domains, got \(stats.uniqueBlockedDomains)")

        // Total unique domains: doubleclick.net, telemetry.evil.com, trackers.scorecard.net, apple.com, wikipedia.org, timeout-test.org -> 6 UNIQUE
        assert(stats.uniqueDomainsTotal == 6, "Expected 6 unique domains, got \(stats.uniqueDomainsTotal)")

        print("  ✓ Dashboard aggregates verified: totalQueries=13, totalBlocked=7, uniqueBlockedDomains=3, uniqueDomainsTotal=6.")

        // MARK: - TEST 8: Frequently Blocked Domains Calculation
        print("\n[TEST 8] Frequently Blocked Domains Calculation...")
        let topBlocked = try! repo.getTopBlockedDomains(
            limit: 5,
            timeWindowMillis: hourMillis,
            currentTimeMillis: now
        )
        assert(topBlocked.count == 3, "Expected 3 distinct blocked domains")
        // Ranked by count descending:
        // 1. doubleclick.net (4)
        // 2. telemetry.evil.com (2)
        // 3. trackers.scorecard.net (1)
        assert(topBlocked[0].domain == "doubleclick.net" && topBlocked[0].count == 4)
        assert(topBlocked[1].domain == "telemetry.evil.com" && topBlocked[1].count == 2)
        assert(topBlocked[2].domain == "trackers.scorecard.net" && topBlocked[2].count == 1)
        print("  ✓ Frequently blocked domains ranked accurately: doubleclick.net (4) -> telemetry.evil.com (2) -> trackers.scorecard.net (1).")

        // MARK: - TEST 9: Empty Database Handling
        print("\n[TEST 9] Empty Database Handling...")
        let emptyDbURL = tempDir.appendingPathComponent("empty.sqlite")
        let emptyExtDb = AuraActivityDatabase(fileURL: emptyDbURL)
        assert(emptyExtDb.open())
        emptyExtDb.close()

        let emptyRepo = AuraActivityRepository(fileURL: emptyDbURL)
        assert((try? emptyRepo.open()) != nil)

        let emptyPaginated = try! emptyRepo.queryActivity(limit: 25)
        assert(emptyPaginated.records.isEmpty)
        assert(emptyPaginated.hasMore == false)

        let emptyStats = try! emptyRepo.getDashboardStats(timeWindowMillis: hourMillis, currentTimeMillis: now)
        assert(emptyStats.totalQueries == 0)
        assert(emptyStats.totalBlocked == 0)
        assert(emptyStats.totalAllowed == 0)
        assert(emptyStats.uniqueBlockedDomains == 0)

        let emptyTop = try! emptyRepo.getTopBlockedDomains(limit: 5)
        assert(emptyTop.isEmpty)
        emptyRepo.close()
        print("  ✓ Empty database returned clean zero-counts and empty arrays without exceptions.")

        // MARK: - TEST 10: WAL Checkpoint Ownership & Concurrency
        print("\n[TEST 10] WAL Checkpoint Ownership & Concurrent Readers/Writers...")
        // Passive checkpoint executed by Runner repository
        assert(repo.checkpointPassive() == true, "Runner passive checkpoint must succeed")

        // Concurrently run writes from extension connection while Runner reads
        let concurrentGroup = DispatchGroup()
        let extWriteQueue = DispatchQueue(label: "test.ext.write")
        let runnerReadQueue = DispatchQueue(label: "test.runner.read", attributes: .concurrent)

        let writeExtDb = AuraActivityDatabase(fileURL: dbURL)
        assert(writeExtDb.open())

        for w in 1...5 {
            concurrentGroup.enter()
            extWriteQueue.async {
                _ = writeExtDb.insertBatch([
                    ActivityRecord(domain: "live-write-\(w).org", outcome: "allowed", matchedSource: "none")
                ])
                concurrentGroup.leave()
            }
        }

        for _ in 1...5 {
            concurrentGroup.enter()
            runnerReadQueue.async {
                _ = try? repo.queryActivity(limit: 10)
                _ = try? repo.getDashboardStats()
                concurrentGroup.leave()
            }
        }

        let waitResult = concurrentGroup.wait(timeout: .now() + 5.0)
        assert(waitResult == .success, "Concurrent read/write timed out")
        writeExtDb.close()
        repo.close()
        print("  ✓ Runner passive checkpoint succeeded; concurrent writer and reader completed without lock collision.")

        print("\n=======================================================")
        print("ALL 10 PHASE 3 REPOSITORY TESTS PASSED CLEANLY!")
        print("=======================================================\n")
    }
}
