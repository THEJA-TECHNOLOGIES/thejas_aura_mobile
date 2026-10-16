import Flutter
import UIKit
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private static let log = OSLog(subsystem: "com.thejatech.aura", category: "AppDelegate")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        RunnerRuleStore.cleanupStaging()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        setupPlatformChannels(messenger: engineBridge.applicationRegistrar.messenger())
    }

    private func setupPlatformChannels(messenger: FlutterBinaryMessenger) {
        let controlChannel = FlutterMethodChannel(name: "com.thejatech.aura/tunnel_control", binaryMessenger: messenger)
        let statusChannel = FlutterEventChannel(name: "com.thejatech.aura/tunnel_status", binaryMessenger: messenger)

        controlChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            os_log(.info, log: Self.log, "[MethodChannel] Received call: %{public}@", call.method)

            switch call.method {
            case "getStatus":
                AuraTunnelManager.shared.getStatus { status in
                    os_log(.info, log: Self.log, "[MethodChannel] getStatus completing with: %{public}@", status.rawValue)
                    result(status.rawValue)
                }

            case "startTunnel":
                AuraTunnelManager.shared.startTunnel { res in
                    switch res {
                    case .success:
                        os_log(.info, log: Self.log, "[MethodChannel] startTunnel succeeded (tunnel initiation requested)")
                        result(nil)
                    case .failure(let error):
                        let message = error.errorDescription ?? error.underlyingDescription
                        os_log(
                            .error,
                            log: Self.log,
                            "[MethodChannel] startTunnel FAILED — stage=%{public}@ domain=%{public}@ code=%{public}ld message=%{public}@",
                            error.stage,
                            error.domain,
                            error.code,
                            message
                        )
                        result(FlutterError(
                            code: "START_FAILED",
                            message: message,
                            details: error.detailsDictionary
                        ))
                    }
                }

            case "stopTunnel":
                AuraTunnelManager.shared.stopTunnel { res in
                    switch res {
                    case .success:
                        os_log(.info, log: Self.log, "[MethodChannel] stopTunnel succeeded")
                        result(nil)
                    case .failure(let error):
                        let message = error.errorDescription ?? error.underlyingDescription
                        os_log(
                            .error,
                            log: Self.log,
                            "[MethodChannel] stopTunnel FAILED — stage=%{public}@ domain=%{public}@ code=%{public}ld message=%{public}@",
                            error.stage,
                            error.domain,
                            error.code,
                            message
                        )
                        result(FlutterError(
                            code: "STOP_FAILED",
                            message: message,
                            details: error.detailsDictionary
                        ))
                    }
                }

            case "getRules":
                let storeResult = RunnerRuleStore.loadRulesResult()
                switch storeResult {
                case .success(let rules):
                    let ruleDicts = rules.map { $0.toDictionary() }
                    os_log(.info, log: Self.log, "[MethodChannel] getRules loaded %{public}ld rule(s) from App Group", ruleDicts.count)
                    result(ruleDicts)
                case .failure(let error):
                    let nsError = error as NSError
                    os_log(.error, log: Self.log, "[MethodChannel] getRules FAILED — domain=%{public}@ code=%{public}ld description=%{public}@", nsError.domain, nsError.code, nsError.localizedDescription)
                    result(FlutterError(
                        code: "LOAD_RULES_FAILED",
                        message: error.localizedDescription,
                        details: ["domain": nsError.domain, "code": nsError.code]
                    ))
                }

            case "syncRules":
                guard let args = call.arguments as? [[String: Any]] else {
                    os_log(.error, log: Self.log, "[MethodChannel] syncRules FAILED — invalid arguments")
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
                    os_log(.info, log: Self.log, "[MethodChannel] syncRules saved %{public}ld rule(s) to App Group", rules.count)
                    // Notify connected tunnel if active, without failing rule persistence if tunnel is disconnected or IPC fails
                    AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                        switch reloadResult {
                        case .success(let didSendIPC):
                            os_log(.info, log: Self.log, "[MethodChannel] syncRules completed (liveIPCNotified=%{public}d)", didSendIPC ? 1 : 0)
                        case .failure(let reloadError):
                            os_log(
                                .error,
                                log: Self.log,
                                "[MethodChannel] syncRules saved rules to App Group, but live reload_rules IPC failed: %{public}@",
                                reloadError.errorDescription ?? reloadError.underlyingDescription
                            )
                        }
                        result(true)
                    }
                } catch {
                    let nsError = error as NSError
                    os_log(
                        .error,
                        log: Self.log,
                        "[MethodChannel] syncRules FAILED to write App Group file — domain=%{public}@ code=%{public}ld description=%{public}@",
                        nsError.domain,
                        nsError.code,
                        nsError.localizedDescription
                    )
                    result(FlutterError(
                        code: "SAVE_RULES_FAILED",
                        message: error.localizedDescription,
                        details: ["domain": nsError.domain, "code": nsError.code]
                    ))
                }

            case "reloadRules":
                AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                    switch reloadResult {
                    case .success(let didSendIPC):
                        os_log(.info, log: Self.log, "[MethodChannel] reloadRules succeeded (sent=%{public}d)", didSendIPC ? 1 : 0)
                        result(didSendIPC)
                    case .failure(let error):
                        let message = error.errorDescription ?? error.underlyingDescription
                        os_log(.error, log: Self.log, "[MethodChannel] reloadRules FAILED: %{public}@", message)
                        result(FlutterError(
                            code: "RELOAD_RULES_FAILED",
                            message: message,
                            details: error.detailsDictionary
                        ))
                    }
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
                    AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(newRule.toDictionary())
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Rule saved, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(updatedRule.toDictionary())
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Rule updated, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(deletedRule.toDictionary())
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Rule deleted, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyRulesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(updatedRule.toDictionary())
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Rule toggled, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyCategoriesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(updatedPrefs)
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Category saved, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyCategoriesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(typedPrefs)
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Categories saved, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                    AuraTunnelManager.shared.notifyDefaultOverridesUpdated { reloadResult in
                        switch reloadResult {
                        case .success:
                            result(Array(updatedDisabled).sorted())
                        case .failure(let tunnelError):
                            result(FlutterError(
                                code: "EXTENSION_RELOAD_FAILED",
                                message: "Override saved, but active firewall failed to reload: \(tunnelError.errorDescription ?? tunnelError.underlyingDescription)",
                                details: tunnelError.detailsDictionary
                            ))
                        }
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
                        version: version,
                        files: files,
                        domainCount: domainCount,
                        etag: etag,
                        checksum: checksum
                    )

                    AuraTunnelManager.shared.notifyCategoriesUpdated { reloadResult in
                        switch reloadResult {
                        case .success(let reloaded):
                            installRes["reloaded"] = reloaded
                            result(installRes)
                        case .failure(let error):
                            os_log(.error, log: Self.log, "[MethodChannel] Release installed but firewall reload failed: %{public}@", error.underlyingDescription)
                            installRes["reloaded"] = false
                            installRes["reloadError"] = error.errorDescription ?? error.underlyingDescription
                            result(installRes)
                        }
                    }
                } catch {
                    result(FlutterError(code: "INSTALL_RELEASE_FAILED", message: error.localizedDescription, details: nil))
                }

            case "clearInstalledRelease":
                do {
                    try RunnerRuleStore.clearInstalledRelease()
                    AuraTunnelManager.shared.notifyCategoriesUpdated { _ in
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

            default:
                os_log(.default, log: Self.log, "[MethodChannel] Unhandled method: %{public}@", call.method)
                result(FlutterMethodNotImplemented)
            }
        }

        statusChannel.setStreamHandler(TunnelStatusStreamHandler())

        // Activity Repository Channel (Read-only, paginated, off main thread)
        let activityRepository = AuraActivityRepository()
        let activityChannel = FlutterMethodChannel(name: "com.thejatech.aura/activity", binaryMessenger: messenger)

        activityChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            let args = call.arguments as? [String: Any]

            switch call.method {
            case "initializeDatabase":
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try activityRepository.initialize()
                        DispatchQueue.main.async {
                            result([
                                "ready": true,
                                "databaseFileName": AuraActivityRepository.databaseFileName
                            ])
                        }
                    } catch let err as AuraRepositoryError {
                        DispatchQueue.main.async {
                            result(FlutterError(code: err.errorCode, message: err.localizedDescription, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
                        }
                    }
                }

            case "getActivity":
                let limit = (args?["limit"] as? Int) ?? 25
                let cursorTimestamp = (args?["cursorTimestamp"] as? NSNumber)?.int64Value
                let cursorId = (args?["cursorId"] as? NSNumber)?.int64Value
                let outcome = args?["outcome"] as? String
                let searchDomain = args?["searchDomain"] as? String
                let startTime = (args?["startTime"] as? NSNumber)?.int64Value
                let endTime = (args?["endTime"] as? NSNumber)?.int64Value

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let paginated = try activityRepository.queryActivity(
                            limit: limit,
                            cursorTimestamp: cursorTimestamp,
                            cursorId: cursorId,
                            outcome: outcome,
                            searchDomain: searchDomain,
                            startTime: startTime,
                            endTime: endTime
                        )
                        let payload = paginated.toDictionary()
                        DispatchQueue.main.async {
                            result(payload)
                        }
                    } catch let err as AuraRepositoryError {
                        DispatchQueue.main.async {
                            result(FlutterError(code: err.errorCode, message: err.localizedDescription, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "QUERY_FAILED", message: error.localizedDescription, details: nil))
                        }
                    }
                }

            case "getDashboardStats":
                let timeWindowMillis = (args?["timeWindowMillis"] as? NSNumber)?.int64Value ?? 86_400_000

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let stats = try activityRepository.getDashboardStats(
                            timeWindowMillis: timeWindowMillis
                        )
                        let payload = stats.toDictionary()
                        DispatchQueue.main.async {
                            result(payload)
                        }
                    } catch let err as AuraRepositoryError {
                        DispatchQueue.main.async {
                            result(FlutterError(code: err.errorCode, message: err.localizedDescription, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "STATS_FAILED", message: error.localizedDescription, details: nil))
                        }
                    }
                }

            case "getTopBlockedDomains":
                let limit = (args?["limit"] as? Int) ?? 5
                let timeWindowMillis = (args?["timeWindowMillis"] as? NSNumber)?.int64Value

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let topList = try activityRepository.getTopBlockedDomains(
                            limit: limit,
                            timeWindowMillis: timeWindowMillis
                        )
                        let payload = topList.map { $0.toDictionary() }
                        DispatchQueue.main.async {
                            result(payload)
                        }
                    } catch let err as AuraRepositoryError {
                        DispatchQueue.main.async {
                            result(FlutterError(code: err.errorCode, message: err.localizedDescription, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "TOP_BLOCKED_FAILED", message: error.localizedDescription, details: nil))
                        }
                    }
                }

            case "checkpoint":
                DispatchQueue.global(qos: .utility).async {
                    let success = activityRepository.checkpointPassive()
                    DispatchQueue.main.async {
                        result(success)
                    }
                }

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

private class TunnelStatusStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        AuraTunnelManager.shared.onStatusChanged = { status in
            events(status.rawValue)
        }
        // Emit current status immediately
        AuraTunnelManager.shared.getStatus { status in
            events(status.rawValue)
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AuraTunnelManager.shared.onStatusChanged = nil
        return nil
    }
}
