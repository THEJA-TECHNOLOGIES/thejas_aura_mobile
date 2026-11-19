import Foundation
import NetworkExtension
import SystemExtensions
import os.log

/// Manages the NEDNSProxyProvider lifecycle from the Flutter/macOS side.
/// Uses NEDNSProxyManager to enable/disable the DNS proxy.
final class AuraDNSProxyManager {
    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "AuraDNSProxyManager")

    static let shared = AuraDNSProxyManager()

    enum Status: String {
        case disconnected = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
        case disconnecting = "disconnecting"
        case invalid = "invalid"
        case approvalRequired = "approval_required"
        case error = "error"
    }

    private var onStatusChanged: ((Status) -> Void)?

    var statusCallback: ((Status) -> Void)? {
        get { onStatusChanged }
        set { onStatusChanged = newValue }
    }

    private var extensionDelegate: SystemExtensionDelegate?

    // MARK: - Control

    func getStatus() -> Status {
        let manager = NEDNSProxyManager.shared()
        return manager.isEnabled ? .connected : .disconnected
    }

    func startFilter(completion: @escaping (Result<Void, Error>) -> Void) {
        os_log(.info, log: Self.log, "startFilter requested")

        // Step 1: Activate the system extension first
        activateSystemExtension { [weak self] activationError in
            if let activationError = activationError {
                os_log(.error, log: Self.log, "System extension activation failed: %{public}@", activationError.localizedDescription)
                // Check if it's a "needs approval" error
                let nsError = activationError as NSError
                if nsError.code == OSSystemExtensionError.authorizationRequired.rawValue {
                    os_log(.info, log: Self.log, "System extension needs user approval in System Settings")
                    self?.onStatusChanged?(.approvalRequired)
                    completion(.failure(activationError))
                    return
                }
                // For other errors, try to continue — extension might already be approved
                os_log(.info, log: Self.log, "Continuing despite activation error (extension may already be approved)")
            }

            // Step 2: Load preferences and enable the proxy
            let manager = NEDNSProxyManager.shared()
            manager.loadFromPreferences { error in
                if let error = error {
                    os_log(.error, log: Self.log, "loadFromPreferences failed: %{public}@", error.localizedDescription)
                    completion(.failure(error))
                    return
                }

                let dnsProtocol = NEDNSProxyProviderProtocol()
                dnsProtocol.providerBundleIdentifier = "com.thejatech.aura.AuraDNSProxy"
                dnsProtocol.serverAddress = "127.0.0.1"
                manager.providerProtocol = dnsProtocol
                manager.localizedDescription = "Theja's Aura DNS Firewall"
                manager.isEnabled = true

                manager.saveToPreferences { saveError in
                    if let saveError = saveError {
                        os_log(.error, log: Self.log, "saveToPreferences failed: %{public}@ (domain=%{public}@, code=%{public}ld)",
                               saveError.localizedDescription, (saveError as NSError).domain, (saveError as NSError).code)
                        completion(.failure(saveError))
                        return
                    }

                    os_log(.info, log: Self.log, "startFilter succeeded — proxy enabled")
                    self?.onStatusChanged?(.connected)
                    completion(.success(()))
                }
            }
        }
    }

    private func activateSystemExtension(completion: @escaping (Error?) -> Void) {
        os_log(.info, log: Self.log, "Activating system extension: com.thejatech.aura.AuraDNSProxy")

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.thejatech.aura.AuraDNSProxy",
            queue: .main
        )
        let delegate = SystemExtensionDelegate(completion: completion)
        request.delegate = delegate
        // Keep a strong reference to the delegate
        self.extensionDelegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func stopFilter(completion: @escaping (Result<Void, Error>) -> Void) {
        os_log(.info, log: Self.log, "stopFilter requested")

        let manager = NEDNSProxyManager.shared()
        manager.loadFromPreferences { [weak self] error in
            if let error = error {
                os_log(.error, log: Self.log, "loadFromPreferences failed: %{public}@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            manager.isEnabled = false
            manager.saveToPreferences { saveError in
                if let saveError = saveError {
                    os_log(.error, log: Self.log, "saveToPreferences failed: %{public}@", saveError.localizedDescription)
                    completion(.failure(saveError))
                    return
                }

                os_log(.info, log: Self.log, "stopFilter succeeded — proxy disabled")
                self?.onStatusChanged?(.disconnected)
                completion(.success(()))
            }
        }
    }

    // MARK: - Policy

    func getPolicyMode() -> String {
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        return defaults?.string(forKey: "vpn_policy_mode") ?? "enabled"
    }

    func getPauseExpiryMillis() -> Int64 {
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        return defaults?.object(forKey: "vpn_pause_expiry_utc_millis") as? Int64 ?? 0
    }

    func pauseFilter(durationMinutes: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let expiry = Int64(Date().timeIntervalSince1970 * 1000) + Int64(durationMinutes) * 60 * 1000
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        defaults?.set("paused", forKey: "vpn_policy_mode")
        defaults?.set(expiry, forKey: "vpn_pause_expiry_utc_millis")
        os_log(.info, log: Self.log, "pauseFilter set for %{public}d minutes", durationMinutes)
        completion(.success(()))
    }

    func shutdownFilter(completion: @escaping (Result<Void, Error>) -> Void) {
        let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
        defaults?.set("manually_disabled", forKey: "vpn_policy_mode")
        defaults?.set(0, forKey: "vpn_pause_expiry_utc_millis")
        stopFilter { _ in }
        os_log(.info, log: Self.log, "shutdownFilter completed")
        completion(.success(()))
    }

    // MARK: - IPC (File-Based Signaling)

    private static let appGroupIdentifier = "group.com.thejatech.aura"
    private static let containerURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )

    private static func signalFileURL(_ name: String) -> URL? {
        return containerURL?.appendingPathComponent(name)
    }

    private func writeSignalFile(_ name: String) {
        guard let url = Self.signalFileURL(name) else { return }
        let timestamp = String(Date().timeIntervalSince1970)
        try? timestamp.write(to: url, atomically: true, encoding: .utf8)
    }

    func notifyRulesUpdated(completion: @escaping (Result<Bool, Error>) -> Void) {
        writeSignalFile(".rules_reload")
        os_log(.info, log: Self.log, "notifyRulesUpdated — signal file written")
        completion(.success(true))
    }

    func notifyCategoriesUpdated(completion: @escaping (Result<Bool, Error>) -> Void) {
        writeSignalFile(".categories_reload")
        os_log(.info, log: Self.log, "notifyCategoriesUpdated — signal file written")
        completion(.success(true))
    }

    func notifyDefaultOverridesUpdated(completion: @escaping (Result<Bool, Error>) -> Void) {
        writeSignalFile(".default_overrides_reload")
        os_log(.info, log: Self.log, "notifyDefaultOverridesUpdated — signal file written")
        completion(.success(true))
    }

    func notifyBlocklistInstalled(completion: @escaping (Result<Bool, Error>) -> Void) {
        writeSignalFile(".blocklist_installed")
        os_log(.info, log: Self.log, "notifyBlocklistInstalled — signal file written")
        completion(.success(true))
    }
}

// MARK: - System Extension Delegate

private class SystemExtensionDelegate: NSObject, OSSystemExtensionRequestDelegate {
    private let completion: (Error?) -> Void

    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension newExtension: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        os_log(.info, log: OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "SystemExtension"), "Replacing existing extension")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log(.info, log: OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "SystemExtension"), "System extension needs user approval — check System Settings > General > Login Items & Extensions")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        os_log(.info, log: OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "SystemExtension"), "System extension activation result: %{public}ld", result.rawValue)
        completion(nil)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        os_log(.error, log: OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "SystemExtension"), "System extension activation failed: %{public}@", error.localizedDescription)
        completion(error)
    }
}
