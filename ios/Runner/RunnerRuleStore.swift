import Foundation

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

/// App Group rule storage used by the Runner application.
public final class RunnerRuleStore {
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
            throw NSError(domain: "RunnerRuleStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(rules)
        try data.write(to: targetURL, options: .atomic)
    }
}
