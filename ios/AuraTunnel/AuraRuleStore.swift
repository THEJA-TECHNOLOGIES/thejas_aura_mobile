import Foundation
import os.log

/// Versioned wrapper for rule persistence inside the AuraTunnel extension.
public struct AuraTunnelRuleContainer: Codable {
    public let version: Int
    public let rules: [AuraDNSEngine.Rule]

    public init(version: Int = 1, rules: [AuraDNSEngine.Rule]) {
        self.version = version
        self.rules = rules
    }
}

/// Shared App Group persistence for rules used by both Runner and AuraTunnel.
public final class AuraRuleStore {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraRuleStore")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let rulesFileName = "aura_rules.json"

    public static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)
    }

    public static var rulesFileURL: URL? {
        return sharedContainerURL?.appendingPathComponent(rulesFileName)
    }

    public static func saveRules(_ rules: [AuraDNSEngine.Rule]) throws {
        guard let targetURL = rulesFileURL else {
            os_log(.error, log: Self.log, "Failed to access App Group container URL for saving rules")
            throw NSError(domain: "AuraRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let container = AuraTunnelRuleContainer(version: 1, rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(container)
        try data.write(to: targetURL, options: .atomic)
        os_log(.info, log: Self.log, "Successfully persisted %{public}ld rules to %{public}@", rules.count, targetURL.path)
    }

    public static func loadRulesResult() -> Result<[AuraDNSEngine.Rule], Error> {
        guard let targetURL = rulesFileURL else {
            let err = NSError(domain: "AuraRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container URL is nil"])
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
            if let container = try? decoder.decode(AuraTunnelRuleContainer.self, from: data) {
                os_log(.info, log: Self.log, "Loaded %{public}ld rules (schema v%{public}d) from %{public}@", container.rules.count, container.version, targetURL.path)
                return .success(container.rules)
            }

            // 2. Fallback to legacy raw array [AuraDNSEngine.Rule] schema
            if let legacyRules = try? decoder.decode([AuraDNSEngine.Rule].self, from: data) {
                os_log(.info, log: Self.log, "Loaded %{public}ld rules from legacy schema at %{public}@", legacyRules.count, targetURL.path)
                return .success(legacyRules)
            }

            let decodeErr = NSError(domain: "AuraRuleStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Malformed or unrecognized rules JSON schema at \(targetURL.path)"])
            os_log(.error, log: Self.log, "%{public}@", decodeErr.localizedDescription)
            return .failure(decodeErr)
        } catch {
            os_log(.error, log: Self.log, "Error reading rules file at %{public}@: %{public}@", targetURL.path, error.localizedDescription)
            return .failure(error)
        }
    }

    public static func loadRules() -> [AuraDNSEngine.Rule] {
        return (try? loadRulesResult().get()) ?? []
    }
}
