import Foundation
import NetworkExtension
import Network
import os.log

/// Handles individual DNS flow queries on macOS.
/// Reads query datagrams from NEAppProxyUDPFlow, evaluates against AuraDNSEngine,
/// and writes blocked/allowed response back to the flow.
///
/// Lifecycle state machine (all transitions on the serial flowQueue):
///   .idle  → .reading   : startReadOperation() calls flow.readDatagrams()
///   .reading → .idle    : readDatagrams completion handler fires, then
///                          startReadOperation() is called again
///   .idle/.reading → .closed : close() is called; terminal, no further reads or writes
///
/// writeResponse() is also dispatched onto flowQueue so that the closed-state
/// check and writeDatagrams() initiation are serialized against closeLocked().
/// Upstream DNS resolution is genuinely asynchronous — flowQueue is never
/// blocked waiting for upstream responses.
@available(macOS 15.0, *)
final class AuraDNSFlow {
    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "AuraDNSFlow")

    let flowIdentifier: Int
    private let flow: NEAppProxyUDPFlow
    private let engine: AuraDNSEngine
    private weak var activityLogger: ActivityLogger?
    private let reloadChecker: (() -> Void)?

    /// Serial queue guarding all flow lifecycle state and operations.
    /// Only one block runs at a time, eliminating races between reads, writes, and close.
    private let flowQueue = DispatchQueue(label: "com.thejatech.aura.flow")

    /// Read/write lifecycle state.
    private enum FlowState {
        case idle     // No readDatagrams outstanding; safe to start a new read or write
        case reading  // readDatagrams is outstanding; must not start another read
        case closed   // Flow is closed; terminal — no further reads or writes
    }
    private var flowState = FlowState.idle

    /// Registry of pending upstream requests owned by this flow.
    /// Accessed only on flowQueue.
    private var pendingRequests: [UUID: UpstreamResolver.UpstreamRequest] = [:]

    init(flow: NEAppProxyUDPFlow, engine: AuraDNSEngine, activityLogger: ActivityLogger? = nil, reloadChecker: (() -> Void)? = nil) {
        self.flowIdentifier = flow.hash
        self.flow = flow
        self.engine = engine
        self.activityLogger = activityLogger
        self.reloadChecker = reloadChecker
    }

    // MARK: - Public entry points

    /// Called by the provider after flow.open() succeeds.
    func startReading() {
        flowQueue.async { [weak self] in
            guard let self = self else { return }
            self.startReadOperationLocked()
        }
    }

    /// Called by the provider or externally to shut the flow down.
    func close() {
        flowQueue.async { [weak self] in
            guard let self = self else { return }
            self.closeLocked()
        }
    }

    // MARK: - Read lifecycle (serial queue only)

    /// Single gatekeeper for starting a readDatagrams operation.
    /// Must be called on flowQueue. Transitions .idle → .reading atomically.
    private func startReadOperationLocked() {
        switch flowState {
        case .idle:
            break
        case .reading:
            // A read is already outstanding; do not start another.
            os_log(.debug, log: Self.log, "Flow %{public}d read already outstanding, skipping", self.flowIdentifier)
            return
        case .closed:
            os_log(.debug, log: Self.log, "Flow %{public}d is closed, not starting read", self.flowIdentifier)
            return
        }

        flowState = .reading

        os_log(.debug, log: Self.log, "Flow %{public}d starting readDatagrams", self.flowIdentifier)
        flow.readDatagrams { [weak self] datagrams, error in
            guard let self = self else { return }

            // Hand back to the serial queue for state transition and processing.
            self.flowQueue.async {
                self.handleReadCompletion(datagrams: datagrams, error: error)
            }
        }
    }

    /// Called on flowQueue when readDatagrams completes.
    /// Transitions .reading → .idle exactly once, processes datagrams,
    /// then restarts reading without waiting for upstream responses.
    private func handleReadCompletion(datagrams: [(Data, Network.NWEndpoint)]?, error: Error?) {
        // Ignore stale successful read completions after closure.
        guard flowState != .closed else {
            os_log(.debug, log: Self.log, "Flow %{public}d read completion after closure — ignoring", self.flowIdentifier)
            return
        }

        // The outstanding read has completed; we are no longer reading.
        flowState = .idle

        if let error = error {
            os_log(.error, log: Self.log, "Flow %{public}d read error: %{public}@", self.flowIdentifier, error.localizedDescription)
            closeLocked()
            return
        }

        guard let datagrams = datagrams, !datagrams.isEmpty else {
            // Empty datagram batch is not terminal for UDP; continue reading.
            os_log(.debug, log: Self.log, "Flow %{public}d received empty datagram batch, continuing", self.flowIdentifier)
            startReadOperationLocked()
            return
        }

        // Process each datagram synchronously on the serial queue.
        // handleQuery initiates async upstream resolution but returns immediately.
        for (queryData, endpoint) in datagrams {
            guard queryData.count >= 12 else {
                os_log(.default, log: Self.log, "Flow %{public}d received invalid data (%{public}ld bytes)", self.flowIdentifier, queryData.count)
                continue
            }
            handleQuery(queryData: queryData, remoteEndpoint: endpoint)
        }

        // All datagrams in this batch have been dispatched for processing.
        // Restart reading immediately — do not wait for upstream responses.
        startReadOperationLocked()
    }

    // MARK: - Query processing

    private func handleQuery(queryData: Data, remoteEndpoint: Network.NWEndpoint) {
        guard flowState != .closed else { return }

        // Check for reload signals before evaluation
        reloadChecker?()

        // Parse question
        guard let question = AuraDNSEngine.parseQuestion(data: queryData, offset: 12) else {
            os_log(.error, log: Self.log, "Flow %{public}d failed to parse DNS question", self.flowIdentifier)
            forwardUpstream(queryData: queryData, remoteEndpoint: remoteEndpoint)
            return
        }

        let domain = question.name
        let qTypeStr = queryTypeToString(question.qType)

        os_log(.info, log: Self.log, "Flow %{public}d query: domain=%{public}@ type=%{public}@", self.flowIdentifier, domain, qTypeStr)

        // Evaluate policy (pause/passthrough)
        let policy = getEffectivePolicy()
        if policy.isPaused() {
            os_log(.info, log: Self.log, "[PASSTHROUGH] %{public}@ bypassed (paused)", domain)
            forwardUpstream(queryData: queryData, remoteEndpoint: remoteEndpoint, domain: domain, queryType: qTypeStr, isPassthrough: true)
            return
        }

        // Normal filtering
        let decision = engine.evaluate(domain: domain)

        os_log(.info, log: Self.log, "Flow %{public}d engine decision: domain=%{public}@ isBlocked=%{public}d source=%{public}@ rule=%{public}@ categories=%{public}@ reason=%{public}@",
               self.flowIdentifier, domain, decision.isBlocked, decision.matchedSource, decision.matchedRule ?? "none",
               decision.matchedCategories.joined(separator: ","), decision.reason)

        if decision.isBlocked {
            os_log(.info, log: Self.log, "[BLOCK] %{public}@ (source: %{public}@)", domain, decision.matchedSource)
            if let response = AuraDNSEngine.synthesizeBlockedResponse(requestData: queryData) {
                let limitedResponse = AuraDNSEngine.limitDnsResponseSize(
                    responseData: response,
                    queryData: queryData,
                    isBlockedResponse: true,
                    isServFailResponse: false
                )
                os_log(.debug, log: Self.log, "Flow %{public}d writing BLOCKED response (%{public}ld bytes) for %{public}@", self.flowIdentifier, limitedResponse.count, domain)
                writeResponse(limitedResponse, remoteEndpoint: remoteEndpoint)

                logActivity(domain: domain, queryType: qTypeStr, outcome: "blocked",
                    matchedSource: decision.matchedSource,
                    matchedRuleId: decision.matchedRule,
                    matchedCategories: decision.matchedCategories,
                    reason: decision.reason)
            } else {
                os_log(.error, log: Self.log, "Flow %{public}d failed to synthesize blocked response for %{public}@", self.flowIdentifier, domain)
                forwardUpstream(queryData: queryData, remoteEndpoint: remoteEndpoint, domain: domain, queryType: qTypeStr)
            }
        } else {
            os_log(.info, log: Self.log, "[ALLOW] %{public}@ (source: %{public}@)", domain, decision.matchedSource)
            forwardUpstream(queryData: queryData, remoteEndpoint: remoteEndpoint, domain: domain, queryType: qTypeStr, decision: decision)
        }
    }

    /// Forward an allowed (or unparseable) query upstream asynchronously.
    /// Does NOT block flowQueue — upstream resolution runs on its own queues
    /// and the completion handler dispatches back to flowQueue for writing.
    /// The read loop is restarted by handleReadCompletion, not here.
    private func forwardUpstream(
        queryData: Data,
        remoteEndpoint: Network.NWEndpoint,
        domain: String? = nil,
        queryType: String = "UNKNOWN",
        decision: AuraDNSEngine.MatchDecision? = nil,
        isPassthrough: Bool = false
    ) {
        guard flowState != .closed else { return }

        let maxTotalBudget: Double = 2.0

        // Create the request ID first so the completion handler can capture it
        // without capturing `request` itself (which is being declared).
        let requestId = UUID()
        let request = UpstreamResolver.UpstreamRequest(id: requestId, userCompletion: { [weak self] response in
            guard let self = self else { return }

            // Dispatch back to flowQueue so lifecycle checks and write initiation
            // are serialized against closeLocked().
            self.flowQueue.async {
                // Always remove from the pending registry, even on closure.
                self.pendingRequests.removeValue(forKey: requestId)

                guard self.flowState != .closed else {
                    // Late upstream response after closure — discard.
                    os_log(.debug, log: Self.log, "Flow %{public}d late upstream response after closure — discarded", self.flowIdentifier)
                    return
                }

                guard let response = response else {
                    os_log(.error, log: Self.log, "[SERVFAIL] %{public}@ failed all upstreams (budget=%.2fs)", domain ?? "unknown", maxTotalBudget)
                    if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: queryData) {
                        let limitedServFail = AuraDNSEngine.limitDnsResponseSize(
                            responseData: servFail,
                            queryData: queryData,
                            isBlockedResponse: false,
                            isServFailResponse: true
                        )
                        os_log(.debug, log: Self.log, "Flow %{public}d writing SERVFAIL response (%{public}ld bytes) for %{public}@", self.flowIdentifier, limitedServFail.count, domain ?? "unknown")
                        self.writeResponse(limitedServFail, remoteEndpoint: remoteEndpoint)
                    } else {
                        os_log(.error, log: Self.log, "Flow %{public}d failed to synthesize SERVFAIL response for %{public}@", self.flowIdentifier, domain ?? "unknown")
                    }
                    if let domain = domain {
                        self.logActivity(domain: domain, queryType: queryType, outcome: "failed",
                            matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                            matchedRuleId: decision?.matchedRule,
                            matchedCategories: decision?.matchedCategories ?? [],
                            reason: "Upstream resolution failed or timed out")
                    }
                    return
                }

                // QNAME Matching
                guard AuraDNSEngine.questionsMatch(query: queryData, response: response) else {
                    os_log(.error, log: Self.log, "QNAME mismatch for %{public}@ — returning SERVFAIL", domain ?? "unknown")
                    if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: queryData) {
                        let limitedServFail = AuraDNSEngine.limitDnsResponseSize(
                            responseData: servFail,
                            queryData: queryData,
                            isBlockedResponse: false,
                            isServFailResponse: true
                        )
                        os_log(.debug, log: Self.log, "Flow %{public}d writing SERVFAIL (QNAME mismatch) for %{public}@", self.flowIdentifier, domain ?? "unknown")
                        self.writeResponse(limitedServFail, remoteEndpoint: remoteEndpoint)
                    }
                    return
                }

                // DNS Rebinding Protection
                guard !AuraDNSEngine.hasPrivateIpAnswers(response) else {
                    os_log(.error, log: Self.log, "DNS rebinding attempt for %{public}@ — returning SERVFAIL", domain ?? "unknown")
                    if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: queryData) {
                        let limitedServFail = AuraDNSEngine.limitDnsResponseSize(
                            responseData: servFail,
                            queryData: queryData,
                            isBlockedResponse: false,
                            isServFailResponse: true
                        )
                        os_log(.debug, log: Self.log, "Flow %{public}d writing SERVFAIL (rebinding) for %{public}@", self.flowIdentifier, domain ?? "unknown")
                        self.writeResponse(limitedServFail, remoteEndpoint: remoteEndpoint)
                    }
                    if let domain = domain {
                        self.logActivity(domain: domain, queryType: queryType, outcome: "failed",
                            matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                            matchedRuleId: decision?.matchedRule,
                            matchedCategories: decision?.matchedCategories ?? [],
                            reason: "DNS rebinding attempt — private IP in upstream answer")
                    }
                    return
                }

                // Apply EDNS0-aware size limiting
                let limitedResponse = AuraDNSEngine.limitDnsResponseSize(
                    responseData: response,
                    queryData: queryData,
                    isBlockedResponse: false,
                    isServFailResponse: false
                )

                os_log(.info, log: Self.log, "[RESOLVED] %{public}@ (%{public}ld bytes)",
                       domain ?? "unknown", limitedResponse.count)

                os_log(.debug, log: Self.log, "Flow %{public}d writing ALLOWED response (%{public}ld bytes) for %{public}@", self.flowIdentifier, limitedResponse.count, domain ?? "unknown")
                self.writeResponse(limitedResponse, remoteEndpoint: remoteEndpoint)

                if let domain = domain {
                    self.logActivity(domain: domain, queryType: queryType, outcome: "allowed",
                        matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                        matchedRuleId: decision?.matchedRule,
                        matchedCategories: decision?.matchedCategories ?? [],
                        reason: nil)
                }
            }
        })

        UpstreamResolver.resolveUpstream(
            requestData: queryData,
            maxTotalBudget: maxTotalBudget,
            request: request,
            completion: request.userCompletion
        )

        // Register the pending request so it can be cancelled on flow closure.
        pendingRequests[requestId] = request
    }

    // MARK: - Response writing

    /// Write a DNS response to the originating endpoint.
    /// Dispatched onto flowQueue so that the closed-state check and writeDatagrams()
    /// initiation are serialized against closeLocked(). Once flowState is .closed,
    /// no new writes may be initiated. The write completion handler does not
    /// mutate lifecycle state.
    private func writeResponse(_ response: Data, remoteEndpoint: Network.NWEndpoint) {
        flowQueue.async { [weak self] in
            guard let self = self else { return }

            guard self.flowState != .closed else {
                os_log(.error, log: Self.log, "Flow %{public}d writeResponse skipped — flow is closed", self.flowIdentifier)
                return
            }

            os_log(.debug, log: Self.log, "Flow %{public}d writeResponse: %{public}ld bytes", self.flowIdentifier, response.count)
            self.flow.writeDatagrams([(response, remoteEndpoint)]) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    os_log(.error, log: Self.log, "Flow %{public}d write error: %{public}@", self.flowIdentifier, error.localizedDescription)
                } else {
                    os_log(.debug, log: Self.log, "Flow %{public}d write success", self.flowIdentifier)
                }
            }
        }
    }

    // MARK: - Flow closure

    /// Called on flowQueue. Transitions to .closed and closes the flow.
    /// Terminal: prevents all future reads and writes.
    /// Cancels all pending upstream requests belonging to this flow.
    private func closeLocked() {
        guard flowState != .closed else { return }
        flowState = .closed

        os_log(.debug, log: Self.log, "Flow %{public}d closing (%{public}d pending upstream requests)",
               self.flowIdentifier, pendingRequests.count)

        // Cancel all pending upstream requests belonging to this flow.
        for (_, request) in pendingRequests {
            request.cancel()
        }
        pendingRequests.removeAll()

        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }

    // MARK: - Activity logging

    private func logActivity(
        domain: String,
        queryType: String,
        outcome: String,
        matchedSource: String,
        matchedRuleId: String?,
        matchedCategories: [String],
        reason: String?
    ) {
        activityLogger?.log(domain: domain, queryType: queryType, outcome: outcome,
            matchedSource: matchedSource, matchedRuleId: matchedRuleId,
            matchedCategories: matchedCategories, reason: reason)
    }

    private func getEffectivePolicy() -> PolicySnapshot {
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        let rawMode = defaults?.string(forKey: "vpn_policy_mode") ?? "enabled"
        let expiry = defaults?.object(forKey: "vpn_pause_expiry_utc_millis") as? Int64 ?? 0
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        if rawMode == "paused" && expiry > 0 && now >= expiry {
            defaults?.set("enabled", forKey: "vpn_policy_mode")
            defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
            return PolicySnapshot(mode: "enabled", pauseExpiryUtcMillis: 0)
        }

        return PolicySnapshot(mode: rawMode, pauseExpiryUtcMillis: expiry)
    }

    private func queryTypeToString(_ qType: UInt16) -> String {
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
}

// MARK: - Supporting Types

struct PolicySnapshot {
    let mode: String
    let pauseExpiryUtcMillis: Int64

    func isPaused() -> Bool {
        return mode == "paused" && Int64(Date().timeIntervalSince1970 * 1000) < pauseExpiryUtcMillis
    }
}

/// Protocol for activity logging (decouples from SQLite implementation).
protocol ActivityLogger: AnyObject {
    func log(domain: String, queryType: String, outcome: String,
             matchedSource: String, matchedRuleId: String?,
             matchedCategories: [String], reason: String?)
}