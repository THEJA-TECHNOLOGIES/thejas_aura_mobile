import Foundation
import NetworkExtension
import os.log

/// Structured error wrapping NetworkExtension failures with the exact lifecycle stage and NSError metadata.
public struct AuraTunnelError: LocalizedError {
    public let stage: String
    public let domain: String
    public let code: Int
    public let underlyingDescription: String
    public let isSimulator: Bool

    public init(stage: String, error: Error) {
        let nsError = error as NSError
        self.stage = stage
        self.domain = nsError.domain
        self.code = nsError.code
        self.underlyingDescription = nsError.localizedDescription
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
    }

    public init(stage: String, domain: String = "AuraTunnelManager", code: Int, description: String) {
        self.stage = stage
        self.domain = domain
        self.code = code
        self.underlyingDescription = description
        #if targetEnvironment(simulator)
        self.isSimulator = true
        #else
        self.isSimulator = false
        #endif
    }

    public var errorDescription: String? {
        var msg = "[\(stage)] \(domain) (code \(code)): \(underlyingDescription)"
        let isIPCFailure = (domain == "NEVPNErrorDomain" && code == 5) || (domain == "NEConfigurationErrorDomain" && code == 11)
        if isSimulator && isIPCFailure {
            msg += " — iOS Simulator does not run com.apple.nehelper or support NEPacketTunnelProvider; a signed physical iOS device is required."
        } else if isIPCFailure {
            msg += " — Verify Runner and AuraTunnel are signed with a provisioning profile containing the packet-tunnel-provider NetworkExtension entitlement."
        }
        return msg
    }

    public var detailsDictionary: [String: Any] {
        return [
            "stage": stage,
            "domain": domain,
            "code": code,
            "localizedDescription": underlyingDescription,
            "isSimulator": isSimulator
        ]
    }
}

/// Controls the lifecycle of the local Aura Packet Tunnel via NETunnelProviderManager.
public final class AuraTunnelManager: NSObject {

    public static let shared = AuraTunnelManager()
    public static let tunnelBundleIdentifier = "com.thejatech.aura.AuraTunnel"
    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "AuraTunnelManager")

    public enum Status: String {
        case disconnected = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
        case disconnecting = "disconnecting"
        case invalid = "invalid"

        static func from(vpnStatus: NEVPNStatus) -> Status {
            switch vpnStatus {
            case .invalid: return .invalid
            case .disconnected: return .disconnected
            case .connecting: return .connecting
            case .connected: return .connected
            case .reasserting: return .connecting
            case .disconnecting: return .disconnecting
            @unknown default: return .invalid
            }
        }
    }

    private var targetManager: NETunnelProviderManager?
    private let knownConnections = NSHashTable<NEVPNConnection>.weakObjects()
    public var onStatusChanged: ((Status) -> Void)?

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVPNStatusChanged(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleVPNStatusChanged(_ notification: Notification) {
        guard let notifiedConnection = notification.object as? NEVPNConnection else { return }

        let isTracked = knownConnections.contains(notifiedConnection) || (targetManager?.connection === notifiedConnection)
        let rawStatus = notifiedConnection.status
        let status = Status.from(vpnStatus: rawStatus)

        os_log(.info, log: Self.log, "[NEVPNStatusDidChange] status=%{public}@ (raw=%{public}ld) isTracked=%{public}d", status.rawValue, rawStatus.rawValue, isTracked ? 1 : 0)
        AuraDiagnostics.log(
            tag: "AuraTunnelManager",
            message: "handleVPNStatusChanged: status=\(status.rawValue) (raw=\(rawStatus.rawValue)) isTracked=\(isTracked)"
        )

        onStatusChanged?(status)
        AuraDiagnostics.flushNewLogsToConsole()
    }

    // MARK: - Authoritative Policy Persistence

    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let keyPolicyMode = "vpn_policy_mode"
    public static let keyPauseExpiryUtcMillis = "vpn_pause_expiry_utc_millis"

    public static let policyEnabled = "enabled"
    public static let policyPaused = "paused"
    public static let policyManuallyDisabled = "manually_disabled"

    public func getPolicyMode() -> String {
        let defaults = UserDefaults(suiteName: Self.sharedAppGroupIdentifier)
        let mode = defaults?.string(forKey: Self.keyPolicyMode) ?? Self.policyManuallyDisabled
        if mode == Self.policyPaused {
            let expiry = getPauseExpiryMillis()
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if expiry > 0 && now >= expiry {
                setPolicyEnabled()
                return Self.policyEnabled
            }
        }
        return mode
    }

    public func getPauseExpiryMillis() -> Int64 {
        let defaults = UserDefaults(suiteName: Self.sharedAppGroupIdentifier)
        return defaults?.object(forKey: Self.keyPauseExpiryUtcMillis) as? Int64 ?? 0
    }

    public func isAutoRecoveryPermitted() -> Bool {
        let mode = getPolicyMode()
        switch mode {
        case Self.policyManuallyDisabled:
            return false
        case Self.policyPaused:
            let expiry = getPauseExpiryMillis()
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            return now >= expiry
        case Self.policyEnabled:
            return true
        default:
            return false
        }
    }

    public func setPolicyEnabled() {
        let defaults = UserDefaults(suiteName: Self.sharedAppGroupIdentifier)
        defaults?.set(Self.policyEnabled, forKey: Self.keyPolicyMode)
        defaults?.set(0, forKey: Self.keyPauseExpiryUtcMillis)
    }

    public func setPolicyPaused(expiryUtcMillis: Int64) {
        let defaults = UserDefaults(suiteName: Self.sharedAppGroupIdentifier)
        defaults?.set(Self.policyPaused, forKey: Self.keyPolicyMode)
        defaults?.set(expiryUtcMillis, forKey: Self.keyPauseExpiryUtcMillis)
    }

    public func setPolicyManuallyDisabled() {
        let defaults = UserDefaults(suiteName: Self.sharedAppGroupIdentifier)
        defaults?.set(Self.policyManuallyDisabled, forKey: Self.keyPolicyMode)
        defaults?.set(0, forKey: Self.keyPauseExpiryUtcMillis)
    }

    public func pauseTunnel(durationMinutes: Int, completion: @escaping (Result<Void, AuraTunnelError>) -> Void) {
        let expiry = Int64(Date().timeIntervalSince1970 * 1000) + Int64(durationMinutes * 60 * 1000)
        setPolicyPaused(expiryUtcMillis: expiry)
        
        getStatus { [weak self] status in
            guard let self = self else { return }
            if status == .connected {
                // Passthrough architecture: DO NOT STOP TUNNEL!
                // Notify connected extension to reload policy and enter DNS passthrough mode
                self.notifyPolicyUpdated { _ in
                    completion(.success(()))
                }
            } else {
                // Tunnel was not connected; start it
                self.startTunnel(completion: completion)
            }
        }
    }

    public func shutdownTunnel(completion: @escaping (Result<Void, AuraTunnelError>) -> Void) {
        setPolicyManuallyDisabled()
        stopTunnel(completion: completion)
    }

    /// Ensures the given manager has the expected NETunnelProviderProtocol and bundle identifier.
    private func applyConfiguration(to manager: NETunnelProviderManager, enableOnDemand: Bool? = nil) {
        let shouldEnableOnDemand = enableOnDemand ?? true
        let tunnelProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = AuraTunnelManager.tunnelBundleIdentifier
        tunnelProtocol.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Theja's Aura Local Firewall"
        manager.isEnabled = true

        if shouldEnableOnDemand {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            manager.onDemandRules = [rule]
            manager.isOnDemandEnabled = true
        } else {
            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }

        os_log(
            .info,
            log: Self.log,
            "[configureManager] providerBundleIdentifier=%{public}@ isEnabled=%{public}d isOnDemand=%{public}d serverAddress=%{public}@",
            tunnelProtocol.providerBundleIdentifier ?? "nil",
            manager.isEnabled ? 1 : 0,
            manager.isOnDemandEnabled ? 1 : 0,
            tunnelProtocol.serverAddress ?? "nil"
        )
    }

    /// Loads the active NETunnelProviderManager or creates a new instance configured for AuraTunnel.
    public func getManager(completion: @escaping (Result<NETunnelProviderManager, AuraTunnelError>) -> Void) {
        os_log(.info, log: Self.log, "[loadAllFromPreferences] Requesting tunnel configurations from preferences...")
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                let nsError = error as NSError
                os_log(
                    .error,
                    log: Self.log,
                    "[loadAllFromPreferences] FAILED — domain=%{public}@ code=%{public}ld description=%{public}@",
                    nsError.domain,
                    nsError.code,
                    nsError.localizedDescription
                )
                completion(.failure(AuraTunnelError(stage: "loadAllFromPreferences", error: error)))
                return
            }

            let count = managers?.count ?? 0
            os_log(.info, log: Self.log, "[loadAllFromPreferences] SUCCEEDED — loaded %{public}ld configuration(s)", count)

            if let existing = managers?.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AuraTunnelManager.tunnelBundleIdentifier
            }) {
                let proto = existing.protocolConfiguration as? NETunnelProviderProtocol
                os_log(
                    .info,
                    log: Self.log,
                    "[getManager] Reusing existing manager — providerBundleIdentifier=%{public}@ isEnabled=%{public}d status=%{public}@",
                    proto?.providerBundleIdentifier ?? "nil",
                    existing.isEnabled ? 1 : 0,
                    Status.from(vpnStatus: existing.connection.status).rawValue
                )
                self?.targetManager = existing
                self?.knownConnections.add(existing.connection)
                completion(.success(existing))
                return
            }

            os_log(.info, log: Self.log, "[getManager] No existing manager for %{public}@; creating new configuration", AuraTunnelManager.tunnelBundleIdentifier)
            let newManager = NETunnelProviderManager()
            self?.applyConfiguration(to: newManager)
            self?.targetManager = newManager
            self?.knownConnections.add(newManager.connection)
            completion(.success(newManager))
        }
    }

    /// Returns current connection status.
    public func getStatus(completion: @escaping (Status) -> Void) {
        getManager { result in
            switch result {
            case .success(let manager):
                let status = Status.from(vpnStatus: manager.connection.status)
                os_log(.info, log: Self.log, "[getStatus] Current status=%{public}@ (raw=%{public}ld)", status.rawValue, manager.connection.status.rawValue)
                completion(status)
            case .failure(let error):
                os_log(.error, log: Self.log, "[getStatus] Returning .invalid due to error: %{public}@", error.errorDescription ?? error.underlyingDescription)
                completion(.invalid)
            }
        }
    }

    /// Starts the local firewall tunnel using verified asynchronous NetworkExtension sequencing:
    /// 1. Load existing configurations
    /// 2. Create/update NETunnelProviderManager & NETunnelProviderProtocol
    /// 3. Save configuration to preferences
    /// 4. Reload saved configuration from preferences
    /// 5. Call startVPNTunnel() and observe status transitions
    public func startTunnel(completion: @escaping (Result<Void, AuraTunnelError>) -> Void) {
        let actId = UUID().uuidString.prefix(6)
        os_log(.info, log: Self.log, "[startTunnel] Beginning tunnel startup sequence [\(actId)]...")
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] sequence initiated")
        AuraDiagnostics.flushNewLogsToConsole()

        getManager { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                self.knownConnections.add(manager.connection)
                self.setPolicyEnabled()
                if manager.connection.status == .connected {
                    os_log(.info, log: Self.log, "[startTunnel] Tunnel is already connected; notifying policy update and returning success")
                    AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] already connected; notifying policy update")
                    AuraDiagnostics.flushNewLogsToConsole()
                    self.notifyPolicyUpdated { _ in
                        completion(.success(()))
                    }
                    return
                }

                // Step 2: Ensure protocol configuration, isEnabled, and OnDemand are set
                self.applyConfiguration(to: manager, enableOnDemand: true)

                // Step 3: Save to preferences
                os_log(.info, log: Self.log, "[saveToPreferences] Saving configuration...")
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] calling saveToPreferences...")
                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        let nsError = saveError as NSError
                        os_log(
                            .error,
                            log: Self.log,
                            "[saveToPreferences] FAILED — domain=%{public}@ code=%{public}ld description=%{public}@",
                            nsError.domain,
                            nsError.code,
                            nsError.localizedDescription
                        )
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] saveToPreferences FAILED: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(stage: "saveToPreferences", error: saveError)))
                        return
                    }

                    os_log(.info, log: Self.log, "[saveToPreferences] SUCCEEDED — reloading configuration from preferences...")
                    AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] saveToPreferences SUCCEEDED, reloading...")

                    // Step 4: Reload before starting
                    manager.loadFromPreferences { reloadError in
                        if let reloadError = reloadError {
                            let nsError = reloadError as NSError
                            os_log(
                                .error,
                                log: Self.log,
                                "[loadFromPreferences] FAILED — domain=%{public}@ code=%{public}ld description=%{public}@",
                                nsError.domain,
                                nsError.code,
                                nsError.localizedDescription
                            )
                            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] loadFromPreferences FAILED: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                            AuraDiagnostics.flushNewLogsToConsole()
                            completion(.failure(AuraTunnelError(stage: "loadFromPreferences", error: reloadError)))
                            return
                        }

                        self.knownConnections.add(manager.connection)
                        let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
                        let statusBefore = manager.connection.status
                        os_log(
                            .info,
                            log: Self.log,
                            "[loadFromPreferences] SUCCEEDED — providerBundleIdentifier=%{public}@ isEnabled=%{public}d statusBeforeStart=%{public}@ (raw=%{public}ld)",
                            proto?.providerBundleIdentifier ?? "nil",
                            manager.isEnabled ? 1 : 0,
                            Status.from(vpnStatus: statusBefore).rawValue,
                            statusBefore.rawValue
                        )
                        AuraDiagnostics.log(
                            tag: "AuraTunnelManager",
                            message: "startTunnel [\(actId)] loadFromPreferences SUCCEEDED — bundleId=\(proto?.providerBundleIdentifier ?? "nil") statusBefore=\(Status.from(vpnStatus: statusBefore).rawValue)(\(statusBefore.rawValue)), calling startVPNTunnel()..."
                        )

                        // Step 5: Start the VPN tunnel
                        do {
                            try manager.connection.startVPNTunnel()
                            let statusAfter = manager.connection.status
                            os_log(
                                .info,
                                log: Self.log,
                                "[startVPNTunnel] Invoked without synchronous throw. statusAfterStart=%{public}@ (raw=%{public}ld)",
                                Status.from(vpnStatus: statusAfter).rawValue,
                                statusAfter.rawValue
                            )
                            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] startVPNTunnel SUCCEEDED — statusAfter=\(Status.from(vpnStatus: statusAfter).rawValue)(\(statusAfter.rawValue))")
                            completion(.success(()))
                        } catch {
                            let nsError = error as NSError
                            os_log(
                                .error,
                                log: Self.log,
                                "[startVPNTunnel] THREW synchronously — domain=%{public}@ code=%{public}ld description=%{public}@",
                                nsError.domain,
                                nsError.code,
                                nsError.localizedDescription
                            )
                            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] startVPNTunnel THREW synchronously: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                            completion(.failure(AuraTunnelError(stage: "startVPNTunnel", error: error)))
                        }
                        AuraDiagnostics.flushNewLogsToConsole()
                    }
                }
            case .failure(let error):
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "startTunnel [\(actId)] getManager FAILED: \(error.underlyingDescription)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.failure(error))
            }
        }
    }

    /// Stops the local firewall tunnel.
    public func stopTunnel(completion: @escaping (Result<Void, AuraTunnelError>) -> Void) {
        os_log(.info, log: Self.log, "[stopTunnel] Requesting tunnel stop...")
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "stopTunnel requested by app")
        AuraDiagnostics.flushNewLogsToConsole()
        getManager { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                self.knownConnections.add(manager.connection)
                let statusBefore = manager.connection.status
                os_log(
                    .info,
                    log: Self.log,
                    "[stopTunnel] Stopping tunnel from status=%{public}@ (raw=%{public}ld)",
                    Status.from(vpnStatus: statusBefore).rawValue,
                    statusBefore.rawValue
                )

                // Critical: Explicitly disable On Demand and save before calling stopVPNTunnel
                // to prevent iOS from immediately reconnecting the tunnel.
                self.applyConfiguration(to: manager, enableOnDemand: false)
                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        os_log(.error, log: Self.log, "[stopTunnel] Failed to disable On Demand in preferences: %{public}@", saveError.localizedDescription)
                    }
                    if statusBefore != .disconnected {
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "Calling stopVPNTunnel() from status=\(Status.from(vpnStatus: statusBefore).rawValue)")
                        manager.connection.stopVPNTunnel()
                    }
                    AuraDiagnostics.flushNewLogsToConsole()
                    completion(.success(()))
                }
            case .failure(let error):
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "stopTunnel getManager failed: \(error.underlyingDescription)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.failure(error))
            }
        }
    }

    /// Signals a currently connected tunnel to reload its rules from the App Group storage.
    public func notifyRulesUpdated(completion: @escaping (Result<Bool, AuraTunnelError>) -> Void) {
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated entered")
        let sendIPC: (NETunnelProviderManager) -> Void = { manager in
            guard let session = manager.connection as? NETunnelProviderSession else {
                os_log(
                    .info,
                    log: Self.log,
                    "[sendProviderMessage] Connection is not a NETunnelProviderSession; skipping live reload IPC"
                )
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: connection is NOT NETunnelProviderSession")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let currentStatus = session.status
            guard currentStatus == .connected else {
                os_log(
                    .info,
                    log: Self.log,
                    "[sendProviderMessage] Tunnel status is %{public}@ (raw=%{public}ld), not .connected; skipping live 'reload_rules' IPC (rules will load on startTunnel).",
                    Status.from(vpnStatus: currentStatus).rawValue,
                    currentStatus.rawValue
                )
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: tunnel status is \(Status.from(vpnStatus: currentStatus).rawValue) (not .connected) — skipping live IPC")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let message = Data("reload_rules".utf8)
            os_log(.info, log: Self.log, "[sendProviderMessage] Sending 'reload_rules' IPC to connected extension...")
            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: sending 'reload_rules' IPC...")
            do {
                try session.sendProviderMessage(message) { responseData in
                    if let responseData = responseData, responseData == Data([1]) {
                        os_log(
                            .info,
                            log: Self.log,
                            "[sendProviderMessage] Extension successfully acknowledged and applied 'reload_rules'."
                        )
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: extension acknowledged reload_rules")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.success(true))
                    } else if let responseData = responseData {
                        os_log(
                            .error,
                            log: Self.log,
                            "[sendProviderMessage] Extension rejected 'reload_rules' with response: %{public}@",
                            responseData as NSData
                        )
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: extension rejected reload_rules: \(responseData as NSData)")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(
                            stage: "sendProviderMessage",
                            code: -2,
                            description: "Extension failed to load and apply rules from App Group storage"
                        )))
                    } else {
                        os_log(
                            .error,
                            log: Self.log,
                            "[sendProviderMessage] Extension returned nil response for 'reload_rules'."
                        )
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: extension returned nil response")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(
                            stage: "sendProviderMessage",
                            code: -1,
                            description: "Extension returned nil response to reload_rules message"
                        )))
                    }
                }
            } catch {
                let nsError = error as NSError
                os_log(
                    .error,
                    log: Self.log,
                    "[sendProviderMessage] THREW synchronously — domain=%{public}@ code=%{public}ld description=%{public}@",
                    nsError.domain,
                    nsError.code,
                    nsError.localizedDescription
                )
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: sendProviderMessage THREW: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.failure(AuraTunnelError(stage: "sendProviderMessage", error: error)))
            }
        }

        if let existing = targetManager {
            sendIPC(existing)
        } else {
            getManager { result in
                switch result {
                case .success(let manager):
                    sendIPC(manager)
                case .failure(let error):
                    os_log(.info, log: Self.log, "[sendProviderMessage] Could not load manager (%{public}@); skipping live reload IPC", error.underlyingDescription)
                    AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyRulesUpdated: getManager failed: \(error.underlyingDescription)")
                    AuraDiagnostics.flushNewLogsToConsole()
                    completion(.success(false))
                }
            }
        }
    }

    /// Signals a currently connected tunnel to reload its category preferences from App Group storage.
    public func notifyCategoriesUpdated(completion: @escaping (Result<Bool, AuraTunnelError>) -> Void) {
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated entered")
        // Ensure compact binary index is compiled in Runner before dispatching reload to extension
        AuraCategoryStore.ensureCompactIndexExists()
        let sendIPC: (NETunnelProviderManager) -> Void = { manager in
            guard let session = manager.connection as? NETunnelProviderSession else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Connection is not a NETunnelProviderSession; skipping live reload_categories IPC")
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: connection is NOT NETunnelProviderSession")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let currentStatus = session.status
            guard currentStatus == .connected else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Tunnel status is %{public}@, not .connected; skipping live reload_categories IPC", Status.from(vpnStatus: currentStatus).rawValue)
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: tunnel status is \(Status.from(vpnStatus: currentStatus).rawValue) (not .connected) — skipping live IPC")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let message = Data("reload_categories".utf8)
            os_log(.info, log: Self.log, "[sendProviderMessage] Sending 'reload_categories' IPC to connected extension...")
            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: sending 'reload_categories' IPC...")
            do {
                try session.sendProviderMessage(message) { responseData in
                    if let responseData = responseData, responseData == Data([1]) {
                        os_log(.info, log: Self.log, "[sendProviderMessage] Extension acknowledged 'reload_categories'.")
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: extension acknowledged reload_categories")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.success(true))
                    } else if let responseData = responseData {
                        os_log(.error, log: Self.log, "[sendProviderMessage] Extension rejected 'reload_categories' with response: %{public}@", responseData as NSData)
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: extension rejected reload_categories: \(responseData as NSData)")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -2, description: "Extension failed to reload categories")))
                    } else {
                        os_log(.error, log: Self.log, "[sendProviderMessage] Extension returned nil response for 'reload_categories'.")
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: extension returned nil response")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -1, description: "Extension returned nil response to reload_categories message")))
                    }
                }
            } catch {
                let nsError = error as NSError
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: sendProviderMessage THREW: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.failure(AuraTunnelError(stage: "sendProviderMessage", error: error)))
            }
        }

        if let existing = targetManager {
            sendIPC(existing)
        } else {
            getManager { result in
                switch result {
                case .success(let manager):
                    sendIPC(manager)
                case .failure(let error):
                    os_log(.info, log: Self.log, "[sendProviderMessage] Could not load manager (%{public}@); skipping live reload_categories IPC", error.underlyingDescription)
                    AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyCategoriesUpdated: getManager failed: \(error.underlyingDescription)")
                    AuraDiagnostics.flushNewLogsToConsole()
                    completion(.success(false))
                }
            }
        }
    }

    /// Signals a currently connected tunnel to reload its default domain overrides from App Group storage.
    public func notifyDefaultOverridesUpdated(completion: @escaping (Result<Bool, AuraTunnelError>) -> Void) {
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated entered")
        let sendIPC: (NETunnelProviderManager) -> Void = { manager in
            guard let session = manager.connection as? NETunnelProviderSession else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Connection is not a NETunnelProviderSession; skipping live reload_default_overrides IPC")
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: connection is NOT NETunnelProviderSession")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let currentStatus = session.status
            guard currentStatus == .connected else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Tunnel status is %{public}@, not .connected; skipping live reload_default_overrides IPC", Status.from(vpnStatus: currentStatus).rawValue)
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: status is \(Status.from(vpnStatus: currentStatus).rawValue) (not .connected)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.success(false))
                return
            }

            let message = Data("reload_default_overrides".utf8)
            os_log(.info, log: Self.log, "[sendProviderMessage] Sending 'reload_default_overrides' IPC to connected extension...")
            AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: sending 'reload_default_overrides' IPC...")
            do {
                try session.sendProviderMessage(message) { responseData in
                    if let responseData = responseData, responseData == Data([1]) {
                        os_log(.info, log: Self.log, "[sendProviderMessage] Extension acknowledged 'reload_default_overrides'.")
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: extension acknowledged reload_default_overrides")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.success(true))
                    } else if let responseData = responseData {
                        os_log(
                            .error,
                            log: Self.log,
                            "[sendProviderMessage] Extension rejected 'reload_default_overrides' with response: %{public}@",
                            responseData as NSData
                        )
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: extension rejected: \(responseData as NSData)")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -2, description: "Extension failed to reload default domain overrides")))
                    } else {
                        os_log(.error, log: Self.log, "[sendProviderMessage] Extension returned nil response for 'reload_default_overrides'.")
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: extension returned nil response")
                        AuraDiagnostics.flushNewLogsToConsole()
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -1, description: "Extension returned nil response to reload_default_overrides message")))
                    }
                }
            } catch {
                let nsError = error as NSError
                AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: sendProviderMessage THREW: \(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
                AuraDiagnostics.flushNewLogsToConsole()
                completion(.failure(AuraTunnelError(stage: "sendProviderMessage", error: error)))
            }
        }

        if let existing = targetManager {
            sendIPC(existing)
        } else {
            getManager { result in
                switch result {
                case .success(let manager):
                    sendIPC(manager)
                case .failure(let error):
                    os_log(.info, log: Self.log, "[sendProviderMessage] Could not load manager (%{public}@); skipping live reload IPC", error.underlyingDescription)
                    AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyDefaultOverridesUpdated: getManager failed: \(error.underlyingDescription)")
                    AuraDiagnostics.flushNewLogsToConsole()
                    completion(.success(false))
                }
            }
        }
    }

    /// Signals a currently connected tunnel to reload its policy mode from the App Group storage.
    public func notifyPolicyUpdated(completion: ((Result<Bool, AuraTunnelError>) -> Void)? = nil) {
        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyPolicyUpdated entered")
        getManager { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                guard let session = manager.connection as? NETunnelProviderSession else {
                    completion?(.success(false))
                    return
                }
                guard session.status == .connected else {
                    completion?(.success(false))
                    return
                }
                let message = Data("reload_policy".utf8)
                do {
                    try session.sendProviderMessage(message) { _ in
                        AuraDiagnostics.log(tag: "AuraTunnelManager", message: "notifyPolicyUpdated acknowledged")
                        completion?(.success(true))
                    }
                } catch {
                    completion?(.success(false))
                }
            case .failure(let err):
                completion?(.failure(err))
            }
        }
    }
}
