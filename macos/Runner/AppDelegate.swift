import Cocoa
import FlutterMacOS
import SQLite3
import os.log

@main
class AppDelegate: FlutterAppDelegate {
    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "macOSAppDelegate")

    private var activityDatabase: AuraActivityDatabase?

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = mainFlutterWindow,
           let controller = window.contentViewController as? FlutterViewController {
            setupPlatformChannels(messenger: controller.engine.binaryMessenger)
        }
        super.applicationDidFinishLaunching(notification)

        // Initialize activity database for reading logs
        do {
            try AuraActivityDatabase.bootstrapSharedDatabase()
            let db = AuraActivityDatabase()
            if db.open() {
                self.activityDatabase = db
                os_log(.info, log: Self.log, "Activity database opened for reading")
            } else {
                os_log(.error, log: Self.log, "Failed to open activity database for reading")
            }
        } catch {
            os_log(.error, log: Self.log, "Activity database bootstrap failed: %{public}@", error.localizedDescription)
        }
    }

    private func setupPlatformChannels(messenger: FlutterBinaryMessenger) {
        let controlChannel = FlutterMethodChannel(name: "com.thejatech.aura/tunnel_control", binaryMessenger: messenger)
        let statusChannel = FlutterEventChannel(name: "com.thejatech.aura/tunnel_status", binaryMessenger: messenger)
        let activityChannel = FlutterMethodChannel(name: "com.thejatech.aura/activity", binaryMessenger: messenger)

        controlChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "getStatus":
                let status = AuraDNSProxyManager.shared.getStatus()
                result(status.rawValue)

            case "startTunnel":
                AuraDNSProxyManager.shared.startFilter { res in
                    switch res {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        let nsError = error as NSError
                        result(FlutterError(
                            code: "START_FAILED",
                            message: error.localizedDescription,
                            details: [
                                "domain": nsError.domain,
                                "code": nsError.code,
                                "localizedDescription": error.localizedDescription
                            ]
                        ))
                    }
                }

            case "stopTunnel":
                AuraDNSProxyManager.shared.stopFilter { res in
                    switch res {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "STOP_FAILED", message: error.localizedDescription, details: nil))
                    }
                }

            case "getRules":
                let storeResult = RunnerRuleStore.loadRulesResult()
                switch storeResult {
                case .success(let rules):
                    let ruleDicts = rules.map { $0.toDictionary() }
                    result(ruleDicts)
                case .failure(let error):
                    let nsError = error as NSError
                    result(FlutterError(code: "LOAD_RULES_FAILED", message: error.localizedDescription, details: nil))
                }

            case "syncRules":
                guard let args = call.arguments as? [[String: Any]] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected array of rule maps", details: nil))
                    return
                }
                var rules: [AuraRule] = []
                for item in args {
                    if let rule = AuraRule(dictionary: item) {
                        rules.append(rule)
                    }
                }
                do {
                    try RunnerRuleStore.saveRules(rules)
                    AuraDNSProxyManager.shared.notifyRulesUpdated { _ in
                        result(true)
                    }
                } catch {
                    result(FlutterError(code: "SAVE_RULES_FAILED", message: error.localizedDescription, details: nil))
                }

            case "validateDomain":
                guard let args = call.arguments as? [String: Any],
                      let rawDomain = args["domain"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'domain'", details: nil))
                    return
                }
                switch RunnerRuleStore.validateDomain(rawDomain) {
                case .success(let validated):
                    result(validated)
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "addRule":
                guard let args = call.arguments as? [String: Any],
                      let rawDomain = args["domain"] as? String,
                      let isBlocked = args["isBlocked"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'domain' and 'isBlocked'", details: nil))
                    return
                }
                let isEnabled = args["isEnabled"] as? Bool ?? true
                switch RunnerRuleStore.addRule(domain: rawDomain, isBlocked: isBlocked, isEnabled: isEnabled) {
                case .success(let newRule):
                    AuraDNSProxyManager.shared.notifyRulesUpdated { _ in
                        result(newRule.toDictionary())
                    }
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "updateRule":
                guard let args = call.arguments as? [String: Any],
                      let id = args["id"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'id'", details: nil))
                    return
                }
                let domain = args["domain"] as? String
                let isBlocked = args["isBlocked"] as? Bool
                let isEnabled = args["isEnabled"] as? Bool
                switch RunnerRuleStore.updateRule(id: id, domain: domain, isBlocked: isBlocked, isEnabled: isEnabled) {
                case .success(let updatedRule):
                    AuraDNSProxyManager.shared.notifyRulesUpdated { _ in
                        result(updatedRule.toDictionary())
                    }
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "deleteRule":
                guard let args = call.arguments as? [String: Any],
                      let id = args["id"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'id'", details: nil))
                    return
                }
                switch RunnerRuleStore.deleteRule(id: id) {
                case .success(let deletedRule):
                    AuraDNSProxyManager.shared.notifyRulesUpdated { _ in
                        result(deletedRule.toDictionary())
                    }
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "toggleRule":
                guard let args = call.arguments as? [String: Any],
                      let id = args["id"] as? String,
                      let isEnabled = args["isEnabled"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'id' and 'isEnabled'", details: nil))
                    return
                }
                switch RunnerRuleStore.toggleRule(id: id, isEnabled: isEnabled) {
                case .success(let updatedRule):
                    AuraDNSProxyManager.shared.notifyRulesUpdated { _ in
                        result(updatedRule.toDictionary())
                    }
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "getCategories":
                switch RunnerRuleStore.loadCategoryPreferences() {
                case .success(let prefs):
                    result(prefs)
                case .failure(let error):
                    result(FlutterError(code: "LOAD_CATEGORIES_FAILED", message: error.localizedDescription, details: nil))
                }

            case "setCategoryPreference":
                guard let args = call.arguments as? [String: Any],
                      let category = args["category"] as? String,
                      let isEnabled = args["isEnabled"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'category' and 'isEnabled'", details: nil))
                    return
                }
                switch RunnerRuleStore.setCategoryPreference(category: category, isEnabled: isEnabled) {
                case .success(let updatedPrefs):
                    AuraDNSProxyManager.shared.notifyCategoriesUpdated { _ in
                        result(updatedPrefs)
                    }
                case .failure(let error):
                    result(FlutterError(code: "SAVE_CATEGORIES_FAILED", message: error.localizedDescription, details: nil))
                }

            case "setAllCategoryPreferences":
                guard let args = call.arguments as? [String: Any],
                      let rawPrefs = args["preferences"] as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'preferences' map", details: nil))
                    return
                }
                var typedPrefs: [String: Bool] = [:]
                for (cat, val) in rawPrefs {
                    if let boolVal = val as? Bool {
                        typedPrefs[cat] = boolVal
                    }
                }
                do {
                    try RunnerRuleStore.saveCategoryPreferences(typedPrefs)
                    AuraDNSProxyManager.shared.notifyCategoriesUpdated { _ in
                        result(typedPrefs)
                    }
                } catch {
                    result(FlutterError(code: "SAVE_CATEGORIES_FAILED", message: error.localizedDescription, details: nil))
                }

            case "getDefaultDomainOverrides":
                switch RunnerRuleStore.loadDisabledDefaultDomains() {
                case .success(let disabled):
                    result(Array(disabled).sorted())
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "toggleDefaultDomain":
                guard let args = call.arguments as? [String: Any],
                      let rawDomain = args["domain"] as? String,
                      let isEnabled = args["isEnabled"] as? Bool else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'domain' and 'isEnabled'", details: nil))
                    return
                }
                switch RunnerRuleStore.toggleDefaultDomain(domain: rawDomain, isEnabled: isEnabled) {
                case .success(let updatedDisabled):
                    AuraDNSProxyManager.shared.notifyDefaultOverridesUpdated { _ in
                        result(Array(updatedDisabled).sorted())
                    }
                case .failure(let error):
                    result(FlutterError(code: error.errorCode, message: error.errorDescription, details: nil))
                }

            case "getInstalledRelease":
                let release = RunnerRuleStore.loadInstalledRelease()
                result(release)

            case "installBlocklistRelease":
                guard let args = call.arguments as? [String: Any],
                      let version = args["version"] as? String,
                      let files = args["files"] as? [String: String] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'version' and 'files'", details: nil))
                    return
                }
                let domainCount = args["domainCount"] as? Int ?? 0
                let etag = args["etag"] as? String
                let checksum = args["checksum"] as? String
                do {
                    var installRes = try RunnerRuleStore.installBlocklistRelease(
                        version: version, files: files, domainCount: domainCount, etag: etag, checksum: checksum
                    )
                    AuraDNSProxyManager.shared.notifyCategoriesUpdated { _ in
                        AuraDNSProxyManager.shared.notifyBlocklistInstalled { _ in
                            result(installRes)
                        }
                    }
                } catch {
                    result(FlutterError(code: "INSTALL_RELEASE_FAILED", message: error.localizedDescription, details: nil))
                }

            case "clearInstalledRelease":
                do {
                    try RunnerRuleStore.clearInstalledRelease()
                    AuraDNSProxyManager.shared.notifyCategoriesUpdated { _ in
                        result(true)
                    }
                } catch {
                    result(FlutterError(code: "CLEAR_RELEASE_FAILED", message: error.localizedDescription, details: nil))
                }

            case "getReleaseCategories":
                let categories = RunnerRuleStore.loadReleaseCategories()
                result(categories)

            case "getCategoryDomains":
                guard let args = call.arguments as? [String: Any],
                      let category = args["category"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'category'", details: nil))
                    return
                }
                let domains = RunnerRuleStore.loadCategoryDomains(category: category)
                result(domains)

            case "getDiagnostics":
                result("")

            case "clearDiagnostics":
                result(true)

            case "getVpnPolicy":
                let mode = AuraDNSProxyManager.shared.getPolicyMode()
                let expiry = AuraDNSProxyManager.shared.getPauseExpiryMillis()
                result([
                    "mode": mode,
                    "pauseExpiryUtcMillis": expiry,
                    "isAutoRecoveryPermitted": false,
                    "isAlwaysOnActive": false,
                    "isLockdownActive": false
                ])

            case "pauseTunnel":
                let args = call.arguments as? [String: Any]
                let durationMinutes = (args?["durationMinutes"] as? Int) ?? 30
                AuraDNSProxyManager.shared.pauseFilter(durationMinutes: durationMinutes) { res in
                    switch res {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "PAUSE_FAILED", message: error.localizedDescription, details: nil))
                    }
                }

            case "shutdownTunnel":
                AuraDNSProxyManager.shared.shutdownFilter { res in
                    switch res {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "SHUTDOWN_FAILED", message: error.localizedDescription, details: nil))
                    }
                }

            case "isAutoRestartEnabled":
                let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
                let enabled = defaults?.object(forKey: "auto_restart_enabled") as? Bool ?? true
                result(enabled)

            case "setAutoRestartEnabled":
                let args = call.arguments as? [String: Any]
                let enabled = (args?["enabled"] as? Bool) ?? true
                let defaults = UserDefaults(suiteName: "group.com.thejatech.aura")
                defaults?.set(enabled, forKey: "auto_restart_enabled")
                result(true)

            case "isAlwaysOnActive":
                result(false)

            case "isLockdownActive":
                result(false)

            case "openVpnSettings":
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
                    NSWorkspace.shared.open(url)
                    result(true)
                } else {
                    result(false)
                }

            default:
                os_log(.default, log: Self.log, "[MethodChannel] Unhandled method: %{public}@", call.method)
                result(FlutterMethodNotImplemented)
            }
        }

        // Status channel
        statusChannel.setStreamHandler(TunnelStatusStreamHandler())

        // Activity channel
        activityChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "initializeDatabase":
                let ready = self.activityDatabase != nil
                result(["ready": ready, "databaseFileName": "dns_activity.sqlite"])

            case "getActivity":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'limit' and 'offset'", details: nil))
                    return
                }
                let limit = (args["limit"] as? Int) ?? 50
                let offset = (args["offset"] as? Int) ?? 0
                let outcomeFilter = args["outcomeFilter"] as? String
                guard let db = self.activityDatabase else {
                    result(["records": [], "hasMore": false, "nextCursorTimestamp": nil, "nextCursorId": nil])
                    return
                }
                let records = db.queryRecords(limit: limit, offset: offset, outcomeFilter: outcomeFilter)
                let recordDicts = records.map { record in
                    [
                        "id": record.id ?? 0,
                        "domain": record.domain,
                        "timestamp": record.timestamp,
                        "queryType": record.queryType,
                        "outcome": record.outcome,
                        "matchedSource": record.matchedSource,
                        "matchedRuleId": record.matchedRuleId ?? NSNull(),
                        "matchedCategories": record.matchedCategories,
                        "reason": record.reason ?? NSNull(),
                        "appIdentifier": record.appIdentifier ?? NSNull(),
                        "appName": record.appName ?? NSNull(),
                        "appIconKey": record.appIconKey ?? NSNull(),
                    ] as [String: Any]
                }
                let hasMore = records.count == limit
                let nextCursor = records.last
                result([
                    "records": recordDicts,
                    "hasMore": hasMore,
                    "nextCursorTimestamp": nextCursor?.timestamp ?? NSNull(),
                    "nextCursorId": nextCursor?.id ?? NSNull(),
                ])

            case "getDashboardStats":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'timeWindowMillis'", details: nil))
                    return
                }
                let timeWindowMillis = (args["timeWindowMillis"] as? Int64) ?? 86400000
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let startTime = now - timeWindowMillis
                guard let db = self.activityDatabase else {
                    result([
                        "timeWindowMillis": timeWindowMillis,
                        "startTime": startTime,
                        "endTime": now,
                        "totalQueries": 0,
                        "totalBlocked": 0,
                        "totalAllowed": 0,
                        "totalFailed": 0,
                        "uniqueBlockedDomains": 0,
                        "uniqueDomainsTotal": 0,
                    ])
                    return
                }
                let allRecords = db.queryRecords(limit: 10000, offset: 0)
                let windowRecords = allRecords.filter { $0.timestamp >= startTime && $0.timestamp <= now }
                let totalBlocked = windowRecords.filter { $0.outcome == "blocked" }.count
                let totalAllowed = windowRecords.filter { $0.outcome == "allowed" }.count
                let totalFailed = windowRecords.filter { $0.outcome == "failed" }.count
                let uniqueBlockedDomains = Set(windowRecords.filter { $0.outcome == "blocked" }.map { $0.domain }).count
                let uniqueDomainsTotal = Set(windowRecords.map { $0.domain }).count
                result([
                    "timeWindowMillis": timeWindowMillis,
                    "startTime": startTime,
                    "endTime": now,
                    "totalQueries": windowRecords.count,
                    "totalBlocked": totalBlocked,
                    "totalAllowed": totalAllowed,
                    "totalFailed": totalFailed,
                    "uniqueBlockedDomains": uniqueBlockedDomains,
                    "uniqueDomainsTotal": uniqueDomainsTotal,
                ])

            case "getTopBlockedDomains":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'limit'", details: nil))
                    return
                }
                let limit = (args["limit"] as? Int) ?? 10
                guard let db = self.activityDatabase else {
                    result([])
                    return
                }
                let allRecords = db.queryRecords(limit: 10000, offset: 0)
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let startTime = now - 86400000 // last 24h
                let blockedRecords = allRecords.filter { $0.outcome == "blocked" && $0.timestamp >= startTime }
                var domainCounts: [String: Int] = [:]
                for record in blockedRecords {
                    domainCounts[record.domain, default: 0] += 1
                }
                let topDomains = domainCounts.sorted { $0.value > $1.value }.prefix(limit).map { [
                    "domain": $0.key,
                    "count": $0.value,
                ] }
                result(topDomains)

            case "checkpoint":
                result(true)

            case "getDailyBlockedActivity":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'startTime' and 'endTime'", details: nil))
                    return
                }
                let startTime = (args["startTime"] as? Int64) ?? 0
                let endTime = (args["endTime"] as? Int64) ?? Int64(Date().timeIntervalSince1970 * 1000)
                guard let db = self.activityDatabase else {
                    result([])
                    return
                }
                let allRecords = db.queryRecords(limit: 10000, offset: 0)
                let windowRecords = allRecords.filter { $0.outcome == "blocked" && $0.timestamp >= startTime && $0.timestamp <= endTime }
                var dailyCounts: [String: Int] = [:]
                for record in windowRecords {
                    let date = Date(timeIntervalSince1970: TimeInterval(record.timestamp) / 1000.0)
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let dayKey = formatter.string(from: date)
                    dailyCounts[dayKey, default: 0] += 1
                }
                let dailyActivity = dailyCounts.map { entry in
                    ["date": entry.key, "blockedCount": entry.value] as [String: Any]
                }.sorted { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }
                result(dailyActivity)

            case "pruneRetention":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary with 'cutoffUtcMillis'", details: nil))
                    return
                }
                let cutoffUtcMillis = (args["cutoffUtcMillis"] as? Int64) ?? 0
                guard let db = self.activityDatabase else {
                    result(0)
                    return
                }
                let deleted = db.pruneRetention(cutoffUtcMillis: cutoffUtcMillis)
                result(deleted)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

private class TunnelStatusStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        AuraDNSProxyManager.shared.statusCallback = { status in
            events(status.rawValue)
        }
        events(AuraDNSProxyManager.shared.getStatus().rawValue)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AuraDNSProxyManager.shared.statusCallback = nil
        return nil
    }
}
