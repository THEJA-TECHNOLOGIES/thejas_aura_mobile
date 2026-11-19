import Foundation
import NetworkExtension
import Network
import os.log

/// Handles individual DNS flow queries on macOS.
/// Reads query datagrams from NEAppProxyUDPFlow, evaluates against AuraDNSEngine,
/// and writes blocked/allowed response back to the flow.
@available(macOS 15.0, *)
final class AuraDNSFlow {
    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "AuraDNSFlow")

    let flowIdentifier: Int
    private let flow: NEAppProxyUDPFlow
    private let engine: AuraDNSEngine
    private weak var activityLogger: ActivityLogger?
    private let reloadChecker: (() -> Void)?
    private var isClosed = false
    private let closeLock = NSLock()

    init(flow: NEAppProxyUDPFlow, engine: AuraDNSEngine, activityLogger: ActivityLogger? = nil, reloadChecker: (() -> Void)? = nil) {
        self.flowIdentifier = flow.hash
        self.flow = flow
        self.engine = engine
        self.activityLogger = activityLogger
        self.reloadChecker = reloadChecker
    }

    func startReading() {
        guard !isClosed else { return }
        readNextQuery()
    }

    private func readNextQuery() {
        guard !isClosed else { return }

        flow.readDatagrams { [weak self] (datagrams: [(Data, Network.NWEndpoint)]?, error: Error?) in
            guard let self = self, !self.isClosed else { return }

            if let error = error {
                os_log(.error, log: Self.log, "Flow %{public}d read error: %{public}@", self.flowIdentifier, error.localizedDescription)
                self.close()
                return
            }

            guard let datagrams = datagrams, !datagrams.isEmpty else {
                os_log(.default, log: Self.log, "Flow %{public}d received no data", self.flowIdentifier)
                self.close()
                return
            }

            for (queryData, _) in datagrams {
                guard queryData.count >= 12 else {
                    os_log(.default, log: Self.log, "Flow %{public}d received invalid data (%{public}ld bytes)", self.flowIdentifier, queryData.count)
                    continue
                }
                self.handleQuery(queryData)
            }
        }
    }

    private func handleQuery(_ queryData: Data) {
        guard !isClosed else { return }

        // Check for reload signals before evaluation
        reloadChecker?()

        // Parse question
        guard let question = AuraDNSEngine.parseQuestion(data: queryData, offset: 12) else {
            // Unparseable — forward upstream as-is
            os_log(.error, log: Self.log, "Flow %{public}d failed to parse DNS question", self.flowIdentifier)
            forwardUpstream(queryData: queryData)
            return
        }

        let domain = question.name
        let qTypeStr = queryTypeToString(question.qType)

        os_log(.info, log: Self.log, "Flow %{public}d query: domain=%{public}@ type=%{public}@", self.flowIdentifier, domain, qTypeStr)

        // Evaluate policy (pause/passthrough)
        let policy = getEffectivePolicy()
        if policy.isPaused() {
            os_log(.info, log: Self.log, "[PASSTHROUGH] %{public}@ bypassed (paused)", domain)
            forwardUpstream(queryData: queryData, domain: domain, queryType: qTypeStr, isPassthrough: true)
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
                writeResponse(limitedResponse)

                logActivity(domain: domain, queryType: qTypeStr, outcome: "blocked",
                    matchedSource: decision.matchedSource,
                    matchedRuleId: decision.matchedRule,
                    matchedCategories: decision.matchedCategories,
                    reason: decision.reason)
            } else {
                os_log(.error, log: Self.log, "Flow %{public}d failed to synthesize blocked response for %{public}@", self.flowIdentifier, domain)
                forwardUpstream(queryData: queryData, domain: domain, queryType: qTypeStr)
            }
        } else {
            os_log(.info, log: Self.log, "[ALLOW] %{public}@ (source: %{public}@)", domain, decision.matchedSource)
            forwardUpstream(queryData: queryData, domain: domain, queryType: qTypeStr, decision: decision)
        }
    }

    private func forwardUpstream(
        queryData: Data,
        domain: String? = nil,
        queryType: String = "UNKNOWN",
        decision: AuraDNSEngine.MatchDecision? = nil,
        isPassthrough: Bool = false
    ) {
        guard !isClosed else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        let maxTotalBudget: Double = 2.0

        guard let response = UpstreamResolver.resolveUpstream(
            requestData: queryData,
            maxTotalBudget: maxTotalBudget
        ) else {
            os_log(.error, log: Self.log, "[SERVFAIL] %{public}@ failed all upstreams (budget=%.2fs)", domain ?? "unknown", maxTotalBudget)
            if let servFail = AuraDNSEngine.synthesizeServFailResponse(requestData: queryData) {
                let limitedServFail = AuraDNSEngine.limitDnsResponseSize(
                    responseData: servFail,
                    queryData: queryData,
                    isBlockedResponse: false,
                    isServFailResponse: true
                )
                os_log(.debug, log: Self.log, "Flow %{public}d writing SERVFAIL response (%{public}ld bytes) for %{public}@", self.flowIdentifier, limitedServFail.count, domain ?? "unknown")
                writeResponse(limitedServFail)
            } else {
                os_log(.error, log: Self.log, "Flow %{public}d failed to synthesize SERVFAIL response for %{public}@", self.flowIdentifier, domain ?? "unknown")
            }
            if let domain = domain {
                logActivity(domain: domain, queryType: queryType, outcome: "failed",
                    matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                    matchedRuleId: decision?.matchedRule,
                    matchedCategories: decision?.matchedCategories ?? [],
                    reason: "Upstream resolution failed or timed out")
            }
            readNextQuery()
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
                writeResponse(limitedServFail)
            }
            readNextQuery()
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
                writeResponse(limitedServFail)
            }
            if let domain = domain {
                logActivity(domain: domain, queryType: queryType, outcome: "failed",
                    matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                    matchedRuleId: decision?.matchedRule,
                    matchedCategories: decision?.matchedCategories ?? [],
                    reason: "DNS rebinding attempt — private IP in upstream answer")
            }
            readNextQuery()
            return
        }

        // Apply EDNS0-aware size limiting
        let limitedResponse = AuraDNSEngine.limitDnsResponseSize(
            responseData: response,
            queryData: queryData,
            isBlockedResponse: false,
            isServFailResponse: false
        )

        os_log(.info, log: Self.log, "[RESOLVED] %{public}@ in %{public}dms (%{public}ld bytes)",
               domain ?? "unknown", Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000), limitedResponse.count)

        os_log(.debug, log: Self.log, "Flow %{public}d writing ALLOWED response (%{public}ld bytes) for %{public}@", self.flowIdentifier, limitedResponse.count, domain ?? "unknown")
        writeResponse(limitedResponse)

        if let domain = domain {
            logActivity(domain: domain, queryType: queryType, outcome: "allowed",
                matchedSource: isPassthrough ? "passthrough" : (decision?.matchedSource ?? "none"),
                matchedRuleId: decision?.matchedRule,
                matchedCategories: decision?.matchedCategories ?? [],
                reason: nil)
        }

        readNextQuery()
    }

    private func writeResponse(_ response: Data) {
        guard !isClosed else {
            os_log(.error, log: Self.log, "Flow %{public}d writeResponse skipped — flow is closed", self.flowIdentifier)
            return
        }
        let endpoint = NWEndpoint.hostPort(host: "0.0.0.0", port: 0)
        os_log(.debug, log: Self.log, "Flow %{public}d writeResponse: %{public}ld bytes", self.flowIdentifier, response.count)
        flow.writeDatagrams([(response, endpoint)]) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                os_log(.error, log: Self.log, "Flow %{public}d write error: %{public}@", self.flowIdentifier, error.localizedDescription)
            } else {
                os_log(.debug, log: Self.log, "Flow %{public}d write success", self.flowIdentifier)
            }
        }
    }

    func close() {
        closeLock.lock()
        guard !isClosed else {
            closeLock.unlock()
            return
        }
        isClosed = true
        closeLock.unlock()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }

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
