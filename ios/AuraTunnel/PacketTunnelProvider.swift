import Foundation
import NetworkExtension
import os.log

/// Clean-room Network Extension PacketTunnelProvider following the Lockdown Privacy architectural pattern:
/// Configures NEDNSSettings to 127.0.0.1 with matchDomains = [""] and runs the local AuraLocalDNSResolver.
open class PacketTunnelProvider: NEPacketTunnelProvider {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "PacketTunnelProvider")

    private let dnsEngine = AuraDNSEngine()
    private lazy var resolver = AuraLocalDNSResolver(engine: self.dnsEngine)
    private let activityDatabase = AuraActivityDatabase()
    private lazy var activityWriter = AuraActivityWriter(database: self.activityDatabase)

    private var tunnelStartTime: Date?

    private static var crashHandlersInstalled = false
    private static func installCrashHandlersOnce() {
        guard !crashHandlersInstalled else { return }
        crashHandlersInstalled = true

        NSSetUncaughtExceptionHandler { exception in
            AuraDiagnostics.log(
                tag: "FATAL-EXCEPTION",
                message: "\(exception.name.rawValue): \(exception.reason ?? "no reason")\n\(exception.callStackSymbols.prefix(10).joined(separator: "\n"))"
            )
        }

        signal(SIGABRT) { sig in
            AuraDiagnostics.log(tag: "FATAL-SIGNAL", message: "Process received SIGABRT (\(sig))")
            exit(128 + sig)
        }
        signal(SIGSEGV) { sig in
            AuraDiagnostics.log(tag: "FATAL-SIGNAL", message: "Process received SIGSEGV (\(sig))")
            exit(128 + sig)
        }
        signal(SIGBUS) { sig in
            AuraDiagnostics.log(tag: "FATAL-SIGNAL", message: "Process received SIGBUS (\(sig))")
            exit(128 + sig)
        }
    }

    open override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Self.installCrashHandlersOnce()
        tunnelStartTime = Date()
        let actId = UUID().uuidString.prefix(6)
        os_log(.info, log: Self.log, "startTunnel invoked")
        AuraDiagnostics.log(tag: "PacketTunnel", message: "startTunnel [\(actId)] ENTERED (options: \(options?.keys.joined(separator: ",") ?? "none"))")

        // 1. Wire up fatal error callback so the tunnel is cancelled if the resolver fails
        resolver.onFatalError = { [weak self] error in
            let nsErr = error as NSError
            os_log(.error, log: Self.log, "Fatal DNS resolver failure: %{public}@ — canceling tunnel", error.localizedDescription)
            AuraDiagnostics.log(tag: "PacketTunnel", message: "onFatalError [\(actId)]: domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) — canceling tunnel")
            self?.cancelTunnelWithError(error)
        }

        // 2. Open activity database and start asynchronous queue writer
        let dbStart = CFAbsoluteTimeGetCurrent()
        if activityDatabase.open() {
            // Prune records according to configured user preference (7 or 30 days, default 30)
            let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
            let configuredDays = defaults?.integer(forKey: "log_retention_days") ?? 30
            let retentionDays: Int64 = (configuredDays == 7 || configuredDays == 30) ? Int64(configuredDays) : 30
            let retentionCutoff = Int64(Date().timeIntervalSince1970 * 1000) - (retentionDays * 24 * 60 * 60 * 1000)
            activityDatabase.pruneRetention(cutoffUtcMillis: retentionCutoff)

            activityWriter.start()
            resolver.activityWriter = activityWriter
            os_log(.info, log: Self.log, "Activity database opened and writer started")
            AuraDiagnostics.log(tag: "PacketTunnel", message: "Activity database opened in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - dbStart))s")
        } else {
            os_log(.error, log: Self.log, "Activity database failed to open; continuing tunnel without activity logging")
            AuraDiagnostics.log(tag: "PacketTunnel", message: "Activity database failed to open; continuing without activity logging")
        }

        // 3. Load active rules and categories from shared App Group container
        let rulesLoaded = loadRulesFromAppGroup()
        let categoriesLoaded = loadCategoriesAndPreferences()
        AuraDiagnostics.log(tag: "PacketTunnel", message: "App Group rules loaded=\(rulesLoaded) categories loaded=\(categoriesLoaded)")

        // 4. Start local DNS socket resolver on 127.0.0.1:53
        let resolverStart = CFAbsoluteTimeGetCurrent()
        let started = resolver.start()
        guard started else {
            os_log(.error, log: Self.log, "Failed to start local DNS resolver on 127.0.0.1:53")
            AuraDiagnostics.log(tag: "PacketTunnel", message: "FATAL [\(actId)]: resolver.start() failed to bind to 127.0.0.1:53")
            resolver.activityWriter = nil
            activityWriter.flushAndClose(timeout: 0.5)
            let error = NSError(domain: "AuraTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind local DNS resolver to 127.0.0.1:53"])
            completionHandler(error)
            return
        }
        AuraDiagnostics.log(tag: "PacketTunnel", message: "resolver.start() SUCCEEDED in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - resolverStart))s")

        // 5. Configure Tunnel Network Settings following Lockdown pattern
        let tunnelSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Direct system DNS to the local loopback resolver with global match
        let dnsSettings = NEDNSSettings(servers: ["127.0.0.1"])
        dnsSettings.matchDomains = [""] // Catch all system domains
        tunnelSettings.dnsSettings = dnsSettings

        // Configure loopback IPv4 settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.255.255.2"], subnetMasks: ["255.255.255.252"])
        ipv4Settings.includedRoutes = [NEIPv4Route(destinationAddress: "127.0.0.1", subnetMask: "255.255.255.255")]
        tunnelSettings.ipv4Settings = ipv4Settings

        AuraDiagnostics.log(tag: "PacketTunnel", message: "Calling setTunnelNetworkSettings [\(actId)]...")
        setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
            if let error = error {
                let nsError = error as NSError
                os_log(
                    .error,
                    log: Self.log,
                    "setTunnelNetworkSettings FAILED — domain=%{public}@ code=%{public}ld description=%{public}@",
                    nsError.domain,
                    nsError.code,
                    nsError.localizedDescription
                )
                AuraDiagnostics.log(
                    tag: "PacketTunnel",
                    message: "setTunnelNetworkSettings FAILED [\(actId)] — domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)"
                )
                self?.resolver.stop()
                self?.resolver.activityWriter = nil
                self?.activityWriter.flushAndClose(timeout: 0.5)
                completionHandler(error)
            } else {
                os_log(.info, log: Self.log, "setTunnelNetworkSettings applied successfully. System DNS routed to 127.0.0.1.")
                AuraDiagnostics.log(
                    tag: "PacketTunnel",
                    message: "setTunnelNetworkSettings SUCCEEDED [\(actId)]. System DNS routed to 127.0.0.1. Tunnel startup complete. Calling completionHandler(nil)"
                )
                completionHandler(nil)
            }
        }
    }

    private static func stopReasonString(_ reason: NEProviderStopReason) -> String {
        switch reason {
        case .none: return "none"
        case .userInitiated: return "userInitiated"
        case .providerFailed: return "providerFailed"
        case .noNetworkAvailable: return "noNetworkAvailable"
        case .unrecoverableNetworkChange: return "unrecoverableNetworkChange"
        case .providerDisabled: return "providerDisabled"
        case .authenticationCanceled: return "authenticationCanceled"
        case .configurationFailed: return "configurationFailed"
        case .idleTimeout: return "idleTimeout"
        case .configurationDisabled: return "configurationDisabled"
        case .configurationRemoved: return "configurationRemoved"
        case .superceded: return "superceded"
        case .userLogout: return "userLogout"
        case .userSwitch: return "userSwitch"
        case .connectionFailed: return "connectionFailed"
        case .sleep: return "sleep"
        case .appUpdate: return "appUpdate"
        case .internalError: return "internalError"
        @unknown default: return "unknown(\(reason.rawValue))"
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let reasonStr = Self.stopReasonString(reason)
        let uptime: String
        if let start = tunnelStartTime {
            uptime = String(format: "%.2fs", Date().timeIntervalSince(start))
        } else {
            uptime = "unknown"
        }
        os_log(.info, log: Self.log, "stopTunnel invoked with reason: %{public}ld (%{public}@)", reason.rawValue, reasonStr)
        AuraDiagnostics.log(tag: "PacketTunnel", message: "stopTunnel INVOKED by iOS — reason=\(reason.rawValue) (\(reasonStr)) uptime=\(uptime)")

        resolver.stop()
        resolver.activityWriter = nil
        activityWriter.flushAndClose(timeout: 0.5)
        dnsEngine.setCompactIndex(nil)
        dnsEngine.setCategories([:])
        dnsEngine.setRules([])
        AuraDiagnostics.log(tag: "PacketTunnel", message: "stopTunnel cleanup finished. Calling completionHandler()")
        completionHandler()
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let command = String(data: messageData, encoding: .utf8) else {
            AuraDiagnostics.log(tag: "PacketTunnel", message: "handleAppMessage received non-UTF8 payload")
            completionHandler?(nil)
            return
        }

        AuraDiagnostics.log(tag: "PacketTunnel", message: "handleAppMessage received: '\(command)'")
        switch command {
        case "reload_rules":
            os_log(.info, log: Self.log, "handleAppMessage: reloading rules and category preferences from App Group")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    completionHandler?(nil)
                    return
                }
                let rulesApplied = self.loadRulesFromAppGroup()
                let categoriesApplied = self.loadCategoriesAndPreferences()
                AuraDiagnostics.log(tag: "PacketTunnel", message: "reload_rules result: rules=\(rulesApplied) categories=\(categoriesApplied)")
                completionHandler?((rulesApplied && categoriesApplied) ? Data([1]) : Data([0]))
            }

        case "reload_categories":
            os_log(.info, log: Self.log, "handleAppMessage: reloading category preferences from App Group")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    completionHandler?(nil)
                    return
                }
                let categoriesApplied = self.loadCategoriesAndPreferences()
                AuraDiagnostics.log(tag: "PacketTunnel", message: "reload_categories result: categories=\(categoriesApplied)")
                completionHandler?(categoriesApplied ? Data([1]) : Data([0]))
            }

        case "reload_default_overrides":
            os_log(.info, log: Self.log, "handleAppMessage: reloading default domain overrides from App Group")
            let overrides = AuraCategoryStore.loadDisabledDefaultDomains()
            dnsEngine.setDisabledDefaultDomains(overrides)
            AuraDiagnostics.log(tag: "PacketTunnel", message: "reload_default_overrides result: count=\(overrides.count)")
            completionHandler?(Data([1]))

        default:
            AuraDiagnostics.log(tag: "PacketTunnel", message: "Unknown handleAppMessage command: '\(command)'")
            completionHandler?(nil)
        }
    }

    @discardableResult
    private func loadRulesFromAppGroup() -> Bool {
        let result = AuraRuleStore.loadRulesResult()
        switch result {
        case .success(let rules):
            os_log(.info, log: Self.log, "Loaded %{public}ld rules from App Group", rules.count)
            dnsEngine.setRules(rules)
            AuraDiagnostics.log(tag: "PacketTunnel", message: "loadRulesFromAppGroup loaded \(rules.count) rules")
            return true
        case .failure(let error):
            os_log(.error, log: Self.log, "Failed to load rules from App Group: %{public}@ — retaining existing in-memory rules", error.localizedDescription)
            AuraDiagnostics.log(tag: "PacketTunnel", message: "loadRulesFromAppGroup failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func loadCategoriesAndPreferences() -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        AuraDiagnostics.log(tag: "PacketTunnel", message: "loadCategoriesAndPreferences started (mem: \(AuraDiagnostics.formattedMemory()))")
        return autoreleasepool {
            // 1. Load active compact category index
            // IMPORTANT: Build new state separately; do NOT clear dnsEngine beforehand so existing rules remain active on failure!
            guard let newIndex = AuraCategoryStore.loadActiveCompactIndex() else {
                // If no release installed, clean swap to nil
                if AuraCategoryStore.categoriesDirectoryURL == nil {
                    dnsEngine.setCompactIndex(nil)
                    let overrides = AuraCategoryStore.loadDisabledDefaultDomains()
                    dnsEngine.setDisabledDefaultDomains(overrides)
                    let prefs = AuraCategoryStore.loadPreferences()
                    dnsEngine.setCategoryPreferences(prefs)
                    AuraDiagnostics.log(tag: "PacketTunnel", message: "loadCategoriesAndPreferences: no active release installed; cleared category index")
                    return true
                }
                // Release directory exists but failed to load index: retain previous index
                os_log(.error, log: Self.log, "Failed to load compact category index — retaining existing in-memory index")
                AuraDiagnostics.log(tag: "PacketTunnel", message: "loadCategoriesAndPreferences FAILED to load index; retaining existing index")
                return false
            }

            // 2. Atomic swap into dnsEngine
            dnsEngine.setCompactIndex(newIndex)
            AuraDiagnostics.log(tag: "PacketTunnel", message: "Atomic swap succeeded: \(newIndex.count) domains across \(newIndex.categoryNames.count) categories: [\(newIndex.categoryNames.joined(separator: ", "))] (mem: \(AuraDiagnostics.formattedMemory()))")

            // 3. Load disabled default domain overrides
            let overrides = AuraCategoryStore.loadDisabledDefaultDomains()
            dnsEngine.setDisabledDefaultDomains(overrides)

            // 4. Load category preferences
            let result = AuraCategoryStore.loadPreferencesResult()
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            switch result {
            case .success(let prefs):
                dnsEngine.setCategoryPreferences(prefs)
                os_log(.info, log: Self.log, "Loaded %{public}ld domains in %{public}ld categories, %{public}ld preferences, and %{public}ld disabled overrides", newIndex.count, newIndex.categoryNames.count, prefs.count, overrides.count)
                AuraDiagnostics.log(tag: "PacketTunnel", message: "loadCategoriesAndPreferences completed in \(String(format: "%.3f", elapsed))s with \(newIndex.count) domains across \(newIndex.categoryNames.count) categories, \(prefs.count) preferences, \(overrides.count) overrides (mem: \(AuraDiagnostics.formattedMemory()))")
                return true
            case .failure(let error):
                os_log(.error, log: Self.log, "Failed to load category preferences from App Group: %{public}@ — using fallback/existing preferences", error.localizedDescription)
                AuraDiagnostics.log(tag: "PacketTunnel", message: "loadCategoriesAndPreferences failed in \(String(format: "%.3f", elapsed))s to load preferences: \(error.localizedDescription) (mem: \(AuraDiagnostics.formattedMemory()))")
                return false
            }
        }
    }
}
