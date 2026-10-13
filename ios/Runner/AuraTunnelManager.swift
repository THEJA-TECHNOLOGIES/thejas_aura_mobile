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
        if let notifiedConnection = notification.object as? NEVPNConnection,
           let targetConnection = targetManager?.connection,
           notifiedConnection !== targetConnection {
            return
        }
        guard let connection = (notification.object as? NEVPNConnection) ?? targetManager?.connection else { return }
        let rawStatus = connection.status
        let status = Status.from(vpnStatus: rawStatus)
        os_log(.info, log: Self.log, "[NEVPNStatusDidChange] status=%{public}@ (raw=%{public}ld)", status.rawValue, rawStatus.rawValue)
        onStatusChanged?(status)
    }

    /// Ensures the given manager has the expected NETunnelProviderProtocol and bundle identifier.
    private func applyConfiguration(to manager: NETunnelProviderManager) {
        let tunnelProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = AuraTunnelManager.tunnelBundleIdentifier
        tunnelProtocol.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Theja's Aura Local Firewall"
        manager.isEnabled = true

        os_log(
            .info,
            log: Self.log,
            "[configureManager] providerBundleIdentifier=%{public}@ isEnabled=%{public}d serverAddress=%{public}@",
            tunnelProtocol.providerBundleIdentifier ?? "nil",
            manager.isEnabled ? 1 : 0,
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
                completion(.success(existing))
                return
            }

            os_log(.info, log: Self.log, "[getManager] No existing manager for %{public}@; creating new configuration", AuraTunnelManager.tunnelBundleIdentifier)
            let newManager = NETunnelProviderManager()
            self?.applyConfiguration(to: newManager)
            self?.targetManager = newManager
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
        os_log(.info, log: Self.log, "[startTunnel] Beginning tunnel startup sequence...")
        getManager { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let manager):
                // Step 2: Ensure protocol configuration and isEnabled are set
                self.applyConfiguration(to: manager)

                // Step 3: Save to preferences
                os_log(.info, log: Self.log, "[saveToPreferences] Saving configuration...")
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
                        completion(.failure(AuraTunnelError(stage: "saveToPreferences", error: saveError)))
                        return
                    }

                    os_log(.info, log: Self.log, "[saveToPreferences] SUCCEEDED — reloading configuration from preferences...")

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
                            completion(.failure(AuraTunnelError(stage: "loadFromPreferences", error: reloadError)))
                            return
                        }

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
                            completion(.failure(AuraTunnelError(stage: "startVPNTunnel", error: error)))
                        }
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Stops the local firewall tunnel.
    public func stopTunnel(completion: @escaping (Result<Void, AuraTunnelError>) -> Void) {
        os_log(.info, log: Self.log, "[stopTunnel] Requesting tunnel stop...")
        getManager { result in
            switch result {
            case .success(let manager):
                let statusBefore = manager.connection.status
                os_log(
                    .info,
                    log: Self.log,
                    "[stopTunnel] Stopping tunnel from status=%{public}@ (raw=%{public}ld)",
                    Status.from(vpnStatus: statusBefore).rawValue,
                    statusBefore.rawValue
                )
                manager.connection.stopVPNTunnel()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Signals a currently connected tunnel to reload its rules from the App Group storage.
    /// Always resolves a fresh manager to ensure no stale manager reference is used.
    public func notifyRulesUpdated(completion: @escaping (Result<Bool, AuraTunnelError>) -> Void) {
        let sendIPC: (NETunnelProviderManager) -> Void = { manager in
            guard let session = manager.connection as? NETunnelProviderSession else {
                os_log(
                    .info,
                    log: Self.log,
                    "[sendProviderMessage] Connection is not a NETunnelProviderSession; skipping live reload IPC"
                )
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
                completion(.success(false))
                return
            }

            let message = Data("reload_rules".utf8)
            os_log(.info, log: Self.log, "[sendProviderMessage] Sending 'reload_rules' IPC to connected extension...")
            do {
                try session.sendProviderMessage(message) { responseData in
                    if let responseData = responseData, responseData == Data([1]) {
                        os_log(
                            .info,
                            log: Self.log,
                            "[sendProviderMessage] Extension successfully acknowledged and applied 'reload_rules'."
                        )
                        completion(.success(true))
                    } else if let responseData = responseData {
                        os_log(
                            .error,
                            log: Self.log,
                            "[sendProviderMessage] Extension rejected 'reload_rules' with response: %{public}@",
                            responseData as NSData
                        )
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
                completion(.failure(AuraTunnelError(stage: "sendProviderMessage", error: error)))
            }
        }

        getManager { result in
            switch result {
            case .success(let manager):
                sendIPC(manager)
            case .failure(let error):
                os_log(.info, log: Self.log, "[sendProviderMessage] Could not load manager (%{public}@); skipping live reload IPC", error.underlyingDescription)
                completion(.success(false))
            }
        }
    }

    /// Signals a currently connected tunnel to reload its category preferences from App Group storage.
    public func notifyCategoriesUpdated(completion: @escaping (Result<Bool, AuraTunnelError>) -> Void) {
        let sendIPC: (NETunnelProviderManager) -> Void = { manager in
            guard let session = manager.connection as? NETunnelProviderSession else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Connection is not a NETunnelProviderSession; skipping live reload_categories IPC")
                completion(.success(false))
                return
            }

            let currentStatus = session.status
            guard currentStatus == .connected else {
                os_log(.info, log: Self.log, "[sendProviderMessage] Tunnel status is %{public}@, not .connected; skipping live reload_categories IPC", Status.from(vpnStatus: currentStatus).rawValue)
                completion(.success(false))
                return
            }

            let message = Data("reload_categories".utf8)
            os_log(.info, log: Self.log, "[sendProviderMessage] Sending 'reload_categories' IPC to connected extension...")
            do {
                try session.sendProviderMessage(message) { responseData in
                    if let responseData = responseData, responseData == Data([1]) {
                        os_log(.info, log: Self.log, "[sendProviderMessage] Extension acknowledged 'reload_categories'.")
                        completion(.success(true))
                    } else if let responseData = responseData {
                        os_log(.error, log: Self.log, "[sendProviderMessage] Extension rejected 'reload_categories' with response: %{public}@", responseData as NSData)
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -2, description: "Extension failed to reload categories")))
                    } else {
                        os_log(.error, log: Self.log, "[sendProviderMessage] Extension returned nil response for 'reload_categories'.")
                        completion(.failure(AuraTunnelError(stage: "sendProviderMessage", code: -1, description: "Extension returned nil response to reload_categories message")))
                    }
                }
            } catch {
                completion(.failure(AuraTunnelError(stage: "sendProviderMessage", error: error)))
            }
        }

        getManager { result in
            switch result {
            case .success(let manager):
                sendIPC(manager)
            case .failure(let error):
                os_log(.info, log: Self.log, "[sendProviderMessage] Could not load manager (%{public}@); skipping live reload_categories IPC", error.underlyingDescription)
                completion(.success(false))
            }
        }
    }
}
