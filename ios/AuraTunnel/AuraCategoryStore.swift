import Foundation
import os.log

public struct AuraCategoryPreferencesContainer: Codable {
    public let version: Int
    public let categories: [String: Bool]

    public init(version: Int = 1, categories: [String: Bool]) {
        self.version = version
        self.categories = categories
    }
}

/// App Group category preference persistence and bundled category list loader.
public final class AuraCategoryStore {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraCategoryStore")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let preferencesFileName = "aura_category_preferences.json"

    public static let defaultCategoryNames = ["Ads", "Trackers", "Analytics"]

    public static var defaultPreferences: [String: Bool] {
        return [
            "Ads": true,
            "Trackers": true,
            "Analytics": true
        ]
    }

    public static var sharedContainerURL: URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)
    }

    public static var customPreferencesFileURL: URL? = nil

    public static var preferencesFileURL: URL? {
        return customPreferencesFileURL ?? sharedContainerURL?.appendingPathComponent(preferencesFileName)
    }

    // MARK: - Preferences Persistence

    public static func savePreferences(_ preferences: [String: Bool]) throws {
        guard let targetURL = preferencesFileURL else {
            os_log(.error, log: Self.log, "App Group container URL is nil for category preferences")
            throw NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let container = AuraCategoryPreferencesContainer(version: 1, categories: preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(container)
        try data.write(to: targetURL, options: .atomic)
        os_log(.info, log: Self.log, "Persisted %{public}ld category preferences to %{public}@", preferences.count, targetURL.path)
    }

    public static func loadPreferencesResult() -> Result<[String: Bool], Error> {
        guard let targetURL = preferencesFileURL else {
            let err = NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container URL is nil"])
            return .failure(err)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            os_log(.info, log: Self.log, "Category preferences file does not exist at %{public}@; using defaults", targetURL.path)
            return .success(defaultPreferences)
        }

        do {
            let data = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()

            if let container = try? decoder.decode(AuraCategoryPreferencesContainer.self, from: data) {
                // Ensure any missing standard categories default to true
                var merged = defaultPreferences
                for (cat, enabled) in container.categories {
                    merged[cat] = enabled
                }
                return .success(merged)
            }

            let decodeErr = NSError(
                domain: "AuraCategoryStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Malformed category preferences JSON schema at \(targetURL.path)"]
            )
            os_log(.error, log: Self.log, "%{public}@ — preserving defaults", decodeErr.localizedDescription)
            return .failure(decodeErr)
        } catch {
            os_log(.error, log: Self.log, "Error reading category preferences at %{public}@: %{public}@", targetURL.path, error.localizedDescription)
            return .failure(error)
        }
    }

    public static func loadPreferences() -> [String: Bool] {
        switch loadPreferencesResult() {
        case .success(let prefs):
            return prefs
        case .failure:
            return defaultPreferences
        }
    }

    // MARK: - Bundled Category Domain Lists Loader

    /// Loads the bundled default domains for a given category ("Ads", "Trackers", "Analytics").
    public static func loadBundledDomains(for category: String) -> Set<String> {
        let fileName = category.lowercased()

        // 1. Try bundle for class or main
        let bundle = Bundle(for: AuraCategoryStore.self)
        var url = bundle.url(forResource: fileName, withExtension: "txt", subdirectory: "categories") ??
                  bundle.url(forResource: fileName, withExtension: "txt") ??
                  Bundle.main.url(forResource: fileName, withExtension: "txt", subdirectory: "categories") ??
                  Bundle.main.url(forResource: fileName, withExtension: "txt")

        // 2. Try App Group container or relative resource path
        if url == nil, let containerURL = sharedContainerURL {
            let candidate = containerURL.appendingPathComponent("categories/\(fileName).txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                url = candidate
            }
        }

        guard let targetURL = url, let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            os_log(.error, log: Self.log, "Could not find bundled domain list resource for category '%{public}@'", category)
            return fallbackDomains(for: category)
        }

        var domains = Set<String>()
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                return
            }
            let normalized = AuraDNSEngine.normalizeDomain(trimmed)
            if !normalized.isEmpty {
                domains.insert(normalized)
            }
        }

        os_log(.info, log: Self.log, "Loaded %{public}ld domains for bundled category '%{public}@'", domains.count, category)
        return domains
    }

    /// Loads all bundled categories into a dictionary mapping category name to domain set.
    public static func loadAllBundledCategories() -> [String: Set<String>] {
        var categories: [String: Set<String>] = [:]
        for name in defaultCategoryNames {
            categories[name] = loadBundledDomains(for: name)
        }
        return categories
    }

    /// Fallback in-memory domains used if resources cannot be located.
    private static func fallbackDomains(for category: String) -> Set<String> {
        switch category.lowercased() {
        case "ads":
            return [
                "doubleclick.net",
                "googleads.g.doubleclick.net",
                "pagead2.googlesyndication.com",
                "adservice.google.com",
                "ads.pubmatic.com",
                "adnxs.com",
                "c.amazon-adsystem.com",
                "advertising.apple.com",
                "taboola.com",
                "outbrain.com",
                "rubiconproject.com",
                "openx.net"
            ]
        case "trackers":
            return [
                "scorecardresearch.com",
                "pixel.facebook.com",
                "tr.snapchat.com",
                "analytics.tiktok.com",
                "ads.linkedin.com",
                "bat.bing.com",
                "crwdcntrl.net",
                "moatads.com",
                "quantserve.com",
                "branch.io",
                "appsflyer.com",
                "adjust.com",
                "telemetry.app.com"
            ]
        case "analytics":
            return [
                "google-analytics.com",
                "ssl.google-analytics.com",
                "analytics.google.com",
                "analytics.facebook.com",
                "api.mixpanel.com",
                "segment.io",
                "api.segment.io",
                "heapanalytics.com",
                "amplitude.com",
                "hotjar.com",
                "clarity.ms",
                "telemetry.microsoft.com",
                "app-measurement.com"
            ]
        default:
            return []
        }
    }
}
