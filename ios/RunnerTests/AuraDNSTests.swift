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
}
