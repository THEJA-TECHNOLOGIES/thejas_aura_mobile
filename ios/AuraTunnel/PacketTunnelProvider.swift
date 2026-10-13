import Foundation
import NetworkExtension
import os.log

/// Clean-room Network Extension PacketTunnelProvider following the Lockdown Privacy architectural pattern:
/// Configures NEDNSSettings to 127.0.0.1 with matchDomains = [""] and runs the local AuraLocalDNSResolver.
open class PacketTunnelProvider: NEPacketTunnelProvider {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "PacketTunnelProvider")

    private let dnsEngine = AuraDNSEngine()
    private lazy var resolver = AuraLocalDNSResolver(engine: self.dnsEngine)

    open override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log(.info, log: Self.log, "startTunnel invoked")

        // 1. Wire up fatal error callback so the tunnel is cancelled if the resolver fails
        resolver.onFatalError = { [weak self] error in
            os_log(.error, log: Self.log, "Fatal DNS resolver failure: %{public}@ — canceling tunnel", error.localizedDescription)
            self?.cancelTunnelWithError(error)
        }

        // 2. Load active rules from shared App Group container
        _ = loadRulesFromAppGroup()

        // 3. Start local DNS socket resolver on 127.0.0.1:53
        let started = resolver.start()
        guard started else {
            os_log(.error, log: Self.log, "Failed to start local DNS resolver on 127.0.0.1:53")
            let error = NSError(domain: "AuraTunnel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind local DNS resolver to 127.0.0.1:53"])
            completionHandler(error)
            return
        }

        // 4. Configure Tunnel Network Settings following Lockdown pattern
        let tunnelSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        // Direct system DNS to the local loopback resolver with global match
        let dnsSettings = NEDNSSettings(servers: ["127.0.0.1"])
        dnsSettings.matchDomains = [""] // Catch all system domains
        tunnelSettings.dnsSettings = dnsSettings

        // Configure loopback IPv4 settings
        let ipv4Settings = NEIPv4Settings(addresses: ["10.255.255.2"], subnetMasks: ["255.255.255.252"])
        ipv4Settings.includedRoutes = [NEIPv4Route(destinationAddress: "127.0.0.1", subnetMask: "255.255.255.255")]
        tunnelSettings.ipv4Settings = ipv4Settings

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
                self?.resolver.stop()
                completionHandler(error)
            } else {
                os_log(.info, log: Self.log, "setTunnelNetworkSettings applied successfully. System DNS routed to 127.0.0.1.")
                completionHandler(nil)
            }
        }
    }

    open override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log(.info, log: Self.log, "stopTunnel invoked with reason: %{public}ld", reason.rawValue)
        resolver.stop()
        completionHandler()
    }

    open override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let command = String(data: messageData, encoding: .utf8), command == "reload_rules" {
            os_log(.info, log: Self.log, "handleAppMessage: reloading rules from App Group")
            let applied = loadRulesFromAppGroup()
            if applied {
                completionHandler?(Data([1]))
            } else {
                os_log(.error, log: Self.log, "handleAppMessage: reload_rules failed to apply rules from storage")
                completionHandler?(Data([0]))
            }
        } else {
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
            return true
        case .failure(let error):
            os_log(.error, log: Self.log, "Failed to load rules from App Group: %{public}@ — retaining existing in-memory rules", error.localizedDescription)
            return false
        }
    }
}
