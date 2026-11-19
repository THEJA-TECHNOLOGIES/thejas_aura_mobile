import Foundation
import os.log

public enum AuraDomainValidationError: Error, Equatable, LocalizedError {
    case emptyDomain
    case singleLabelDomain(String)
    case publicSuffix(String)
    case invalidCharacters(String)
    case ipAddress(String)

    public var errorDescription: String? {
        switch self {
        case .emptyDomain:
            return "Domain name cannot be empty."
        case .singleLabelDomain(let d):
            return "Domain '\(d)' is a top-level domain without a registrable name."
        case .publicSuffix(let d):
            return "Domain '\(d)' is a public suffix (TLD or registry suffix) and cannot be blocked as a whole."
        case .invalidCharacters(let d):
            return "Domain '\(d)' contains invalid characters."
        case .ipAddress(let d):
            return "IP address '\(d)' cannot be used as a domain firewall rule."
        }
    }

    public var errorCode: String {
        switch self {
        case .emptyDomain:
            return "EMPTY_DOMAIN"
        case .singleLabelDomain:
            return "SINGLE_LABEL_DOMAIN"
        case .publicSuffix:
            return "PUBLIC_SUFFIX"
        case .invalidCharacters:
            return "INVALID_CHARACTERS"
        case .ipAddress:
            return "IP_ADDRESS"
        }
    }
}

/// Mozilla Public Suffix List (PSL) Validator for Theja's Aura.
///
/// Upstream Source: https://publicsuffix.org/list/public_suffix_list.dat
/// Snapshot Version: 2026-10-07_07-28-19_UTC (Commit: 3929462652695bad04f0a27afb600974014a3c8b)
/// License: Mozilla Public License, v. 2.0 (MPL-2.0)
///
/// Update Procedure:
/// Download latest snapshot to `ios/AuraTunnel/Resources/public_suffix_list.dat`.
///
/// Staleness Limitation:
/// Because this snapshot is bundled offline within the application to avoid network dependencies,
/// newly registered gTLDs or private suffixes will not be recognized until an application update is distributed.
public final class AuraPSLValidator {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraPSLValidator")

    public static let shared = AuraPSLValidator()

    private let exactRules: Set<String>
    private let wildcardRules: Set<String> // Stores the parent label, e.g. for *.ck, stores "ck"
    private let exceptionRules: Set<String> // Stores the exception rule without '!', e.g. "city.kobe.jp"

    public init(rulesContent: String) {
        var exacts = Set<String>()
        var wildcards = Set<String>()
        var exceptions = Set<String>()

        rulesContent.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
                return
            }

            let lower = trimmed.lowercased()
            if lower.hasPrefix("!") {
                let rule = String(lower.dropFirst())
                exceptions.insert(rule)
            } else if lower.hasPrefix("*.") {
                let parent = String(lower.dropFirst(2))
                wildcards.insert(parent)
            } else {
                exacts.insert(lower)
            }
        }

        self.exactRules = exacts
        self.wildcardRules = wildcards
        self.exceptionRules = exceptions
    }

    public convenience init(fileURL: URL) {
        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
            self.init(rulesContent: content)
        } else {
            os_log(.error, log: Self.log, "Failed to load PSL from %{public}@; using built-in minimal fallback", fileURL.path)
            self.init(rulesContent: Self.fallbackRules)
        }
    }

    private convenience init() {
        // 1. Try bundle for current class / framework
        let bundle = Bundle(for: AuraPSLValidator.self)
        if let url = bundle.url(forResource: "public_suffix_list", withExtension: "dat") ??
                     Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            self.init(rulesContent: content)
            return
        }

        // 2. Try App Group container if copied or staged
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.thejatech.aura"),
           let content = try? String(contentsOf: containerURL.appendingPathComponent("public_suffix_list.dat"), encoding: .utf8) {
            self.init(rulesContent: content)
            return
        }

        // 3. Fallback to bundled static snapshot
        self.init(rulesContent: Self.fallbackRules)
    }

    /// Determines the effective public suffix for a domain per Mozilla PSL specification.
    /// Supports exact rules, wildcard rules (*.ck), and exception rules (!city.kobe.jp).
    public func getPublicSuffix(_ domain: String) -> String {
        let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            .lowercased()
        let labels = cleaned.split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return cleaned }

        // Generate candidate suffixes from longest to shortest (e.g. ["a.b.c", "b.c", "c"])
        var candidates: [String] = []
        for i in 0..<labels.count {
            candidates.append(labels[i...].joined(separator: "."))
        }

        // 1. Check Exception rules (!city.kobe.jp)
        for candidate in candidates {
            if exceptionRules.contains(candidate) {
                // An exception rule matches: the public suffix is the rule minus its first label
                let candidateLabels = candidate.split(separator: ".")
                if candidateLabels.count > 1 {
                    return candidateLabels.dropFirst().joined(separator: ".")
                }
                return ""
            }
        }

        // 2. Check Wildcard and Exact rules; pick the matching rule with the most labels
        var bestSuffix: String? = nil
        var bestLabelCount = -1

        for candidate in candidates {
            let candidateLabels = candidate.split(separator: ".")
            let count = candidateLabels.count

            // Wildcard match: if candidate's parent is in wildcardRules
            if count >= 2 {
                let parent = candidateLabels.dropFirst().joined(separator: ".")
                if wildcardRules.contains(parent) {
                    if count > bestLabelCount {
                        bestSuffix = candidate
                        bestLabelCount = count
                    }
                }
            }

            // Exact match
            if exactRules.contains(candidate) {
                if count > bestLabelCount {
                    bestSuffix = candidate
                    bestLabelCount = count
                }
            }
        }

        if let best = bestSuffix {
            return best
        }

        // Fallback: the rightmost label (TLD)
        return labels.last ?? cleaned
    }

    /// Returns true if the domain is a bare public suffix (e.g. "com", "co.uk", "gov.au", "github.io").
    public func isPublicSuffix(_ domain: String) -> Bool {
        let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            .lowercased()
        guard !cleaned.isEmpty else { return false }
        let suffix = getPublicSuffix(cleaned)
        return cleaned == suffix
    }

    /// Returns the registrable domain (eTLD+1) for a domain, or nil if it is a bare public suffix.
    public func registrableDomain(_ domain: String) -> String? {
        let cleaned = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            .lowercased()
        let labels = cleaned.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }

        let suffix = getPublicSuffix(cleaned)
        if cleaned == suffix {
            return nil // Bare public suffix has no registrable domain
        }

        let suffixLabels = suffix.split(separator: ".").map(String.init)
        guard labels.count > suffixLabels.count else { return nil }

        let registrableIndex = labels.count - suffixLabels.count - 1
        return labels[registrableIndex...].joined(separator: ".")
    }

    // MARK: - IP Address Detection

    /// Returns true if the string is a valid IPv4 or IPv6 address.
    public static func isIPAddress(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if isIPv4(trimmed) { return true }
        if isIPv6(trimmed) { return true }
        return false
    }

    /// Validates IPv4 format using POSIX inet_pton.
    public static func isIPv4(_ str: String) -> Bool {
        var sin = in_addr()
        return str.withCString { inet_pton(AF_INET, $0, &sin) == 1 }
    }

    /// Validates IPv6 format using POSIX inet_pton.
    public static func isIPv6(_ str: String) -> Bool {
        let clean = str.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        var sin6 = in6_addr()
        return clean.withCString { inet_pton(AF_INET6, $0, &sin6) == 1 }
    }

    /// Validates whether a domain is eligible to be added as a custom blocking or allowlist rule.
    public func validateRuleDomain(_ rawDomain: String) -> Result<String, AuraDomainValidationError> {
        let trimmed = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .failure(.emptyDomain)
        }

        // Check if raw input was an IP address before stripping
        if Self.isIPAddress(trimmed) {
            return .failure(.ipAddress(trimmed))
        }

        var domain = trimmed.lowercased()

        // Strip scheme, paths, ports, trailing dots
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

        if domain.isEmpty {
            return .failure(.emptyDomain)
        }

        // Check if normalized domain is an IP address
        if Self.isIPAddress(domain) {
            return .failure(.ipAddress(domain))
        }

        // Overall RFC 1035 domain length check (max 253 characters)
        if domain.count > 253 {
            return .failure(.invalidCharacters(domain))
        }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 {
            return .failure(.singleLabelDomain(domain))
        }

        // Verify each label
        for label in labels {
            if label.isEmpty || label.count > 63 || label.hasPrefix("-") || label.hasSuffix("-") {
                return .failure(.invalidCharacters(domain))
            }
            for char in label {
                if !char.isASCII || (!char.isLetter && !char.isNumber && char != "-") {
                    return .failure(.invalidCharacters(domain))
                }
            }
        }

        // Top-level domain (the rightmost label) cannot be all numeric (RFC 1123 / ICANN)
        if let tld = labels.last, tld.allSatisfy({ $0.isNumber }) {
            return .failure(.ipAddress(domain))
        }

        if isPublicSuffix(domain) {
            return .failure(.publicSuffix(domain))
        }

        return .success(domain)
    }

    /// Built-in fallback rule set containing common TLDs and multi-part suffixes
    /// used when public_suffix_list.dat is missing from the bundle.
    private static let fallbackRules: String = """
    // Minimal built-in fallback PSL
    com
    net
    org
    edu
    gov
    mil
    int
    io
    co.uk
    org.uk
    gov.uk
    me.uk
    ltd.uk
    plc.uk
    com.au
    net.au
    org.au
    edu.au
    gov.au
    co.jp
    ne.jp
    ac.jp
    go.jp
    or.jp
    github.io
    *.ck
    !city.kobe.jp
    *.kobe.jp
    """
}
