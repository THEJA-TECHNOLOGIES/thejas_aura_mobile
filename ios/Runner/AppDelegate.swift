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

            case "syncRules":
                guard let args = call.arguments as? [[String: Any]] else {
                    os_log(.error, log: Self.log, "[MethodChannel] syncRules FAILED — invalid arguments")
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected array of rule maps", details: nil))
                    return
                }

                var rules: [AuraRule] = []
                for item in args {
                    if let domain = item["domain"] as? String {
                        let isEnabled = item["isEnabled"] as? Bool ?? true
                        let isBlocked = item["isBlocked"] as? Bool ?? true
                        rules.append(AuraRule(domain: domain, isEnabled: isEnabled, isBlocked: isBlocked))
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

            default:
                os_log(.default, log: Self.log, "[MethodChannel] Unhandled method: %{public}@", call.method)
                result(FlutterMethodNotImplemented)
            }
        }

        statusChannel.setStreamHandler(TunnelStatusStreamHandler())
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
