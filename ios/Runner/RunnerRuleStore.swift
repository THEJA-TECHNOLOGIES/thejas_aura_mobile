import Foundation
import os.log

/// Pure Swift domain rule definitions shared with AuraTunnel.
public struct AuraRule: Codable, Equatable {
    public let id: String
    public let domain: String
    public let isEnabled: Bool
    public let isBlocked: Bool // true: blocklist, false: allowlist

    enum CodingKeys: String, CodingKey {
        case id, domain, isEnabled, isBlocked
    }

    public init(id: String? = nil, domain: String, isEnabled: Bool = true, isBlocked: Bool = true) {
        let normalized = AuraRule.normalizeDomain(domain)
        self.id = (id == nil || id?.isEmpty == true) ? normalized : id!
        self.domain = normalized
        self.isEnabled = isEnabled
        self.isBlocked = isBlocked
    }

    public init?(dictionary: [String: Any]) {
        guard let domain = dictionary["domain"] as? String else { return nil }
        let normalized = AuraRule.normalizeDomain(domain)
        let rawId = dictionary["id"] as? String
        self.id = (rawId == nil || rawId?.isEmpty == true) ? normalized : rawId!
        self.domain = normalized
        self.isEnabled = dictionary["isEnabled"] as? Bool ?? true
        self.isBlocked = dictionary["isBlocked"] as? Bool ?? true
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDomain = try container.decode(String.self, forKey: .domain)
        let normalized = AuraRule.normalizeDomain(rawDomain)
        let rawId = try container.decodeIfPresent(String.self, forKey: .id)
        self.id = (rawId == nil || rawId?.isEmpty == true) ? normalized : rawId!
        self.domain = normalized
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(domain, forKey: .domain)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isBlocked, forKey: .isBlocked)
    }

    public func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "domain": domain,
            "isEnabled": isEnabled,
            "isBlocked": isBlocked
        ]
    }

    public static func normalizeDomain(_ raw: String) -> String {
        return AuraDNSEngine.normalizeDomain(raw)
    }

    public func toDNSRule() -> AuraDNSEngine.Rule {
        return AuraDNSEngine.Rule(id: id, domain: domain, isEnabled: isEnabled, isBlocked: isBlocked)
    }
}

/// Versioned wrapper for rule persistence.
public struct AuraRuleContainer: Codable {
    public let version: Int
    public let rules: [AuraRule]

    public init(version: Int = 1, rules: [AuraRule]) {
        self.version = version
        self.rules = rules
    }
}

/// Typed errors for custom rule management and validation.
public enum AuraRuleManagementError: Error, Equatable, LocalizedError {
    case validationFailed(AuraDomainValidationError)
    case duplicateRule(String)
    case ruleNotFound(String)
    case persistenceFailed(String)
    case malformedData(String)

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let valErr):
            return valErr.errorDescription
        case .duplicateRule(let domain):
            return "A rule for domain '\(domain)' already exists."
        case .ruleNotFound(let id):
            return "Rule with identifier '\(id)' was not found."
        case .persistenceFailed(let msg):
            return "Failed to persist rules: \(msg)"
        case .malformedData(let msg):
            return "Malformed rule storage: \(msg)"
        }
    }

    public var errorCode: String {
        switch self {
        case .validationFailed(let valErr):
            return valErr.errorCode
        case .duplicateRule:
            return "DUPLICATE_RULE"
        case .ruleNotFound:
            return "RULE_NOT_FOUND"
        case .persistenceFailed:
            return "PERSISTENCE_FAILED"
        case .malformedData:
            return "MALFORMED_DATA"
        }
    }
}

/// App Group rule storage and business operations used by the Runner application.
public final class RunnerRuleStore {
    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "RunnerRuleStore")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let rulesFileName = "aura_rules.json"

    public static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)
    }

    public static var customRulesFileURL: URL? = nil

    public static var rulesFileURL: URL? {
        return customRulesFileURL ?? sharedContainerURL?.appendingPathComponent(rulesFileName)
    }

    // MARK: - Core Persistence

    public static func saveRules(_ rules: [AuraRule]) throws {
        guard let targetURL = rulesFileURL else {
            os_log(.error, log: Self.log, "Failed to access App Group container URL for saving rules")
            throw NSError(domain: "RunnerRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let container = AuraRuleContainer(version: 1, rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(container)
        try data.write(to: targetURL, options: .atomic)
        os_log(.info, log: Self.log, "Successfully persisted %{public}ld rules to %{public}@", rules.count, targetURL.path)
    }

    public static func loadRulesResult() -> Result<[AuraRule], Error> {
        guard let targetURL = rulesFileURL else {
            let err = NSError(domain: "RunnerRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container URL is nil"])
            os_log(.error, log: Self.log, "%{public}@", err.localizedDescription)
            return .failure(err)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            os_log(.info, log: Self.log, "Rules file does not exist at %{public}@; returning empty list", targetURL.path)
            return .success([])
        }

        do {
            let data = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()

            // 1. Attempt to decode versioned container schema
            if let container = try? decoder.decode(AuraRuleContainer.self, from: data) {
                os_log(.info, log: Self.log, "Loaded %{public}ld rules (schema v%{public}d) from %{public}@", container.rules.count, container.version, targetURL.path)
                return .success(container.rules)
            }

            // 2. Fallback to legacy raw array [AuraRule] schema
            if let legacyRules = try? decoder.decode([AuraRule].self, from: data) {
                os_log(.info, log: Self.log, "Loaded %{public}ld rules from legacy schema at %{public}@", legacyRules.count, targetURL.path)
                return .success(legacyRules)
            }

            let decodeErr = NSError(domain: "RunnerRuleStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Malformed or unrecognized rules JSON schema at \(targetURL.path)"])
            os_log(.error, log: Self.log, "%{public}@", decodeErr.localizedDescription)
            return .failure(decodeErr)
        } catch {
            os_log(.error, log: Self.log, "Error reading rules file at %{public}@: %{public}@", targetURL.path, error.localizedDescription)
            return .failure(error)
        }
    }

    public static func loadRules() -> [AuraRule] {
        return (try? loadRulesResult().get()) ?? []
    }

    // MARK: - Domain Validation & Rule Management

    /// Validates a raw domain candidate using PSL rules and syntax checks.
    public static func validateDomain(
        _ rawDomain: String,
        validator: AuraPSLValidator = .shared
    ) -> Result<String, AuraDomainValidationError> {
        return validator.validateRuleDomain(rawDomain)
    }

    /// Lists all custom rules with typed error reporting.
    public static func listRules() -> Result<[AuraRule], AuraRuleManagementError> {
        switch loadRulesResult() {
        case .success(let rules):
            return .success(rules)
        case .failure(let error):
            return .failure(.malformedData(error.localizedDescription))
        }
    }

    /// Adds a new rule with PSL validation and duplicate prevention.
    public static func addRule(
        domain rawDomain: String,
        isBlocked: Bool,
        isEnabled: Bool = true,
        validator: AuraPSLValidator = .shared
    ) -> Result<AuraRule, AuraRuleManagementError> {
        // 1. Validate domain
        let validatedDomain: String
        switch validator.validateRuleDomain(rawDomain) {
        case .success(let valid):
            validatedDomain = valid
        case .failure(let valErr):
            return .failure(.validationFailed(valErr))
        }

        // 2. Load existing rules
        var currentRules: [AuraRule]
        switch loadRulesResult() {
        case .success(let rules):
            currentRules = rules
        case .failure(let error):
            return .failure(.malformedData(error.localizedDescription))
        }

        // 3. Prevent duplicate rules (after normalization)
        if currentRules.contains(where: { $0.domain == validatedDomain }) {
            return .failure(.duplicateRule(validatedDomain))
        }

        // 4. Create and persist rule
        let newRule = AuraRule(id: validatedDomain, domain: validatedDomain, isEnabled: isEnabled, isBlocked: isBlocked)
        currentRules.append(newRule)

        do {
            try saveRules(currentRules)
            return .success(newRule)
        } catch {
            return .failure(.persistenceFailed(error.localizedDescription))
        }
    }

    /// Edits an existing rule's properties.
    public static func updateRule(
        id: String,
        domain newRawDomain: String? = nil,
        isBlocked: Bool? = nil,
        isEnabled: Bool? = nil,
        validator: AuraPSLValidator = .shared
    ) -> Result<AuraRule, AuraRuleManagementError> {
        // 1. Load current rules
        var currentRules: [AuraRule]
        switch loadRulesResult() {
        case .success(let rules):
            currentRules = rules
        case .failure(let error):
            return .failure(.malformedData(error.localizedDescription))
        }

        // 2. Find rule by ID
        guard let index = currentRules.firstIndex(where: { $0.id == id }) else {
            return .failure(.ruleNotFound(id))
        }

        let existing = currentRules[index]
        var targetDomain = existing.domain

        // 3. If domain changed, validate and check for duplicates
        if let newRaw = newRawDomain, !newRaw.isEmpty {
            switch validator.validateRuleDomain(newRaw) {
            case .success(let valid):
                if valid != existing.domain && currentRules.contains(where: { $0.id != id && $0.domain == valid }) {
                    return .failure(.duplicateRule(valid))
                }
                targetDomain = valid
            case .failure(let valErr):
                return .failure(.validationFailed(valErr))
            }
        }

        let updatedRule = AuraRule(
            id: existing.id,
            domain: targetDomain,
            isEnabled: isEnabled ?? existing.isEnabled,
            isBlocked: isBlocked ?? existing.isBlocked
        )

        currentRules[index] = updatedRule

        do {
            try saveRules(currentRules)
            return .success(updatedRule)
        } catch {
            return .failure(.persistenceFailed(error.localizedDescription))
        }
    }

    /// Deletes a rule by its stable identifier.
    public static func deleteRule(id: String) -> Result<AuraRule, AuraRuleManagementError> {
        var currentRules: [AuraRule]
        switch loadRulesResult() {
        case .success(let rules):
            currentRules = rules
        case .failure(let error):
            return .failure(.malformedData(error.localizedDescription))
        }

        guard let index = currentRules.firstIndex(where: { $0.id == id }) else {
            return .failure(.ruleNotFound(id))
        }

        let deleted = currentRules.remove(at: index)

        do {
            try saveRules(currentRules)
            return .success(deleted)
        } catch {
            return .failure(.persistenceFailed(error.localizedDescription))
        }
    }

    /// Toggles the enabled state of a rule.
    public static func toggleRule(id: String, isEnabled: Bool) -> Result<AuraRule, AuraRuleManagementError> {
        return updateRule(id: id, isEnabled: isEnabled)
    }

    // MARK: - Category Preferences Bridge

    public static func loadCategoryPreferences() -> Result<[String: Bool], Error> {
        return AuraCategoryStore.loadPreferencesResult()
    }

    public static func saveCategoryPreferences(_ preferences: [String: Bool]) throws {
        try AuraCategoryStore.savePreferences(preferences)
    }

    public static func setCategoryPreference(category: String, isEnabled: Bool) -> Result<[String: Bool], Error> {
        var prefs = AuraCategoryStore.loadPreferences()
        prefs[category] = isEnabled
        do {
            try AuraCategoryStore.savePreferences(prefs)
            return .success(prefs)
        } catch {
            return .failure(error)
        }
    }
}
