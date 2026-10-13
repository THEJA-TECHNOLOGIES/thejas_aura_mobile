import Foundation
import Network
import os.log

/// Lightweight native UDP DNS resolver running inside the AuraTunnel extension.
/// Binds to 127.0.0.1:53 via POSIX socket, intercepts system DNS queries,
/// evaluates them against local rules, and forwards permitted queries to Quad9.
public final class AuraLocalDNSResolver {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraLocalDNSResolver")

    private let engine: AuraDNSEngine
    private let upstreamAddress = "9.9.9.9"
    private let upstreamPort: UInt16 = 53
    private var serverSocket: Int32 = -1
    private var dispatchSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.thejatech.aura.dnsresolver", qos: .userInitiated)
    private var isRunning = false

    public init(engine: AuraDNSEngine) {
        self.engine = engine
    }

    /// Starts listening on 127.0.0.1:53.
    public func start() -> Bool {
        guard !isRunning else { return true }

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            os_log(.error, log: Self.log, "Failed to create UDP socket: errno %{public}d", errno)
            return false
        }

        // Enable SO_REUSEADDR
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(53).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let bindErr = errno
            os_log(.error, log: Self.log, "Failed to bind UDP socket to 127.0.0.1:53: errno %{public}d (%{public}s)", bindErr, strerror(bindErr))
            close(sock)
            return false
        }

        serverSocket = sock
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleIncomingQuery()
        }
        source.setCancelHandler {
            close(sock)
        }
        source.resume()
        dispatchSource = source

        os_log(.info, log: Self.log, "Local DNS resolver successfully bound to 127.0.0.1:53")
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

    // MARK: - Query Handling

    private func handleIncomingQuery() {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        var buffer = [UInt8](repeating: 0, count: 4096)

        let bytesRead = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(serverSocket, &buffer, buffer.count, 0, sa, &addrLen)
            }
        }

        guard bytesRead > 0 else { return }
        let requestData = Data(buffer[0..<bytesRead])

        // Parse Question
        if let question = AuraDNSEngine.parseQuestion(data: requestData) {
            let evaluation = engine.evaluate(domain: question.name)

            switch evaluation {
            case .blocked(let ruleDomain):
                os_log(.info, log: Self.log, "[BLOCK] Intercepted %{public}@ (matched rule: %{public}@, type: %{public}u) -> Synthesizing 0.0.0.0/::", question.name, ruleDomain, question.qType)
                if let response = AuraDNSEngine.synthesizeBlockedResponse(requestData: requestData) {
                    sendResponse(response, to: clientAddr, addrLen: addrLen)
                    return
                }
            case .allowed(let ruleDomain):
                let ruleStr = ruleDomain ?? "none"
                os_log(.info, log: Self.log, "[ALLOW] Query %{public}@ permitted (rule: %{public}@) -> Forwarding upstream", question.name, ruleStr)
            }
        } else {
            os_log(.default, log: Self.log, "Received unparseable DNS payload (%{public}ld bytes) -> Forwarding upstream", requestData.count)
        }

        // Forward allowed/unmatched queries to upstream Quad9
        forwardUpstream(requestData: requestData, clientAddr: clientAddr, addrLen: addrLen)
    }

    private func sendResponse(_ response: Data, to clientAddr: sockaddr_in, addrLen: socklen_t) {
        var addr = clientAddr
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(serverSocket, baseAddress, response.count, 0, sa, addrLen)
                }
            }
        }
    }

    // MARK: - Upstream Resolution (Quad9 9.9.9.9)

    private func forwardUpstream(requestData: Data, clientAddr: sockaddr_in, addrLen: socklen_t) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let upstreamSock = socket(AF_INET, SOCK_DGRAM, 0)
            guard upstreamSock >= 0 else {
                os_log(.error, log: Self.log, "Failed to create upstream UDP socket: errno %{public}d", errno)
                if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: requestData) {
                    self.sendResponse(servFail, to: clientAddr, addrLen: addrLen)
                }
                return
            }
            defer { close(upstreamSock) }

            // Set socket timeout to 3 seconds
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            setsockopt(upstreamSock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var serverAddr = sockaddr_in()
            serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            serverAddr.sin_family = sa_family_t(AF_INET)
            serverAddr.sin_port = in_port_t(self.upstreamPort).bigEndian
            serverAddr.sin_addr.s_addr = inet_addr(self.upstreamAddress)

            let sent = requestData.withUnsafeBytes { raw in
                withUnsafePointer(to: &serverAddr) { saPtr in
                    saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        sendto(upstreamSock, raw.baseAddress, requestData.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard sent > 0 else {
                os_log(.error, log: Self.log, "Failed to send query upstream to %{public}@: errno %{public}d", self.upstreamAddress, errno)
                if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: requestData) {
                    self.sendResponse(servFail, to: clientAddr, addrLen: addrLen)
                }
                return
            }

            var responseBuffer = [UInt8](repeating: 0, count: 4096)
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let received = withUnsafeMutablePointer(to: &fromAddr) { saPtr in
                saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(upstreamSock, &responseBuffer, responseBuffer.count, 0, sa, &fromLen)
                }
            }

            if received > 0 {
                let upstreamResponse = Data(responseBuffer[0..<received])
                self.sendResponse(upstreamResponse, to: clientAddr, addrLen: addrLen)
            } else {
                // Upstream timeout or failure -> Return ServFail
                os_log(.error, log: Self.log, "Upstream DNS query timed out or failed to receive response -> Returning SERVFAIL")
                if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: requestData) {
                    self.sendResponse(servFail, to: clientAddr, addrLen: addrLen)
                }
            }
        }
    }
}
