import Foundation
import Network
import os.log

/// Upstream DNS resolver for macOS DNS proxy.
/// Uses Network framework (NWConnection) for upstream DNS resolution.
/// BSD sockets do NOT work from macOS System Extensions — NWConnection is required.
final class UpstreamResolver {
    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "UpstreamResolver")

    struct Resolver {
        let address: String
        let port: UInt16
        let isIPv6: Bool

        init(address: String, port: UInt16 = 53, isIPv6: Bool = false) {
            self.address = address
            self.port = port
            self.isIPv6 = isIPv6
        }
    }

    static let upstreams: [Resolver] = [
        Resolver(address: "9.9.9.9", port: 53, isIPv6: false),           // Primary Quad9
        Resolver(address: "1.1.1.1", port: 53, isIPv6: false),           // Fallback Cloudflare
        Resolver(address: "8.8.8.8", port: 53, isIPv6: false),           // Fallback Google
        Resolver(address: "2620:fe::fe", port: 53, isIPv6: true),       // Quad9 IPv6
        Resolver(address: "2606:4700:4700::1111", port: 53, isIPv6: true) // Cloudflare IPv6
    ]

    /// Forward a query through all upstreams with time budget.
    static func resolveUpstream(
        requestData: Data,
        maxTotalBudget: Double = 5.0
    ) -> Data? {
        let reqTxId = requestData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log(.info, log: Self.log, "resolveUpstream: txId=%{public}hu budget=%.2fs upstreams=%{public}d", reqTxId, maxTotalBudget, upstreams.count)

        var responseData: Data?

        for resolver in upstreams {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            if timeElapsed >= maxTotalBudget {
                os_log(.info, log: Self.log, "resolveUpstream: txId=%{public}hu budget exhausted after %.2fs", reqTxId, timeElapsed)
                break
            }

            let remainingBudget = max(1.0, min(3.0, maxTotalBudget - timeElapsed))
            os_log(.debug, log: Self.log, "resolveUpstream: trying resolver=%{public}@ remaining=%.2fs", resolver.address, remainingBudget)
            if let data = queryUpstream(
                resolver: resolver,
                requestData: requestData,
                timeoutSeconds: remainingBudget
            ) {
                responseData = data
                os_log(.info, log: Self.log, "resolveUpstream: txId=%{public}hu SUCCESS via %{public}@ in %.2fs", reqTxId, resolver.address, CFAbsoluteTimeGetCurrent() - startTime)
                break
            } else {
                os_log(.debug, log: Self.log, "resolveUpstream: resolver=%{public}@ failed", resolver.address)
            }
        }

        if responseData == nil {
            os_log(.error, log: Self.log, "resolveUpstream: txId=%{public}hu ALL upstreams failed after %.2fs", reqTxId, CFAbsoluteTimeGetCurrent() - startTime)
        }

        return responseData
    }

    /// Queries an upstream resolver over UDP with TCP fallback on truncation (TC=1).
    /// Uses NWConnection (Network framework) which works from System Extensions.
    private static func queryUpstream(
        resolver: Resolver,
        requestData: Data,
        timeoutSeconds: Double
    ) -> Data? {
        let reqTxId = requestData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        os_log(.debug, log: Self.log, "queryUpstream: resolver=%{public}@ txId=%{public}hu timeout=%.2fs",
               resolver.address, reqTxId, timeoutSeconds)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var completed = false
        let lock = NSLock()

        func finish(_ data: Data?) {
            lock.lock()
            if !completed {
                completed = true
                result = data
            }
            lock.unlock()
            semaphore.signal()
        }

        let host = NWEndpoint.Host(resolver.address)
        let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(integerLiteral: resolver.port))

        let connection = NWConnection(to: endpoint, using: .udp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                os_log(.debug, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ connection ready", resolver.address)
            case .failed(let error):
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ connection failed: %{public}@", resolver.address, error.localizedDescription)
                finish(nil)
            case .cancelled:
                break
            case .waiting(let error):
                os_log(.debug, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ waiting: %{public}@", resolver.address, error.localizedDescription)
            case .setup:
                break
            case .preparing:
                break
            @unknown default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global())

        // For UDP, send immediately without waiting for .ready (UDP is connectionless)
        connection.send(content: requestData, completion: .contentProcessed({ sendError in
            if let sendError = sendError {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ send failed: %{public}@", resolver.address, sendError.localizedDescription)
                finish(nil)
                return
            }
            os_log(.debug, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ send success", resolver.address)
        }))

        // Set up receive immediately
        connection.receive(minimumIncompleteLength: 12, maximumLength: 65536) { data, _, _, recvError in
            if let recvError = recvError {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ receive error: %{public}@", resolver.address, recvError.localizedDescription)
                finish(nil)
                return
            }
            guard let data = data, data.count >= 12 else {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ received insufficient data: %{public}ld bytes", resolver.address, data?.count ?? 0)
                finish(nil)
                return
            }

            // Validate TXID
            let respTxId = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            guard reqTxId == respTxId else {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ TXID mismatch req=%{public}hu resp=%{public}hu",
                       resolver.address, reqTxId, respTxId)
                finish(nil)
                return
            }

            // Validate QR bit
            let flagsByte = data[2]
            guard (flagsByte & 0x80) != 0 else {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ QR bit not set flags=0x%{public}02x", resolver.address, flagsByte)
                finish(nil)
                return
            }

            os_log(.debug, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ receive success %{public}d bytes", resolver.address, data.count)
            finish(data)
        }

        // Timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
            if !completed {
                os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ timeout after %.2fs", resolver.address, timeoutSeconds)
                finish(nil)
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 0.5)
        if waitResult == .timedOut {
            os_log(.error, log: Self.log, "queryUpstreamUdp: resolver=%{public}@ semaphore timed out", resolver.address)
            connection.cancel()
            return nil
        }

        let udpResponse = result

        // Check for TC (truncated) flag — retry over TCP
        if let udpResponse = udpResponse, isTruncatedResponse(udpResponse) {
            os_log(.info, log: Self.log, "Upstream UDP response truncated (TC=1) for %{public}@, retrying over TCP", resolver.address)
            return queryUpstreamTcp(resolver: resolver, requestData: requestData, timeoutSeconds: timeoutSeconds)
        }

        os_log(.debug, log: Self.log, "queryUpstream: resolver=%{public}@ UDP success (%{public}ld bytes)", resolver.address, udpResponse?.count ?? 0)
        return udpResponse
    }

    /// TCP upstream query with RFC 7766 framing using NWConnection.
    private static func queryUpstreamTcp(
        resolver: Resolver,
        requestData: Data,
        timeoutSeconds: Double
    ) -> Data? {
        let reqTxId = requestData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        os_log(.debug, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ txId=%{public}hu timeout=%.2fs", resolver.address, reqTxId, timeoutSeconds)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        var completed = false
        let lock = NSLock()

        func finish(_ data: Data?) {
            lock.lock()
            if !completed {
                completed = true
                result = data
            }
            lock.unlock()
            semaphore.signal()
        }

        let host = NWEndpoint.Host(resolver.address)
        let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(integerLiteral: resolver.port))

        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                os_log(.debug, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ connection ready", resolver.address)

                // DNS-over-TCP framing: send length prefix + query
                var length = UInt16(requestData.count).bigEndian
                let lengthPrefix = Data(bytes: &length, count: 2)
                let queryFrame = lengthPrefix + requestData

                connection.send(content: queryFrame, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ send failed: %{public}@", resolver.address, sendError.localizedDescription)
                        finish(nil)
                        return
                    }
                    os_log(.debug, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ send success %{public}d bytes", resolver.address, queryFrame.count)
                }))

                // Read response length (2 bytes)
                connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { lenData, _, _, lenError in
                    if let lenError = lenError {
                        os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ receive length error: %{public}@", resolver.address, lenError.localizedDescription)
                        finish(nil)
                        return
                    }
                    guard let lenData = lenData, lenData.count >= 2 else {
                        os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ received insufficient length bytes: %{public}ld", resolver.address, lenData?.count ?? 0)
                        finish(nil)
                        return
                    }

                    let responseLength = Int(UInt16(bigEndian: lenData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self) }))
                    guard responseLength >= 12 && responseLength <= 16384 else {
                        os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ invalid response length=%{public}d", resolver.address, responseLength)
                        finish(nil)
                        return
                    }

                    // Read exact response body
                    connection.receive(minimumIncompleteLength: responseLength, maximumLength: responseLength) { bodyData, _, _, bodyError in
                        if let bodyError = bodyError {
                            os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ receive body error: %{public}@", resolver.address, bodyError.localizedDescription)
                            finish(nil)
                            return
                        }
                        guard let bodyData = bodyData, bodyData.count >= 12 else {
                            os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ received insufficient body: %{public}ld bytes", resolver.address, bodyData?.count ?? 0)
                            finish(nil)
                            return
                        }

                        // Validate TXID
                        let respTxId = bodyData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                        guard reqTxId == respTxId else {
                            os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ TXID mismatch", resolver.address)
                            finish(nil)
                            return
                        }

                        // Validate QR bit
                        let flagsByte = bodyData[2]
                        guard (flagsByte & 0x80) != 0 else {
                            os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ QR bit not set", resolver.address)
                            finish(nil)
                            return
                        }

                        os_log(.debug, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ success %{public}d bytes", resolver.address, bodyData.count)
                        finish(bodyData)
                    }
                }

            case .failed(let error):
                os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ connection failed: %{public}@", resolver.address, error.localizedDescription)
                finish(nil)
            case .cancelled:
                break
            case .waiting(let error):
                os_log(.debug, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ waiting: %{public}@", resolver.address, error.localizedDescription)
            case .setup:
                break
            case .preparing:
                break
            @unknown default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global())

        // Timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
            if !completed {
                os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ timeout after %.2fs", resolver.address, timeoutSeconds)
                finish(nil)
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 0.5)
        if waitResult == .timedOut {
            os_log(.error, log: Self.log, "queryUpstreamTcp: resolver=%{public}@ semaphore timed out", resolver.address)
            connection.cancel()
            return nil
        }

        return result
    }

    /// Checks if a DNS response has the TC (Truncated) flag set.
    static func isTruncatedResponse(_ response: Data) -> Bool {
        return response.count >= 3 && (response[2] & 0x02) != 0
    }
}
