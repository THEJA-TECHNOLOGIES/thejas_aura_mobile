import Foundation

@main
struct DefaultDomainOverridesTests {
    static func main() {
        print("===================================================================")
        print("THEJA AURA — INDIVIDUAL DEFAULT-DOMAIN OVERRIDES TEST SUITE")
        print("===================================================================")

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("aura_overrides_tests_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Configure custom store file locations for isolated testing
        let preferencesURL = tempDir.appendingPathComponent("aura_category_preferences.json")
        let overridesURL = tempDir.appendingPathComponent("aura_default_domain_overrides.json")
        let rulesURL = tempDir.appendingPathComponent("aura_rules.json")

        AuraCategoryStore.customPreferencesFileURL = preferencesURL
        AuraCategoryStore.customOverridesFileURL = overridesURL
        RunnerRuleStore.customRulesFileURL = rulesURL

        // MARK: - TEST 1: Bundled Default Domains Loading
        print("\n[TEST 1] Bundled Default Domains Loading...")
        let adsDomains = AuraCategoryStore.loadBundledDomains(for: "Ads")
        let trackerDomains = AuraCategoryStore.loadBundledDomains(for: "Trackers")
        let analyticsDomains = AuraCategoryStore.loadBundledDomains(for: "Analytics")

        assert(!adsDomains.isEmpty, "Ads domains should not be empty")
        assert(!trackerDomains.isEmpty, "Trackers domains should not be empty")
        assert(!analyticsDomains.isEmpty, "Analytics domains should not be empty")
        assert(adsDomains.contains("doubleclick.net"), "Ads should contain doubleclick.net")
        assert(trackerDomains.contains("scorecardresearch.com"), "Trackers should contain scorecardresearch.com")
        assert(analyticsDomains.contains("google-analytics.com"), "Analytics should contain google-analytics.com")

        let allBundled = AuraCategoryStore.allBundledDomains()
        assert(allBundled.count == (adsDomains.union(trackerDomains).union(analyticsDomains)).count, "allBundledDomains should be union of all 3 categories")
        print("  ✓ Bundled categories loaded: Ads=\(adsDomains.count), Trackers=\(trackerDomains.count), Analytics=\(analyticsDomains.count), Total=\(allBundled.count)")

        // MARK: - TEST 2: Category Preferences Persistence
        print("\n[TEST 2] Category Preferences Persistence...")
        let defaultPrefs = AuraCategoryStore.loadPreferences()
        assert(defaultPrefs["Ads"] == true, "Ads defaults to true")
        assert(defaultPrefs["Trackers"] == true, "Trackers defaults to true")
        assert(defaultPrefs["Analytics"] == true, "Analytics defaults to true")

        try! AuraCategoryStore.savePreferences(["Ads": false, "Trackers": true, "Analytics": true])
        let reloadedPrefs = AuraCategoryStore.loadPreferences()
        assert(reloadedPrefs["Ads"] == false, "Ads persisted as false")
        assert(reloadedPrefs["Trackers"] == true, "Trackers persisted as true")
        print("  ✓ Category preferences persisted and reloaded successfully")

        // MARK: - TEST 3: Default Domain Overrides Persistence & JSON Schema
        print("\n[TEST 3] Default Domain Overrides JSON Schema & Persistence...")
        let initialOverrides = AuraCategoryStore.loadDisabledDefaultDomains()
        assert(initialOverrides.isEmpty, "Initial disabled default domains must be empty")

        let testDisabledSet: Set<String> = ["doubleclick.net", "pixel.facebook.com"]
        try! AuraCategoryStore.saveDisabledDefaultDomains(testDisabledSet)

        assert(fileManager.fileExists(atPath: overridesURL.path), "Overrides file must exist on disk")
        let rawData = try! Data(contentsOf: overridesURL)
        let jsonObj = try! JSONSerialization.jsonObject(with: rawData, options: []) as! [String: Any]
        assert(jsonObj["version"] as? Int == 1, "Schema version must be 1")
        let disabledList = jsonObj["disabledDomains"] as? [String]
        assert(disabledList != nil, "disabledDomains array must exist")
        assert(disabledList!.count == 2, "disabledDomains must contain 2 items")
        assert(disabledList! == ["doubleclick.net", "pixel.facebook.com"], "disabledDomains must be alphabetically sorted")

        let loadedOverrides = AuraCategoryStore.loadDisabledDefaultDomains()
        assert(loadedOverrides == testDisabledSet, "Reloaded overrides must match saved set")
        print("  ✓ Verified aura_default_domain_overrides.json format and atomic persistence")

        // MARK: - TEST 4 & 5: Engine Evaluation with Default Domain Overrides
        print("\n[TEST 4 & 5] DNS Engine Evaluation with Default Domain Overrides...")
        let engine = AuraDNSEngine()
        engine.setCategories([
            "Ads": adsDomains,
            "Trackers": trackerDomains,
            "Analytics": analyticsDomains
        ])
        engine.setCategoryPreferences([
            "Ads": true,
            "Trackers": true,
            "Analytics": true
        ])

        // 4. Absent domain in disabled set participates in blocking
        engine.setDisabledDefaultDomains([])
        var decision = engine.evaluate(domain: "doubleclick.net")
        assert(decision.isBlocked, "Absent domain must be blocked by default category")
        assert(decision.matchedSource == "default", "Matched source must be default")
        assert(decision.matchedCategories.contains("Ads"), "Matched categories must include Ads")

        decision = engine.evaluate(domain: "sub.doubleclick.net")
        assert(decision.isBlocked, "Subdomain of absent domain must be blocked")

        // 5. Disabled domain in disabledDefaultDomains is excluded from default category blocking
        engine.setDisabledDefaultDomains(["doubleclick.net"])
        decision = engine.evaluate(domain: "doubleclick.net")
        assert(!decision.isBlocked, "Disabled default domain must NOT be blocked by category")
        assert(decision.matchedSource == "none", "Decision must fall through to none (default allow)")

        decision = engine.evaluate(domain: "sub.doubleclick.net")
        assert(!decision.isBlocked, "Subdomain of disabled default domain must NOT be blocked")

        // Other non-disabled default domains remain blocked
        decision = engine.evaluate(domain: "adnxs.com")
        assert(decision.isBlocked, "Non-disabled domain adnxs.com must remain blocked")
        assert(decision.matchedCategories.contains("Ads"))
        print("  ✓ Verified absent domains participate in blocking, disabled domains are excluded")

        // MARK: - TEST 6: Precedence 2 — Custom Block Rule Overrides Disabled Default Domain
        print("\n[TEST 6] Precedence 2: Custom BLOCK rule overrides disabled default domain...")
        // User disabled doubleclick.net in default category, BUT added an explicit custom BLOCK rule
        engine.setDisabledDefaultDomains(["doubleclick.net"])
        engine.setRules([
            AuraDNSEngine.Rule(id: "custom-block-1", domain: "doubleclick.net", isEnabled: true, isBlocked: true)
        ])

        decision = engine.evaluate(domain: "doubleclick.net")
        assert(decision.isBlocked, "Custom BLOCK rule must block domain even when disabled in default category")
        assert(decision.matchedSource == "custom", "Matched source must be custom")
        assert(decision.matchedRule == "doubleclick.net", "Matched rule domain must match")
        assert(decision.matchedCategories.isEmpty, "Must match custom rule, not category")
        print("  ✓ Verified custom BLOCK rule takes precedence over disabled default domain")

        // MARK: - TEST 7: Precedence 1 — Custom Allow Rule Takes Highest Precedence
        print("\n[TEST 7] Precedence 1: Custom ALLOW rule takes highest precedence...")
        // Domain is enabled in Ads category, but user has explicit custom ALLOW rule
        engine.setDisabledDefaultDomains([]) // doubleclick.net is enabled in default category
        engine.setRules([
            AuraDNSEngine.Rule(id: "custom-allow-1", domain: "doubleclick.net", isEnabled: true, isBlocked: false)
        ])

        decision = engine.evaluate(domain: "doubleclick.net")
        assert(!decision.isBlocked, "Custom ALLOW rule must allow query even when category block exists")
        assert(decision.matchedSource == "allowlist", "Matched source must be allowlist")
        assert(decision.matchedRule == "doubleclick.net", "Matched rule domain must match")

        decision = engine.evaluate(domain: "sub.doubleclick.net")
        assert(!decision.isBlocked, "Subdomain under custom ALLOW rule must also be allowed")
        assert(decision.matchedSource == "allowlist")
        print("  ✓ Verified custom ALLOW rule takes highest precedence (Precedence 1)")

        // MARK: - TEST 8: Precedence 4 — Default Allow
        print("\n[TEST 8] Precedence 4: Default Allow...")
        engine.setRules([])
        engine.setDisabledDefaultDomains([])
        decision = engine.evaluate(domain: "example.org")
        assert(!decision.isBlocked, "Uncategorized, non-matching domain must be allowed")
        assert(decision.matchedSource == "none")
        print("  ✓ Verified default allow for uncategorized domains")

        // MARK: - TEST 9: Domain Normalization
        print("\n[TEST 9] Domain Normalization...")
        assert(AuraDNSEngine.normalizeDomain("  DOUBLECLICK.NET.  ") == "doubleclick.net", "Must lowercase, trim, and strip trailing dot")
        assert(AuraDNSEngine.normalizeDomain("HTTPS://Pixel.Facebook.COM/tr?id=1") == "pixel.facebook.com", "Must extract hostname")
        print("  ✓ Verified domain normalization across engine and category stores")

        // MARK: - TEST 10: RunnerRuleStore Validation Against Bundled Categories
        print("\n[TEST 10] RunnerRuleStore Validation Against Bundled Categories...")
        // 10.1 Toggle bundled domain succeeds
        let toggleSuccess = RunnerRuleStore.toggleDefaultDomain(domain: "doubleclick.net", isEnabled: false)
        switch toggleSuccess {
        case .success(let disabled):
            assert(disabled.contains("doubleclick.net"), "doubleclick.net must be in disabled set")
            print("  ✓ Successfully disabled bundled domain doubleclick.net")
        case .failure(let err):
            fatalError("Failed to toggle bundled domain: \(err)")
        }

        // 10.2 Toggle unbundled domain fails with typed error
        let toggleFailure = RunnerRuleStore.toggleDefaultDomain(domain: "my-random-domain.com", isEnabled: false)
        switch toggleFailure {
        case .success:
            fatalError("Should not allow toggling an unbundled domain")
        case .failure(let err):
            assert(err.errorCode == "NOT_IN_BUNDLED_CATEGORIES", "Expected NOT_IN_BUNDLED_CATEGORIES error code, got \(err.errorCode)")
            if case .notInBundledCategories(let d) = err {
                assert(d == "my-random-domain.com", "Error domain must match")
            } else {
                fatalError("Unexpected error type: \(err)")
            }
            print("  ✓ Correctly rejected unbundled domain with NOT_IN_BUNDLED_CATEGORIES")
        }

        // MARK: - TEST 11: Disabling and Re-enabling Default Domains
        print("\n[TEST 11] Disabling and Re-enabling Default Domains...")
        // Re-enable doubleclick.net
        let reEnableRes = RunnerRuleStore.toggleDefaultDomain(domain: "doubleclick.net", isEnabled: true)
        switch reEnableRes {
        case .success(let disabled):
            assert(!disabled.contains("doubleclick.net"), "doubleclick.net must be removed from disabled set")
            print("  ✓ Successfully re-enabled bundled domain doubleclick.net")
        case .failure(let err):
            fatalError("Failed to re-enable: \(err)")
        }

        let reloadedAfterReEnable = AuraCategoryStore.loadDisabledDefaultDomains()
        assert(!reloadedAfterReEnable.contains("doubleclick.net"), "Persisted file must reflect removal")

        // MARK: - TEST 12: Separation of Custom Rules and Default Domain Overrides
        print("\n[TEST 12] Separation of Custom Rules and Default Domain Overrides...")
        // Add a custom rule
        let addRuleRes = RunnerRuleStore.addRule(domain: "custom-tracker.com", isBlocked: true)
        assert(caseSuccess(addRuleRes), "Custom rule must be added")

        // Toggle default domain
        _ = RunnerRuleStore.toggleDefaultDomain(domain: "scorecardresearch.com", isEnabled: false)

        // Custom rules must NOT contain scorecardresearch.com or be mutated
        let currentCustomRules = RunnerRuleStore.loadRules()
        assert(currentCustomRules.count == 1, "Custom rules count must remain exactly 1")
        assert(currentCustomRules.first?.domain == "custom-tracker.com", "Custom rule must remain intact")
        assert(!currentCustomRules.contains(where: { $0.domain == "scorecardresearch.com" }), "Default domain must NEVER appear in custom rules")
        print("  ✓ Strict separation confirmed: default domain toggles never mutate custom rules")

        // MARK: - TEST 13: Corrupt Overrides File Graceful Fallback
        print("\n[TEST 13] Corrupt Overrides File Graceful Fallback...")
        try! "invalid non-json garbage content".data(using: .utf8)!.write(to: overridesURL)
        let fallbackDisabled = AuraCategoryStore.loadDisabledDefaultDomains()
        assert(fallbackDisabled.isEmpty, "Corrupt file must gracefully fallback to empty set (all domains enabled)")
        print("  ✓ Corrupt overrides file safely falls back to empty set without crashing")

        print("\n===================================================================")
        print("✓ ALL INDIVIDUAL DEFAULT-DOMAIN OVERRIDES TESTS PASSED PERFECTLY!")
        print("===================================================================")
    }

    private static func caseSuccess<T, E>(_ res: Result<T, E>) -> Bool {
        switch res {
        case .success: return true
        case .failure: return false
        }
    }
}
