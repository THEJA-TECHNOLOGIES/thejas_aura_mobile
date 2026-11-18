import XCTest
@testable import Runner

final class AuraDNSTests: XCTestCase {

    var engine: AuraDNSEngine!

    override func setUp() {
        super.setUp()
        engine = AuraDNSEngine()
    }

    // MARK: - Normalization Tests

    func testDomainNormalization() {
        XCTAssertEqual(AuraDNSEngine.normalizeDomain("  Google.COM  "), "google.com")
        XCTAssertEqual(AuraDNSEngine.normalizeDomain("https://ads.tracker.com/api?v=1"), "ads.tracker.com")
        XCTAssertEqual(AuraDNSEngine.normalizeDomain("http://example.com:8080/"), "example.com")
        XCTAssertEqual(AuraDNSEngine.normalizeDomain("tracker.net."), "tracker.net")
    }

    // MARK: - Matching Policy Tests

    func testExactAndSubdomainMatching() {
        let rules = [
            AuraDNSEngine.Rule(domain: "google.com", isEnabled: true, isBlocked: true),
            AuraDNSEngine.Rule(domain: "telemetry.apple.com", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        // Exact match
        XCTAssertEqual(engine.evaluate(domain: "google.com"), .blocked(matchedRule: "google.com"))

        // Subdomain matches parent domain rule
        XCTAssertEqual(engine.evaluate(domain: "ads.google.com"), .blocked(matchedRule: "google.com"))
        XCTAssertEqual(engine.evaluate(domain: "deep.sub.ads.google.com"), .blocked(matchedRule: "google.com"))

        // Unrelated domain does NOT match
        XCTAssertEqual(engine.evaluate(domain: "apple.com"), .allowed(matchedRule: nil))
        XCTAssertEqual(engine.evaluate(domain: "notgoogle.com"), .allowed(matchedRule: nil))
        XCTAssertEqual(engine.evaluate(domain: "google.com.other.org"), .allowed(matchedRule: nil))

        // Specific subdomain rule
        XCTAssertEqual(engine.evaluate(domain: "telemetry.apple.com"), .blocked(matchedRule: "telemetry.apple.com"))
        XCTAssertEqual(engine.evaluate(domain: "sub.telemetry.apple.com"), .blocked(matchedRule: "telemetry.apple.com"))
        XCTAssertEqual(engine.evaluate(domain: "developer.apple.com"), .allowed(matchedRule: nil))
    }

    func testDisabledRuleIsIgnored() {
        let rules = [
            AuraDNSEngine.Rule(domain: "google.com", isEnabled: false, isBlocked: true)
        ]
        engine.setRules(rules)

        XCTAssertEqual(engine.evaluate(domain: "google.com"), .allowed(matchedRule: nil))
        XCTAssertEqual(engine.evaluate(domain: "ads.google.com"), .allowed(matchedRule: nil))
    }

    func testAllowlistPrecedenceOverBlocklist() {
        let rules = [
            AuraDNSEngine.Rule(domain: "google.com", isEnabled: true, isBlocked: true),
            AuraDNSEngine.Rule(domain: "mail.google.com", isEnabled: true, isBlocked: false) // Allowed
        ]
        engine.setRules(rules)

        // General domain is blocked
        XCTAssertEqual(engine.evaluate(domain: "google.com"), .blocked(matchedRule: "google.com"))
        XCTAssertEqual(engine.evaluate(domain: "ads.google.com"), .blocked(matchedRule: "google.com"))

        // Specific subdomain is allowed via allowlist precedence
        XCTAssertEqual(engine.evaluate(domain: "mail.google.com"), .allowed(matchedRule: "mail.google.com"))
        XCTAssertEqual(engine.evaluate(domain: "sub.mail.google.com"), .allowed(matchedRule: "mail.google.com"))
    }

    func testCategoryAttribution_AllowlistPreservesMatchedCategories() {
        let rules = [
            AuraDNSEngine.Rule(domain: "doubleclick.net", isEnabled: true, isBlocked: false)
        ]
        engine.setRules(rules)
        engine.setCategories([
            "Ads": ["doubleclick.net"],
            "Trackers": ["doubleclick.net"]
        ])
        engine.setCategoryPreferences(["Ads": true, "Trackers": true])

        let decision = engine.evaluate(domain: "ad.doubleclick.net")
        XCTAssertFalse(decision.isBlocked)
        XCTAssertEqual(decision.matchedSource, "allowlist")
        XCTAssertEqual(decision.matchedRule, "doubleclick.net")
        XCTAssertEqual(decision.matchedCategories, ["Ads", "Trackers"])
    }

    func testCategoryAttribution_CaseInsensitivePreferences() {
        engine.setRules([])
        engine.setCategories([
            "Ads": ["adservice.google.com"],
            "Crypto_mining": ["crypto.miner.org"]
        ])
        engine.setCategoryPreferences([
            "ADS": true,
            "Crypto Mining": true
        ])

        let adDecision = engine.evaluate(domain: "adservice.google.com")
        XCTAssertTrue(adDecision.isBlocked)
        XCTAssertEqual(adDecision.matchedSource, "default")
        XCTAssertEqual(adDecision.matchedCategories, ["Ads"])

        let cryptoDecision = engine.evaluate(domain: "crypto.miner.org")
        XCTAssertTrue(cryptoDecision.isBlocked)
        XCTAssertEqual(cryptoDecision.matchedSource, "default")
        XCTAssertEqual(cryptoDecision.matchedCategories, ["Crypto_mining"])
    }

    func testCategoryAttribution_DisabledCategoryPreservesMatchedCategories() {
        engine.setRules([])
        engine.setCategories([
            "Ads": ["doubleclick.net"]
        ])
        engine.setCategoryPreferences(["Ads": false])

        let decision = engine.evaluate(domain: "doubleclick.net")
        XCTAssertFalse(decision.isBlocked)
        XCTAssertEqual(decision.matchedSource, "none")
        XCTAssertEqual(decision.matchedCategories, ["Ads"])
    }

    func testCategoryAttribution_CustomBlockPreservesMatchedCategories() {
        let rules = [
            AuraDNSEngine.Rule(domain: "doubleclick.net", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)
        engine.setCategories([
            "Ads": ["doubleclick.net"]
        ])
        engine.setCategoryPreferences(["Ads": true])

        let decision = engine.evaluate(domain: "doubleclick.net")
        XCTAssertTrue(decision.isBlocked)
        XCTAssertEqual(decision.matchedSource, "custom")
        XCTAssertEqual(decision.matchedRule, "doubleclick.net")
        XCTAssertEqual(decision.matchedCategories, ["Ads"])
    }

    // MARK: - DNS Packet Parsing & Synthesis Tests

    func testDNSHeaderParsing() {
        // Construct valid raw DNS query packet (12 bytes header + question "example.com")
        var data = Data()
        var id: UInt16 = 0x1234.bigEndian
        data.append(Data(bytes: &id, count: 2))
        var flags: UInt16 = 0x0100.bigEndian // Standard query, RD=1
        data.append(Data(bytes: &flags, count: 2))
        var qdCount: UInt16 = 1.bigEndian
        data.append(Data(bytes: &qdCount, count: 2))
        var zero: UInt16 = 0
        data.append(Data(bytes: &zero, count: 2)) // ANCOUNT
        data.append(Data(bytes: &zero, count: 2)) // NSCOUNT
        data.append(Data(bytes: &zero, count: 2)) // ARCOUNT

        let header = AuraDNSEngine.parseHeader(data: data)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.id, 0x1234)
        XCTAssertEqual(header?.flags, 0x0100)
        XCTAssertEqual(header?.qdCount, 1)
        XCTAssertEqual(header?.anCount, 0)
    }

    func testMalformedPacketHandledSafely() {
        // Less than 12 bytes
        let shortData = Data([0x01, 0x02, 0x03])
        XCTAssertNil(AuraDNSEngine.parseHeader(data: shortData))
        XCTAssertNil(AuraDNSEngine.parseQuestion(data: shortData))
        XCTAssertNil(AuraDNSEngine.synthesizeBlockedResponse(requestData: shortData))
    }

    func testSyntheticBlockedResponseGeneration() {
        // Build query for "google.com", QTYPE=A (1), QCLASS=IN (1)
        var query = Data()
        var id: UInt16 = 0xABCD.bigEndian
        query.append(Data(bytes: &id, count: 2))
        var flags: UInt16 = 0x0100.bigEndian
        query.append(Data(bytes: &flags, count: 2))
        var qdCount: UInt16 = 1.bigEndian
        query.append(Data(bytes: &qdCount, count: 2))
        var zero: UInt16 = 0
        query.append(Data(bytes: &zero, count: 2))
        query.append(Data(bytes: &zero, count: 2))
        query.append(Data(bytes: &zero, count: 2))

        // Question: 6 "google" 3 "com" 0
        query.append(6)
        query.append("google".data(using: .ascii)!)
        query.append(3)
        query.append("com".data(using: .ascii)!)
        query.append(0)

        // QTYPE = 1 (A), QCLASS = 1 (IN)
        var qtype: UInt16 = 1.bigEndian
        query.append(Data(bytes: &qtype, count: 2))
        var qclass: UInt16 = 1.bigEndian
        query.append(Data(bytes: &qclass, count: 2))

        let question = AuraDNSEngine.parseQuestion(data: query)
        XCTAssertEqual(question?.name, "google.com")
        XCTAssertEqual(question?.qType, 1)

        guard let response = AuraDNSEngine.synthesizeBlockedResponse(requestData: query) else {
            XCTFail("Failed to synthesize response")
            return
        }

        // Validate response preserves transaction ID
        let respHeader = AuraDNSEngine.parseHeader(data: response)
        XCTAssertEqual(respHeader?.id, 0xABCD)
        XCTAssertEqual(respHeader?.flags, 0x8180) // QR=1, RCODE=0
        XCTAssertEqual(respHeader?.qdCount, 1)
        XCTAssertEqual(respHeader?.anCount, 1)

        // Check Answer: last 4 bytes must be 0.0.0.0
        let ipBytes = response.suffix(4)
        XCTAssertEqual(Array(ipBytes), [0, 0, 0, 0])
    }

    // MARK: - M8: DNS Rebinding Protection Tests

    func testPrivateIpv4Detection() {
        // Private ranges
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 10, b1: 0, b2: 0, b3: 1))        // 10.0.0.0/8
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 172, b1: 16, b2: 0, b3: 1))      // 172.16.0.0/12
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 172, b1: 31, b2: 255, b3: 255))  // 172.31.255.255
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 192, b1: 168, b2: 0, b3: 1))     // 192.168.0.0/16
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 127, b1: 0, b2: 0, b3: 1))       // 127.0.0.0/8
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 169, b1: 254, b2: 0, b3: 1))     // 169.254.0.0/16
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 224, b1: 0, b2: 0, b3: 1))       // 224.0.0.0/4
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv4(b0: 239, b1: 255, b2: 255, b3: 255)) // 239.255.255.255

        // Public IPs
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv4(b0: 9, b1: 9, b2: 9, b3: 9))        // Quad9
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv4(b0: 1, b1: 1, b2: 1, b3: 1))        // Cloudflare
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv4(b0: 8, b1: 8, b2: 8, b3: 8))        // Google
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv4(b0: 172, b1: 15, b2: 255, b3: 255)) // Just outside 172.16/12
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv4(b0: 172, b1: 32, b2: 0, b3: 0))     // Just outside 172.16/12
    }

    func testPrivateIpv6Detection() {
        // Loopback ::1
        var loopback = [UInt8](repeating: 0, count: 15); loopback[15] = 1
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(loopback))

        // Unique local fc00::/7
        var ula = [UInt8](repeating: 0, count: 16); ula[0] = 0xFC
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(ula))
        ula[0] = 0xFD
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(ula))

        // Link-local fe80::/10
        var linkLocal = [UInt8](repeating: 0, count: 16); linkLocal[0] = 0xFE; linkLocal[1] = 0x80
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(linkLocal))

        // Multicast ff00::/8
        var multicast = [UInt8](repeating: 0, count: 16); multicast[0] = 0xFF
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(multicast))

        // IPv4-mapped private ::ffff:10.0.0.1
        var mapped = [UInt8](repeating: 0, count: 12); mapped.append(0xFF); mapped.append(contentsOf: [10, 0, 0, 1])
        XCTAssertTrue(AuraDNSEngine.isPrivateIpv6(mapped))

        // Public IPv6 (2001:db8:: - documentation range)
        var publicIpv6 = [UInt8](repeating: 0, count: 16); publicIpv6[0] = 0x20; publicIpv6[1] = 0x01
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv6(publicIpv6))

        // Invalid length
        XCTAssertFalse(AuraDNSEngine.isPrivateIpv6([1, 2, 3]))
    }

    func testHasPrivateIpAnswers() {
        // Build a response with an A record pointing to 10.0.0.1 (private)
        var response = Data()
        var id: UInt16 = 0x1234.bigEndian; response.append(Data(bytes: &id, count: 2))
        var flags: UInt16 = 0x8180.bigEndian; response.append(Data(bytes: &flags, count: 2))
        var qdCount: UInt16 = 1.bigEndian; response.append(Data(bytes: &qdCount, count: 2))
        var anCount: UInt16 = 1.bigEndian; response.append(Data(bytes: &anCount, count: 2))
        var zero: UInt16 = 0; response.append(Data(bytes: &zero, count: 2))
        response.append(Data(bytes: &zero, count: 2))

        // Question: example.com, type A, class IN
        response.append(7); response.append("example".data(using: .ascii)!)
        response.append(3); response.append("com".data(using: .ascii)!)
        response.append(0)
        var qtype: UInt16 = 1.bigEndian; response.append(Data(bytes: &qtype, count: 2))
        var qclass: UInt16 = 1.bigEndian; response.append(Data(bytes: &qclass, count: 2))

        // Answer: name pointer, type A, class IN, TTL, rdlength=4, rdata=10.0.0.1
        response.append(0xC0); response.append(0x0C) // Name pointer to offset 12
        var aType: UInt16 = 1.bigEndian; response.append(Data(bytes: &aType, count: 2))
        var aClass: UInt16 = 1.bigEndian; response.append(Data(bytes: &aClass, count: 2))
        var ttl: UInt32 = 300.bigEndian; response.append(Data(bytes: &ttl, count: 4))
        var rdLen: UInt16 = 4.bigEndian; response.append(Data(bytes: &rdLen, count: 2))
        response.append(contentsOf: [10, 0, 0, 1])

        XCTAssertTrue(AuraDNSEngine.hasPrivateIpAnswers(response))

        // Build a response with an A record pointing to 9.9.9.9 (public)
        var publicResponse = Data()
        var pid: UInt16 = 0x1234.bigEndian; publicResponse.append(Data(bytes: &pid, count: 2))
        var pflags: UInt16 = 0x8180.bigEndian; publicResponse.append(Data(bytes: &pflags, count: 2))
        var pqdCount: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &pqdCount, count: 2))
        var panCount: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &panCount, count: 2))
        publicResponse.append(Data(bytes: &zero, count: 2))
        publicResponse.append(Data(bytes: &zero, count: 2))

        publicResponse.append(7); publicResponse.append("example".data(using: .ascii)!)
        publicResponse.append(3); publicResponse.append("com".data(using: .ascii)!)
        publicResponse.append(0)
        var pqtype: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &pqtype, count: 2))
        var pqclass: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &pqclass, count: 2))

        publicResponse.append(0xC0); publicResponse.append(0x0C)
        var paType: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &paType, count: 2))
        var paClass: UInt16 = 1.bigEndian; publicResponse.append(Data(bytes: &paClass, count: 2))
        var pttl: UInt32 = 300.bigEndian; publicResponse.append(Data(bytes: &pttl, count: 4))
        var prdLen: UInt16 = 4.bigEndian; publicResponse.append(Data(bytes: &prdLen, count: 2))
        publicResponse.append(contentsOf: [9, 9, 9, 9])

        XCTAssertFalse(AuraDNSEngine.hasPrivateIpAnswers(publicResponse))

        // Empty response should not have private IPs
        XCTAssertFalse(AuraDNSEngine.hasPrivateIpAnswers(Data()))
    }

    func testQuestionsMatch() {
        // Build a query for example.com, type A
        var query = Data()
        var qid: UInt16 = 0x1234.bigEndian; query.append(Data(bytes: &qid, count: 2))
        var qflags: UInt16 = 0x0100.bigEndian; query.append(Data(bytes: &qflags, count: 2))
        var qqdCount: UInt16 = 1.bigEndian; query.append(Data(bytes: &qqdCount, count: 2))
        query.append(Data(bytes: &zero, count: 2))
        query.append(Data(bytes: &zero, count: 2))
        query.append(Data(bytes: &zero, count: 2))
        query.append(7); query.append("example".data(using: .ascii)!)
        query.append(3); query.append("com".data(using: .ascii)!)
        query.append(0)
        var qqtype: UInt16 = 1.bigEndian; query.append(Data(bytes: &qqtype, count: 2))
        var qqclass: UInt16 = 1.bigEndian; query.append(Data(bytes: &qqclass, count: 2))

        // Matching response (same question section)
        var matchingResponse = query
        matchingResponse[2] = 0x81 // QR=1
        matchingResponse[3] = 0x80 // RA, NoError

        XCTAssertTrue(AuraDNSEngine.questionsMatch(query: query, response: matchingResponse))

        // Non-matching response (different domain)
        var differentQuery = Data()
        var did: UInt16 = 0x5678.bigEndian; differentQuery.append(Data(bytes: &did, count: 2))
        var dflags: UInt16 = 0x0100.bigEndian; differentQuery.append(Data(bytes: &dflags, count: 2))
        var dqdCount: UInt16 = 1.bigEndian; differentQuery.append(Data(bytes: &dqdCount, count: 2))
        differentQuery.append(Data(bytes: &zero, count: 2))
        differentQuery.append(Data(bytes: &zero, count: 2))
        differentQuery.append(Data(bytes: &zero, count: 2))
        differentQuery.append(3); differentQuery.append("evil".data(using: .ascii)!)
        differentQuery.append(3); differentQuery.append("com".data(using: .ascii)!)
        differentQuery.append(0)
        var dqtype: UInt16 = 1.bigEndian; differentQuery.append(Data(bytes: &dqtype, count: 2))
        var dqclass: UInt16 = 1.bigEndian; differentQuery.append(Data(bytes: &dqclass, count: 2))

        XCTAssertFalse(AuraDNSEngine.questionsMatch(query: query, response: differentQuery))
    }

    func testCompressionPointerLoopGuard() {
        // Build a packet with a cyclic compression pointer
        // Offset 12: pointer to offset 10 (before itself) - creates a cycle
        var cyclicData = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                               0x00, 0x00, 0x00, 0x00]) // 12 bytes header
        cyclicData.append(0xC0) // Compression pointer first byte
        cyclicData.append(0x0A) // Points to offset 10 (inside header, creates cycle)

        // parseDnsName starting at offset 12 should detect the cycle and return nil
        let result = AuraDNSEngine.parseDnsName(data: cyclicData, current: 12)
        XCTAssertNil(result)
    }
}
