import Foundation
import NetworkExtension
import SQLite3
import os.log

/// macOS DNS Proxy Provider using NEDNSProxyProvider.
/// Intercepts system DNS queries via NEAppProxyUDPFlow (macOS 15+),
/// evaluates against AuraDNSEngine, and either synthesizes blocked responses
/// or forwards upstream.
@available(macOS 15.0, *)
final class AuraDNSProxyProvider: NEDNSProxyProvider {
    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraDNSProxy", category: "AuraDNSProxyProvider")

    private let engine = AuraDNSEngine()
    private var activeFlows: [Int: AuraDNSFlow] = [:]
    private let flowLock = NSLock()

    // MARK: - Activity Logging

    private var activityDatabase: AuraActivityDatabase?
    private var activityWriter: AuraActivityWriter?

    // MARK: - Reload Signal Tracking

    private var lastRulesReloadTime: Date?
    private var lastCategoriesReloadTime: Date?
    private var lastOverridesReloadTime: Date?
    private var lastBlocklistReloadTime: Date?

    private static let appGroupIdentifier = "group.com.thejatech.aura"
    private static let containerURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )

    private static func signalFileURL(_ name: String) -> URL? {
        return containerURL?.appendingPathComponent(name)
    }

    // MARK: - Reload Signal Checking

    func checkReloadSignals() {
        // Check rules reload
        if let url = Self.signalFileURL(".rules_reload"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            if lastRulesReloadTime == nil || mtime > lastRulesReloadTime! {
                lastRulesReloadTime = mtime
                reloadRules()
            }
        }

        // Check categories reload
        if let url = Self.signalFileURL(".categories_reload"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            if lastCategoriesReloadTime == nil || mtime > lastCategoriesReloadTime! {
                lastCategoriesReloadTime = mtime
                reloadCategories()
            }
        }

        // Check default overrides reload
        if let url = Self.signalFileURL(".default_overrides_reload"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            if lastOverridesReloadTime == nil || mtime > lastOverridesReloadTime! {
                lastOverridesReloadTime = mtime
                reloadDefaultOverrides()
            }
        }

        // Check blocklist installed (full reload)
        if let url = Self.signalFileURL(".blocklist_installed"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            if lastBlocklistReloadTime == nil || mtime > lastBlocklistReloadTime! {
                lastBlocklistReloadTime = mtime
                reloadRules()
                reloadCategories()
                reloadDefaultOverrides()
            }
        }
    }

    private func reloadRules() {
        let rules = AuraRuleStore.loadRules()
        engine.setRules(rules)
        os_log(.info, log: Self.log, "Reloaded %{public}ld rules from App Group", rules.count)
    }

    private func reloadCategories() {
        let categories = AuraCategoryStore.loadAllBundledCategories()
        engine.setCategories(categories)

        let prefs = AuraCategoryStore.loadPreferences()
        engine.setCategoryPreferences(prefs)

        if let compactIndex = AuraCategoryStore.loadActiveCompactIndex() {
            engine.setCompactIndex(compactIndex)
        }
        os_log(.info, log: Self.log, "Reloaded %{public}ld categories", categories.count)
    }

    private func reloadDefaultOverrides() {
        let disabled = AuraCategoryStore.loadDisabledDefaultDomains()
        engine.setDisabledDefaultDomains(disabled)
        os_log(.info, log: Self.log, "Reloaded %{public}ld disabled default domains", disabled.count)
    }

    // MARK: - NEDNSProxyProvider Lifecycle

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        os_log(.info, log: Self.log, "startProxy invoked")

        // Initialize activity database and writer for DNS event logging
        do {
            try AuraActivityDatabase.bootstrapSharedDatabase()
            let db = AuraActivityDatabase()
            if db.open() {
                self.activityDatabase = db
                let writer = AuraActivityWriter(database: db)
                writer.start()
                self.activityWriter = writer
                os_log(.info, log: Self.log, "Activity database and writer initialized")
            } else {
                os_log(.error, log: Self.log, "Failed to open activity database")
            }
        } catch {
            os_log(.error, log: Self.log, "Activity database bootstrap failed: %{public}@", error.localizedDescription)
        }

        // Load rules and categories from App Group
        let rulesLoaded = loadRulesFromAppGroup()
        let categoriesLoaded = loadCategoriesAndPreferences()
        os_log(.info, log: Self.log, "Rules loaded=%{public}d categories loaded=%{public}d", rulesLoaded ? 1 : 0, categoriesLoaded ? 1 : 0)

        // Log rule/category counts for diagnostics
        let ruleCount = AuraRuleStore.loadRules().count
        let categoryPrefs = AuraCategoryStore.loadPreferences()
        os_log(.info, log: Self.log, "Custom rules: %{public}d, Category preferences: %{public}d", ruleCount, categoryPrefs.count)

        completionHandler(nil)
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log(.info, log: Self.log, "stopProxy invoked — reason=%{public}ld", reason.rawValue)

        // Close all active flows
        flowLock.lock()
        let flowsToClose = activeFlows
        activeFlows.removeAll()
        flowLock.unlock()

        for (_, flow) in flowsToClose {
            flow.close()
        }

        completionHandler()
    }

    // MARK: - Flow Handling (macOS 15+)

    override func handleNewUDPFlow(_ flow: NEAppProxyUDPFlow, initialRemoteEndpoint remoteEndpoint: NWEndpoint) -> Bool {
        os_log(.info, log: Self.log, "handleNewUDPFlow — flowIdentifier=%{public}d", flow.hash)

        let dnsFlow = AuraDNSFlow(
            flow: flow,
            engine: engine,
            activityLogger: activityWriter,
            reloadChecker: { [weak self] in self?.checkReloadSignals() }
        )

        flowLock.lock()
        activeFlows[flow.hash] = dnsFlow
        flowLock.unlock()

        // Open the flow with a local endpoint
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            if let error = error {
                os_log(.error, log: Self.log, "Flow open failed: %{public}@", error.localizedDescription)
                self?.removeFlow(withIdentifier: flow.hash)
                return
            }
            os_log(.info, log: Self.log, "Flow %{public}d opened successfully", flow.hash)
            dnsFlow.startReading()
        }

        return true
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        os_log(.debug, log: Self.log, "handleNewFlow — flowIdentifier=%{public}d (fallback path)", flow.hash)

        // On macOS 15+, UDP flows should go through handleNewUDPFlow.
        // This fallback handles any non-UDP flows by terminating them.
        return false
    }

    func removeFlow(withIdentifier flowIdentifier: Int) {
        flowLock.lock()
        activeFlows.removeValue(forKey: flowIdentifier)
        flowLock.unlock()
    }

    // MARK: - App Group Loading

    private func loadRulesFromAppGroup() -> Bool {
        reloadRules()
        return true
    }

    private func loadCategoriesAndPreferences() -> Bool {
        reloadCategories()
        reloadDefaultOverrides()
        return true
    }

    deinit {
        activityWriter?.stop()
        activityDatabase?.close()
    }
}

// MARK: - ActivityLogger conformance for AuraActivityWriter

extension AuraActivityWriter: ActivityLogger {
    public func log(domain: String, queryType: String, outcome: String,
                    matchedSource: String, matchedRuleId: String?,
                    matchedCategories: [String], reason: String?) {
        let record = ActivityRecord(
            domain: domain,
            queryType: queryType,
            outcome: outcome,
            matchedSource: matchedSource,
            matchedRuleId: matchedRuleId,
            matchedCategories: matchedCategories,
            reason: reason
        )
        enqueue(record)
    }
}
