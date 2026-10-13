import Foundation

/// Shared App Group persistence for rules used by both Runner and AuraTunnel.
public final class AuraRuleStore {

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
            throw NSError(domain: "AuraRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(rules)
        try data.write(to: targetURL, options: .atomic)
    }

    public static func loadRules() -> [AuraDNSEngine.Rule] {
        guard let targetURL = rulesFileURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()
            return try decoder.decode([AuraDNSEngine.Rule].self, from: data)
        } catch {
            return []
        }
    }
}
