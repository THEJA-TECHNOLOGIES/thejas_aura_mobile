import XCTest
@testable import Runner

final class AuraTCPDNSTests: XCTestCase {

    private func buildDnsQuery(id: UInt16, domain: String, qtype: UInt16 = 1) -> Data {
        var data = Data()
        var idBig = id.bigEndian
        data.append(Data(bytes: &idBig, count: 2))
        var flags: UInt16 = UInt16(0x0100).bigEndian // RD = 1
        data.append(Data(bytes: &flags, count: 2))
        var qdCount: UInt16 = UInt16(1).bigEndian
        data.append(Data(bytes: &qdCount, count: 2))
        var zero: UInt16 = 0
        data.append(Data(bytes: &zero, count: 2)) // ANCOUNT
        data.append(Data(bytes: &zero, count: 2)) // NSCOUNT
        data.append(Data(bytes: &zero, count: 2)) // ARCOUNT

        for part in domain.split(separator: ".") {
            let bytes = Array(part.utf8)
            data.append(UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        data.append(0) // Root null label

        var qtypeBig = qtype.bigEndian
        data.append(Data(bytes: &qtypeBig, count: 2))
        var qclassBig: UInt16 = UInt16(1).bigEndian // IN class
        data.append(Data(bytes: &qclassBig, count: 2))

        return data
    }

    private func frameDnsMessage(_ msg: Data) -> Data {
        var framed = Data()
        var lenBig = UInt16(msg.count).bigEndian
        framed.append(Data(bytes: &lenBig, count: 2))
        framed.append(msg)
        return framed
    }

    private func connectTcpClient(port: UInt16) -> Int32? {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }

        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard res == 0 else {
            Darwin.close(sock)
            return nil
        }
        return sock
    }

    private func sendAll(sock: Int32, data: Data) -> Bool {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress?.advanced(by: sent) else { return -1 }
                return send(sock, base, data.count - sent, 0)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    private func readFramedDnsMessage(sock: Int32) -> Data? {
        var lenBuf = [UInt8](repeating: 0, count: 2)
        var lenRead = 0
        while lenRead < 2 {
            let n = lenBuf.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.baseAddress?.advanced(by: lenRead) else { return -1 }
                return recv(sock, base, 2 - lenRead, 0)
            }
            if n <= 0 { return nil }
            lenRead += n
        }
        let length = Int(UInt16(lenBuf[0]) << 8 | UInt16(lenBuf[1]))
        guard length >= 12 && length <= 16384 else { return nil }

        var msgBuf = [UInt8](repeating: 0, count: length)
        var msgRead = 0
        while msgRead < length {
            let n = msgBuf.withUnsafeMutableBytes { ptr -> Int in
                guard let base = ptr.baseAddress?.advanced(by: msgRead) else { return -1 }
                return recv(sock, base, length - msgRead, 0)
            }
            if n <= 0 { return nil }
            msgRead += n
        }
        return Data(msgBuf)
    }

    // MARK: - Tests

    func testTcpListenerBindsAndAcceptsConnection() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54101
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect to TCP DNS listener on port \(port)")
            resolver.stop()
            return
        }

        // Allow event loop to process accept
        let exp = expectation(description: "Client accepted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(resolver.pendingTcpClientCount, 1)
            Darwin.close(sock)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // Allow event loop to process disconnect
        let exp2 = expectation(description: "Client disconnected")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(resolver.pendingTcpClientCount, 0)
            resolver.stop()
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 2.0)
    }

    func testTcpDnsQueryBlockedDomainReturnsSynthesizedResponse() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "ads.eviltracker.com", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54102
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        let query = buildDnsQuery(id: 0x4321, domain: "ads.eviltracker.com", qtype: 1)
        let framedQuery = frameDnsMessage(query)
        XCTAssertTrue(sendAll(sock: sock, data: framedQuery))

        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read framed DNS response")
            return
        }

        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.id, 0x4321)
        XCTAssertEqual(header?.flags, 0x8180) // QR=1, RCODE=0 (NOERROR)
        XCTAssertEqual(header?.qdCount, 1)
        XCTAssertEqual(header?.anCount, 1)

        // Blocked response returns 0.0.0.0
        let ipBytes = response.suffix(4)
        XCTAssertEqual(Array(ipBytes), [0, 0, 0, 0])
    }

    func testTcpDnsQueryAllowedDomainResolvesUpstream() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54103
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        let query = buildDnsQuery(id: 0x9876, domain: "one.one.one.one", qtype: 1)
        let framedQuery = frameDnsMessage(query)
        XCTAssertTrue(sendAll(sock: sock, data: framedQuery))

        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read framed DNS response from upstream")
            return
        }

        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.id, 0x9876)
        XCTAssertEqual((header?.flags ?? 0) & 0x8000, 0x8000) // QR=1 (Response)
        XCTAssertEqual(header?.qdCount, 1)
        XCTAssertGreaterThanOrEqual(header?.anCount ?? 0, 1)
    }

    func testTcpDnsPipelinedQueriesOnSingleConnection() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "block1.com", isEnabled: true, isBlocked: true),
            AuraDNSEngine.Rule(domain: "block2.com", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54104
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Pipeline two queries back-to-back
        let q1 = frameDnsMessage(buildDnsQuery(id: 0x1111, domain: "block1.com", qtype: 1))
        let q2 = frameDnsMessage(buildDnsQuery(id: 0x2222, domain: "block2.com", qtype: 1))

        var combined = Data()
        combined.append(q1)
        combined.append(q2)
        XCTAssertTrue(sendAll(sock: sock, data: combined))

        // Read both responses
        guard let r1 = readFramedDnsMessage(sock: sock),
              let r2 = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read pipelined responses")
            return
        }

        let h1 = AuraDNSEngine.parseHeader(data: r1)
        let h2 = AuraDNSEngine.parseHeader(data: r2)

        let ids = Set([h1?.id, h2?.id])
        XCTAssertTrue(ids.contains(0x1111))
        XCTAssertTrue(ids.contains(0x2222))
    }

    func testTcpDnsPartialReadHandling() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "partial.com", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54105
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        let query = buildDnsQuery(id: 0x5555, domain: "partial.com", qtype: 1)
        let framed = frameDnsMessage(query)

        // Send 2-byte length prefix first
        let lenPart = framed.subdata(in: 0..<2)
        XCTAssertTrue(sendAll(sock: sock, data: lenPart))
        usleep(30000) // 30ms delay

        // Send half of the query
        let mid = 2 + (query.count / 2)
        let part1 = framed.subdata(in: 2..<mid)
        XCTAssertTrue(sendAll(sock: sock, data: part1))
        usleep(30000) // 30ms delay

        // Send remaining bytes
        let part2 = framed.subdata(in: mid..<framed.count)
        XCTAssertTrue(sendAll(sock: sock, data: part2))

        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to reassemble segmented TCP request")
            return
        }

        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertEqual(header?.id, 0x5555)
        XCTAssertEqual(header?.anCount, 1)
    }

    func testTcpDnsOversizedMessageRejected() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54106
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Send frame length = 20000 (> maxDnsMessageSize 16384)
        var oversizedFrame = Data()
        var lenBig: UInt16 = UInt16(20000).bigEndian
        oversizedFrame.append(Data(bytes: &lenBig, count: 2))
        oversizedFrame.append(Data(repeating: 0xAA, count: 20))
        XCTAssertTrue(sendAll(sock: sock, data: oversizedFrame))

        // Resolver must reject and close the client socket
        var buf = [UInt8](repeating: 0, count: 16)
        let n = recv(sock, &buf, buf.count, 0)
        XCTAssertLessThanOrEqual(n, 0, "Expected socket to be closed upon oversized message length")
    }

    func testTcpDnsPausePassthroughBypassesRules() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "one.one.one.one", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        // Set UserDefaults App Group policy to paused
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        defaults?.set("paused", forKey: "vpn_policy_mode")
        defaults?.set(now + 3600000, forKey: "vpn_pause_expiry_utc_millis")

        let port: UInt16 = 54107
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        resolver.reloadPolicyFromAppGroup()
        XCTAssertTrue(resolver.start())
        defer {
            resolver.stop()
            defaults?.set("enabled", forKey: "vpn_policy_mode")
            defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
        }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Query normally blocked domain; under pause it must pass through to upstream!
        let query = buildDnsQuery(id: 0x7777, domain: "one.one.one.one", qtype: 1)
        let framedQuery = frameDnsMessage(query)
        XCTAssertTrue(sendAll(sock: sock, data: framedQuery))

        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read passthrough response")
            return
        }

        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertEqual(header?.id, 0x7777)
        // Upstream response for 1.1.1.1 is NOT 0.0.0.0
        let ipBytes = response.suffix(4)
        XCTAssertNotEqual(Array(ipBytes), [0, 0, 0, 0], "Passthrough mode should forward to upstream, not return synthetic 0.0.0.0")
    }

    func testTcpDnsPauseExpiryReconcilesToEnabled() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "expireblock.com", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        // Set expired pause timestamp (in the past)
        defaults?.set("paused", forKey: "vpn_policy_mode")
        defaults?.set(now - 10000, forKey: "vpn_pause_expiry_utc_millis")

        let port: UInt16 = 54108
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        resolver.reloadPolicyFromAppGroup()
        XCTAssertTrue(resolver.start())
        defer {
            resolver.stop()
            defaults?.set("enabled", forKey: "vpn_policy_mode")
            defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
        }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        let query = buildDnsQuery(id: 0x8888, domain: "expireblock.com", qtype: 1)
        let framedQuery = frameDnsMessage(query)
        XCTAssertTrue(sendAll(sock: sock, data: framedQuery))

        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read response")
            return
        }

        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertEqual(header?.id, 0x8888)
        // Reconciled to enabled -> must be blocked (0.0.0.0)
        let ipBytes = response.suffix(4)
        XCTAssertEqual(Array(ipBytes), [0, 0, 0, 0])
    }

    func testTcpListenerStopClosesActiveConnections() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "test1.local", isEnabled: true, isBlocked: true),
            AuraDNSEngine.Rule(domain: "test2.local", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54109
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())

        guard let sock1 = connectTcpClient(port: port),
              let sock2 = connectTcpClient(port: port) else {
            XCTFail("Failed to connect test clients")
            resolver.stop()
            return
        }
        defer {
            Darwin.close(sock1)
            Darwin.close(sock2)
        }

        // Send a query on each client to promote them to active
        let q1 = frameDnsMessage(buildDnsQuery(id: 0x101, domain: "test1.local"))
        let q2 = frameDnsMessage(buildDnsQuery(id: 0x102, domain: "test2.local"))
        _ = sendAll(sock: sock1, data: q1)
        _ = sendAll(sock: sock2, data: q2)
        _ = readFramedDnsMessage(sock: sock1)
        _ = readFramedDnsMessage(sock: sock2)

        let exp = expectation(description: "Clients promoted to active")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(resolver.activeTcpClientCount, 2)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // Stopping resolver should terminate active connections
        resolver.stop()
        XCTAssertEqual(resolver.activeTcpClientCount, 0)

        var buf = [UInt8](repeating: 0, count: 8)
        let n1 = recv(sock1, &buf, buf.count, 0)
        let n2 = recv(sock2, &buf, buf.count, 0)
        XCTAssertLessThanOrEqual(n1, 0)
        XCTAssertLessThanOrEqual(n2, 0)
    }

    func testPendingTimerCancellationOnPromotion() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "promote.test", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54110
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Send initial query to promote connection
        let q1 = frameDnsMessage(buildDnsQuery(id: 0x1111, domain: "promote.test"))
        XCTAssertTrue(sendAll(sock: sock, data: q1))

        guard let r1 = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read first response")
            return
        }
        let h1 = AuraDNSEngine.parseHeader(data: r1)
        XCTAssertEqual(h1?.id, 0x1111)
        XCTAssertEqual(resolver.activeTcpClientCount, 1)
        XCTAssertEqual(resolver.pendingTcpClientCount, 0)

        // Sleep past the 3-second pending timeout (3.5s)
        // If pending timer wasn't cancelled, it would fire and kill the connection
        Thread.sleep(forTimeInterval: 3.5)

        // Send second query on same promoted connection
        let q2 = frameDnsMessage(buildDnsQuery(id: 0x2222, domain: "promote.test"))
        XCTAssertTrue(sendAll(sock: sock, data: q2), "Promoted connection should still be open after 3.5s")

        guard let r2 = readFramedDnsMessage(sock: sock) else {
            XCTFail("Promoted connection was closed by pending timer")
            return
        }
        let h2 = AuraDNSEngine.parseHeader(data: r2)
        XCTAssertEqual(h2?.id, 0x2222)
        XCTAssertEqual(resolver.activeTcpClientCount, 1)
    }

    func testPendingTimeoutFiringImmediatelyBeforePromotion() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54111
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Verify registered as pending
        let exp1 = expectation(description: "Registered as pending")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(resolver.pendingTcpClientCount, 1)
            XCTAssertEqual(resolver.activeTcpClientCount, 0)
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 2.0)

        // Wait for pending timeout to fire (3.0s + 0.5s margin)
        Thread.sleep(forTimeInterval: 3.5)

        // Server should have closed connection
        XCTAssertEqual(resolver.pendingTcpClientCount, 0)
        XCTAssertEqual(resolver.activeTcpClientCount, 0)

        var buf = [UInt8](repeating: 0, count: 16)
        let n = recv(sock, &buf, buf.count, 0)
        XCTAssertLessThanOrEqual(n, 0, "Socket should be closed by pending timeout")
    }

    func testPendingTimeoutRacingWithPromotion() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "race.test", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54112
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        // Sleep 2.9 seconds - right before the 3.0s pending timeout
        Thread.sleep(forTimeInterval: 2.9)

        // Send query during the race window
        let query = frameDnsMessage(buildDnsQuery(id: 0x3333, domain: "race.test"))
        _ = sendAll(sock: sock, data: query)

        // Either promotion succeeded and we read response, or timeout closed cleanly
        if let response = readFramedDnsMessage(sock: sock) {
            let h = AuraDNSEngine.parseHeader(data: response)
            XCTAssertEqual(h?.id, 0x3333)
        }

        // Stop resolver: must clean up with zero lingering sockets or double close
        resolver.stop()
        XCTAssertEqual(resolver.activeTcpClientCount, 0)
        XCTAssertEqual(resolver.pendingTcpClientCount, 0)
    }

    func testClientDisconnectDuringPromotion() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54113
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }

        // Send 2-byte prefix and immediately close client socket
        var lenBig = UInt16(30).bigEndian
        var partial = Data(bytes: &lenBig, count: 2)
        _ = sendAll(sock: sock, data: partial)
        Darwin.close(sock)

        let exp = expectation(description: "Cleanup completed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(resolver.pendingTcpClientCount, 0)
            XCTAssertEqual(resolver.activeTcpClientCount, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testExactlyOnceSocketClosureUnderChurn() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54114
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        var sockets = [Int32]()
        for _ in 0..<30 {
            if let sock = connectTcpClient(port: port) {
                sockets.append(sock)
            }
        }
        XCTAssertEqual(sockets.count, 30)

        // 10: close immediately from client
        for i in 0..<10 {
            Darwin.close(sockets[i])
        }

        // 10: send queries to promote
        let q = frameDnsMessage(buildDnsQuery(id: 0x4444, domain: "churn.test"))
        for i in 10..<20 {
            _ = sendAll(sock: sockets[i], data: q)
        }

        // 10: leave pending
        // Wait for processing
        let exp = expectation(description: "Churn processed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            // Stop resolver - must close all without double close
            resolver.stop()
            XCTAssertEqual(resolver.activeTcpClientCount, 0)
            XCTAssertEqual(resolver.pendingTcpClientCount, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)

        for i in 10..<30 {
            Darwin.close(sockets[i])
        }
    }

    func testPartialFirstFrameDeliveryAcrossPacketBoundaries() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "partial.stream", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54115
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        guard let sock = connectTcpClient(port: port) else {
            XCTFail("Failed to connect")
            return
        }
        defer { Darwin.close(sock) }

        let query = buildDnsQuery(id: 0x5555, domain: "partial.stream")
        let framed = frameDnsMessage(query)

        // 1. Send first byte of 2-byte prefix
        let b1 = framed.subdata(in: 0..<1)
        XCTAssertTrue(sendAll(sock: sock, data: b1))
        usleep(30000)

        // Still pending
        XCTAssertEqual(resolver.pendingTcpClientCount, 1)
        XCTAssertEqual(resolver.activeTcpClientCount, 0)

        // 2. Send second byte + half of query
        let mid = 2 + (query.count / 2)
        let b2 = framed.subdata(in: 1..<mid)
        XCTAssertTrue(sendAll(sock: sock, data: b2))
        usleep(30000)

        // Still pending
        XCTAssertEqual(resolver.pendingTcpClientCount, 1)
        XCTAssertEqual(resolver.activeTcpClientCount, 0)

        // 3. Send remainder of query
        let b3 = framed.subdata(in: mid..<framed.count)
        XCTAssertTrue(sendAll(sock: sock, data: b3))

        // Read response
        guard let response = readFramedDnsMessage(sock: sock) else {
            XCTFail("Failed to read response after reassembled segments")
            return
        }
        let header = AuraDNSEngine.parseHeader(data: response)
        XCTAssertEqual(header?.id, 0x5555)

        // Promoted to active!
        XCTAssertEqual(resolver.pendingTcpClientCount, 0)
        XCTAssertEqual(resolver.activeTcpClientCount, 1)
    }

    func testPendingConnectionLimitEnforcementMax20() {
        let engine = AuraDNSEngine()
        let port: UInt16 = 54116
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())
        defer { resolver.stop() }

        var sockets = [Int32]()
        defer {
            for s in sockets { Darwin.close(s) }
        }

        // Connect 20 pending clients
        for _ in 0..<20 {
            if let sock = connectTcpClient(port: port) {
                sockets.append(sock)
            }
        }
        XCTAssertEqual(sockets.count, 20)

        let exp = expectation(description: "20 pending accepted")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(resolver.pendingTcpClientCount, 20)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // 21st connection must be rejected/dropped
        if let sock21 = connectTcpClient(port: port) {
            defer { Darwin.close(sock21) }
            // Verify resolver dropped it immediately
            var buf = [UInt8](repeating: 0, count: 16)
            let n = recv(sock21, &buf, buf.count, 0)
            XCTAssertLessThanOrEqual(n, 0, "21st pending connection should be closed by server")
        }
        XCTAssertEqual(resolver.pendingTcpClientCount, 20)
    }

    func testCleanResolverShutdownWithPendingAndActiveClients() {
        let engine = AuraDNSEngine()
        let rules = [
            AuraDNSEngine.Rule(domain: "shutdown.test", isEnabled: true, isBlocked: true)
        ]
        engine.setRules(rules)

        let port: UInt16 = 54117
        let resolver = AuraLocalDNSResolver(engine: engine, listenPort: port)
        XCTAssertTrue(resolver.start())

        var activeSocks = [Int32]()
        var pendingSocks = [Int32]()
        defer {
            for s in activeSocks { Darwin.close(s) }
            for s in pendingSocks { Darwin.close(s) }
        }

        // 5 active clients
        let q = frameDnsMessage(buildDnsQuery(id: 0x7777, domain: "shutdown.test"))
        for _ in 0..<5 {
            if let sock = connectTcpClient(port: port) {
                activeSocks.append(sock)
                _ = sendAll(sock: sock, data: q)
                _ = readFramedDnsMessage(sock: sock)
            }
        }

        // 5 pending clients
        for _ in 0..<5 {
            if let sock = connectTcpClient(port: port) {
                pendingSocks.append(sock)
            }
        }

        let exp = expectation(description: "Collections settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(resolver.activeTcpClientCount, 5)
            XCTAssertEqual(resolver.pendingTcpClientCount, 5)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        // Stop resolver
        resolver.stop()
        XCTAssertEqual(resolver.activeTcpClientCount, 0)
        XCTAssertEqual(resolver.pendingTcpClientCount, 0)

        // All sockets should be disconnected
        var buf = [UInt8](repeating: 0, count: 8)
        for s in activeSocks {
            XCTAssertLessThanOrEqual(recv(s, &buf, buf.count, 0), 0)
        }
        for s in pendingSocks {
            XCTAssertLessThanOrEqual(recv(s, &buf, buf.count, 0), 0)
        }
    }
}
