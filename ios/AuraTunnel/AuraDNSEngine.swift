import Foundation

/// Pure Swift, clean-room DNS and domain-matching engine for Theja's Aura.
/// Zero GPL dependencies. Compliant with RFC 1035 and RFC 3596 specifications.
public final class AuraDNSEngine {

    public struct Rule: Codable, Equatable {
        public let domain: String
        public let isEnabled: Bool
        public let isBlocked: Bool // true: block, false: allow/whitelist

        public init(domain: String, isEnabled: Bool = true, isBlocked: Bool = true) {
            self.domain = AuraDNSEngine.normalizeDomain(domain)
            self.isEnabled = isEnabled
            self.isBlocked = isBlocked
        }
    }

    public enum MatchResult: Equatable {
        case blocked(matchedRule: String)
        case allowed(matchedRule: String?)
    }

    private var rules: [String: Rule] = [:]
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

    /// Sets or replaces the active rule set. Thread-safe.
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

    /// Evaluates a domain against active rules:
    /// - Policy: Exact domain matches or subdomain matches (e.g. `ads.google.com` matches `google.com`).
    /// - Allowlist Precedence: If an allow rule matches the domain, it takes precedence over block rules.
    public func evaluate(domain: String) -> MatchResult {
        let target = AuraDNSEngine.normalizeDomain(domain)
        if target.isEmpty {
            return .allowed(matchedRule: nil)
        }

        lock.lock()
        let currentRules = self.rules
        lock.unlock()

        let parts = target.split(separator: ".")
        var candidates: [String] = []
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            candidates.append(candidate)
        }

        // 1. Check Allowlist first across all candidates (Allowlist precedence)
        for candidate in candidates {
            if let rule = currentRules[candidate], rule.isEnabled && !rule.isBlocked {
                return .allowed(matchedRule: candidate)
            }
        }

        // 2. Check Blocklist across candidates
        for candidate in candidates {
            if let rule = currentRules[candidate], rule.isEnabled && rule.isBlocked {
                return .blocked(matchedRule: candidate)
            }
        }

        return .allowed(matchedRule: nil)
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

    /// Synthesizes a RFC 1035 compliant DNS response sinkholing blocked queries to 0.0.0.0 (for A) or :: (for AAAA).
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
