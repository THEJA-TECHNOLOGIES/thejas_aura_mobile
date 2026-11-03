import Foundation
import Network
import os.log

/// Lightweight native UDP DNS resolver running inside the AuraTunnel extension.
/// Binds to 127.0.0.1:53 via POSIX socket, intercepts system DNS queries,
/// evaluates them against local rules, and forwards permitted queries upstream
/// concurrently to Quad9 with fallback to Cloudflare and IPv6 endpoints.
public final class AuraLocalDNSResolver {

    public struct UpstreamResolver {
        public let address: String
        public let port: UInt16
        public let isIPv6: Bool

        public init(address: String, port: UInt16 = 53, isIPv6: Bool = false) {
            self.address = address
            self.port = port
            self.isIPv6 = isIPv6
        }
    }

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraLocalDNSResolver")

    private let engine: AuraDNSEngine
    private let upstreams: [UpstreamResolver] = [
        UpstreamResolver(address: "9.9.9.9", port: 53, isIPv6: false),           // Primary Quad9
        UpstreamResolver(address: "1.1.1.1", port: 53, isIPv6: false),           // Fallback Cloudflare
        UpstreamResolver(address: "8.8.8.8", port: 53, isIPv6: false),           // Fallback Google
        UpstreamResolver(address: "2620:fe::fe", port: 53, isIPv6: true),       // Quad9 IPv6
        UpstreamResolver(address: "2606:4700:4700::1111", port: 53, isIPv6: true) // Cloudflare IPv6
    ]

    public var onFatalError: ((Error) -> Void)?
    public var activityWriter: AuraActivityWriter?

    private var serverSocket: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.thejatech.aura.dnsresolver", qos: .userInitiated)
    private var isRunning = false

    public struct VpnPolicySnapshot {
        public let mode: String
        public let pauseExpiryUtcMillis: Int64

        public init(mode: String, pauseExpiryUtcMillis: Int64) {
            self.mode = mode
            self.pauseExpiryUtcMillis = pauseExpiryUtcMillis
        }

        public func isPaused(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
            return mode == "paused" && now < pauseExpiryUtcMillis
        }

        public func isExpiredPause(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
            return mode == "paused" && now >= pauseExpiryUtcMillis
        }
    }

    private var policyLock = os_unfair_lock_s()
    private var currentPolicy = VpnPolicySnapshot(mode: "enabled", pauseExpiryUtcMillis: 0)

    public func reloadPolicyFromAppGroup() {
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        let rawMode = defaults?.string(forKey: "vpn_policy_mode") ?? "enabled"
        let expiry = defaults?.object(forKey: "vpn_pause_expiry_utc_millis") as? Int64 ?? 0
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        os_unfair_lock_lock(&policyLock)
        if rawMode == "paused" && expiry > 0 && now >= expiry {
            defaults?.set("enabled", forKey: "vpn_policy_mode")
            defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
            currentPolicy = VpnPolicySnapshot(mode: "enabled", pauseExpiryUtcMillis: 0)
        } else {
            currentPolicy = VpnPolicySnapshot(mode: rawMode, pauseExpiryUtcMillis: expiry)
        }
        os_unfair_lock_unlock(&policyLock)

        os_log(.info, log: Self.log, "AuraLocalDNSResolver reloaded policy snapshot: mode=%{public}@ expiry=%{public}lld", currentPolicy.mode, currentPolicy.pauseExpiryUtcMillis)
    }

    public init(engine: AuraDNSEngine) {
        self.engine = engine
        reloadPolicyFromAppGroup()
    }

    public static func queryTypeToString(_ qType: UInt16) -> String {
        switch qType {
        case 1: return "A"
        case 28: return "AAAA"
        case 5: return "CNAME"
        case 15: return "MX"
        case 16: return "TXT"
        case 65: return "HTTPS"
        default: return "TYPE\(qType)"
        }
    }

    /// Starts listening on 127.0.0.1:53.
    public func start() -> Bool {
        guard !isRunning else { return true }

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            let err = errno
            os_log(.error, log: Self.log, "Failed to create UDP socket: errno %{public}d", err)
            AuraDiagnostics.log(tag: "DNSResolver", message: "Failed to create UDP socket: errno \(err)")
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create UDP socket: \(err)"])
            onFatalError?(nsErr)
            return false
        }

        // Enable SO_REUSEADDR and SO_REUSEPORT to prevent EADDRINUSE on rapid restarts
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(53).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let bindErr = errno
            let errDesc = String(cString: strerror(bindErr))
            os_log(.error, log: Self.log, "Failed to bind UDP socket to 127.0.0.1:53: errno %{public}d (%{public}s)", bindErr, errDesc)
            AuraDiagnostics.log(tag: "DNSResolver", message: "FATAL: Failed to bind UDP socket to 127.0.0.1:53: errno \(bindErr) (\(errDesc))")
            close(sock)
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(bindErr), userInfo: [NSLocalizedDescriptionKey: "Failed to bind 127.0.0.1:53: \(bindErr) (\(errDesc))"])
            onFatalError?(nsErr)
            return false
        }

        serverSocket = sock
        isRunning = true

        AuraDiagnostics.log(tag: "DNSResolver", message: "Successfully bound UDP socket fd=\(sock) to 127.0.0.1:53")

        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleIncomingQueries()
        }
        source.setCancelHandler { [weak self] in
            close(sock)
            if self?.isRunning == true {
                let cancelErr = NSError(domain: "AuraLocalDNSResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "DNS listener socket cancelled unexpectedly"])
                self?.onFatalError?(cancelErr)
            }
        }
        source.resume()
        dispatchSource = source

        os_log(.info, log: Self.log, "Local DNS resolver successfully bound to 127.0.0.1:53 (upstreams: %{public}ld endpoints configured)", self.upstreams.count)
        return true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        dispatchSource?.cancel()
        dispatchSource = nil
        serverSocket = -1
        os_log(.info, log: Self.log, "Local DNS resolver stopped")
    }

    // MARK: - Query Handling (Non-blocking loop)

    private func handleIncomingQueries() {
        while isRunning {
            var clientAddr = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            var buffer = [UInt8](repeating: 0, count: 4096)

            let bytesRead = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(serverSocket, &buffer, buffer.count, 0, sa, &addrLen)
                }
            }

            if bytesRead < 0 {
                let err = errno
                if err == EWOULDBLOCK || err == EAGAIN {
                    break // All pending packets drained from kernel socket buffer
                }
                break
            }
            guard bytesRead > 0 else { break }

            let requestData = Data(buffer[0..<bytesRead])
            processQuery(requestData: requestData, clientAddr: clientAddr, addrLen: addrLen)
        }
    }

    private func processQuery(requestData: Data, clientAddr: sockaddr_storage, addrLen: socklen_t) {
        if let question = AuraDNSEngine.parseQuestion(data: requestData) {
            let qTypeStr = Self.queryTypeToString(question.qType)
            let now = Int64(Date().timeIntervalSince1970 * 1000)

            os_unfair_lock_lock(&policyLock)
            var policy = currentPolicy
            if policy.isExpiredPause(now: now) {
                let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
                defaults?.set("enabled", forKey: "vpn_policy_mode")
                defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
                currentPolicy = VpnPolicySnapshot(mode: "enabled", pauseExpiryUtcMillis: 0)
                policy = currentPolicy
                os_log(.info, log: Self.log, "Pause expired; reconciled policy to enabled in DNS resolver")
            }
            os_unfair_lock_unlock(&policyLock)

            // DNS Passthrough mode when policy is paused
            if policy.isPaused(now: now) {
                os_log(
                    .info,
                    log: Self.log,
                    "[PASSTHROUGH] Query %{public}@ bypassed (protection paused, expiry=%{public}lld) -> Forwarding upstream",
                    question.name,
                    policy.pauseExpiryUtcMillis
                )
                forwardUpstream(
                    requestData: requestData,
                    clientAddr: clientAddr,
                    addrLen: addrLen,
                    domain: question.name,
                    queryType: qTypeStr,
                    decision: nil,
                    isPassthrough: true
                )
                return
            }

            // Normal DNS filtering when policy is enabled
            let decision = engine.evaluate(domain: question.name)

            if decision.isBlocked {
                os_log(
                    .info,
                    log: Self.log,
                    "[BLOCK] Intercepted %{public}@ (source: %{public}@, rule: %{public}@, categories: %{public}@, type: %{public}u) -> Synthesizing 0.0.0.0/::",
                    question.name,
                    decision.matchedSource,
                    decision.matchedRule ?? "unknown",
                    decision.matchedCategories.joined(separator: ","),
                    question.qType
                )
                if let response = AuraDNSEngine.synthesizeBlockedResponse(requestData: requestData) {
                    sendResponse(response, to: clientAddr, addrLen: addrLen)

                    let record = ActivityRecord(
                        domain: question.name,
                        queryType: qTypeStr,
                        outcome: "blocked",
                        matchedSource: decision.matchedSource,
                        matchedRuleId: decision.matchedRule,
                        matchedCategories: decision.matchedCategories,
                        reason: decision.reason
                    )
                    activityWriter?.enqueue(record)
                    return
                }
            } else {
                os_log(
                    .info,
                    log: Self.log,
                    "[ALLOW] Query %{public}@ permitted (source: %{public}@, rule: %{public}@, type: %{public}u) -> Forwarding upstream",
                    question.name,
                    decision.matchedSource,
                    decision.matchedRule ?? "none",
                    question.qType
                )
            }
            forwardUpstream(
                requestData: requestData,
                clientAddr: clientAddr,
                addrLen: addrLen,
                domain: question.name,
                queryType: qTypeStr,
                decision: decision
            )
        } else {
            os_log(.default, log: Self.log, "Received unparseable DNS payload (%{public}ld bytes) -> Forwarding upstream", requestData.count)
            forwardUpstream(
                requestData: requestData,
                clientAddr: clientAddr,
                addrLen: addrLen,
                domain: nil,
                queryType: "UNKNOWN",
                decision: nil
            )
        }
    }

    private func sendResponse(_ response: Data, to clientAddr: sockaddr_storage, addrLen: socklen_t) {
        queue.async { [weak self] in
            guard let self = self, self.serverSocket >= 0 else { return }
            var addr = clientAddr
            response.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        _ = sendto(self.serverSocket, baseAddress, response.count, 0, sa, addrLen)
                    }
                }
            }
        }
    }

    // MARK: - Concurrent Upstream Resolution with Fallback & Timeout Budget

    private func forwardUpstream(
        requestData: Data,
        clientAddr: sockaddr_storage,
        addrLen: socklen_t,
        domain: String?,
        queryType: String,
        decision: AuraDNSEngine.MatchDecision?,
        isPassthrough: Bool = false
    ) {
        // Run upstream queries concurrently on global worker queue to prevent head-of-line blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, self.isRunning else { return }

            let startTime = CFAbsoluteTimeGetCurrent()
            var responseData: Data?
            var resolvedBy: String?
            let maxTotalBudget: Double = 2.0 // Maximum 2.0s budget to prevent iOS mDNSResponder timeouts

            for resolver in self.upstreams {
                let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                if timeElapsed >= maxTotalBudget {
                    break
                }

                let remainingBudget = max(0.5, min(1.0, maxTotalBudget - timeElapsed))
                if let data = Self.queryUpstream(resolver: resolver, requestData: requestData, timeoutSeconds: remainingBudget) {
                    responseData = data
                    resolvedBy = resolver.address
                    break
                }
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            if let response = responseData {
                os_log(
                    .info,
                    log: Self.log,
                    "[RESOLVED] %{public}@ via %{public}@ in %{public}dms (%{public}ld bytes)",
                    domain ?? "unknown",
                    resolvedBy ?? "upstream",
                    elapsedMs,
                    response.count
                )
                self.sendResponse(response, to: clientAddr, addrLen: addrLen)

                if let domain = domain {
                    let record = ActivityRecord(
                        domain: domain,
                        queryType: queryType,
                        outcome: "allowed",
                        matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                        matchedRuleId: decision?.matchedRule,
                        matchedCategories: decision?.matchedCategories ?? [],
                        reason: nil
                    )
                    self.activityWriter?.enqueue(record)
                }
            } else {
                os_log(
                    .error,
                    log: Self.log,
                    "[SERVFAIL] %{public}@ failed all upstreams after %{public}dms -> Returning SERVFAIL",
                    domain ?? "unknown",
                    elapsedMs
                )
                if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: requestData) {
                    self.sendResponse(servFail, to: clientAddr, addrLen: addrLen)
                }

                if let domain = domain {
                    let record = ActivityRecord(
                        domain: domain,
                        queryType: queryType,
                        outcome: "failed",
                        matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                        matchedRuleId: decision?.matchedRule,
                        matchedCategories: decision?.matchedCategories ?? [],
                        reason: "Upstream resolution failed or timed out"
                    )
                    self.activityWriter?.enqueue(record)
                }
            }
        }
    }

    /// Queries an upstream DNS resolver over a dedicated connected UDP socket.
    /// Strictly validates:
    /// 1. Transaction ID matching (RFC 1035 §4.1.1, RFC 5452)
    /// 2. Response QR bit set (Flags byte 2, bit 7 == 1)
    /// 3. Kernel-level destination binding via connect() to prevent rogue datagrams
    public static func queryUpstream(
        resolver: UpstreamResolver,
        requestData: Data,
        timeoutSeconds: Double
    ) -> Data? {
        let family: Int32 = resolver.isIPv6 ? AF_INET6 : AF_INET
        let sock = socket(family, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        let sec = time_t(floor(timeoutSeconds))
        let usec = suseconds_t((timeoutSeconds - floor(timeoutSeconds)) * 1_000_000)
        var tv = timeval(tv_sec: sec, tv_usec: usec)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Connect UDP socket to upstream endpoint so kernel strictly isolates traffic
        if resolver.isIPv6 {
            var addr6 = sockaddr_in6()
            addr6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr6.sin6_family = sa_family_t(AF_INET6)
            addr6.sin6_port = in_port_t(resolver.port).bigEndian
            guard inet_pton(AF_INET6, resolver.address, &addr6.sin6_addr) == 1 else { return nil }

            let connectRes = withUnsafePointer(to: &addr6) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            guard connectRes == 0 else { return nil }
        } else {
            var addr4 = sockaddr_in()
            addr4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr4.sin_family = sa_family_t(AF_INET)
            addr4.sin_port = in_port_t(resolver.port).bigEndian
            guard inet_pton(AF_INET, resolver.address, &addr4.sin_addr) == 1 else { return nil }

            let connectRes = withUnsafePointer(to: &addr4) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connectRes == 0 else { return nil }
        }

        let sent = requestData.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return send(sock, base, requestData.count, 0)
        }
        guard sent > 0 else { return nil }

        var responseBuf = [UInt8](repeating: 0, count: 4096)
        let received = recv(sock, &responseBuf, responseBuf.count, 0)

        // RFC 1035 §4.1.1 & RFC 5452 Validation:
        guard received >= 12 else { return nil }

        // 1. Transaction ID matching
        let reqTxId = requestData.subdata(in: 0..<2)
        let respTxId = Data(responseBuf[0..<2])
        guard reqTxId == respTxId else {
            os_log(.error, log: Self.log, "Mismatched DNS transaction ID: expected %{public}@, got %{public}@", reqTxId as NSData, respTxId as NSData)
            return nil
        }

        // 2. Response QR bit check: Flags byte 2, bit 7 must be 1 (Response)
        let flagsByte = responseBuf[2]
        guard (flagsByte & 0x80) != 0 else {
            os_log(.error, log: Self.log, "Received DNS packet with QR=0 (Query, not Response)")
            return nil
        }

        return Data(responseBuf[0..<received])
    }
}
