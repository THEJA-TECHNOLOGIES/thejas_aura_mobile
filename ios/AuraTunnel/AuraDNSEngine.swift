import Foundation
import os.log

/// Pure Swift, clean-room DNS and domain-matching engine for Theja's Aura.
/// Zero GPL dependencies. Compliant with RFC 1035 and RFC 3596 specifications.
/// Includes Mozilla Public Suffix List (PSL) validation and multi-category attribution.
public final class AuraDNSEngine {

    public struct Rule: Codable, Equatable {
        public let id: String
        public let domain: String
        public let isEnabled: Bool
        public let isBlocked: Bool // true: block, false: allow/whitelist

        enum CodingKeys: String, CodingKey {
            case id, domain, isEnabled, isBlocked
        }

        public init(id: String? = nil, domain: String, isEnabled: Bool = true, isBlocked: Bool = true) {
            let normalized = AuraDNSEngine.normalizeDomain(domain)
            self.id = (id == nil || id?.isEmpty == true) ? normalized : id!
            self.domain = normalized
            self.isEnabled = isEnabled
            self.isBlocked = isBlocked
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawDomain = try container.decode(String.self, forKey: .domain)
            let normalized = AuraDNSEngine.normalizeDomain(rawDomain)
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
    }

    /// Legacy match result for backward-compatible call sites.
    public enum MatchResult: Equatable {
        case blocked(matchedRule: String)
        case allowed(matchedRule: String?)
    }

    /// Structured, deterministic decision for a queried domain.
    public struct MatchDecision: Equatable {
        public let isBlocked: Bool
        public let matchedSource: String // "allowlist", "custom", "default", "none"
        public let matchedRule: String?   // The rule domain that triggered the decision (if any)
        public let matchedCategories: [String] // Sorted array of matching enabled categories
        public let reason: String

        public var legacyMatchResult: MatchResult {
            if isBlocked {
                return .blocked(matchedRule: matchedRule ?? matchedCategories.first ?? "")
            } else {
                return .allowed(matchedRule: matchedRule)
            }
        }

        public static func allowedByAllowlist(rule: String, categories: [String] = []) -> MatchDecision {
            return MatchDecision(
                isBlocked: false,
                matchedSource: "allowlist",
                matchedRule: rule,
                matchedCategories: categories,
                reason: "Allowed by custom allowlist rule: \(rule)"
            )
        }

        public static func allowedDefault(domain: String, categories: [String] = []) -> MatchDecision {
            return MatchDecision(
                isBlocked: false,
                matchedSource: "none",
                matchedRule: nil,
                matchedCategories: categories,
                reason: "Permitted domain"
            )
        }

        public static func blockedByCustom(rule: String, categories: [String] = []) -> MatchDecision {
            let catStr = categories.isEmpty ? "" : " (also matches: \(categories.joined(separator: ", ")))"
            return MatchDecision(
                isBlocked: true,
                matchedSource: "custom",
                matchedRule: rule,
                matchedCategories: categories,
                reason: "Blocked by custom rule: \(rule)\(catStr)"
            )
        }

        public static func blockedByDefault(categories: [String], matchedDomain: String) -> MatchDecision {
            return MatchDecision(
                isBlocked: true,
                matchedSource: "default",
                matchedRule: matchedDomain,
                matchedCategories: categories,
                reason: "Blocked by \(categories.joined(separator: ", "))"
            )
        }

        public static func == (lhs: MatchDecision, rhs: MatchResult) -> Bool {
            return lhs.legacyMatchResult == rhs
        }

        public static func == (lhs: MatchResult, rhs: MatchDecision) -> Bool {
            return lhs == rhs.legacyMatchResult
        }
    }

    private var rules: [String: Rule] = [:]
    private var compactIndex: AuraCompactCategoryIndex? = nil
    private var legacyCategories: [String: Set<String>] = [:]
    private var categoryPreferences: [String: Bool] = [:]
    private var disabledDefaultDomains: Set<String> = []
    private let lock = NSLock()

    public init() {}

    // MARK: - Domain Normalization & Rule Management

    /// Normalizes a domain name: lowercase, strips schemes, paths, port numbers, and trailing dots.
    public static func normalizeDomain(_ raw: String) -> String {
        var domain = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Strip scheme if present
        if let schemeRange = domain.range(of: "://") {
            domain = String(domain[schemeRange.upperBound...])
        }

        // Strip path or query
        if let slashIndex = domain.firstIndex(of: "/") {
            domain = String(domain[..<slashIndex])
        }

        // Strip port if present
        if let colonIndex = domain.firstIndex(of: ":") {
            domain = String(domain[..<colonIndex])
        }

        // Strip trailing dots
        while domain.hasSuffix(".") {
            domain.removeLast()
        }

        return domain
    }

    /// Sets or replaces the active custom rule set. Thread-safe.
    public func setRules(_ newRules: [Rule]) {
        lock.lock()
        defer { lock.unlock() }
        rules.removeAll(keepingCapacity: true)
        for rule in newRules {
            let normalized = rule.domain
            if !normalized.isEmpty {
                rules[normalized] = rule
            }
        }
    }

    /// Sets or replaces default category domain compact index. Thread-safe.
    public func setCompactIndex(_ newIndex: AuraCompactCategoryIndex?) {
        lock.lock()
        defer { lock.unlock() }
        compactIndex = newIndex
    }

    /// Sets or replaces default category domain lists (e.g. "Ads", "Trackers", "Analytics"). Thread-safe.
    public func setCategories(_ newCategories: [String: Set<String>]) {
        lock.lock()
        defer { lock.unlock() }
        legacyCategories = newCategories
        if newCategories.isEmpty {
            compactIndex = nil
        } else {
            compactIndex = AuraCompactCategoryIndex(from: newCategories)
        }
    }

    /// Sets or replaces category enable/disable preferences. Thread-safe.
    public func setCategoryPreferences(_ prefs: [String: Bool]) {
        lock.lock()
        defer { lock.unlock() }
        categoryPreferences = prefs
    }

    /// Sets or replaces disabled default domains. Thread-safe.
    public func setDisabledDefaultDomains(_ domains: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        disabledDefaultDomains = domains
    }

    // MARK: - Candidate Suffix Generation with PSL Guard

    /// Generates candidate domain suffixes for matching against rules (e.g. "ads.google.com" -> ["ads.google.com", "google.com"]).
    /// Enforces:
    /// 1. Strict label boundaries (whole '.' separated labels only).
    /// 2. PSL Guard: Excludes candidate suffixes that are bare Public Suffixes (e.g. "com", "co.uk", "gov.au").
    public static func generateCandidateSuffixes(
        for domain: String,
        pslValidator: AuraPSLValidator = .shared
    ) -> [String] {
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty else { return [] }

        let parts = normalized.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return [] }

        var candidates: [String] = []
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            // Exclude bare public suffixes from rule candidate evaluation
            if !pslValidator.isPublicSuffix(candidate) {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    // MARK: - Deterministic Domain Evaluation & Rule Precedence

    /// Evaluates a domain against custom rules and default blocklist categories.
    ///
    /// Semantics:
    /// 1. An applicable enabled custom allow rule takes precedence over ALL blocking rules.
    /// 2. Otherwise, a matching enabled custom block rule blocks the query.
    /// 3. Otherwise, any matching enabled default category blocks the query.
    /// 4. If multiple enabled default categories match, all matching categories are recorded deterministically.
    /// 5. Disabling one category does not unblock a domain still matched by another enabled category or custom block rule.
    /// 6. A child allow rule (e.g. "mail.google.com") permits itself and its subdomains, but does NOT allow parent or sibling domains.
    private func isCategoryEnabled(catName: String, prefs: [String: Bool]) -> Bool {
        if let exact = prefs[catName] { return exact }
        let normTarget = catName.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        for (key, value) in prefs {
            let normKey = key.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            if normKey == normTarget {
                return value
            }
        }
        return true
    }

    public func evaluate(domain: String) -> MatchDecision {
        let target = AuraDNSEngine.normalizeDomain(domain)
        guard !target.isEmpty else {
            return .allowedDefault(domain: "")
        }

        lock.lock()
        let currentRules = self.rules
        let currentCompactIndex = self.compactIndex
        let currentLegacyCategories = self.legacyCategories
        let currentPrefs = self.categoryPreferences
        let currentDisabledDefaultDomains = self.disabledDefaultDomains
        lock.unlock()

        let candidates = AuraDNSEngine.generateCandidateSuffixes(for: target)
        guard !candidates.isEmpty else {
            return .allowedDefault(domain: target)
        }

        // 1. Check Custom Allowlist first (highest precedence across all candidates)
        var matchedAllowRule: String? = nil
        for candidate in candidates {
            if let rule = currentRules[candidate], rule.isEnabled && !rule.isBlocked {
                matchedAllowRule = candidate
                break
            }
        }

        // 2. Check Custom Blocklist across candidates
        var matchedCustomBlock: String? = nil
        for candidate in candidates {
            if let rule = currentRules[candidate], rule.isEnabled && rule.isBlocked {
                matchedCustomBlock = candidate
                break
            }
        }

        // Check matching categories across all candidates
        var matchingEnabledCategories = Set<String>()
        var allMatchingCategories = Set<String>()
        var firstCategoryMatchedDomain: String? = nil

        if let index = currentCompactIndex, index.count > 0 {
            for candidate in candidates {
                let h = AuraCompactCategoryIndex.fnv1a64(candidate)
                if let mask = index.matchingCategoryMask(for: h) {
                    let catNames = index.categories(for: mask)
                    for catName in catNames {
                        allMatchingCategories.insert(catName)
                        let isEnabled = isCategoryEnabled(catName: catName, prefs: currentPrefs)
                        if isEnabled && !currentDisabledDefaultDomains.contains(candidate) {
                            matchingEnabledCategories.insert(catName)
                            if firstCategoryMatchedDomain == nil {
                                firstCategoryMatchedDomain = candidate
                            }
                        }
                    }
                }
            }
        } else if !currentLegacyCategories.isEmpty {
            for (catName, domainSet) in currentLegacyCategories {
                let isEnabled = isCategoryEnabled(catName: catName, prefs: currentPrefs)
                for candidate in candidates {
                    if domainSet.contains(candidate) {
                        allMatchingCategories.insert(catName)
                        if isEnabled && !currentDisabledDefaultDomains.contains(candidate) {
                            matchingEnabledCategories.insert(catName)
                            if firstCategoryMatchedDomain == nil {
                                firstCategoryMatchedDomain = candidate
                            }
                        }
                        break
                    }
                }
            }
        }

        let sortedEnabledCategories = matchingEnabledCategories.sorted()
        let sortedAllCategories = allMatchingCategories.sorted()
        let recordCategories = !sortedEnabledCategories.isEmpty ? sortedEnabledCategories : sortedAllCategories

        if let allowRule = matchedAllowRule {
            return .allowedByAllowlist(rule: allowRule, categories: recordCategories)
        }

        // If custom block matched:
        if let customRule = matchedCustomBlock {
            return .blockedByCustom(rule: customRule, categories: recordCategories)
        }

        // 3. Check Default Categories (if any enabled category matched)
        if !sortedEnabledCategories.isEmpty {
            let matchedDomain = firstCategoryMatchedDomain ?? target
            return .blockedByDefault(categories: sortedEnabledCategories, matchedDomain: matchedDomain)
        }

        // 4. Default Allow
        return .allowedDefault(domain: target, categories: recordCategories)
    }

    /// Legacy evaluation method for callers expecting MatchResult.
    public func evaluateLegacy(domain: String) -> MatchResult {
        return evaluate(domain: domain).legacyMatchResult
    }

    // MARK: - DNS Packet Parsing & Synthesis

    public struct DNSHeader {
        public let id: UInt16
        public let flags: UInt16
        public let qdCount: UInt16
        public let anCount: UInt16
        public let nsCount: UInt16
        public let arCount: UInt16
    }

    public struct DNSQuestion {
        public let name: String
        public let qType: UInt16
        public let qClass: UInt16
        public let rawLength: Int
    }

    /// Safely parses DNS Header with bounds checking.
    public static func parseHeader(data: Data) -> DNSHeader? {
        guard data.count >= 12 else { return nil }
        let id = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let flags = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let qdCount = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let anCount = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let nsCount = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let arCount = data.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }

        return DNSHeader(id: id, flags: flags, qdCount: qdCount, anCount: anCount, nsCount: nsCount, arCount: arCount)
    }

    /// Safely parses the first Question section in a DNS packet with bounds checking.
    public static func parseQuestion(data: Data, offset: Int = 12) -> DNSQuestion? {
        guard data.count > offset else { return nil }
        var current = offset
        var domainParts: [String] = []

        while current < data.count {
            let length = Int(data[current])
            if length == 0 {
                current += 1
                break
            }

            if (length & 0xC0) == 0xC0 {
                current += 2
                break
            }

            current += 1
            guard current + length <= data.count else { return nil }
            guard let label = String(data: data.subdata(in: current..<(current + length)), encoding: .utf8) ??
                              String(data: data.subdata(in: current..<(current + length)), encoding: .ascii) else {
                return nil
            }
            domainParts.append(label)
            current += length
        }

        guard current + 4 <= data.count else { return nil }
        let qType = data.subdata(in: current..<(current + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let qClass = data.subdata(in: (current + 2)..<(current + 4)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }

        let fullDomain = domainParts.joined(separator: ".")
        return DNSQuestion(name: fullDomain, qType: qType, qClass: qClass, rawLength: (current + 4) - offset)
    }

    /// Synthesizes an RFC 1035 compliant DNS response sinkholing blocked queries to 0.0.0.0 (for A) or :: (for AAAA).
    public static func synthesizeBlockedResponse(requestData: Data) -> Data? {
        guard let header = parseHeader(data: requestData), header.qdCount > 0 else { return nil }
        guard let question = parseQuestion(data: requestData, offset: 12) else { return nil }

        var response = Data()

        // 1. Header (12 bytes)
        var idBig = header.id.bigEndian
        response.append(Data(bytes: &idBig, count: 2))

        // Flags: Standard response, No error (0x8180)
        var flagsBig: UInt16 = UInt16(0x8180).bigEndian
        response.append(Data(bytes: &flagsBig, count: 2))

        // QDCOUNT: 1
        var qdCountBig: UInt16 = UInt16(1).bigEndian
        response.append(Data(bytes: &qdCountBig, count: 2))

        // ANCOUNT: 1
        var anCountBig: UInt16 = UInt16(1).bigEndian
        response.append(Data(bytes: &anCountBig, count: 2))

        // NSCOUNT: 0, ARCOUNT: 0
        var zeroCount: UInt16 = 0
        response.append(Data(bytes: &zeroCount, count: 2))
        response.append(Data(bytes: &zeroCount, count: 2))

        // 2. Question section (copied verbatim from request)
        let questionData = requestData.subdata(in: 12..<(12 + question.rawLength))
        response.append(questionData)

        // 3. Answer Section
        // Name pointer back to question name (0xC00C = offset 12)
        var pointer: UInt16 = UInt16(0xC00C).bigEndian
        response.append(Data(bytes: &pointer, count: 2))

        // TYPE (A = 1, AAAA = 28)
        var typeBig = question.qType.bigEndian
        response.append(Data(bytes: &typeBig, count: 2))

        // CLASS (IN = 1)
        var classBig: UInt16 = UInt16(1).bigEndian
        response.append(Data(bytes: &classBig, count: 2))

        // TTL (300 seconds)
        var ttlBig: UInt32 = UInt32(300).bigEndian
        response.append(Data(bytes: &ttlBig, count: 4))

        if question.qType == 28 {
            // AAAA: 16 bytes of 0x00 (::)
            var rdLengthBig: UInt16 = UInt16(16).bigEndian
            response.append(Data(bytes: &rdLengthBig, count: 2))
            response.append(Data(repeating: 0, count: 16))
        } else {
            // Default A: 4 bytes of 0x00 (0.0.0.0)
            var rdLengthBig: UInt16 = UInt16(4).bigEndian
            response.append(Data(bytes: &rdLengthBig, count: 2))
            response.append(Data(repeating: 0, count: 4))
        }

        return response
    }

    /// Synthesizes a SERVFAIL (RCODE 2) DNS response for upstream timeout/unreachable states.
    public static func synthesizeServFailResponse(requestData: Data) -> Data? {
        guard let header = parseHeader(data: requestData) else { return nil }
        var response = Data()

        var idBig = header.id.bigEndian
        response.append(Data(bytes: &idBig, count: 2))

        // Flags: Response, ServFail (0x8182)
        var flagsBig: UInt16 = UInt16(0x8182).bigEndian
        response.append(Data(bytes: &flagsBig, count: 2))

        // QDCOUNT: preserved if valid, otherwise 0
        var qdCountBig: UInt16 = header.qdCount.bigEndian
        response.append(Data(bytes: &qdCountBig, count: 2))

        var zeroCount: UInt16 = 0
        response.append(Data(bytes: &zeroCount, count: 2)) // ANCOUNT: 0
        response.append(Data(bytes: &zeroCount, count: 2)) // NSCOUNT: 0
        response.append(Data(bytes: &zeroCount, count: 2)) // ARCOUNT: 0

        if header.qdCount > 0, let question = parseQuestion(data: requestData, offset: 12) {
            response.append(requestData.subdata(in: 12..<(12 + question.rawLength)))
        }

        return response
    }
}
