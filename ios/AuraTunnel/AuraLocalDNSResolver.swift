import Foundation
import Network
import os.log

/// Lightweight native UDP and TCP DNS resolver running inside the AuraTunnel extension.
/// Binds to 127.0.0.1:53 via POSIX socket, intercepts system DNS queries,
/// evaluates them against local rules, and forwards permitted queries upstream
/// concurrently to Quad9 with fallback to Cloudflare and IPv6 endpoints.
public final class AuraLocalDNSResolver {

    public static let maxDnsMessageSize: Int = 16384
    public static let maxConcurrentTcpConnections: Int = 100
    public static let maxPendingTcpConnections: Int = 20
    public static let tcpIdleTimeoutSeconds: Double = 10.0
    public static let tcpPendingTimeoutSeconds: Double = 3.0

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
    private let listenPort: UInt16
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

    private var tcpServerSocket: Int32 = -1
    private var tcpDispatchSource: DispatchSourceRead?
    private let tcpQueue = DispatchQueue(label: "com.thejatech.aura.dnsresolver.tcp", qos: .userInitiated)
    private var activeTcpClients = Set<TcpClientConnection>()
    private var pendingTcpClients = Set<PendingTcpClient>()
    private var clientsLock = os_unfair_lock_s()
    private var nextClientId: UInt64 = 1

    fileprivate var isRunning = false

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

    public init(engine: AuraDNSEngine, listenPort: UInt16 = 53) {
        self.engine = engine
        self.listenPort = listenPort
        reloadPolicyFromAppGroup()
    }

    /// Testing accessor for currently active TCP client connections count (fully established).
    public var activeTcpClientCount: Int {
        os_unfair_lock_lock(&clientsLock)
        defer { os_unfair_lock_unlock(&clientsLock) }
        return activeTcpClients.count
    }

    /// Testing accessor for currently pending TCP client connections count (incomplete handshake).
    public var pendingTcpClientCount: Int {
        os_unfair_lock_lock(&clientsLock)
        defer { os_unfair_lock_unlock(&clientsLock) }
        return pendingTcpClients.count
    }

    /// Testing accessor for bound TCP server socket file descriptor.
    public var tcpSocketFd: Int32 {
        return tcpServerSocket
    }

    /// Testing accessor for bound UDP server socket file descriptor.
    public var udpSocketFd: Int32 {
        return serverSocket
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

    /// Starts listening on 127.0.0.1 for both UDP and TCP on port 53 (or configured listenPort).
    public func start() -> Bool {
        guard !isRunning else { return true }

        // 1. Create and bind UDP socket
        let udpSock = socket(AF_INET, SOCK_DGRAM, 0)
        guard udpSock >= 0 else {
            let err = errno
            os_log(.error, log: Self.log, "Failed to create UDP socket: errno %{public}d", err)
            AuraDiagnostics.log(tag: "DNSResolver", message: "Failed to create UDP socket: errno \(err)")
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create UDP socket: \(err)"])
            onFatalError?(nsErr)
            return false
        }

        // Enable SO_REUSEADDR and SO_REUSEPORT to prevent EADDRINUSE on rapid restarts
        var reuse: Int32 = 1
        setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(udpSock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking
        let udpFlags = fcntl(udpSock, F_GETFL, 0)
        _ = fcntl(udpSock, F_SETFL, udpFlags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(listenPort).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let udpBindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(udpSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard udpBindResult == 0 else {
            let bindErr = errno
            let errDesc = String(cString: strerror(bindErr))
            os_log(.error, log: Self.log, "Failed to bind UDP socket to 127.0.0.1:%{public}u: errno %{public}d (%{public}s)", listenPort, bindErr, errDesc)
            AuraDiagnostics.log(tag: "DNSResolver", message: "FATAL: Failed to bind UDP socket to 127.0.0.1:\(listenPort): errno \(bindErr) (\(errDesc))")
            close(udpSock)
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(bindErr), userInfo: [NSLocalizedDescriptionKey: "Failed to bind UDP 127.0.0.1:\(listenPort): \(bindErr) (\(errDesc))"])
            onFatalError?(nsErr)
            return false
        }

        // 2. Create, bind, and listen on TCP socket
        let tcpSock = socket(AF_INET, SOCK_STREAM, 0)
        guard tcpSock >= 0 else {
            let err = errno
            os_log(.error, log: Self.log, "Failed to create TCP socket: errno %{public}d", err)
            AuraDiagnostics.log(tag: "DNSResolver", message: "Failed to create TCP socket: errno \(err)")
            close(udpSock)
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to create TCP socket: \(err)"])
            onFatalError?(nsErr)
            return false
        }

        setsockopt(tcpSock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(tcpSock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let tcpFlags = fcntl(tcpSock, F_GETFL, 0)
        _ = fcntl(tcpSock, F_SETFL, tcpFlags | O_NONBLOCK)

        let tcpBindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(tcpSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard tcpBindResult == 0 else {
            let bindErr = errno
            let errDesc = String(cString: strerror(bindErr))
            os_log(.error, log: Self.log, "Failed to bind TCP socket to 127.0.0.1:%{public}u: errno %{public}d (%{public}s)", listenPort, bindErr, errDesc)
            AuraDiagnostics.log(tag: "DNSResolver", message: "FATAL: Failed to bind TCP socket to 127.0.0.1:\(listenPort): errno \(bindErr) (\(errDesc))")
            close(tcpSock)
            close(udpSock)
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(bindErr), userInfo: [NSLocalizedDescriptionKey: "Failed to bind TCP 127.0.0.1:\(listenPort): \(bindErr) (\(errDesc))"])
            onFatalError?(nsErr)
            return false
        }

        guard listen(tcpSock, 128) == 0 else {
            let listenErr = errno
            let errDesc = String(cString: strerror(listenErr))
            os_log(.error, log: Self.log, "Failed to listen on TCP socket 127.0.0.1:%{public}u: errno %{public}d (%{public}s)", listenPort, listenErr, errDesc)
            AuraDiagnostics.log(tag: "DNSResolver", message: "FATAL: Failed to listen on TCP socket: errno \(listenErr) (\(errDesc))")
            close(tcpSock)
            close(udpSock)
            let nsErr = NSError(domain: NSPOSIXErrorDomain, code: Int(listenErr), userInfo: [NSLocalizedDescriptionKey: "Failed to listen on TCP 127.0.0.1:\(listenPort): \(listenErr) (\(errDesc))"])
            onFatalError?(nsErr)
            return false
        }

        serverSocket = udpSock
        tcpServerSocket = tcpSock
        isRunning = true

        AuraDiagnostics.log(tag: "DNSResolver", message: "Successfully bound UDP socket fd=\(udpSock) and TCP socket fd=\(tcpSock) to 127.0.0.1:\(listenPort)")

        // 3. Setup UDP dispatch source
        let udpSource = DispatchSource.makeReadSource(fileDescriptor: udpSock, queue: queue)
        udpSource.setEventHandler { [weak self] in
            self?.handleIncomingQueries()
        }
        udpSource.setCancelHandler { [weak self] in
            close(udpSock)
            if self?.isRunning == true {
                let cancelErr = NSError(domain: "AuraLocalDNSResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "UDP DNS listener socket cancelled unexpectedly"])
                self?.onFatalError?(cancelErr)
            }
        }
        udpSource.resume()
        dispatchSource = udpSource

        // 4. Setup TCP accept dispatch source
        let tcpSource = DispatchSource.makeReadSource(fileDescriptor: tcpSock, queue: tcpQueue)
        tcpSource.setEventHandler { [weak self] in
            self?.handleIncomingTcpConnections()
        }
        tcpSource.setCancelHandler { [weak self] in
            close(tcpSock)
            if self?.isRunning == true {
                let cancelErr = NSError(domain: "AuraLocalDNSResolver", code: -1, userInfo: [NSLocalizedDescriptionKey: "TCP DNS listener socket cancelled unexpectedly"])
                self?.onFatalError?(cancelErr)
            }
        }
        tcpSource.resume()
        tcpDispatchSource = tcpSource

        os_log(.info, log: Self.log, "Local DNS resolver successfully bound UDP and TCP to 127.0.0.1:%{public}u (upstreams: %{public}ld endpoints configured)", listenPort, self.upstreams.count)
        return true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        // Cancel and release UDP listener
        dispatchSource?.cancel()
        dispatchSource = nil
        serverSocket = -1

        // Cancel and release TCP listener
        tcpDispatchSource?.cancel()
        tcpDispatchSource = nil
        tcpServerSocket = -1

        // Close all active TCP client connections
        os_unfair_lock_lock(&clientsLock)
        let clientsToClose = activeTcpClients
        let pendingToClose = pendingTcpClients
        activeTcpClients.removeAll()
        pendingTcpClients.removeAll()
        os_unfair_lock_unlock(&clientsLock)

        for client in clientsToClose {
            client.close()
        }
        for client in pendingToClose {
            client.close()
        }

        os_log(.info, log: Self.log, "Local DNS resolver stopped (UDP and TCP)")
    }

    // MARK: - TCP Connection Management

    private func handleIncomingTcpConnections() {
        while isRunning {
            var clientAddr = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientSock = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(tcpServerSocket, sa, &addrLen)
                }
            }

            if clientSock < 0 {
                let err = errno
                if err == EWOULDBLOCK || err == EAGAIN {
                    break // All pending incoming connections accepted
                }
                if err == EINTR {
                    continue
                }
                break
            }

            os_unfair_lock_lock(&clientsLock)
            let totalClients = activeTcpClients.count + pendingTcpClients.count
            if totalClients >= Self.maxConcurrentTcpConnections {
                os_unfair_lock_unlock(&clientsLock)
                os_log(.error, log: Self.log, "Max total TCP clients (%{public}d) reached, dropping client fd=%{public}d", Self.maxConcurrentTcpConnections, clientSock)
                close(clientSock)
                continue
            }
            if pendingTcpClients.count >= Self.maxPendingTcpConnections {
                os_unfair_lock_unlock(&clientsLock)
                os_log(.error, log: Self.log, "Max pending TCP clients (%{public}d) reached, dropping client fd=%{public}d", Self.maxPendingTcpConnections, clientSock)
                close(clientSock)
                continue
            }
            let connId = nextClientId
            nextClientId += 1
            let socketOwner = SocketOwner(fd: clientSock)
            let pendingConn = PendingTcpClient(id: connId, socketOwner: socketOwner, resolver: self)
            pendingTcpClients.insert(pendingConn)
            os_unfair_lock_unlock(&clientsLock)

            pendingConn.start()
        }
    }

    fileprivate func removeClientConnection(_ connection: TcpClientConnection) {
        os_unfair_lock_lock(&clientsLock)
        activeTcpClients.remove(connection)
        os_unfair_lock_unlock(&clientsLock)
    }

    @discardableResult
    fileprivate func promotePendingToActive(_ pending: PendingTcpClient, _ active: TcpClientConnection) -> Bool {
        os_unfair_lock_lock(&clientsLock)
        defer { os_unfair_lock_unlock(&clientsLock) }
        guard isRunning else {
            return false
        }
        pendingTcpClients.remove(pending)
        activeTcpClients.insert(active)
        return true
    }

    fileprivate func removePendingConnection(_ connection: PendingTcpClient) {
        os_unfair_lock_lock(&clientsLock)
        pendingTcpClients.remove(connection)
        os_unfair_lock_unlock(&clientsLock)
    }

    private func getEffectivePolicy(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> VpnPolicySnapshot {
        os_unfair_lock_lock(&policyLock)
        defer { os_unfair_lock_unlock(&policyLock) }
        if currentPolicy.isExpiredPause(now: now) {
            let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
            defaults?.set("enabled", forKey: "vpn_policy_mode")
            defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
            currentPolicy = VpnPolicySnapshot(mode: "enabled", pauseExpiryUtcMillis: 0)
            os_log(.info, log: Self.log, "Pause expired; reconciled policy to enabled in DNS resolver")
        }
        return currentPolicy
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
            let policy = getEffectivePolicy(now: now)

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
                    // Apply EDNS0-aware size limiting to blocked response
                    let limitedResponse = AuraDNSEngine.limitDnsResponseSize(
                        responseData: response,
                        queryData: requestData,
                        isBlockedResponse: true,
                        isServFailResponse: false
                    )
                    sendResponse(limitedResponse, to: clientAddr, addrLen: addrLen)

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
                if let data = Self.queryUpstream(
                    resolver: resolver,
                    requestData: requestData,
                    timeoutSeconds: remainingBudget,
                    globalStartTime: startTime,
                    globalMaxBudget: maxTotalBudget
                ) {
                    responseData = data
                    resolvedBy = resolver.address
                    break
                }
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            if let response = responseData {
                // Apply EDNS0-aware size limiting to upstream response
                let limitedResponse = AuraDNSEngine.limitDnsResponseSize(
                    responseData: response,
                    queryData: requestData,
                    isBlockedResponse: false,
                    isServFailResponse: false
                )
                os_log(
                    .info,
                    log: Self.log,
                    "[RESOLVED] %{public}@ via %{public}@ in %{public}dms (%{public}ld bytes)",
                    domain ?? "unknown",
                    resolvedBy ?? "upstream",
                    elapsedMs,
                    limitedResponse.count
                )
                self.sendResponse(limitedResponse, to: clientAddr, addrLen: addrLen)

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
                    // Apply EDNS0-aware size limiting to SERVFAIL response too
                    let limitedServFail = AuraDNSEngine.limitDnsResponseSize(
                        responseData: servFail,
                        queryData: requestData,
                        isBlockedResponse: false,
                        isServFailResponse: true
                    )
                    self.sendResponse(limitedServFail, to: clientAddr, addrLen: addrLen)
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

    // MARK: - TCP Query Processing and Forwarding

    fileprivate func processTcpQuery(requestData: Data, connection: TcpClientConnection) {
        if let question = AuraDNSEngine.parseQuestion(data: requestData) {
            let qTypeStr = Self.queryTypeToString(question.qType)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let policy = getEffectivePolicy(now: now)

            // DNS Passthrough mode when policy is paused
            if policy.isPaused(now: now) {
                os_log(
                    .info,
                    log: Self.log,
                    "[PASSTHROUGH-TCP] Query %{public}@ bypassed (protection paused, expiry=%{public}lld) -> Forwarding upstream",
                    question.name,
                    policy.pauseExpiryUtcMillis
                )
                forwardUpstreamTcp(
                    requestData: requestData,
                    connection: connection,
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
                    "[BLOCK-TCP] Intercepted %{public}@ (source: %{public}@, rule: %{public}@, categories: %{public}@, type: %{public}u) -> Synthesizing 0.0.0.0/::",
                    question.name,
                    decision.matchedSource,
                    decision.matchedRule ?? "unknown",
                    decision.matchedCategories.joined(separator: ","),
                    question.qType
                )
                if let response = AuraDNSEngine.synthesizeBlockedResponse(requestData: requestData) {
                    connection.sendResponse(response)

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
                    "[ALLOW-TCP] Query %{public}@ permitted (source: %{public}@, rule: %{public}@, type: %{public}u) -> Forwarding upstream",
                    question.name,
                    decision.matchedSource,
                    decision.matchedRule ?? "none",
                    question.qType
                )
            }
            forwardUpstreamTcp(
                requestData: requestData,
                connection: connection,
                domain: question.name,
                queryType: qTypeStr,
                decision: decision
            )
        } else {
            os_log(.default, log: Self.log, "Received unparseable TCP DNS payload (%{public}ld bytes) -> Forwarding upstream", requestData.count)
            forwardUpstreamTcp(
                requestData: requestData,
                connection: connection,
                domain: nil,
                queryType: "UNKNOWN",
                decision: nil
            )
        }
    }

    private func forwardUpstreamTcp(
        requestData: Data,
        connection: TcpClientConnection,
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
            let maxTotalBudget: Double = 2.0 // Maximum 2.0s budget to prevent client timeouts

            for resolver in self.upstreams {
                let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                if timeElapsed >= maxTotalBudget {
                    break
                }

                let remainingBudget = max(0.5, min(1.0, maxTotalBudget - timeElapsed))
                if let data = Self.queryUpstream(
                    resolver: resolver,
                    requestData: requestData,
                    timeoutSeconds: remainingBudget,
                    globalStartTime: startTime,
                    globalMaxBudget: maxTotalBudget
                ) {
                    responseData = data
                    resolvedBy = resolver.address
                    break
                }
            }

            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            if let response = responseData {
                // Downstream DNS-over-TCP: Do NOT truncate to EDNS0 UDP payload limit.
                // Transmit the full DNS response up to maxDnsMessageSize (16KB) over TCP.
                os_log(
                    .info,
                    log: Self.log,
                    "[RESOLVED-TCP] %{public}@ via %{public}@ in %{public}dms (%{public}ld bytes)",
                    domain ?? "unknown",
                    resolvedBy ?? "upstream",
                    elapsedMs,
                    response.count
                )
                connection.sendResponse(response)

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
                    "[SERVFAIL-TCP] %{public}@ failed all upstreams after %{public}dms -> Returning SERVFAIL",
                    domain ?? "unknown",
                    elapsedMs
                )
                if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: requestData) {
                    connection.sendResponse(servFail)
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

    /// Checks if a DNS response has the TC (Truncated) flag set.
    /// TC flag is bit 1 (0x02) of the flags byte (byte index 2).
    private static func isTruncatedResponse(_ response: Data) -> Bool {
        return response.count >= 3 && (response[2] & 0x02) != 0
    }

    /// Queries an upstream DNS resolver over TCP with proper DNS-over-TCP framing.
    /// Implements two-byte length prefix, partial read/write handling, and response validation.
    private static func queryUpstreamTcp(
        resolver: UpstreamResolver,
        requestData: Data,
        timeoutSeconds: Double
    ) -> Data? {
        let family: Int32 = resolver.isIPv6 ? AF_INET6 : AF_INET
        let sock = socket(family, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        let sec = time_t(floor(timeoutSeconds))
        let usec = suseconds_t((timeoutSeconds - floor(timeoutSeconds)) * 1_000_000)
        var tv = timeval(tv_sec: sec, tv_usec: usec)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Connect TCP socket to upstream endpoint
        var connectRes: Int32
        if resolver.isIPv6 {
            var addr6 = sockaddr_in6()
            addr6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr6.sin6_family = sa_family_t(AF_INET6)
            addr6.sin6_port = in_port_t(resolver.port).bigEndian
            guard inet_pton(AF_INET6, resolver.address, &addr6.sin6_addr) == 1 else { return nil }

            connectRes = withUnsafePointer(to: &addr6) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var addr4 = sockaddr_in()
            addr4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr4.sin_family = sa_family_t(AF_INET)
            addr4.sin_port = in_port_t(resolver.port).bigEndian
            guard inet_pton(AF_INET, resolver.address, &addr4.sin_addr) == 1 else { return nil }

            connectRes = withUnsafePointer(to: &addr4) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard connectRes == 0 else { return nil }

        // Prevent SIGPIPE on upstream socket writes (extension has no SIGPIPE handler)
        var nosigpipe: Int32 = 1
        let setNosigpipeResult = setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        guard setNosigpipeResult == 0 else {
            os_log(.error, log: Self.log, "Failed to set SO_NOSIGPIPE on upstream TCP socket: errno %{public}d", errno)
            return nil
        }

        // DNS-over-TCP framing: 2-byte length prefix (network byte order) + DNS message
        var lengthPrefix = Data()
        var length = UInt16(requestData.count).bigEndian
        lengthPrefix.append(Data(bytes: &length, count: 2))

        // Send length prefix + DNS query (handle partial writes)
        let queryFrame = lengthPrefix + requestData
        var querySent = 0
        while querySent < queryFrame.count {
            let sent = queryFrame.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.advanced(by: querySent) else { return 0 }
                return send(sock, base, queryFrame.count - querySent, 0)
            }
            guard sent > 0 else { return nil }
            querySent += sent
        }

        // Read response: first 2 bytes = length
        var lenBuf = Data(count: 2)
        var lenRead = 0
        while lenRead < 2 {
            let read = lenBuf.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress?.advanced(by: lenRead) else { return 0 }
                return recv(sock, base, 2 - lenRead, 0)
            }
            guard read > 0 else { return nil } // Connection closed prematurely
            lenRead += read
        }

        let responseLength = Int(UInt16(bigEndian: lenBuf.withUnsafeBytes { $0.load(as: UInt16.self) }))

        // Sanity check: reasonable DNS message size (max 64KB per RFC, but limit to 16KB)
        guard responseLength >= 12 && responseLength <= 16384 else {
            os_log(.error, log: Self.log, "Invalid TCP DNS response length: %{public}d", responseLength)
            return nil
        }

        // Read exact response length (handle partial reads)
        var responseBuf = Data(count: responseLength)
        var totalRead = 0
        while totalRead < responseLength {
            let read = responseBuf.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress?.advanced(by: totalRead) else { return 0 }
                return recv(sock, base, responseLength - totalRead, 0)
            }
            guard read > 0 else { return nil } // Connection closed prematurely
            totalRead += read
        }

        // Validate response
        guard responseBuf.count >= 12 else { return nil }

        // 1. Transaction ID matching (first 2 bytes)
        let reqTxId = requestData.subdata(in: 0..<2)
        let respTxId = responseBuf.subdata(in: 0..<2)
        guard reqTxId == respTxId else {
            os_log(.error, log: Self.log, "TCP response transaction ID mismatch for %{public}@", resolver.address)
            return nil
        }

        // 2. Response QR bit check (Flags byte 2, bit 7 must be 1)
        let flagsByte = responseBuf[2]
        guard (flagsByte & 0x80) != 0 else {
            os_log(.error, log: Self.log, "TCP response QR bit not set for %{public}@", resolver.address)
            return nil
        }

        return responseBuf
    }

    /// Queries an upstream DNS resolver over a dedicated connected UDP socket.
    /// Strictly validates:
    /// 1. Transaction ID matching (RFC 1035 §4.1.1, RFC 5452)
    /// 2. Response QR bit set (Flags byte 2, bit 7 == 1)
    /// 3. Kernel-level destination binding via connect() to prevent rogue datagrams
    /// 4. TC (Truncated) flag - if set, retries over TCP
    ///
    /// - Parameters:
    ///   - resolver: The upstream DNS resolver to query.
    ///   - requestData: The DNS query to send.
    ///   - timeoutSeconds: Per-resolver timeout for the UDP attempt.
    ///   - globalStartTime: The global query start time (CFAbsoluteTime) for budget tracking.
    ///   - globalMaxBudget: The global maximum budget in seconds.
    public static func queryUpstream(
        resolver: UpstreamResolver,
        requestData: Data,
        timeoutSeconds: Double,
        globalStartTime: CFAbsoluteTime,
        globalMaxBudget: Double
    ) -> Data? {
        // First attempt: UDP
        guard let udpResponse = queryUpstreamUdp(resolver: resolver, requestData: requestData, timeoutSeconds: timeoutSeconds) else {
            return nil
        }

        // Check for TC (Truncated) flag - bit 1 of flags byte
        if isTruncatedResponse(udpResponse) {
            os_log(.info, log: Self.log, "Upstream UDP response truncated (TC=1) for %{public}@, retrying over TCP", resolver.address)
            // Pass the remaining time within the global budget, not the full per-resolver timeout.
            let elapsed = CFAbsoluteTimeGetCurrent() - globalStartTime
            let remainingForTcp = max(0.2, globalMaxBudget - elapsed)
            return queryUpstreamTcp(resolver: resolver, requestData: requestData, timeoutSeconds: remainingForTcp)
        }

        return udpResponse
    }

    /// UDP-only upstream query implementation (extracted for TCP fallback reuse)
    private static func queryUpstreamUdp(
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

// MARK: - Downstream TCP Client Connection (RFC 7766)

/// Explicit socket ownership wrapper guaranteeing the underlying file descriptor
/// is closed strictly once across all promotion, timeout, disconnect, and shutdown paths.
fileprivate final class SocketOwner {
    let fd: Int32
    private var isClosed = false
    private var lock = os_unfair_lock_s()

    init(fd: Int32) {
        self.fd = fd
    }

    /// Closes the underlying file descriptor exactly once.
    /// Returns true if this call performed the close, false if it was already closed.
    @discardableResult
    func close() -> Bool {
        os_unfair_lock_lock(&lock)
        if isClosed {
            os_unfair_lock_unlock(&lock)
            return false
        }
        isClosed = true
        os_unfair_lock_unlock(&lock)

        Darwin.close(fd)
        return true
    }

    var isSocketClosed: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isClosed
    }
}

/// Manages an individual downstream DNS-over-TCP client connection per RFC 7766.
/// Handles 2-byte big-endian length prefix framing, partial reads/writes,
/// connection limits, pipelined requests, serialized writes, and idle timeout.
fileprivate final class TcpClientConnection: Hashable {
    let id: UInt64
    let socketOwner: SocketOwner
    var clientSocket: Int32 { socketOwner.fd }
    private weak var resolver: AuraLocalDNSResolver?
    private let connectionQueue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var idleTimer: DispatchSourceTimer?
    private var readBuffer = Data()
    private var isClosed = false
    private var closeLock = os_unfair_lock_s()

    static func == (lhs: TcpClientConnection, rhs: TcpClientConnection) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: UInt64, socketOwner: SocketOwner, resolver: AuraLocalDNSResolver, readBuffer: Data = Data()) {
        self.id = id
        self.socketOwner = socketOwner
        self.resolver = resolver
        self.connectionQueue = DispatchQueue(
            label: "com.thejatech.aura.dnsresolver.tcpclient.\(id)",
            qos: .userInitiated
        )
        self.readBuffer = readBuffer
    }

    func start() {
        // Prevent SIGPIPE on broken client connections
        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking
        let flags = fcntl(clientSocket, F_GETFL, 0)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        let owner = socketOwner
        let source = DispatchSource.makeReadSource(fileDescriptor: clientSocket, queue: connectionQueue)
        source.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        source.setCancelHandler {
            owner.close()
        }
        source.resume()
        readSource = source

        setupIdleTimer()
    }

    private func setupIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: connectionQueue)
        timer.schedule(deadline: .now() + AuraLocalDNSResolver.tcpIdleTimeoutSeconds)
        timer.setEventHandler { [weak self] in
            self?.close()
        }
        timer.resume()
        idleTimer = timer
    }

    private func resetIdleTimer() {
        idleTimer?.schedule(deadline: .now() + AuraLocalDNSResolver.tcpIdleTimeoutSeconds)
    }

    private func handleReadable() {
        os_unfair_lock_lock(&closeLock)
        guard !isClosed else {
            os_unfair_lock_unlock(&closeLock)
            return
        }
        os_unfair_lock_unlock(&closeLock)

        var chunk = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(clientSocket, &chunk, chunk.count, 0)

        if bytesRead > 0 {
            resetIdleTimer()
            readBuffer.append(chunk, count: bytesRead)

            // Bounded safety limit: 64KB max buffer to prevent unbounded memory growth
            if readBuffer.count > 65536 {
                os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "TcpClientConnection"), "TCP client [%{public}llu] read buffer exceeded 64KB limit, closing", id)
                close()
                return
            }

            processReadBuffer()
        } else if bytesRead == 0 {
            // Client closed connection cleanly (FIN)
            close()
        } else {
            let err = errno
            if err != EWOULDBLOCK && err != EAGAIN && err != EINTR {
                close()
            }
        }
    }

    fileprivate func processReadBuffer() {
        while readBuffer.count >= 2 {
            let msgLen = Int(UInt16(readBuffer[0]) << 8 | UInt16(readBuffer[1]))
            if msgLen < 12 || msgLen > AuraLocalDNSResolver.maxDnsMessageSize {
                os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "TcpClientConnection"), "TCP client [%{public}llu] received invalid DNS frame length: %{public}d, closing", id, msgLen)
                close()
                return
            }
            if readBuffer.count < 2 + msgLen {
                // Incomplete frame, wait for additional segments
                break
            }
            let queryData = readBuffer.subdata(in: 2..<(2 + msgLen))
            readBuffer.removeSubrange(0..<(2 + msgLen))

            // Forward complete request frame to resolver
            resolver?.processTcpQuery(requestData: queryData, connection: self)
        }
    }

    /// Process pipelined frames transferred during promotion from pending state
    fileprivate func processPipelinedData() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.closeLock)
            guard !self.isClosed else {
                os_unfair_lock_unlock(&self.closeLock)
                return
            }
            os_unfair_lock_unlock(&self.closeLock)
            self.processReadBuffer()
        }
    }

    func sendResponse(_ responseData: Data) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.closeLock)
            guard !self.isClosed else {
                os_unfair_lock_unlock(&self.closeLock)
                return
            }
            os_unfair_lock_unlock(&self.closeLock)

            guard responseData.count <= AuraLocalDNSResolver.maxDnsMessageSize else {
                os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "TcpClientConnection"), "TCP client [%{public}llu] response size %{public}ld exceeds safety limit", self.id, responseData.count)
                return
            }

            var frame = Data()
            var lenBig = UInt16(responseData.count).bigEndian
            frame.append(Data(bytes: &lenBig, count: 2))
            frame.append(responseData)

            var totalSent = 0
            while totalSent < frame.count {
                let sent = frame.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress?.advanced(by: totalSent) else { return -1 }
                    return send(self.clientSocket, base, frame.count - totalSent, 0)
                }

                if sent > 0 {
                    totalSent += sent
                } else if sent < 0 {
                    let err = errno
                    if err == EINTR { continue }
                    if err == EWOULDBLOCK || err == EAGAIN {
                        var pfd = pollfd(fd: self.clientSocket, events: Int16(POLLOUT), revents: 0)
                        let pollRes = poll(&pfd, 1, 3000)
                        if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                            continue
                        }
                    }
                    self.close()
                    return
                } else {
                    self.close()
                    return
                }
            }
            self.resetIdleTimer()
        }
    }

    func close() {
        os_unfair_lock_lock(&closeLock)
        if isClosed {
            os_unfair_lock_unlock(&closeLock)
            return
        }
        isClosed = true
        os_unfair_lock_unlock(&closeLock)

        idleTimer?.setEventHandler {}
        idleTimer?.cancel()
        idleTimer = nil

        if let source = readSource {
            source.cancel()
            readSource = nil
        } else {
            socketOwner.close()
        }

        resolver?.removeClientConnection(self)
    }
}

/// Manages a pending TCP client connection that hasn't yet sent a complete DNS frame.
/// Has a shorter timeout (3 seconds) to prevent resource exhaustion from incomplete connections.
fileprivate final class PendingTcpClient: Hashable {
    private enum State {
        case pending
        case promoted
        case closed
    }

    let id: UInt64
    let socketOwner: SocketOwner
    var clientSocket: Int32 { socketOwner.fd }
    private weak var resolver: AuraLocalDNSResolver?
    private let connectionQueue: DispatchQueue
    private var readSource: DispatchSourceRead?
    private var pendingTimer: DispatchSourceTimer?
    private var readBuffer = Data()
    private var state: State = .pending
    private var stateLock = os_unfair_lock_s()

    static func == (lhs: PendingTcpClient, rhs: PendingTcpClient) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: UInt64, socketOwner: SocketOwner, resolver: AuraLocalDNSResolver) {
        self.id = id
        self.socketOwner = socketOwner
        self.resolver = resolver
        self.connectionQueue = DispatchQueue(
            label: "com.thejatech.aura.dnsresolver.tcpclient.pending.\(id)",
            qos: .userInitiated
        )
    }

    func start() {
        // Prevent SIGPIPE on broken client connections
        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking
        let flags = fcntl(clientSocket, F_GETFL, 0)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: clientSocket, queue: connectionQueue)
        source.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        source.resume()
        readSource = source

        setupPendingTimer()
    }

    private func setupPendingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: connectionQueue)
        timer.schedule(deadline: .now() + AuraLocalDNSResolver.tcpPendingTimeoutSeconds)
        timer.setEventHandler { [weak self] in
            self?.handlePendingTimeout()
        }
        timer.resume()
        pendingTimer = timer
    }

    private func handlePendingTimeout() {
        os_unfair_lock_lock(&stateLock)
        guard state == .pending else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        state = .closed
        os_unfair_lock_unlock(&stateLock)

        pendingTimer?.setEventHandler {}
        pendingTimer?.cancel()
        pendingTimer = nil

        readSource?.cancel()
        readSource = nil

        socketOwner.close()

        resolver?.removePendingConnection(self)
    }

    private func handleReadable() {
        os_unfair_lock_lock(&stateLock)
        guard state == .pending else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        os_unfair_lock_unlock(&stateLock)

        var chunk = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(clientSocket, &chunk, chunk.count, 0)

        if bytesRead > 0 {
            readBuffer.append(chunk, count: bytesRead)

            // Bounded safety limit: 64KB max buffer
            if readBuffer.count > 65536 {
                os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "PendingTcpClient"), "Pending TCP client [%{public}llu] read buffer exceeded 64KB limit, closing", id)
                close()
                return
            }

            processReadBuffer()
        } else if bytesRead == 0 {
            // Client closed connection cleanly (FIN)
            close()
        } else {
            let err = errno
            if err != EWOULDBLOCK && err != EAGAIN && err != EINTR {
                close()
            }
        }
    }

    fileprivate func processReadBuffer() {
        while readBuffer.count >= 2 {
            let msgLen = Int(UInt16(readBuffer[0]) << 8 | UInt16(readBuffer[1]))
            if msgLen < 12 || msgLen > AuraLocalDNSResolver.maxDnsMessageSize {
                os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "PendingTcpClient"), "Pending TCP client [%{public}llu] received invalid DNS frame length: %{public}d, closing", id, msgLen)
                close()
                return
            }
            if readBuffer.count < 2 + msgLen {
                // Incomplete frame, wait for additional segments
                break
            }
            let queryData = readBuffer.subdata(in: 2..<(2 + msgLen))
            readBuffer.removeSubrange(0..<(2 + msgLen))

            // Valid complete DNS frame received - promote to active connection
            promoteToActive(initialQuery: queryData)
            return
        }
    }

    private func promoteToActive(initialQuery: Data) {
        os_unfair_lock_lock(&stateLock)
        guard state == .pending else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        state = .promoted
        os_unfair_lock_unlock(&stateLock)

        // Invalidate and cancel pending timer BEFORE active ownership begins
        pendingTimer?.setEventHandler {}
        pendingTimer?.cancel()
        pendingTimer = nil

        // Cancel pending readSource without closing the transferred socketOwner
        readSource?.cancel()
        readSource = nil

        guard let resolver = self.resolver, resolver.isRunning else {
            socketOwner.close()
            self.resolver?.removePendingConnection(self)
            return
        }

        // Transfer remaining read buffer
        let remainingBuffer = self.readBuffer
        self.readBuffer = Data()

        // Create active connection taking ownership of socketOwner and remaining buffer
        let activeConn = TcpClientConnection(
            id: id,
            socketOwner: socketOwner,
            resolver: resolver,
            readBuffer: remainingBuffer
        )

        // Atomically transition resolver collections
        if !resolver.promotePendingToActive(self, activeConn) {
            activeConn.close()
            return
        }

        // Start active connection
        activeConn.start()

        // Process the initial query that completed the promotion
        resolver.processTcpQuery(requestData: initialQuery, connection: activeConn)

        // Process any pipelined data that was buffered
        if !remainingBuffer.isEmpty {
            activeConn.processPipelinedData()
        }
    }

    func close() {
        os_unfair_lock_lock(&stateLock)
        guard state == .pending else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        state = .closed
        os_unfair_lock_unlock(&stateLock)

        pendingTimer?.setEventHandler {}
        pendingTimer?.cancel()
        pendingTimer = nil

        readSource?.cancel()
        readSource = nil

        socketOwner.close()

        resolver?.removePendingConnection(self)
    }
}
