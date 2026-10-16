import XCTest
import SQLite3
@testable import Runner

final class AuraReleaseStoreTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuraReleaseStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        AuraCategoryStore.customSharedContainerURL = tempDirectory
        AuraCategoryStore.customReleasesDirectoryURL = tempDirectory.appendingPathComponent("releases")
        AuraCategoryStore.customStagingDirectoryURL = tempDirectory.appendingPathComponent("staging")
        AuraCategoryStore.customReleaseFileURL = tempDirectory.appendingPathComponent("installed_release.json")
        AuraCategoryStore.customPreferencesFileURL = tempDirectory.appendingPathComponent("aura_category_preferences.json")
        AuraCategoryStore.customOverridesFileURL = tempDirectory.appendingPathComponent("aura_default_domain_overrides.json")
        AuraCategoryStore.customCategoriesDirectoryURL = tempDirectory.appendingPathComponent("categories")

        RunnerRuleStore.customSharedContainerURL = tempDirectory
        RunnerRuleStore.customRulesFileURL = tempDirectory.appendingPathComponent("aura_rules.json")
    }

    override func tearDown() {
        AuraCategoryStore.resetCustomURLs()
        RunnerRuleStore.resetCustomURLs()
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Scenario 1: Obsolete Category Removal

    func testScenario1_ObsoleteCategoryRemoval() throws {
        // Release 1 contains ads, trackers, analytics, and malware
        let rel1Files = [
            "ads": "adservice.google.com\ndoubleclick.net",
            "trackers": "scorecardresearch.com\npixel.facebook.com",
            "analytics": "google-analytics.com",
            "malware": "malicious-phish.biz\nbad-trojan.xyz"
        ]
        let res1 = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: rel1Files,
            domainCount: 7
        )
        XCTAssertEqual(res1["success"] as? Bool, true)

        // Verify Release 1 loaded malware
        let cats1 = AuraCategoryStore.loadAllBundledCategories()
        XCTAssertNotNil(cats1["Malware"], "Release 1 must include Malware")
        XCTAssertTrue(cats1["Malware"]?.contains("malicious-phish.biz") == true)
        let domains1 = AuraCategoryStore.allBundledDomains()
        XCTAssertTrue(domains1.contains("malicious-phish.biz"))
        XCTAssertTrue(domains1.contains("bad-trojan.xyz"))

        // Release 2 removes malware (only contains ads, trackers, analytics)
        let rel2Files = [
            "ads": "adservice.google.com\ndoubleclick.net\nnew-ad.com",
            "trackers": "scorecardresearch.com",
            "analytics": "google-analytics.com"
        ]
        let res2 = try AuraCategoryStore.installRelease(
            version: "2026.10.16-01",
            files: rel2Files,
            domainCount: 4
        )
        XCTAssertEqual(res2["success"] as? Bool, true)

        // Verify Malware is completely removed from categories and all domains
        let cats2 = AuraCategoryStore.loadAllBundledCategories()
        XCTAssertNil(cats2["Malware"], "Malware category must be completely eliminated after Release 2 activation")
        let domains2 = AuraCategoryStore.allBundledDomains()
        XCTAssertFalse(domains2.contains("malicious-phish.biz"), "Obsolete malware domain must not be in allBundledDomains")
        XCTAssertFalse(domains2.contains("bad-trojan.xyz"))
        XCTAssertTrue(domains2.contains("new-ad.com"))

        // Verify active release directory contains only the 3 files and NOT malware.txt
        guard let activeDir = AuraCategoryStore.activeReleaseDirectoryURL else {
            XCTFail("activeReleaseDirectoryURL is nil")
            return
        }
        let malwareFile = activeDir.appendingPathComponent("malware.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: malwareFile.path), "malware.txt must not exist in active release directory")
    }

    // MARK: - Scenario 2: Successful Replacement and Pruning

    func testScenario2_SuccessfulReplacementAndPruning() throws {
        let releasesRoot = AuraCategoryStore.releasesRootDirectoryURL!

        // Release 1 install
        let res1 = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: ["ads": "ad1.com\n", "trackers": "tr1.com\n", "analytics": "an1.com\n"],
            domainCount: 3
        )
        let dir1Name = res1["releaseDirectory"] as? String
        XCTAssertNotNil(dir1Name)
        let dir1 = releasesRoot.appendingPathComponent(dir1Name!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir1.path))

        // Release 2 install
        let res2 = try AuraCategoryStore.installRelease(
            version: "2026.10.16-01",
            files: ["ads": "ad2.com\n", "trackers": "tr2.com\n", "analytics": "an2.com\n"],
            domainCount: 3
        )
        let dir2Name = res2["releaseDirectory"] as? String
        XCTAssertNotNil(dir2Name)
        XCTAssertNotEqual(dir1Name, dir2Name)
        let dir2 = releasesRoot.appendingPathComponent(dir2Name!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir2.path))

        // Verify old release directory was pruned
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir1.path), "Previous release directory must be pruned")

        // Verify only active release directory exists in releases/
        let contents = try FileManager.default.contentsOfDirectory(atPath: releasesRoot.path)
        XCTAssertEqual(contents, [dir2Name!], "releases/ root must only contain the active release directory")

        let installed = AuraCategoryStore.loadInstalledRelease()
        XCTAssertEqual(installed?["version"] as? String, "2026.10.16-01")
        XCTAssertEqual(installed?["releaseDirectory"] as? String, dir2Name)
    }

    // MARK: - Scenario 3: Failure During Staging Leaves Previous Release Active

    func testScenario3_FailureDuringStagingLeavesPreviousReleaseActive() throws {
        // Install Release 1 successfully
        let res1 = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: ["ads": "ad1.com\n", "trackers": "tr1.com\n", "analytics": "an1.com\n"]
        )
        let dir1Name = res1["releaseDirectory"] as? String
        XCTAssertNotNil(dir1Name)

        // Attempt Release 2 with an empty file (violates integrity check)
        XCTAssertThrowsError(
            try AuraCategoryStore.installRelease(
                version: "2026.10.16-bad",
                files: ["ads": "ad2.com", "trackers": "   \n\t  "]
            )
        ) { error in
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.domain, "AuraCategoryStore")
            XCTAssertEqual(nsErr.code, 5) // Staged file is empty or unreadable
        }

        // Active release must still be Release 1
        let installed = AuraCategoryStore.loadInstalledRelease()
        XCTAssertEqual(installed?["version"] as? String, "2026.10.15-01")
        XCTAssertEqual(installed?["releaseDirectory"] as? String, dir1Name)

        // Staging directory must be clean
        let stagingRoot = AuraCategoryStore.stagingRootDirectoryURL!
        let stagingItems = try FileManager.default.contentsOfDirectory(atPath: stagingRoot.path)
        XCTAssertTrue(stagingItems.isEmpty, "Staging directory must be cleaned up on failure")
    }

    // MARK: - Scenario 4: Failure During Activation Rolls Back Cleanly

    func testScenario4_FailureDuringActivationRollsBackCleanly() throws {
        // Install Release 1
        _ = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: ["ads": "ad1.com\n", "trackers": "tr1.com\n", "analytics": "an1.com\n"]
        )
        let meta1 = AuraCategoryStore.loadInstalledRelease()
        let dir1Name = meta1?["releaseDirectory"] as? String

        // Point metadata file to an invalid unwritable path (e.g. a directory)
        let invalidMetaDir = tempDirectory.appendingPathComponent("invalid_meta_dir")
        try FileManager.default.createDirectory(at: invalidMetaDir, withIntermediateDirectories: true)
        AuraCategoryStore.customReleaseFileURL = invalidMetaDir

        // Attempt to install Release 2
        XCTAssertThrowsError(
            try AuraCategoryStore.installRelease(
                version: "2026.10.16-fail",
                files: ["ads": "ad2.com\n", "trackers": "tr2.com\n", "analytics": "an2.com\n"]
            )
        )

        // Restore valid metadata URL
        AuraCategoryStore.customReleaseFileURL = tempDirectory.appendingPathComponent("installed_release.json")

        // Release 1 must still be active and intact
        let metaAfter = AuraCategoryStore.loadInstalledRelease()
        XCTAssertEqual(metaAfter?["version"] as? String, "2026.10.15-01")
        XCTAssertEqual(metaAfter?["releaseDirectory"] as? String, dir1Name)

        // Candidate release folder in releases/ must have been rolled back and deleted
        let releasesRoot = AuraCategoryStore.releasesRootDirectoryURL!
        let releaseContents = try FileManager.default.contentsOfDirectory(atPath: releasesRoot.path)
        XCTAssertEqual(releaseContents, [dir1Name!], "Failed candidate release must be rolled back from releases/")
    }

    // MARK: - Scenario 5: Recovery After Interrupted Installation

    func testScenario5_RecoveryAfterInterruptedInstallation() throws {
        // Install Release 1
        _ = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: ["ads": "ad1.com\n", "trackers": "tr1.com\n", "analytics": "an1.com\n"]
        )

        // Simulate an interrupted installation: orphaned staging directory
        let stagingRoot = AuraCategoryStore.stagingRootDirectoryURL!
        let orphanedStage = stagingRoot.appendingPathComponent("stage_rel_interrupted_12345")
        try FileManager.default.createDirectory(at: orphanedStage, withIntermediateDirectories: true)
        let dummyFile = orphanedStage.appendingPathComponent("partial.txt")
        try "incomplete data".write(to: dummyFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanedStage.path))

        // Trigger cleanup
        AuraCategoryStore.cleanupStaging()
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanedStage.path), "Orphaned staging folder must be cleaned up")

        // Active release remains intact
        let installed = AuraCategoryStore.loadInstalledRelease()
        XCTAssertEqual(installed?["version"] as? String, "2026.10.15-01")

        // Test corrupt metadata recovery: pointer points to non-existent directory
        let corruptMetadata = AuraInstalledReleaseContainer(
            version: "2026.10.99",
            releaseDirectory: "non_existent_release_dir"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(corruptMetadata)
        try data.write(to: AuraCategoryStore.releaseFileURL!, options: .atomic)

        // loadInstalledRelease() verifies disk existence and returns nil safely
        XCTAssertNil(AuraCategoryStore.loadInstalledRelease())
        XCTAssertNil(AuraCategoryStore.activeReleaseDirectoryURL)

        // loadAllBundledCategories() returns empty map safely without crashing and without static fallback
        let fallbackCats = AuraCategoryStore.loadAllBundledCategories()
        XCTAssertTrue(fallbackCats.isEmpty, "No categories should be loaded when release directory is invalid/missing")
        XCTAssertTrue(AuraCategoryStore.allBundledDomains().isEmpty, "allBundledDomains must be empty when no release is installed")
    }

    // MARK: - Scenario 6: Network Extension Consistency

    func testScenario6_NetworkExtensionConsistency() throws {
        // Install Release
        let relFiles = [
            "ads": "ad1.com\nad2.com",
            "trackers": "tr1.com",
            "analytics": "an1.com"
        ]
        _ = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: relFiles,
            domainCount: 4
        )

        guard let activeDir = AuraCategoryStore.activeReleaseDirectoryURL else {
            XCTFail("activeReleaseDirectoryURL must not be nil")
            return
        }

        let items = try FileManager.default.contentsOfDirectory(atPath: activeDir.path)
        let sortedItems = items.sorted()
        XCTAssertEqual(sortedItems, ["ads.txt", "analytics.txt", "trackers.txt"])

        for item in sortedItems {
            let fileURL = activeDir.appendingPathComponent(item)
            let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = attr[.size] as? UInt64 ?? 0
            XCTAssertGreaterThan(size, 0, "File \(item) must not be zero bytes")
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(content.isEmpty)
        }
    }

    // MARK: - Scenario 7: Existing Rules, Preferences, Overrides, and DB Survive

    func testScenario7_ExistingRulesAndPreferencesSurviveReleaseReplacement() throws {
        // 1. Save custom rules
        let customBlock = AuraRule(domain: "custom-malicious.com", isEnabled: true, isBlocked: true)
        let customAllow = AuraRule(domain: "custom-trusted.com", isEnabled: true, isBlocked: false)
        try RunnerRuleStore.saveRules([customBlock, customAllow])

        // 2. Save category preferences
        try AuraCategoryStore.savePreferences(["Ads": true, "Trackers": false, "Analytics": true])

        // 3. Save default domain overrides
        try AuraCategoryStore.saveDisabledDefaultDomains(["google-analytics.com", "adservice.google.com"])

        // 4. Initialize SQLite activity database and insert record
        let dbURL = tempDirectory.appendingPathComponent("dns_activity.sqlite")
        _ = try AuraActivityDatabase.bootstrapSharedDatabase(fileURL: dbURL)
        let dbWriter = AuraActivityDatabase(fileURL: dbURL)
        XCTAssertTrue(dbWriter.open())
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let records = [
            ActivityRecord(
                domain: "custom-malicious.com",
                timestamp: now,
                queryType: "A",
                outcome: "blocked",
                matchedSource: "rule",
                matchedRuleId: "custom-malicious.com"
            )
        ]
        XCTAssertTrue(dbWriter.insertBatch(records))
        dbWriter.close()

        let repo = AuraActivityRepository(fileURL: dbURL)
        try repo.open()
        let initialStats = try repo.getDashboardStats(timeWindowMillis: 86400000)
        XCTAssertEqual(initialStats.totalQueries, 1)
        repo.close()

        // Install Release 1
        _ = try AuraCategoryStore.installRelease(
            version: "2026.10.15-01",
            files: ["ads": "ad1.com\n", "trackers": "tr1.com\n", "analytics": "an1.com\n"]
        )

        // Install Release 2 (replacing Release 1)
        _ = try AuraCategoryStore.installRelease(
            version: "2026.10.16-01",
            files: ["ads": "ad2.com\n", "trackers": "tr2.com\n", "analytics": "an2.com\n"]
        )

        // 5. Verify custom rules survived intact
        let loadedRules = RunnerRuleStore.loadRules()
        XCTAssertEqual(loadedRules.count, 2)
        XCTAssertTrue(loadedRules.contains { $0.domain == "custom-malicious.com" && $0.isBlocked == true })
        XCTAssertTrue(loadedRules.contains { $0.domain == "custom-trusted.com" && $0.isBlocked == false })

        // 6. Verify category preferences survived intact
        let loadedPrefs = AuraCategoryStore.loadPreferences()
        XCTAssertEqual(loadedPrefs["Trackers"], false)
        XCTAssertEqual(loadedPrefs["Ads"], true)
        XCTAssertEqual(loadedPrefs["Analytics"], true)

        // 7. Verify default domain overrides survived intact
        let loadedOverrides = AuraCategoryStore.loadDisabledDefaultDomains()
        XCTAssertTrue(loadedOverrides.contains("google-analytics.com"))
        XCTAssertTrue(loadedOverrides.contains("adservice.google.com"))

        // 8. Verify SQLite activity database survived intact with its record
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path), "SQLite database must not be deleted or recreated")
        let repoAfter = AuraActivityRepository(fileURL: dbURL)
        try repoAfter.open()
        let statsAfter = try repoAfter.getDashboardStats(timeWindowMillis: 86400000)
        XCTAssertEqual(statsAfter.totalQueries, 1)
        let activityAfter = try repoAfter.queryActivity(limit: 5)
        XCTAssertEqual(activityAfter.records.first?.domain, "custom-malicious.com")
        XCTAssertEqual(activityAfter.records.first?.outcome, "blocked")
        repoAfter.close()
    }

    // MARK: - Scenario 8: First Launch Without Backend Sync Has Zero Categories or Fallback Domains

    func testScenario8_FirstLaunchWithoutBackendSyncReturnsEmpty() {
        // Fresh state: no release installed
        XCTAssertNil(AuraCategoryStore.loadInstalledRelease())
        XCTAssertNil(AuraCategoryStore.activeReleaseDirectoryURL)

        // Must return empty categories and empty domains
        let categories = AuraCategoryStore.loadAllBundledCategories()
        XCTAssertTrue(categories.isEmpty, "First launch without sync must have 0 categories")

        let allDomains = AuraCategoryStore.allBundledDomains()
        XCTAssertTrue(allDomains.isEmpty, "First launch without sync must have 0 domains")

        let releaseCats = RunnerRuleStore.loadReleaseCategories()
        XCTAssertTrue(releaseCats.isEmpty, "Method channel release categories must be empty on first launch")

        let adsDomains = RunnerRuleStore.loadCategoryDomains(category: "ads")
        XCTAssertTrue(adsDomains.isEmpty, "Category domains must be empty when no release is installed")
    }

    // MARK: - Scenario 9: Empty Backend Category Preserved Without Synthetic Domains

    func testScenario9_EmptyCategoryPreservedWithoutSyntheticDomains() throws {
        // Backend published release where analytics has 0 domains (header comments only)
        let files = [
            "ads": "ad1.com\nad2.com",
            "trackers": "tr1.com",
            "analytics": "# PrivacyShield compiled blocklist\n# Domains: 0\n"
        ]
        let res = try AuraCategoryStore.installRelease(
            version: "2026.10.16-backend",
            files: files,
            domainCount: 3
        )
        XCTAssertEqual(res["success"] as? Bool, true)

        let categories = AuraCategoryStore.loadAllBundledCategories()
        XCTAssertEqual(categories.count, 3)
        XCTAssertEqual(categories["Ads"]?.count, 2)
        XCTAssertEqual(categories["Trackers"]?.count, 1)
        XCTAssertEqual(categories["Analytics"]?.count, 0, "Empty category must have 0 domains")

        let releaseCats = RunnerRuleStore.loadReleaseCategories()
        XCTAssertEqual(releaseCats.count, 3)

        let analyticsMeta = releaseCats.first { ($0["name"] as? String)?.lowercased() == "analytics" }
        XCTAssertNotNil(analyticsMeta)
        XCTAssertEqual(analyticsMeta?["domainCount"] as? Int, 0)

        let analyticsDomains = RunnerRuleStore.loadCategoryDomains(category: "analytics")
        XCTAssertTrue(analyticsDomains.isEmpty, "Analytics domains array must be empty, no synthetic domains fabricated")
    }
}
