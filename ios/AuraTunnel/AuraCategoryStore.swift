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

public struct AuraDefaultDomainOverridesContainer: Codable {
    public let version: Int
    public let disabledDomains: [String]

    public init(version: Int = 1, disabledDomains: [String]) {
        self.version = version
        self.disabledDomains = disabledDomains
    }
}

/// Metadata container for an installed backend blocklist release.
public struct AuraInstalledReleaseContainer: Codable {
    public let version: String
    public let installedAt: Date
    public let domainCount: Int
    public let files: [String: String]
    public let checksum: String?
    public let etag: String?
    public let releaseDirectory: String?

    public init(
        version: String,
        installedAt: Date = Date(),
        domainCount: Int = 0,
        files: [String: String] = [:],
        checksum: String? = nil,
        etag: String? = nil,
        releaseDirectory: String? = nil
    ) {
        self.version = version
        self.installedAt = installedAt
        self.domainCount = domainCount
        self.files = files
        self.checksum = checksum
        self.etag = etag
        self.releaseDirectory = releaseDirectory
    }
}

/// App Group category preference persistence and bundled category list loader.
public final class AuraCategoryStore {

    private static let log = OSLog(subsystem: "com.thejatech.aura.AuraTunnel", category: "AuraCategoryStore")
    public static let sharedAppGroupIdentifier = "group.com.thejatech.aura"
    public static let preferencesFileName = "aura_category_preferences.json"
    public static let overridesFileName = "aura_default_domain_overrides.json"
    public static let releaseFileName = "installed_release.json"

    public static let defaultCategoryNames = ["Ads", "Trackers", "Analytics"]

    public static var defaultPreferences: [String: Bool] {
        return [
            "Ads": true,
            "Trackers": true,
            "Analytics": true
        ]
    }

    public static var customSharedContainerURL: URL? = nil

    public static var sharedContainerURL: URL? {
        return customSharedContainerURL ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedAppGroupIdentifier)
    }

    public static var customPreferencesFileURL: URL? = nil

    public static var preferencesFileURL: URL? {
        return customPreferencesFileURL ?? sharedContainerURL?.appendingPathComponent(preferencesFileName)
    }

    public static var customOverridesFileURL: URL? = nil

    public static var overridesFileURL: URL? {
        return customOverridesFileURL ?? sharedContainerURL?.appendingPathComponent(overridesFileName)
    }

    public static var customReleaseFileURL: URL? = nil

    public static var releaseFileURL: URL? {
        return customReleaseFileURL ?? sharedContainerURL?.appendingPathComponent(releaseFileName)
    }

    public static var customReleasesDirectoryURL: URL? = nil

    public static var releasesRootDirectoryURL: URL? {
        return customReleasesDirectoryURL ?? sharedContainerURL?.appendingPathComponent("releases")
    }

    public static var customStagingDirectoryURL: URL? = nil

    public static var stagingRootDirectoryURL: URL? {
        return customStagingDirectoryURL ?? sharedContainerURL?.appendingPathComponent("staging")
    }

    public static var customCategoriesDirectoryURL: URL? = nil

    /// URL of the currently active release directory containing its category .txt files.
    /// Derived from `installed_release.json`. If no valid release directory is found, falls back to nil.
    public static var activeReleaseDirectoryURL: URL? {
        guard let targetURL = releaseFileURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: targetURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let container = try? decoder.decode(AuraInstalledReleaseContainer.self, from: data) else {
            return nil
        }
        guard let dirName = container.releaseDirectory, !dirName.isEmpty,
              let root = releasesRootDirectoryURL else {
            return nil
        }
        let candidate = root.appendingPathComponent(dirName)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
            return candidate
        }
        return nil
    }

    /// For backward compatibility, returns activeReleaseDirectoryURL if active, or legacy categories directory.
    public static var categoriesDirectoryURL: URL? {
        return activeReleaseDirectoryURL ?? customCategoriesDirectoryURL ?? sharedContainerURL?.appendingPathComponent("categories")
    }

    public static var customCategoryDomainFiles: [String: URL]? = nil

    /// Cleans up any orphaned staging directories left behind by interrupted installations.
    public static func cleanupStaging() {
        guard let stagingRoot = stagingRootDirectoryURL, FileManager.default.fileExists(atPath: stagingRoot.path) else { return }
        if let stagingItems = try? FileManager.default.contentsOfDirectory(atPath: stagingRoot.path) {
            for item in stagingItems {
                let leftover = stagingRoot.appendingPathComponent(item)
                try? FileManager.default.removeItem(at: leftover)
            }
        }
    }

    /// Resets all custom test URLs to defaults.
    public static func resetCustomURLs() {
        customSharedContainerURL = nil
        customPreferencesFileURL = nil
        customOverridesFileURL = nil
        customReleaseFileURL = nil
        customCategoriesDirectoryURL = nil
        customReleasesDirectoryURL = nil
        customStagingDirectoryURL = nil
        customCategoryDomainFiles = nil
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

    // MARK: - Default Domain Overrides Persistence

    public static func saveDisabledDefaultDomains(_ domains: Set<String>) throws {
        guard let targetURL = overridesFileURL else {
            os_log(.error, log: Self.log, "App Group container URL is nil for default domain overrides")
            throw NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to access App Group container URL"])
        }

        let sorted = domains.map { AuraDNSEngine.normalizeDomain($0) }.filter { !$0.isEmpty }.sorted()
        let container = AuraDefaultDomainOverridesContainer(version: 1, disabledDomains: sorted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(container)
        try data.write(to: targetURL, options: .atomic)
        os_log(.info, log: Self.log, "Persisted %{public}ld disabled default domains to %{public}@", sorted.count, targetURL.path)
    }

    public static func loadDisabledDefaultDomainsResult() -> Result<Set<String>, Error> {
        guard let targetURL = overridesFileURL else {
            let err = NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container URL is nil"])
            return .failure(err)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            os_log(.info, log: Self.log, "Default domain overrides file does not exist at %{public}@; returning empty set", targetURL.path)
            return .success([])
        }

        do {
            let data = try Data(contentsOf: targetURL)
            let decoder = JSONDecoder()

            if let container = try? decoder.decode(AuraDefaultDomainOverridesContainer.self, from: data) {
                var normalizedSet = Set<String>()
                for domain in container.disabledDomains {
                    let norm = AuraDNSEngine.normalizeDomain(domain)
                    if !norm.isEmpty {
                        normalizedSet.insert(norm)
                    }
                }
                return .success(normalizedSet)
            }

            let decodeErr = NSError(
                domain: "AuraCategoryStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Malformed default domain overrides JSON schema at \(targetURL.path)"]
            )
            os_log(.error, log: Self.log, "%{public}@", decodeErr.localizedDescription)
            return .failure(decodeErr)
        } catch {
            os_log(.error, log: Self.log, "Error reading default domain overrides at %{public}@: %{public}@", targetURL.path, error.localizedDescription)
            return .failure(error)
        }
    }

    public static func loadDisabledDefaultDomains() -> Set<String> {
        switch loadDisabledDefaultDomainsResult() {
        case .success(let set):
            return set
        case .failure:
            return []
        }
    }

    // MARK: - Installed Release Persistence

    public static func installRelease(
        version: String,
        files: [String: String],
        domainCount: Int = 0,
        etag: String? = nil,
        checksum: String? = nil
    ) throws -> [String: Any] {
        guard let containerURL = sharedContainerURL else {
            throw NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container URL is nil"])
        }
        guard !files.isEmpty else {
            throw NSError(domain: "AuraCategoryStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot install empty release with no files"])
        }

        let fileManager = FileManager.default
        guard let releasesRoot = releasesRootDirectoryURL,
              let stagingRoot = stagingRootDirectoryURL else {
            throw NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Releases or staging root directory URL is nil"])
        }

        // 1. Clean up any orphaned staging directories and create roots if needed
        cleanupStaging()
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: releasesRoot, withIntermediateDirectories: true)

        // 2. Create an isolated staging directory for this release
        let releaseToken = UUID().uuidString.prefix(8)
        let sanitizedVersion = version.replacingOccurrences(of: "[^a-zA-Z0-9.-]", with: "_", options: .regularExpression)
        let releaseDirName = "rel_\(sanitizedVersion)_\(releaseToken)"
        let stageDir = stagingRoot.appendingPathComponent("stage_\(releaseDirName)")
        let finalReleaseDir = releasesRoot.appendingPathComponent(releaseDirName)

        if fileManager.fileExists(atPath: stageDir.path) {
            try fileManager.removeItem(at: stageDir)
        }
        try fileManager.createDirectory(at: stageDir, withIntermediateDirectories: true)

        var activationSucceeded = false
        defer {
            if !activationSucceeded {
                try? fileManager.removeItem(at: stageDir)
                if fileManager.fileExists(atPath: finalReleaseDir.path) {
                    try? fileManager.removeItem(at: finalReleaseDir)
                }
            }
        }

        // 3. Write each file into staging directory
        var installedFilesMap: [String: String] = [:]
        for (name, content) in files {
            let normalizedName = name.lowercased().hasSuffix(".txt") ? name.lowercased() : "\(name.lowercased()).txt"
            let fileURL = stageDir.appendingPathComponent(normalizedName)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            installedFilesMap[name] = normalizedName
        }

        // 4. Verify release integrity in staging before moving
        for (name, _) in files {
            let normalizedName = name.lowercased().hasSuffix(".txt") ? name.lowercased() : "\(name.lowercased()).txt"
            let fileURL = stageDir.appendingPathComponent(normalizedName)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
                throw NSError(domain: "AuraCategoryStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Staged file \(normalizedName) is missing or is a directory"])
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "AuraCategoryStore", code: 5, userInfo: [NSLocalizedDescriptionKey: "Staged file \(normalizedName) is empty or unreadable"])
            }
        }

        // 5. Move stageDir to finalReleaseDir in releases/
        if fileManager.fileExists(atPath: finalReleaseDir.path) {
            try fileManager.removeItem(at: finalReleaseDir)
        }
        try fileManager.moveItem(at: stageDir, to: finalReleaseDir)

        // 6. Atomically write metadata pointing to the new release
        let releaseContainer = AuraInstalledReleaseContainer(
            version: version,
            installedAt: Date(),
            domainCount: domainCount,
            files: installedFilesMap,
            checksum: checksum,
            etag: etag,
            releaseDirectory: releaseDirName
        )

        guard let metadataURL = releaseFileURL else {
            throw NSError(domain: "AuraCategoryStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Release file URL is nil"])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(releaseContainer)
        try data.write(to: metadataURL, options: .atomic)

        // Activation succeeded!
        activationSucceeded = true

        // 7. Prune older releases (keep only the active releaseDirName)
        if let releaseDirs = try? fileManager.contentsOfDirectory(atPath: releasesRoot.path) {
            for item in releaseDirs where item != releaseDirName {
                let oldDir = releasesRoot.appendingPathComponent(item)
                try? fileManager.removeItem(at: oldDir)
            }
        }

        // Clean up legacy categories/ directory if it exists to eliminate any obsolete files
        if let legacyCatDir = customCategoriesDirectoryURL ?? containerURL.appendingPathComponent("categories") as URL?,
           fileManager.fileExists(atPath: legacyCatDir.path) {
            try? fileManager.removeItem(at: legacyCatDir)
        }

        // Clean up any other staging directories
        if let stagingItems = try? fileManager.contentsOfDirectory(atPath: stagingRoot.path) {
            for item in stagingItems {
                let leftover = stagingRoot.appendingPathComponent(item)
                try? fileManager.removeItem(at: leftover)
            }
        }

        os_log(.info, log: Self.log, "Successfully activated release %{public}@ (dir: %{public}@) with %{public}ld files into App Group", version, releaseDirName, files.count)

        let isoDate = ISO8601DateFormatter().string(from: releaseContainer.installedAt)
        return [
            "success": true,
            "version": version,
            "installedAt": isoDate,
            "domainCount": domainCount,
            "files": installedFilesMap,
            "releaseDirectory": releaseDirName
        ]
    }

    public static func loadInstalledRelease() -> [String: Any]? {
        guard let targetURL = releaseFileURL, FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: targetURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let container = try? decoder.decode(AuraInstalledReleaseContainer.self, from: data) else {
            return nil
        }

        // Verify that if a releaseDirectory is specified, it exists on disk and contains all declared files
        if let dirName = container.releaseDirectory, let root = releasesRootDirectoryURL {
            let releaseDir = root.appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: releaseDir.path, isDirectory: &isDir), isDir.boolValue else {
                os_log(.error, log: Self.log, "Active release points to missing directory %{public}@ — treating release as invalid", dirName)
                return nil
            }
            for (_, fileName) in container.files {
                let fileURL = releaseDir.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    os_log(.error, log: Self.log, "Active release directory is missing declared file %{public}@ — treating release as invalid", fileName)
                    return nil
                }
            }
        }

        var dict: [String: Any] = [
            "version": container.version,
            "installedAt": ISO8601DateFormatter().string(from: container.installedAt),
            "domainCount": container.domainCount,
            "files": container.files
        ]
        if let dir = container.releaseDirectory { dict["releaseDirectory"] = dir }
        if let etag = container.etag { dict["etag"] = etag }
        if let checksum = container.checksum { dict["checksum"] = checksum }
        return dict
    }

    public static func clearInstalledRelease() throws {
        let fileManager = FileManager.default
        if let releasesRoot = releasesRootDirectoryURL, fileManager.fileExists(atPath: releasesRoot.path) {
            try? fileManager.removeItem(at: releasesRoot)
        }
        if let stagingRoot = stagingRootDirectoryURL, fileManager.fileExists(atPath: stagingRoot.path) {
            try? fileManager.removeItem(at: stagingRoot)
        }
        if let legacyDir = customCategoriesDirectoryURL ?? sharedContainerURL?.appendingPathComponent("categories"),
           fileManager.fileExists(atPath: legacyDir.path) {
            try? fileManager.removeItem(at: legacyDir)
        }
        if let metadataURL = releaseFileURL, fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
        os_log(.info, log: Self.log, "Cleared installed release from App Group; reverting to static bundle")
    }

    // MARK: - Bundled Category Domain Lists Loader

    /// Loads the active domains for a given category ("Ads", "Trackers", "Analytics", "Malware", etc.).
    /// Checks the App Group container active release directory first, falling back to static bundled files.
    public static func loadBundledDomains(for category: String) -> Set<String> {
        let fileName = category.lowercased()

        if let customURL = customCategoryDomainFiles?[fileName],
           FileManager.default.fileExists(atPath: customURL.path) {
            if let content = try? String(contentsOf: customURL, encoding: .utf8) {
                return parseDomains(from: content)
            }
        }

        // 1. Try App Group container active release directory first (downloaded release takes precedence)
        if let activeDir = activeReleaseDirectoryURL {
            let candidate = activeDir.appendingPathComponent("\(fileName).txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                    let domains = parseDomains(from: content)
                    if !domains.isEmpty {
                        os_log(.info, log: Self.log, "Loaded %{public}ld domains from active release directory for category '%{public}@'", domains.count, category)
                        return domains
                    }
                }
            }
        }

        // 2. Try legacy categories directory if no activeReleaseDirectoryURL
        if let legacyDir = customCategoriesDirectoryURL ?? sharedContainerURL?.appendingPathComponent("categories"),
           FileManager.default.fileExists(atPath: legacyDir.path) {
            let candidate = legacyDir.appendingPathComponent("\(fileName).txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                    let domains = parseDomains(from: content)
                    if !domains.isEmpty {
                        os_log(.info, log: Self.log, "Loaded %{public}ld domains from legacy categories directory for category '%{public}@'", domains.count, category)
                        return domains
                    }
                }
            }
        }

        // 3. Try bundle for class or main (fallback if no dynamic release installed)
        let bundle = Bundle(for: AuraCategoryStore.self)
        var url = bundle.url(forResource: fileName, withExtension: "txt", subdirectory: "categories") ??
                  bundle.url(forResource: fileName, withExtension: "txt") ??
                  Bundle.main.url(forResource: fileName, withExtension: "txt", subdirectory: "categories") ??
                  Bundle.main.url(forResource: fileName, withExtension: "txt")

        // 4. Try App Plugins folder if running inside host Runner.app
        if url == nil, let pluginsURL = Bundle.main.builtInPlugInsURL {
            let extBundleURL = pluginsURL.appendingPathComponent("AuraTunnel.appex")
            if let extBundle = Bundle(url: extBundleURL) {
                url = extBundle.url(forResource: fileName, withExtension: "txt", subdirectory: "categories") ??
                      extBundle.url(forResource: fileName, withExtension: "txt")
            }
        }

        // 5. Try development filesystem relative path (for SPM/CLI tests)
        if url == nil {
            let devCandidates = [
                "ios/AuraTunnel/Resources/categories/\(fileName).txt",
                "../ios/AuraTunnel/Resources/categories/\(fileName).txt"
            ]
            for candidate in devCandidates {
                if FileManager.default.fileExists(atPath: candidate) {
                    url = URL(fileURLWithPath: candidate)
                    break
                }
            }
        }

        guard let targetURL = url, let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            os_log(.error, log: Self.log, "Could not find bundled domain list resource for category '%{public}@'", category)
            return fallbackDomains(for: category)
        }

        let domains = parseDomains(from: content)
        os_log(.info, log: Self.log, "Loaded %{public}ld domains for bundled category '%{public}@'", domains.count, category)
        return domains
    }

    private static func parseDomains(from content: String) -> Set<String> {
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
        return domains
    }

    /// Set of all domains belonging to any active or bundled default category.
    public static func allBundledDomains() -> Set<String> {
        var all = Set<String>()
        for (_, domains) in loadAllBundledCategories() {
            all.formUnion(domains)
        }
        return all
    }

    /// Loads all bundled and dynamic categories into a dictionary mapping category name to domain set.
    /// Strictly guarantees that only categories belonging to the single active release are loaded.
    public static func loadAllBundledCategories() -> [String: Set<String>] {
        var categories: [String: Set<String>] = [:]

        // 1. If an active release directory exists, ONLY load categories that exist in this active release
        if let activeDir = activeReleaseDirectoryURL {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: activeDir.path) {
                for item in items where item.hasSuffix(".txt") {
                    let catName = (item as NSString).deletingPathExtension.capitalized
                    categories[catName] = loadBundledDomains(for: catName)
                }
            }

            // Ensure standard default category names (Ads, Trackers, Analytics) are also checked
            // (in case a standard category is not in the directory, loadBundledDomains falls back to bundle)
            for name in defaultCategoryNames {
                if categories[name] == nil {
                    let domains = loadBundledDomains(for: name)
                    if !domains.isEmpty {
                        categories[name] = domains
                    }
                }
            }

            return categories
        }

        // 2. If no active release directory exists, use standard categories and legacy categories directory
        for name in defaultCategoryNames {
            categories[name] = loadBundledDomains(for: name)
        }

        if let legacyDir = customCategoriesDirectoryURL ?? sharedContainerURL?.appendingPathComponent("categories") {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path) {
                for item in items where item.hasSuffix(".txt") {
                    let catName = (item as NSString).deletingPathExtension.capitalized
                    if categories[catName] == nil {
                        categories[catName] = loadBundledDomains(for: catName)
                    }
                }
            }
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
