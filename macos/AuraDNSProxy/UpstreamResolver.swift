import Foundation
import Network
import os.log

/// Upstream DNS resolver for macOS DNS proxy.
/// Uses Network framework (NWConnection) for upstream DNS resolution.
/// BSD sockets do NOT work from macOS System Extensions — NWConnection is required.
///
/// All resolution is asynchronous via completion handler. No synchronous waits.
/// `resolveUpstream()` returns an `UpstreamRequest` token that can be used to
/// cancel the in-flight resolution (e.g. when its originating flow closes).
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

    // MARK: - UpstreamRequest (cancellation handle)

    /// Opaque handle to an in-flight upstream DNS resolution.
    /// Call `cancel()` to abort the resolution (e.g. when the originating flow closes).
    /// Cancellation is idempotent and delivers the user completion at most once.
    final class UpstreamRequest {
        let id: UUID
        let userCompletion: (Data?) -> Void

        /// Guard for completed/cancelled state.
        private let stateLock = NSLock()
        private var completed = false

        /// Cancel handler for the currently active resolver attempt.
        /// Updated each time a new resolver/NWConnection is started.
        private var cancelHandler: (() -> Void)?

        init(id: UUID, userCompletion: @escaping (Data?) -> Void) {
            self.id = id
            self.userCompletion = userCompletion
        }

        /// Called internally each time a new resolver attempt begins.
        /// Replaces the previous cancel handler so that `cancel()` always
        /// cancels the currently active connection/timer.
        func setCancelHandler(_ handler: (() -> Void)?) {
            stateLock.lock()
            cancelHandler = handler
            stateLock.unlock()
        }

        /// Cancel the in-flight resolution. Idempotent.
        /// Does NOT deliver the user completion — the caller (flow) is closing
        /// and will discard any late response.
        func cancel() {
            stateLock.lock()
            guard !completed else {
                stateLock.unlock()
                return
            }
            completed = true
            let handler = cancelHandler
            stateLock.unlock()
            handler?()
        }

        /// Deliver the final result to the user completion handler. Idempotent.
        /// Called internally when a resolver returns a valid response, when all
        //  resolvers are exhausted, or when a timeout fires.
        func complete(with data: Data?) {
            stateLock.lock()
            guard !completed else {
                stateLock.unlock()
                return
            }
            completed = true
            stateLock.unlock()
            userCompletion(data)
        }
    }

    // MARK: - Public API (asynchronous)

    /// Resolve a DNS query against upstream resolvers asynchronously.
    /// Returns an `UpstreamRequest` token immediately; the completion handler
    /// is called exactly once with the response data, or nil on failure.
    /// Call `request.cancel()` to abort (e.g. on flow closure).
    static func resolveUpstream(requestData: Data,
                                maxTotalBudget: Double = 2.0,
                                request: UpstreamRequest,
                                completion: @escaping (Data?) -> Void) {
        guard requestData.count >= 2 else {
            os_log(.error, log: log, "requestData too small (%{public}ld bytes)", requestData.count)
            request.complete(with: nil)
            return
        }
        let requestTxId = UInt16(requestData[0]) << 8 | UInt16(requestData[1])
        let startTime = CFAbsoluteTimeGetCurrent()

        let ctx = UpstreamResolutionContext(
            request: request,
            requestData: requestData,
            requestTxId: requestTxId,
            startTime: startTime,
            maxTotalBudget: maxTotalBudget
        )

        tryNextUpstream(ctx: ctx, request: request)
    }

    // MARK: - Upstream iteration

    private static func tryNextUpstream(ctx: UpstreamResolutionContext, request: UpstreamRequest) {
        guard ctx.resolverIndex < upstreams.count else {
            // All resolvers exhausted
            os_log(.error, log: log, "All upstreams failed after %.2fs",
                   CFAbsoluteTimeGetCurrent() - ctx.startTime)
            ctx.complete(with: nil)
            return
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - ctx.startTime
        guard elapsed < ctx.maxTotalBudget else {
            os_log(.info, log: log, "Total budget exhausted before trying %{public}@",
                   upstreams[ctx.resolverIndex].address)
            ctx.complete(with: nil)
            return
        }

        let resolver = upstreams[ctx.resolverIndex]
        ctx.resolverIndex += 1

        let remainingBudget = max(ctx.maxTotalBudget - elapsed, 0.5)

        // Try UDP first
        resolveUdp(requestData: ctx.requestData,
                   requestTxId: ctx.requestTxId,
                   resolver: resolver,
                   timeout: remainingBudget,
                   request: request) { [weak ctx, weak request] udpResult in
            guard let ctx = ctx, let request = request else { return }
            if let response = udpResult {
                ctx.complete(with: response)
                return
            }

            // UDP failed — try TCP fallback for remaining budget
            let remainingAfterUdp = max(ctx.maxTotalBudget - (CFAbsoluteTimeGetCurrent() - ctx.startTime), 0.5)
            if remainingAfterUdp > 0.5 {
                resolveTcp(requestData: ctx.requestData,
                           requestTxId: ctx.requestTxId,
                           resolver: resolver,
                           timeout: remainingAfterUdp,
                           request: request) { [weak ctx] tcpResult in
                    guard let ctx = ctx else { return }
                    if let response = tcpResult {
                        ctx.complete(with: response)
                        return
                    }
                    // Both UDP and TCP failed for this resolver — try next
                    tryNextUpstream(ctx: ctx, request: request)
                }
            } else {
                tryNextUpstream(ctx: ctx, request: request)
            }
        }
    }

    // MARK: - UDP Resolution (asynchronous)

    private static func resolveUdp(requestData: Data,
                                   requestTxId: UInt16,
                                   resolver: Resolver,
                                   timeout: Double,
                                   request: UpstreamRequest,
                                   completion: @escaping (Data?) -> Void) {
        os_log(.debug, log: log, "UDP query to %{public}@:%{public}d txId=0x%{04X}",
               resolver.address, resolver.port, requestTxId)

        let endpoint = NWEndpoint.hostPort(host: .name(resolver.address, nil),
                                           port: NWEndpoint.Port(integerLiteral: resolver.port))

        let parameters = NWParameters.udp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)

        let lock = NSLock()
        var completed = false

        let connectionQueue = DispatchQueue(label: "com.thejatech.aura.upstreamResolver.\(resolver.address)", qos: .userInitiated)

        var timeoutTimer: DispatchSourceTimer?

        // Install cancel handler for this attempt
        request.setCancelHandler {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            connection.cancel()
            timeoutTimer?.cancel()
            lock.unlock()
        }

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
                        completeOnce(&completed, lock: lock) {
                            completion(nil)
                        }
                        return
                    }

                    os_log(.debug, log: log, "UDP %{public}@ send complete", resolver.address)

                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65535) { data, context, isComplete, receiveError in
                        if let receiveError = receiveError {
                            os_log(.error, log: log, "UDP %{public}@ receive error: %{public}@", resolver.address, receiveError.localizedDescription)
                            completeOnce(&completed, lock: lock) {
                                completion(nil)
                            }
                            return
                        }

                        guard let data = data, !data.isEmpty else {
                            os_log(.default, log: log, "UDP %{public}@ received empty data", resolver.address)
                            completeOnce(&completed, lock: lock) {
                                completion(nil)
                            }
                            return
                        }

                        if data.count >= 2 {
                            let responseTxId = UInt16(data[0]) << 8 | UInt16(data[1])
                            let qrBit = (data[2] & 0x80) >> 7
                            if responseTxId == requestTxId && qrBit == 1 {
                                os_log(.debug, log: log, "UDP %{public}@ valid response (%{public}ld bytes, txId=0x%{04X})",
                                       resolver.address, data.count, responseTxId)
                                completeOnce(&completed, lock: lock) {
                                    completion(data)
                                }
                            } else {
                                os_log(.error, log: log, "UDP %{public}@ invalid response: txId=0x%{04X} expected 0x%{04X}, qr=%{public}d",
                                       resolver.address, responseTxId, requestTxId, qrBit)
                                completeOnce(&completed, lock: lock) {
                                    completion(nil)
                                }
                            }
                        } else {
                            os_log(.default, log: log, "UDP %{public}@ response too small (%{public}ld bytes)", resolver.address, data.count)
                            completeOnce(&completed, lock: lock) {
                                completion(nil)
                            }
                        }
                    }
                })

            case .failed(let error):
                os_log(.error, log: log, "UDP %{public}@ failed: %{public}@", resolver.address, error.localizedDescription)
                completeOnce(&completed, lock: lock) {
                    completion(nil)
                }

            case .waiting:
                break

            case .cancelled:
                os_log(.default, log: log, "UDP %{public}@ cancelled", resolver.address)
                completeOnce(&completed, lock: lock) {
                    completion(nil)
                }

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
            completeOnce(&completed, lock: lock) {
                connection.cancel()
                completion(nil)
            }
        }
        timeoutTimer?.resume()
    }

    // MARK: - TCP Resolution (asynchronous)

    private static func resolveTcp(requestData: Data,
                                   requestTxId: UInt16,
                                   resolver: Resolver,
                                   timeout: Double,
                                   request: UpstreamRequest,
                                   completion: @escaping (Data?) -> Void) {
        os_log(.debug, log: log, "TCP fallback to %{public}@:%{public}d txId=0x%{04X}",
               resolver.address, resolver.port, requestTxId)

        var lengthPrefix = [UInt16(requestData.count >> 8), UInt16(requestData.count & 0xFF)]
        let framedRequest = Data(bytes: &lengthPrefix, count: 2) + requestData

        let endpoint = NWEndpoint.hostPort(host: .name(resolver.address, nil),
                                           port: NWEndpoint.Port(integerLiteral: resolver.port))

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)

        let ctx = TcpReadContext()

        let connectionQueue = DispatchQueue(label: "com.thejatech.aura.tcpResolver.\(resolver.address)", qos: .userInitiated)

        var timeoutTimer: DispatchSourceTimer?

        // Install cancel handler for this attempt
        request.setCancelHandler {
            ctx.completeOnce {
                connection.cancel()
                timeoutTimer?.cancel()
                completion(nil)
            }
        }

        connection.stateUpdateHandler = { [weak connection] (state: NWConnection.State) in
            guard let connection = connection else { return }

            switch state {
            case .ready:
                os_log(.debug, log: log, "TCP %{public}@ ready", resolver.address)

                guard !ctx.tryComplete() else { return }

                connection.send(content: framedRequest, completion: .contentProcessed { sendError in
                    if let sendError = sendError {
                        os_log(.error, log: log, "TCP %{public}@ send error: %{public}@", resolver.address, sendError.localizedDescription)
                        ctx.completeOnce {
                            completion(nil)
                        }
                        return
                    }

                    os_log(.debug, log: log, "TCP %{public}@ send complete", resolver.address)

                    readTcpLength(connection: connection, resolver: resolver, ctx: ctx,
                                  requestTxId: requestTxId,
                                  connectionQueue: connectionQueue,
                                  timeout: timeout,
                                  completion: completion)
                })

            case .failed(let error):
                os_log(.error, log: log, "TCP %{public}@ failed: %{public}@", resolver.address, error.localizedDescription)
                ctx.completeOnce {
                    completion(nil)
                }

            case .waiting:
                break

            case .cancelled:
                os_log(.default, log: log, "TCP %{public}@ cancelled", resolver.address)
                ctx.completeOnce {
                    completion(nil)
                }

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
            ctx.completeOnce {
                connection.cancel()
                completion(nil)
            }
        }
        timeoutTimer?.resume()
    }

    // MARK: - TCP Length-Prefix Reading (asynchronous)

    private static func readTcpLength(connection: NWConnection,
                                      resolver: Resolver,
                                      ctx: TcpReadContext,
                                      requestTxId: UInt16,
                                      connectionQueue: DispatchQueue,
                                      timeout: Double,
                                      completion: @escaping (Data?) -> Void) {

        ctx.timeoutTimer?.cancel()
        ctx.timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        ctx.timeoutTimer?.schedule(deadline: .now() + timeout)
        ctx.timeoutTimer?.setEventHandler {
            guard !ctx.tryComplete() else { return }
            os_log(.error, log: log, "TCP %{public}@ length read timeout", resolver.address)
            ctx.completeOnce {
                completion(nil)
            }
        }
        ctx.timeoutTimer?.resume()

        connection.receive(minimumIncompleteLength: 1, maximumLength: ctx.lengthBytesRemaining) { data, context, isComplete, error in
            if let error = error {
                os_log(.error, log: log, "TCP %{public}@ length read error: %{public}@", resolver.address, error.localizedDescription)
                ctx.completeOnce {
                    completion(nil)
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                os_log(.default, log: log, "TCP %{public}@ connection closed before length complete", resolver.address)
                ctx.completeOnce {
                    completion(nil)
                }
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
                              timeout: timeout,
                              completion: completion)
                return
            }

            guard ctx.lengthBuffer.count >= 2 else {
                os_log(.default, log: log, "TCP %{public}@ incomplete length prefix (%{public}ld bytes)", resolver.address, ctx.lengthBuffer.count)
                ctx.completeOnce {
                    completion(nil)
                }
                return
            }

            let bodyLength = Int(ctx.lengthBuffer[0]) << 8 | Int(ctx.lengthBuffer[1])
            os_log(.debug, log: log, "TCP %{public}@ response body length: %{public}d", resolver.address, bodyLength)

            guard bodyLength > 0 else {
                os_log(.default, log: log, "TCP %{public}@ zero-length response body", resolver.address)
                ctx.completeOnce {
                    completion(nil)
                }
                return
            }

            ctx.bodyBytesRemaining = bodyLength
            ctx.bodyBuffer = Data()
            ctx.lengthBuffer = Data()

            readTcpBody(connection: connection, resolver: resolver, ctx: ctx,
                        requestTxId: requestTxId,
                        connectionQueue: connectionQueue,
                        timeout: timeout,
                        completion: completion)
        }
    }

    private static func readTcpBody(connection: NWConnection,
                                    resolver: Resolver,
                                    ctx: TcpReadContext,
                                    requestTxId: UInt16,
                                    connectionQueue: DispatchQueue,
                                    timeout: Double,
                                    completion: @escaping (Data?) -> Void) {

        ctx.timeoutTimer?.cancel()
        ctx.timeoutTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        ctx.timeoutTimer?.schedule(deadline: .now() + timeout)
        ctx.timeoutTimer?.setEventHandler {
            guard !ctx.tryComplete() else { return }
            os_log(.error, log: log, "TCP %{public}@ body read timeout", resolver.address)
            ctx.completeOnce {
                completion(nil)
            }
        }
        ctx.timeoutTimer?.resume()

        connection.receive(minimumIncompleteLength: 1, maximumLength: ctx.bodyBytesRemaining) { data, context, isComplete, error in
            if let error = error {
                os_log(.error, log: log, "TCP %{public}@ body read error: %{public}@", resolver.address, error.localizedDescription)
                ctx.completeOnce {
                    completion(nil)
                }
                return
            }

            guard let data = data, !data.isEmpty else {
                os_log(.default, log: log, "TCP %{public}@ connection closed before body complete", resolver.address)
                ctx.completeOnce {
                    completion(nil)
                }
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
                            timeout: timeout,
                            completion: completion)
                return
            }

            let responseData = ctx.bodyBuffer
            guard responseData.count >= 2 else {
                os_log(.default, log: log, "TCP %{public}@ response too small (%{public}ld bytes)", resolver.address, responseData.count)
                ctx.completeOnce {
                    completion(nil)
                }
                return
            }

            let responseTxId = UInt16(responseData[0]) << 8 | UInt16(responseData[1])
            let qrBit = (responseData[2] & 0x80) >> 7

            if responseTxId == requestTxId && qrBit == 1 {
                os_log(.debug, log: log, "TCP %{public}@ valid response (%{public}ld bytes, txId=0x%{04X})",
                       resolver.address, responseData.count, responseTxId)
                ctx.completeOnce {
                    completion(responseData)
                }
            } else {
                os_log(.error, log: log, "TCP %{public}@ invalid response: txId=0x%{04X} expected 0x%{04X}, qr=%{public}d",
                       resolver.address, responseTxId, requestTxId, qrBit)
                ctx.completeOnce {
                    completion(nil)
                }
            }
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

    private static func completeOnce(_ completed: inout Bool, lock: NSLock, action: @escaping () -> Void) {
        lock.lock()
        if !completed {
            completed = true
            lock.unlock()
            action()
        } else {
            lock.unlock()
        }
    }
}

// MARK: - Upstream Resolution Context

/// Holds mutable state for iterating across upstream resolvers asynchronously.
private final class UpstreamResolutionContext {
    let request: UpstreamResolver.UpstreamRequest
    let requestData: Data
    let requestTxId: UInt16
    let startTime: CFAbsoluteTime
    let maxTotalBudget: Double

    var resolverIndex = 0
    var completed = false
    let lock = NSLock()

    init(request: UpstreamResolver.UpstreamRequest,
         requestData: Data,
         requestTxId: UInt16,
         startTime: CFAbsoluteTime,
         maxTotalBudget: Double) {
        self.request = request
        self.requestData = requestData
        self.requestTxId = requestTxId
        self.startTime = startTime
        self.maxTotalBudget = maxTotalBudget
    }

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return true }
        completed = true
        return false
    }

    func complete(with data: Data?) {
        lock.lock()
        if !completed {
            completed = true
            lock.unlock()
            request.complete(with: data)
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
    var timeoutTimer: DispatchSourceTimer?

    // Length reading state
    var lengthBytesRemaining = 2
    var lengthBuffer = Data()

    // Body reading state
    var bodyBytesRemaining = 0
    var bodyBuffer = Data()

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if completed { return true }
        completed = true
        return false
    }

    func completeOnce(action: @escaping () -> Void) {
        lock.lock()
        if !completed {
            completed = true
            lock.unlock()
            action()
        } else {
            lock.unlock()
        }
    }
}