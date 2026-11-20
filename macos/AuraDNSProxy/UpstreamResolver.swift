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
        Resolver(address: "9.9.9.9", port: 53, isIPv6: false),
        Resolver(address: "1.1.1.1", port: 53, isIPv6: false),
        Resolver(address: "8.8.8.8", port: 53, isIPv6: false),
        Resolver(address: "2620:fe::fe", port: 53, isIPv6: true),
        Resolver(address: "2606:4700:4700::1111", port: 53, isIPv6: true)
    ]

    // MARK: - Public API

    static func resolveUpstream(requestData: Data, maxTotalBudget: Double = 2.0) -> Data? {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard requestData.count >= 2 else {
            os_log(.error, log: log, "requestData too small (%{public}ld bytes)", requestData.count)
            return nil
        }
        let requestTxId = UInt16(requestData[0]) << 8 | UInt16(requestData[1])

        for resolver in upstreams {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            guard elapsed < maxTotalBudget else {
                os_log(.info, log: log, "Total budget exhausted before trying %{public}@", resolver.address)
                break
            }

            let remainingBudget = max(maxTotalBudget - elapsed, 0.5)

            if let response = resolveUdp(requestData: requestData,
                                         requestTxId: requestTxId,
                                         resolver: resolver,
                                         timeout: remainingBudget) {
                return response
            }

            let remainingAfterUdp = max(maxTotalBudget - (CFAbsoluteTimeGetCurrent() - startTime), 0.5)
            if remainingAfterUdp > 0.5 {
                if let response = resolveTcp(requestData: requestData,
                                             requestTxId: requestTxId,
                                             resolver: resolver,
                                             timeout: remainingAfterUdp) {
                    return response
                }
            }
        }

        os_log(.error, log: log, "All upstreams failed after %.2fs", CFAbsoluteTimeGetCurrent() - startTime)
        return nil
    }

    // MARK: - UDP Resolution

    private static func resolveUdp(requestData: Data,
                                   requestTxId: UInt16,
                                   resolver: Resolver,
                                   timeout: Double) -> Data? {
        os_log(.debug, log: log, "UDP query to %{public}@:%{public}d txId=0x%{04X}",
               resolver.address, resolver.port, requestTxId)

        let endpoint = NWEndpoint.hostPort(host: .name(resolver.address, nil),
                                           port: NWEndpoint.Port(integerLiteral: resolver.port))

        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)

        let lock = NSLock()
        var completed = false
        var result: Data?

        let connectionQueue = DispatchQueue(label: "com.thejatech.aura.upstreamResolver.\(resolver.address)", qos: .userInitiated)

        let semaphore = DispatchSemaphore(value: 0)

        var timeoutTimer: DispatchSourceTimer?

        connection.stateUpdateHandler = { [weak connection] (state: NWConnection.State) in
            guard let connection = connection else { return }

            switch state {
            case .ready:
                os_log(.debug, log: log, "UDP %{public}@ ready", resolver.address)
                timeoutTimer?.cancel()
                timeoutTimer = nil

                guard !tryComplete(&completed, lock: lock) else { return }

                connection.send(content: requestData, completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        os_log(.error, log: log, "UDP %{public}@ send error: %{public}@", resolver.address, sendError.localizedDescription)
                        signalOnce(&completed, lock: lock, semaphore: semaphore)
                        return
                    }

                    os_log(.debug, log: log, "UDP %{public}@ send complete", resolver.address)

                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, context, isComplete, receiveError in
                        if let receiveError = receiveError {
                            os_log(.error, log: log, "UDP %{public}@ receive error: %{public}@", resolver.address, receiveError.localizedDescription)
                            signalOnce(&completed, lock: lock, semaphore: semaphore)
                            return
                        }

                        guard let data = data, !data.isEmpty else {
                            os_log(.default, log: log, "UDP %{public}@ received empty data", resolver.address)
                            signalOnce(&completed, lock: lock, semaphore: semaphore)
                            return
                        }

                        if data.count >= 2 {
                            let responseTxId = UInt16(data[0]) << 8 | UInt16(data[1])
                            let qrBit = (data[2] & 0x80) >> 7
                            if responseTxId == requestTxId && qrBit == 1 {
                                os_log(.debug, log: log, "UDP %{public}@ valid response (%{public}ld bytes, txId=0x%{04X})",
                                       resolver.address, data.count, responseTxId)
                                result = data
                            } else {
                                os_log(.error, log: log, "UDP %{public}@ invalid response: txId=0x%{04X} expected 0x%{04X}, qr=%{public}d",
                                       resolver.address, responseTxId, requestTxId, qrBit)
                            }
                        } else {
                            os_log(.default, log: log, "UDP %{public}@ response too small (%{public}ld bytes)", resolver.address, data.count)
                        }

                        signalOnce(&completed, lock: lock, semaphore: semaphore)
                    }
                })

            case .failed(let error):
                os_log(.error, log: log, "UDP %{public}@ failed: %{public}@", resolver.address, error.localizedDescription)
                signalOnce(&completed, lock: lock, semaphore: semaphore)

            case .waiting:
                break

            case .cancelled:
                os_log(.default, log: log, "UDP %{public}@ cancelled", resolver.address)
                signalOnce(&completed, lock: lock, semaphore: semaphore)

            default:
                break
            }
        }

        connection.start(queue: connectionQueue)

        timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        timeoutTimer?.schedule(deadline: .now() + timeout)
        timeoutTimer?.setEventHandler {
            guard !tryComplete(&completed, lock: lock) else { return }
            os_log(.error, log: log, "UDP %{public}@ timeout after %.1fs", resolver.address, timeout)
            signalOnce(&completed, lock: lock, semaphore: semaphore)
            connection.cancel()
        }
        timeoutTimer?.resume()

        _ = semaphore.wait(timeout: .now() + timeout + 1.0)

        connection.cancel()

        return result
    }

    // MARK: - TCP Resolution

    private static func resolveTcp(requestData: Data,
                                   requestTxId: UInt16,
                                   resolver: Resolver,
                                   timeout: Double) -> Data? {
        os_log(.debug, log: log, "TCP fallback to %{public}@:%{public}d txId=0x%{04X}",
               resolver.address, resolver.port, requestTxId)

        var lengthPrefix = [UInt16(requestData.count >> 8), UInt16(requestData.count & 0xFF)]
        let framedRequest = Data(bytes: &lengthPrefix, count: 2) + requestData

        let endpoint = NWEndpoint.hostPort(host: .name(resolver.address, nil),
                                           port: NWEndpoint.Port(integerLiteral: resolver.port))

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)

        let ctx = TcpReadContext(semaphore: DispatchSemaphore(value: 0))
        let lock = ctx.lock

        let connectionQueue = DispatchQueue(label: "com.thejatech.aura.tcpResolver.\(resolver.address)", qos: .userInitiated)

        var timeoutTimer: DispatchSourceTimer?

        connection.stateUpdateHandler = { [weak connection] (state: NWConnection.State) in
            guard let connection = connection else { return }

            switch state {
            case .ready:
                os_log(.debug, log: log, "TCP %{public}@ ready", resolver.address)

                guard !ctx.tryComplete() else { return }

                connection.send(content: framedRequest, completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        os_log(.error, log: log, "TCP %{public}@ send error: %{public}@", resolver.address, sendError.localizedDescription)
                        ctx.signalOnce()
                        return
                    }

                    os_log(.debug, log: log, "TCP %{public}@ send complete", resolver.address)

                    readTcpLength(connection: connection, resolver: resolver, ctx: ctx,
                                  requestTxId: requestTxId,
                                  connectionQueue: connectionQueue,
                                  timeout: timeout)
                })

            case .failed(let error):
                os_log(.error, log: log, "TCP %{public}@ failed: %{public}@", resolver.address, error.localizedDescription)
                ctx.signalOnce()

            case .waiting:
                break

            case .cancelled:
                os_log(.default, log: log, "TCP %{public}@ cancelled", resolver.address)
                ctx.signalOnce()

            default:
                break
            }
        }

        connection.start(queue: connectionQueue)

        timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        timeoutTimer?.schedule(deadline: .now() + timeout)
        timeoutTimer?.setEventHandler {
            guard !ctx.tryComplete() else { return }
            os_log(.error, log: log, "TCP %{public}@ timeout after %.1fs", resolver.address, timeout)
            ctx.signalOnce()
            connection.cancel()
        }
        timeoutTimer?.resume()

        _ = ctx.semaphore.wait(timeout: .now() + timeout + 1.0)

        connection.cancel()

        return ctx.result
    }

    // MARK: - TCP Length-Prefix Reading

    private static func readTcpLength(connection: NWConnection,
                                      resolver: Resolver,
                                      ctx: TcpReadContext,
                                      requestTxId: UInt16,
                                      connectionQueue: DispatchQueue,
                                      timeout: Double) {

        ctx.timeoutTimer?.cancel()
        ctx.timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        ctx.timeoutTimer?.schedule(deadline: .now() + timeout)
        ctx.timeoutTimer?.setEventHandler {
            guard !ctx.tryComplete() else { return }
            os_log(.error, log: log, "TCP %{public}@ length read timeout", resolver.address)
            ctx.signalOnce()
        }
        ctx.timeoutTimer?.resume()

        connection.receive(minimumIncompleteLength: 1, maximumLength: ctx.lengthBytesRemaining) { data, context, isComplete, error in
            if let error = error {
                os_log(.error, log: log, "TCP %{public}@ length read error: %{public}@", resolver.address, error.localizedDescription)
                ctx.signalOnce()
                return
            }

            guard let data = data, !data.isEmpty else {
                os_log(.default, log: log, "TCP %{public}@ connection closed before length complete", resolver.address)
                ctx.signalOnce()
                return
            }

            ctx.timeoutTimer?.cancel()
            ctx.timeoutTimer = nil

            ctx.lengthBuffer.append(data)
            ctx.lengthBytesRemaining -= data.count

            if ctx.lengthBytesRemaining > 0 {
                readTcpLength(connection: connection, resolver: resolver, ctx: ctx,
                              requestTxId: requestTxId,
                              connectionQueue: connectionQueue,
                              timeout: timeout)
                return
            }

            guard ctx.lengthBuffer.count >= 2 else {
                os_log(.default, log: log, "TCP %{public}@ incomplete length prefix (%{public}ld bytes)", resolver.address, ctx.lengthBuffer.count)
                ctx.signalOnce()
                return
            }

            let bodyLength = Int(ctx.lengthBuffer[0]) << 8 | Int(ctx.lengthBuffer[1])
            os_log(.debug, log: log, "TCP %{public}@ response body length: %{public}d", resolver.address, bodyLength)

            guard bodyLength > 0 else {
                os_log(.default, log: log, "TCP %{public}@ zero-length response body", resolver.address)
                ctx.signalOnce()
                return
            }

            ctx.bodyBytesRemaining = bodyLength
            ctx.bodyBuffer = Data()
            ctx.lengthBuffer = Data()

            readTcpBody(connection: connection, resolver: resolver, ctx: ctx,
                        requestTxId: requestTxId,
                        connectionQueue: connectionQueue,
                        timeout: timeout)
        }
    }

    private static func readTcpBody(connection: NWConnection,
                                    resolver: Resolver,
                                    ctx: TcpReadContext,
                                    requestTxId: UInt16,
                                    connectionQueue: DispatchQueue,
                                    timeout: Double) {

        ctx.timeoutTimer?.cancel()
        ctx.timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        ctx.timeoutTimer?.schedule(deadline: .now() + timeout)
        ctx.timeoutTimer?.setEventHandler {
            guard !ctx.tryComplete() else { return }
            os_log(.error, log: log, "TCP %{public}@ body read timeout", resolver.address)
            ctx.signalOnce()
        }
        ctx.timeoutTimer?.resume()

        connection.receive(minimumIncompleteLength: 1, maximumLength: ctx.bodyBytesRemaining) { data, context, isComplete, error in
            if let error = error {
                os_log(.error, log: log, "TCP %{public}@ body read error: %{public}@", resolver.address, error.localizedDescription)
                ctx.signalOnce()
                return
            }

            guard let data = data, !data.isEmpty else {
                os_log(.default, log: log, "TCP %{public}@ connection closed before body complete", resolver.address)
                ctx.signalOnce()
                return
            }

            ctx.timeoutTimer?.cancel()
            ctx.timeoutTimer = nil

            ctx.bodyBuffer.append(data)
            ctx.bodyBytesRemaining -= data.count

            if ctx.bodyBytesRemaining > 0 {
                readTcpBody(connection: connection, resolver: resolver, ctx: ctx,
                            requestTxId: requestTxId,
                            connectionQueue: connectionQueue,
                            timeout: timeout)
                return
            }

            let responseData = ctx.bodyBuffer
            guard responseData.count >= 2 else {
                os_log(.default, log: log, "TCP %{public}@ response too small (%{public}ld bytes)", resolver.address, responseData.count)
                ctx.signalOnce()
                return
            }

            let responseTxId = UInt16(responseData[0]) << 8 | UInt16(responseData[1])
            let qrBit = (responseData[2] & 0x80) >> 7

            if responseTxId == requestTxId && qrBit == 1 {
                os_log(.debug, log: log, "TCP %{public}@ valid response (%{public}ld bytes, txId=0x%{04X})",
                       resolver.address, responseData.count, responseTxId)
                ctx.result = responseData
            } else {
                os_log(.error, log: log, "TCP %{public}@ invalid response: txId=0x%{04X} expected 0x%{04X}, qr=%{public}d",
                       resolver.address, responseTxId, requestTxId, qrBit)
            }

            ctx.signalOnce()
        }
    }

    // MARK: - Helpers (UDP only)

    private static func tryComplete(_ completed: inout Bool, lock: NSLock) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return true }
        completed = true
        return false
    }

    private static func signalOnce(_ completed: inout Bool, lock: NSLock, semaphore: DispatchSemaphore) {
        lock.lock()
        if !completed {
            completed = true
            lock.unlock()
            semaphore.signal()
        } else {
            lock.unlock()
        }
    }
}

// MARK: - TCP Read Context

/// Holds mutable state for TCP DNS reads, avoiding `inout` parameter capture by escaping closures.
private final class TcpReadContext {
    let lock = NSLock()
    var completed = false
    var result: Data?
    let semaphore: DispatchSemaphore
    var timeoutTimer: DispatchSourceTimer?

    // Length reading state
    var lengthBytesRemaining = 2
    var lengthBuffer = Data()

    // Body reading state
    var bodyBytesRemaining = 0
    var bodyBuffer = Data()

    init(semaphore: DispatchSemaphore) {
        self.semaphore = semaphore
    }

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return true }
        completed = true
        return false
    }

    func signalOnce() {
        lock.lock()
        if !completed {
            completed = true
            lock.unlock()
            semaphore.signal()
        } else {
            lock.unlock()
        }
    }
}