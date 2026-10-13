import Foundation

@main
struct Phase4Tests {
    static func main() {
        print("=======================================================")
        print("THEJA AURA — PHASE 4 RULES & CATEGORIES TEST SUITE")
        print("=======================================================")

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("aura_phase4_tests_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        let pslURL = URL(fileURLWithPath: "ios/AuraTunnel/Resources/public_suffix_list.dat")
        guard fileManager.fileExists(atPath: pslURL.path) else {
            fatalError("CRITICAL FAILURE: Missing PSL resource at \(pslURL.path)")
        }
        let pslValidator = AuraPSLValidator(fileURL: pslURL)

        // MARK: - TEST 1: Strict Domain Validation & Typed Error Codes
        print("\n[TEST 1] Domain Validation & Typed Error Codes...")
        
        // 1.1 Empty domain
        let emptyResult = pslValidator.validateRuleDomain("   ")
        switch emptyResult {
        case .failure(let err):
            assert(err.errorCode == "EMPTY_DOMAIN", "Expected EMPTY_DOMAIN error code")
            print("  ✓ Correctly rejected empty domain with EMPTY_DOMAIN")
        case .success:
            fatalError("Failed to reject empty domain")
        }

        // 1.2 Single-label domain
        let singleTargets = ["localhost", "com", "org", "net", "internal"]
        for target in singleTargets {
            let singleResult = pslValidator.validateRuleDomain(target)
            switch singleResult {
            case .failure(let err):
                assert(err.errorCode == "SINGLE_LABEL_DOMAIN", "Expected SINGLE_LABEL_DOMAIN for \(target)")
                print("  ✓ Correctly rejected single-label domain '\(target)' with SINGLE_LABEL_DOMAIN")
            case .success:
                fatalError("Failed to reject single-label domain: \(target)")
            }
        }

        // 1.3 IPv4 Address Rejection
        let ipv4Targets = ["1.1.1.1", "127.0.0.1", "192.168.1.1", "8.8.8.8"]
        for target in ipv4Targets {
            let res = pslValidator.validateRuleDomain(target)
            switch res {
            case .failure(let err):
                assert(err.errorCode == "IP_ADDRESS", "Expected IP_ADDRESS for \(target)")
                print("  ✓ Correctly rejected IPv4 address '\(target)'")
            case .success:
                fatalError("Failed to reject IPv4 address: \(target)")
            }
        }

        // 1.4 IPv6 Address Rejection
        let ipv6Targets = ["::1", "2001:db8::1", "fe80::1", "2001:4860:4860::8888"]
        for target in ipv6Targets {
            let res = pslValidator.validateRuleDomain(target)
            switch res {
            case .failure(let err):
                assert(err.errorCode == "IP_ADDRESS", "Expected IP_ADDRESS for \(target)")
                print("  ✓ Correctly rejected IPv6 address '\(target)'")
            case .success:
                fatalError("Failed to reject IPv6 address: \(target)")
            }
        }

        // 1.5 Public Suffix Rejection (Multi-label public suffixes from PSL)
        let pslTargets = ["co.uk", "github.io", "gov.au", "com.au", "s3.amazonaws.com"]
        for target in pslTargets {
            let res = pslValidator.validateRuleDomain(target)
            switch res {
            case .failure(let err):
                assert(err.errorCode == "PUBLIC_SUFFIX", "Expected PUBLIC_SUFFIX for \(target), got \(err.errorCode)")
                print("  ✓ Correctly rejected public suffix '\(target)' with PUBLIC_SUFFIX")
            case .success:
                fatalError("Failed to reject public suffix: \(target)")
            }
        }

        // 1.6 Malformed & Invalid Characters
        let malformedTargets = ["-leading.com", "trailing-.com", "has space.com", "under_score.com", "ex..ample.com"]
        for target in malformedTargets {
            let res = pslValidator.validateRuleDomain(target)
            switch res {
            case .failure(let err):
                assert(err.errorCode == "INVALID_CHARACTERS" || err.errorCode == "EMPTY_DOMAIN", "Expected error for \(target)")
                print("  ✓ Correctly rejected malformed domain '\(target)' with \(err.errorCode)")
            case .success:
                fatalError("Failed to reject malformed domain: \(target)")
            }
        }

        // 1.7 Normalization & Acceptance of Valid Domains
        let validPairs: [(String, String)] = [
            ("HTTPS://EXAMPLE.COM/path?query=1#hash", "example.com"),
            ("http://sub.domain.co.uk.", "sub.domain.co.uk"),
            ("  My-Tracker.NET   ", "my-tracker.net"),
            ("api.service.io", "api.service.io")
        ]
        for (input, expected) in validPairs {
            let res = pslValidator.validateRuleDomain(input)
            switch res {
            case .success(let normalized):
                assert(normalized == expected, "Expected normalized '\(expected)', got '\(normalized)'")
                print("  ✓ Correctly normalized and accepted '\(input)' -> '\(normalized)'")
            case .failure(let err):
                fatalError("Failed to accept valid domain '\(input)': \(err)")
            }
        }

        // MARK: - TEST 2: RunnerRuleStore CRUD & Atomic Persistence
        print("\n[TEST 2] RunnerRuleStore CRUD & Persistence...")
        let rulesFileURL = tempDir.appendingPathComponent("aura_rules.json")
        let categoryFileURL = tempDir.appendingPathComponent("aura_category_preferences.json")
        RunnerRuleStore.customRulesFileURL = rulesFileURL
        AuraCategoryStore.customPreferencesFileURL = categoryFileURL

        // 2.1 Initial load is empty
        let rulesResult = RunnerRuleStore.listRules()
        switch rulesResult {
        case .success(let rules):
            assert(rules.isEmpty, "Initial rules list must be empty")
            print("  ✓ Initial rules list is empty")
        case .failure(let err):
            fatalError("Failed to list rules: \(err)")
        }

        // 2.2 Add Rule
        let rule1: AuraRule
        let addRes1 = RunnerRuleStore.addRule(domain: "analytics.evilcorp.com", isBlocked: true, isEnabled: true, validator: pslValidator)
        switch addRes1 {
        case .success(let rule):
            rule1 = rule
            assert(rule1.domain == "analytics.evilcorp.com")
            assert(rule1.isBlocked == true)
            assert(rule1.isEnabled == true)
            assert(!rule1.id.isEmpty)
            print("  ✓ Added rule with stable id: \(rule1.id) for domain: \(rule1.domain)")
        case .failure(let err):
            fatalError("Failed to add rule: \(err)")
        }

        // 2.3 Duplicate Rejection
        let dupRes = RunnerRuleStore.addRule(domain: "  Analytics.EvilCorp.COM.  ", isBlocked: false, isEnabled: true, validator: pslValidator)
        switch dupRes {
        case .failure(let err):
            assert(err.errorCode == "DUPLICATE_RULE")
            print("  ✓ Correctly rejected duplicate domain with DUPLICATE_RULE error code")
        case .success:
            fatalError("CRITICAL FAILURE: Expected duplicate domain addition to fail")
        }

        // 2.4 Add Second Rule (Allowlist)
        let rule2: AuraRule
        let addRes2 = RunnerRuleStore.addRule(domain: "goodservice.org", isBlocked: false, isEnabled: true, validator: pslValidator)
        switch addRes2 {
        case .success(let rule):
            rule2 = rule
            assert(rule2.isBlocked == false)
            print("  ✓ Added allowlist rule: \(rule2.domain) (id: \(rule2.id))")
        case .failure(let err):
            fatalError("Failed to add second rule: \(err)")
        }

        let listed = (try? RunnerRuleStore.listRules().get()) ?? []
        assert(listed.count == 2, "Expected 2 rules in store")

        // 2.5 Toggle Rule
        let toggleRes = RunnerRuleStore.toggleRule(id: rule1.id, isEnabled: false)
        switch toggleRes {
        case .success(let toggled):
            assert(toggled.isEnabled == false)
            let updatedList = (try? RunnerRuleStore.listRules().get()) ?? []
            assert(updatedList.first(where: { $0.id == rule1.id })?.isEnabled == false)
            print("  ✓ Successfully toggled rule state to isEnabled=false")
        case .failure(let err):
            fatalError("Failed to toggle rule: \(err)")
        }

        // 2.6 Update Rule
        let updateRes = RunnerRuleStore.updateRule(id: rule1.id, domain: "analytics.evilcorp.com", isBlocked: false, isEnabled: true, validator: pslValidator)
        switch updateRes {
        case .success(let updated):
            assert(updated.isBlocked == false)
            assert(updated.isEnabled == true)
            print("  ✓ Successfully updated rule to isBlocked=false, isEnabled=true")
        case .failure(let err):
            fatalError("Failed to update rule: \(err)")
        }

        // 2.7 Delete Rule
        let deleteRes = RunnerRuleStore.deleteRule(id: rule1.id)
        switch deleteRes {
        case .success(let deleted):
            assert(deleted.id == rule1.id)
            let remaining = (try? RunnerRuleStore.listRules().get()) ?? []
            assert(remaining.count == 1)
            assert(remaining.first?.id == rule2.id)
            print("  ✓ Successfully deleted rule \(rule1.id)")
        case .failure(let err):
            fatalError("Failed to delete rule: \(err)")
        }

        // 2.8 Operations on nonexistent rule fail with RULE_NOT_FOUND
        let deleteMissing = RunnerRuleStore.deleteRule(id: "nonexistent-id")
        switch deleteMissing {
        case .failure(let err):
            assert(err.errorCode == "RULE_NOT_FOUND")
            print("  ✓ Correctly rejected operation on nonexistent rule with RULE_NOT_FOUND")
        case .success:
            fatalError("Expected delete of nonexistent rule to throw")
        }

        // 2.9 Validation rejection on addRule
        let addPSL = RunnerRuleStore.addRule(domain: "github.io", isBlocked: true, isEnabled: true, validator: pslValidator)
        switch addPSL {
        case .failure(let err):
            assert(err.errorCode == "PUBLIC_SUFFIX")
            print("  ✓ Correctly rejected addRule for PSL domain with PUBLIC_SUFFIX error")
        case .success:
            fatalError("Expected addRule for public suffix to throw")
        }

        // 2.10 Persistence Durability across reload
        let reloadedRules = (try? RunnerRuleStore.listRules().get()) ?? []
        assert(reloadedRules.count == 1)
        assert(reloadedRules.first?.id == rule2.id)
        assert(reloadedRules.first?.domain == "goodservice.org")
        print("  ✓ Persisted rules verified across store reload")

        // MARK: - TEST 3: Category Preferences Management
        print("\n[TEST 3] Category Preferences Management...")

        // 3.1 Initial defaults
        var catPrefs = (try? RunnerRuleStore.loadCategoryPreferences().get()) ?? [:]
        assert(catPrefs["Ads"] == true)
        assert(catPrefs["Trackers"] == true)
        assert(catPrefs["Analytics"] == true)
        print("  ✓ Initial category preferences are all true: \(catPrefs)")

        // 3.2 Update preference
        let setPrefRes = RunnerRuleStore.setCategoryPreference(category: "Ads", isEnabled: false)
        switch setPrefRes {
        case .success(let updatedPrefs):
            assert(updatedPrefs["Ads"] == false)
            assert(updatedPrefs["Trackers"] == true)
            assert(updatedPrefs["Analytics"] == true)
            print("  ✓ Successfully updated Ads category to false: \(updatedPrefs)")
        case .failure(let err):
            fatalError("Failed to set category preference: \(err)")
        }

        // 3.3 Reload categories from disk
        catPrefs = (try? RunnerRuleStore.loadCategoryPreferences().get()) ?? [:]
        assert(catPrefs["Ads"] == false)
        assert(catPrefs["Trackers"] == true)
        print("  ✓ Category preferences verified across file reload")

        // MARK: - TEST 4: Engine Precedence & Category Overlap
        print("\n[TEST 4] Engine Precedence & Category Overlap Evaluation...")
        
        let engine = AuraDNSEngine()

        // Seed domain lists
        let adsList: Set<String> = ["adserver.com", "doubleclick.net", "shared-tracker.com"]
        let trackersList: Set<String> = ["fingerprint.com", "shared-tracker.com"]
        let analyticsList: Set<String> = ["metrics.app.com"]
        engine.setCategories([
            "Ads": adsList,
            "Trackers": trackersList,
            "Analytics": analyticsList
        ])

        // 4.1 Category Overlap Isolation
        // "shared-tracker.com" belongs to both Ads and Trackers
        // Enable both
        engine.setCategoryPreferences(["Ads": true, "Trackers": true, "Analytics": true])
        var decision = engine.evaluate(domain: "shared-tracker.com")
        assert(decision.isBlocked == true, "Expected shared-tracker.com to be blocked")
        assert(decision.matchedCategories.contains("Ads") || decision.matchedCategories.contains("Trackers"))
        print("  ✓ Overlapping domain blocked when both categories enabled (\(decision.matchedCategories))")

        // Now disable Ads only! Since Trackers is still enabled, it MUST still be blocked!
        engine.setCategoryPreferences(["Ads": false, "Trackers": true, "Analytics": true])
        decision = engine.evaluate(domain: "shared-tracker.com")
        assert(decision.isBlocked == true, "Expected shared-tracker.com to remain blocked by Trackers")
        assert(decision.matchedCategories == ["Trackers"], "Expected matchedCategories to be [Trackers], got: \(decision.matchedCategories)")
        print("  ✓ Overlapping domain remains blocked by Trackers when Ads is disabled")

        // Disable Trackers as well -> Now it should be allowed!
        engine.setCategoryPreferences(["Ads": false, "Trackers": false, "Analytics": true])
        decision = engine.evaluate(domain: "shared-tracker.com")
        assert(decision.isBlocked == false, "Expected shared-tracker.com to be allowed when all matched categories are disabled")
        assert(decision.matchedSource == "none")
        print("  ✓ Overlapping domain allowed when all its categories are disabled")

        // 4.2 Precedence Level 1: Custom Allowlist Overrides Category Block
        // Re-enable Trackers
        engine.setCategoryPreferences(["Ads": true, "Trackers": true, "Analytics": true])
        // "shared-tracker.com" is currently blocked by Ads/Trackers
        // Add custom allowlist rule for "shared-tracker.com"
        let allowRule = AuraDNSEngine.Rule(id: "rule-allow-shared", domain: "shared-tracker.com", isEnabled: true, isBlocked: false)
        engine.setRules([allowRule])

        decision = engine.evaluate(domain: "shared-tracker.com")
        assert(decision.isBlocked == false, "Custom allowlist MUST override category block!")
        assert(decision.matchedSource == "allowlist")
        assert(decision.matchedRule == "shared-tracker.com")
        print("  ✓ Precedence 1: Custom allowlist successfully overrides category block")

        // Test subdomain under custom allowlist
        decision = engine.evaluate(domain: "sub.shared-tracker.com")
        assert(decision.isBlocked == false, "Subdomain under allowlist must also be allowed")
        assert(decision.matchedSource == "allowlist")
        print("  ✓ Precedence 1: Subdomain under custom allowlist allowed")

        // 4.3 Precedence Level 2: Custom Blocklist
        // Add custom block rule for "clean-site.org" which is NOT in any category
        let blockRule = AuraDNSEngine.Rule(id: "rule-block-clean", domain: "clean-site.org", isEnabled: true, isBlocked: true)
        engine.setRules([allowRule, blockRule])

        decision = engine.evaluate(domain: "clean-site.org")
        assert(decision.isBlocked == true, "Custom blocklist rule MUST block domain")
        assert(decision.matchedSource == "custom")
        assert(decision.matchedRule == "clean-site.org")
        print("  ✓ Precedence 2: Custom blocklist blocks uncategorized domain")

        // Subdomain under custom blocklist
        decision = engine.evaluate(domain: "api.clean-site.org")
        assert(decision.isBlocked == true, "Subdomain under custom blocklist must be blocked")
        assert(decision.matchedSource == "custom")
        print("  ✓ Precedence 2: Subdomain under custom blocklist blocked")

        // 4.4 Disabled Custom Rules are Ignored
        let disabledBlockRule = AuraDNSEngine.Rule(id: "rule-block-clean", domain: "clean-site.org", isEnabled: false, isBlocked: true)
        engine.setRules([allowRule, disabledBlockRule])

        decision = engine.evaluate(domain: "clean-site.org")
        assert(decision.isBlocked == false, "Disabled custom rule must not block domain")
        print("  ✓ Disabled custom rule is ignored and query is allowed")

        // 4.5 Exact Label Boundary Enforcement
        // "clean-site.org" is in rule, but "notclean-site.org" must NOT be matched!
        let activeBlock = AuraDNSEngine.Rule(id: "rule-block-clean", domain: "clean-site.org", isEnabled: true, isBlocked: true)
        engine.setRules([activeBlock])

        decision = engine.evaluate(domain: "notclean-site.org")
        assert(decision.isBlocked == false, "Exact label boundary: 'notclean-site.org' must not match 'clean-site.org'")
        assert(decision.matchedSource == "none")
        print("  ✓ Label boundary: 'notclean-site.org' correctly NOT matched by 'clean-site.org'")

        // 4.6 Default Allow
        decision = engine.evaluate(domain: "unrelated-domain.com")
        assert(decision.isBlocked == false)
        assert(decision.matchedSource == "none")
        print("  ✓ Precedence 4: Default allow for non-matching domain")

        // MARK: - TEST 5: Legacy Rule Schema Backward Compatibility
        print("\n[TEST 5] Legacy Rule Schema Backward Compatibility...")
        // Write JSON without 'id' fields (schema v1)
        let legacyJSON = """
        [
            {"domain": "legacy-block.com", "isBlocked": true, "isEnabled": true},
            {"domain": "legacy-allow.org", "isBlocked": false, "isEnabled": true}
        ]
        """.data(using: .utf8)!
        let legacyFileURL = tempDir.appendingPathComponent("legacy_rules.json")
        try! legacyJSON.write(to: legacyFileURL)

        RunnerRuleStore.customRulesFileURL = legacyFileURL
        let loadedLegacy = (try? RunnerRuleStore.listRules().get()) ?? []
        assert(loadedLegacy.count == 2)
        assert(loadedLegacy[0].id == "legacy-block.com", "Legacy rule must default id to domain")
        assert(loadedLegacy[1].id == "legacy-allow.org", "Legacy rule must default id to domain")
        print("  ✓ Legacy schema without 'id' field successfully decoded with id defaulting to domain")

        // Verify Engine Rule decoding for legacy schema
        let decodedEngineRules = try! JSONDecoder().decode([AuraDNSEngine.Rule].self, from: legacyJSON)
        assert(decodedEngineRules.count == 2)
        assert(decodedEngineRules[0].id == "legacy-block.com")
        assert(decodedEngineRules[1].id == "legacy-allow.org")
        print("  ✓ AuraDNSEngine.Rule successfully decoded legacy schema")

        print("\n=======================================================")
        print("✓ ALL 5 PHASE 4 NATIVE SUITE TESTS PASSED PERFECTLY")
        print("=======================================================\n")
    }
}
