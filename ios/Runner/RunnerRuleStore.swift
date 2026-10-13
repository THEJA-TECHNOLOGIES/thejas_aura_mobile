import Foundation
import os.log

/// Pure Swift domain rule definitions shared with AuraTunnel.
public struct AuraRule: Codable, Equatable {
    public let domain: String
    public let isEnabled: Bool
    public let isBlocked: Bool

    public init(domain: String, isEnabled: Bool = true, isBlocked: Bool = true) {
        self.domain = AuraRule.normalizeDomain(domain)
        self.isEnabled = isEnabled
        self.isBlocked = isBlocked
    }

    public init?(dictionary: [String: Any]) {
        guard let domain = dictionary["domain"] as? String else { return nil }
        self.domain = AuraRule.normalizeDomain(domain)
        self.isEnabled = dictionary["isEnabled"] as? Bool ?? true
        self.isBlocked = dictionary["isBlocked"] as? Bool ?? true
    }

    public func toDictionary() -> [String: Any] {
        return [
            "domain": domain,
            "isEnabled": isEnabled,
            "isBlocked": isBlocked
        ]
    }

    public static func normalizeDomain(_ raw: String) -> String {
        var domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeRange = domain.range(of: "://") {
            domain = String(domain[schemeRange.upperBound...])
        }
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }
        if let colonIndex = domain.firstIndex(of: ":") {
            domain = String(domain[..<colonIndex])
        }
        while domain.hasSuffix(".") {
            domain.removeLast()
        }
        return domain
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

/// App Group rule storage used by the Runner application.
public final class RunnerRuleStore {
    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "RunnerRuleStore")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let rulesFileName = "aura_rules.json"

    public static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)
    }

    public static var rulesFileURL: URL? {
        return sharedContainerURL?.appendingPathComponent(rulesFileName)
    }

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
}
