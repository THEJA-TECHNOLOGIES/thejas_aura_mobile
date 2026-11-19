import Foundation
import os.log
import Darwin.Mach

/// Shared, cross-process diagnostic logger and memory tracker for Theja Aura.
/// Writes thread-safely to `group.com.thejatech.aura/diagnostics.log`.
/// Accessible by both Runner (main app) and AuraTunnel (Network Extension).
public final class AuraDiagnostics {

    private static let logFileName = "diagnostics.log"
    private static let lock = NSLock()
    private static var lastReadOffset: UInt64 = 0

    public static var logFileURL: URL? {
        return AuraCategoryStore.sharedContainerURL?.appendingPathComponent(logFileName)
    }

    /// Current physical footprint in bytes as measured by Mach kernel (same metric as iOS Jetsam).
    public static func currentMemoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return UInt64(info.phys_footprint)
        }
        return 0
    }

    public static func formattedMemory() -> String {
        let bytes = currentMemoryFootprint()
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.2fMB", mb)
    }

    public static func log(tag: String, message: String) {
        lock.lock()
        defer { lock.unlock() }

        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let procName = bundleId.contains("AuraTunnel") ? "Extension" : "Runner"
        let pid = getpid()
        let mem = formattedMemory()
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = df.string(from: Date())
        let line = "[\(timestamp)] [\(procName):\(pid)] [\(mem)] [\(tag)] \(message)\n"

        // OSLog
        os_log(.default, "[AuraDiag] %{public}@", line)

        // Stderr/Stdout
        print("[AuraDiag] \(line)", terminator: "")

        // Append to diagnostics.log in shared App Group container
        guard let url = logFileURL else { return }
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Reads all diagnostics logs recorded in App Group storage.
    public static func readAllLogs() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logFileURL, FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }

    /// Flushes unread log entries from diagnostics.log directly to Xcode/terminal console.
    public static func flushNewLogsToConsole(prefix: String = "[AURA-STREAM]") {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logFileURL, FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return
        }
        let endOffset = handle.seekToEndOfFile()
        if endOffset > lastReadOffset {
            handle.seek(toFileOffset: lastReadOffset)
            let newData = handle.readDataToEndOfFile()
            lastReadOffset = endOffset
            if let text = String(data: newData, encoding: .utf8), !text.isEmpty {
                for line in text.split(separator: "\n") {
                    print("\(prefix) \(line)")
                }
            }
        }
        try? handle.close()
    }

    public static func clear() {
        lock.lock()
        defer { lock.unlock() }
        lastReadOffset = 0
        guard let url = logFileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Ultra-compact, low-memory binary index for domain blocklists.
/// Supports 600,000+ domains in under 7.5MB of RAM (or 0MB dirty footprint with mmap).
/// Performs sub-microsecond binary search lookups with 64-bit FNV-1a hashes.
public final class AuraCompactCategoryIndex {
    public static let magic: UInt32 = 0x41555241 // "AURA"
    public static let currentVersion: UInt32 = 1

    public let categoryNames: [String]
    public let count: Int

    private let mmapData: Data?
    private let heapHashes: [UInt64]?
    private let heapMasks: [UInt32]?
    private let hOffset: Int
    private let mOffset: Int

    // MARK: - Hashing

    /// 64-bit FNV-1a hash of a normalized domain string
    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            let lowerByte: UInt8 = (byte >= 0x41 && byte <= 0x5A) ? (byte | 0x20) : byte
            hash ^= UInt64(lowerByte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    /// 64-bit FNV-1a hash over raw byte buffer, converting ASCII uppercase to lowercase on the fly
    public static func fnv1a64(from ptr: UnsafePointer<UInt8>, count: Int) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for i in 0..<count {
            let b = ptr[i]
            let lowerByte: UInt8 = (b >= 0x41 && b <= 0x5A) ? (b | 0x20) : b
            hash ^= UInt64(lowerByte)
            hash = hash &* 1099511628211
        }
        return hash
    }

    // MARK: - Initializers

    public init(categoryNames: [String], hashes: [UInt64], categoryMasks: [UInt32]) {
        self.categoryNames = categoryNames
        self.count = hashes.count
        self.heapHashes = hashes
        self.heapMasks = categoryMasks
        self.mmapData = nil
        self.hOffset = 0
        self.mOffset = 0
    }

    /// In-memory initialization from legacy dictionary [CategoryName: Set<Domain>]
    public convenience init(from categories: [String: Set<String>]) {
        let sortedCatNames = categories.keys.sorted()
        var tempMap: [UInt64: UInt32] = [:]
        let totalCount = categories.values.reduce(0) { $0 + $1.count }
        tempMap.reserveCapacity(max(16, totalCount))

        for (catIndex, catName) in sortedCatNames.enumerated() {
            guard let domainSet = categories[catName] else { continue }
            let bit: UInt32 = 1 << min(catIndex, 31)
            for domain in domainSet {
                let norm = AuraDNSEngine.normalizeDomain(domain)
                guard !norm.isEmpty else { continue }
                let h = AuraCompactCategoryIndex.fnv1a64(norm)
                tempMap[h] = (tempMap[h] ?? 0) | bit
            }
        }

        let sortedPairs = tempMap.sorted { $0.key < $1.key }
        var hashes: [UInt64] = []
        hashes.reserveCapacity(sortedPairs.count)
        var masks: [UInt32] = []
        masks.reserveCapacity(sortedPairs.count)

        for pair in sortedPairs {
            hashes.append(pair.key)
            masks.append(pair.value)
        }

        self.init(categoryNames: sortedCatNames, hashes: hashes, categoryMasks: masks)
    }

    /// Memory-mapped initialization from compiled binary file (.bin)
    public init?(contentsOf fileURL: URL) {
        guard let data = try? Data(contentsOf: fileURL, options: .alwaysMapped) else {
            return nil
        }
        guard data.count >= 32 else { return nil }

        let raw = data.withUnsafeBytes { $0 }

        let readMagic = raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        let readVer = raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        guard readMagic == Self.magic, readVer == Self.currentVersion else {
            return nil
        }

        let catCount = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
        let domCount = Int(raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self))
        let catOffset = Int(raw.loadUnaligned(fromByteOffset: 16, as: UInt32.self))
        let hOff = Int(raw.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
        let mOff = Int(raw.loadUnaligned(fromByteOffset: 24, as: UInt32.self))

        guard hOff + domCount * 8 <= data.count,
              mOff + domCount * 4 <= data.count else {
            return nil
        }

        // Read category names
        var names: [String] = []
        var curOffset = catOffset
        for _ in 0..<catCount {
            guard curOffset + 2 <= data.count else { return nil }
            let nameLen = Int(raw.loadUnaligned(fromByteOffset: curOffset, as: UInt16.self))
            curOffset += 2
            guard curOffset + nameLen <= data.count else { return nil }
            let nameData = data.subdata(in: curOffset..<(curOffset + nameLen))
            guard let nameStr = String(data: nameData, encoding: .utf8) else { return nil }
            names.append(nameStr)
            curOffset += nameLen
        }

        self.categoryNames = names
        self.count = domCount
        self.mmapData = data
        self.heapHashes = nil
        self.heapMasks = nil
        self.hOffset = hOff
        self.mOffset = mOff
    }

    // MARK: - Binary Serialization

    public func write(to destinationURL: URL) throws {
        var data = Data()
        // Header placeholder (32 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 32))

        // Category Table
        let catOffset = data.count
        for name in categoryNames {
            let utf8 = Array(name.utf8)
            var nameLen = UInt16(utf8.count)
            let lenBytes = withUnsafeBytes(of: &nameLen) { Array($0) }
            data.append(contentsOf: lenBytes)
            data.append(contentsOf: utf8)
        }

        // Align to 8 bytes for hashes
        while data.count % 8 != 0 {
            data.append(0)
        }
        let hOffset = data.count

        // Write hashes
        let domCount = self.count
        if let dataSrc = mmapData {
            let sub = dataSrc.subdata(in: self.hOffset..<(self.hOffset + domCount * 8))
            data.append(sub)
        } else if let hh = heapHashes {
            hh.withUnsafeBufferPointer { data.append($0) }
        }

        // Align to 4 bytes for masks
        while data.count % 4 != 0 {
            data.append(0)
        }
        let mOffset = data.count

        // Write masks
        if let dataSrc = mmapData {
            let sub = dataSrc.subdata(in: self.mOffset..<(self.mOffset + domCount * 4))
            data.append(sub)
        } else if let hm = heapMasks {
            hm.withUnsafeBufferPointer { data.append($0) }
        }

        // Fill in header at offset 0
        let magic = Self.magic
        let ver = Self.currentVersion
        let catC = UInt32(categoryNames.count)
        let domC = UInt32(domCount)
        let catOff = UInt32(catOffset)
        let hOff = UInt32(hOffset)
        let mOff = UInt32(mOffset)
        let flags: UInt32 = 0

        data.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: magic, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: ver, toByteOffset: 4, as: UInt32.self)
            buf.storeBytes(of: catC, toByteOffset: 8, as: UInt32.self)
            buf.storeBytes(of: domC, toByteOffset: 12, as: UInt32.self)
            buf.storeBytes(of: catOff, toByteOffset: 16, as: UInt32.self)
            buf.storeBytes(of: hOff, toByteOffset: 20, as: UInt32.self)
            buf.storeBytes(of: mOff, toByteOffset: 24, as: UInt32.self)
            buf.storeBytes(of: flags, toByteOffset: 28, as: UInt32.self)
        }

        try data.write(to: destinationURL, options: .atomic)
    }

    // MARK: - Query / Matching

    @inline(__always)
    public func hashAt(_ index: Int) -> UInt64 {
        if let data = mmapData {
            return data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: hOffset + index * 8, as: UInt64.self)
            }
        }
        return heapHashes![index]
    }

    @inline(__always)
    public func maskAt(_ index: Int) -> UInt32 {
        if let data = mmapData {
            return data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: mOffset + index * 4, as: UInt32.self)
            }
        }
        return heapMasks![index]
    }

    public func matchingCategoryMask(for domainHash: UInt64) -> UInt32? {
        guard count > 0 else { return nil }
        var low = 0
        var high = count - 1
        while low <= high {
            let mid = (low + high) &>> 1
            let midHash = hashAt(mid)
            if midHash == domainHash {
                return maskAt(mid)
            } else if midHash < domainHash {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    public func categories(for mask: UInt32) -> [String] {
        var names: [String] = []
        for i in 0..<categoryNames.count {
            if (mask & (1 << i)) != 0 {
                names.append(categoryNames[i])
            }
        }
        return names
    }

    // MARK: - Streaming Parser & K-Way Merge Builder

    public static func parseDomainSlice(from ptr: UnsafePointer<UInt8>, length: Int) -> (offset: Int, length: Int)? {
        guard length > 0 else { return nil }
        var start = 0
        var end = length

        // 1. Trim leading whitespace
        while start < end {
            let b = ptr[start]
            if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A {
                start += 1
            } else {
                break
            }
        }

        // 2. Trim trailing whitespace
        while end > start {
            let b = ptr[end - 1]
            if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A {
                end -= 1
            } else {
                break
            }
        }

        guard start < end else { return nil }

        // 3. Comments at start
        let firstByte = ptr[start]
        if firstByte == 0x23 || firstByte == 0x21 { // '#' or '!'
            return nil
        }
        if firstByte == 0x2F && (start + 1 < end) && ptr[start + 1] == 0x2F { // '//'
            return nil
        }

        // 4. Strip inline comment if '#' or '//' is present
        for i in start..<end {
            let b = ptr[i]
            if b == 0x23 {
                end = i
                break
            } else if b == 0x2F && (i + 1 < end) && ptr[i + 1] == 0x2F {
                end = i
                break
            }
        }

        // Re-trim trailing whitespace before comment
        while end > start {
            let b = ptr[end - 1]
            if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A {
                end -= 1
            } else {
                break
            }
        }

        guard start < end else { return nil }

        // 5. Check hosts prefix: "0.0.0.0 " or "127.0.0.1 "
        if (end - start) > 8 {
            if ptr[start] == 0x30 && ptr[start+1] == 0x2E && ptr[start+2] == 0x30 && ptr[start+3] == 0x2E && ptr[start+4] == 0x30 && ptr[start+5] == 0x2E && ptr[start+6] == 0x30 {
                start += 7
                while start < end && (ptr[start] == 0x20 || ptr[start] == 0x09) {
                    start += 1
                }
            } else if (end - start) > 10 && ptr[start] == 0x31 && ptr[start+1] == 0x32 && ptr[start+2] == 0x37 && ptr[start+3] == 0x2E && ptr[start+4] == 0x30 && ptr[start+5] == 0x2E && ptr[start+6] == 0x30 && ptr[start+7] == 0x2E && ptr[start+8] == 0x31 {
                start += 9
                while start < end && (ptr[start] == 0x20 || ptr[start] == 0x09) {
                    start += 1
                }
            }
        }

        guard start < end else { return nil }

        // 6. Strip scheme "://"
        if (end - start) > 3 {
            for i in start..<(end - 2) {
                if ptr[i] == 0x3A && ptr[i+1] == 0x2F && ptr[i+2] == 0x2F {
                    start = i + 3
                    break
                }
            }
        }

        // 7. Strip path "/" or port ":"
        for i in start..<end {
            let b = ptr[i]
            if b == 0x2F || b == 0x3A {
                end = i
                break
            }
        }

        // 8. Strip trailing dots '.'
        while end > start && ptr[end - 1] == 0x2E {
            end -= 1
        }

        guard start < end else { return nil }
        return (start, end - start)
    }

    private static func parseHashes(from data: Data) -> [UInt64] {
        var hashes: [UInt64] = []
        hashes.reserveCapacity(max(1024, data.count / 25))

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let totalLen = rawBuffer.count
            var lineStart = 0

            for i in 0..<totalLen {
                let byte = ptr[i]
                if byte == 0x0A || byte == 0x0D {
                    if i > lineStart {
                        let lineLen = i - lineStart
                        let linePtr = ptr + lineStart
                        if let (domainOffset, domainLen) = parseDomainSlice(from: linePtr, length: lineLen) {
                            let domainPtr = linePtr + domainOffset
                            let h = fnv1a64(from: domainPtr, count: domainLen)
                            hashes.append(h)
                        }
                    }
                    lineStart = i + 1
                }
            }
            if lineStart < totalLen {
                let lineLen = totalLen - lineStart
                let linePtr = ptr + lineStart
                if let (domainOffset, domainLen) = parseDomainSlice(from: linePtr, length: lineLen) {
                    let domainPtr = linePtr + domainOffset
                    let h = fnv1a64(from: domainPtr, count: domainLen)
                    hashes.append(h)
                }
            }
        }

        hashes.sort()
        if hashes.isEmpty { return hashes }
        var uniqueHashes: [UInt64] = []
        uniqueHashes.reserveCapacity(hashes.count)
        var last: UInt64? = nil
        for h in hashes {
            if h != last {
                uniqueHashes.append(h)
                last = h
            }
        }
        return uniqueHashes
    }

    private static func kWayMerge(catHashes: inout [[UInt64]]) -> (hashes: [UInt64], masks: [UInt32]) {
        let k = catHashes.count
        guard k > 0 else { return ([], []) }
        if k == 1 {
            let singleHashes = catHashes[0]
            let singleMasks = [UInt32](repeating: 1, count: singleHashes.count)
            return (singleHashes, singleMasks)
        }

        var totalEstimated = 0
        for arr in catHashes { totalEstimated += arr.count }

        var mergedHashes: [UInt64] = []
        mergedHashes.reserveCapacity(totalEstimated)
        var mergedMasks: [UInt32] = []
        mergedMasks.reserveCapacity(totalEstimated)

        var indices = [Int](repeating: 0, count: k)

        while true {
            var minHash: UInt64 = UInt64.max
            var hasRemaining = false

            for catIdx in 0..<k {
                let curIdx = indices[catIdx]
                if curIdx < catHashes[catIdx].count {
                    hasRemaining = true
                    let h = catHashes[catIdx][curIdx]
                    if h < minHash {
                        minHash = h
                    }
                }
            }

            guard hasRemaining else { break }

            var mask: UInt32 = 0
            for catIdx in 0..<k {
                let curIdx = indices[catIdx]
                if curIdx < catHashes[catIdx].count && catHashes[catIdx][curIdx] == minHash {
                    mask |= (1 << min(catIdx, 31))
                    indices[catIdx] = curIdx + 1
                    if indices[catIdx] >= catHashes[catIdx].count {
                        catHashes[catIdx] = []
                    }
                }
            }

            mergedHashes.append(minHash)
            mergedMasks.append(mask)
        }

        return (mergedHashes, mergedMasks)
    }

    /// Builds compact index from a directory of .txt files using low-memory streaming parser.
    public static func buildFromDirectory(_ dirURL: URL) -> AuraCompactCategoryIndex? {
        guard FileManager.default.fileExists(atPath: dirURL.path) else { return nil }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) else { return nil }

        let txtFiles = items.filter { item in
            let lower = item.lowercased()
            return lower.hasSuffix(".txt") && lower != "domains.txt" && lower != "hosts.txt"
        }.sorted()

        guard !txtFiles.isEmpty else {
            return AuraCompactCategoryIndex(categoryNames: [], hashes: [], categoryMasks: [])
        }

        var catNames: [String] = []
        var catHashes: [[UInt64]] = []

        for (catIdx, fileItem) in txtFiles.enumerated() {
            guard catIdx < 32 else { break }
            let catName = (fileItem as NSString).deletingPathExtension.capitalized
            catNames.append(catName)

            let fileURL = dirURL.appendingPathComponent(fileItem)
            AuraDiagnostics.log(tag: "CompactIndex", message: "Parsing category [\(catIdx+1)/\(txtFiles.count)] '\(catName)' (\(AuraDiagnostics.formattedMemory()))...")

            let hashesForCat = autoreleasepool { () -> [UInt64] in
                guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return [] }
                return parseHashes(from: data)
            }

            AuraDiagnostics.log(tag: "CompactIndex", message: "Parsed '\(catName)': \(hashesForCat.count) unique domains (\(AuraDiagnostics.formattedMemory()))")
            catHashes.append(hashesForCat)
        }

        AuraDiagnostics.log(tag: "CompactIndex", message: "Starting K-way merge of \(catHashes.count) categories (\(AuraDiagnostics.formattedMemory()))...")
        let (mergedHashes, mergedMasks) = kWayMerge(catHashes: &catHashes)
        AuraDiagnostics.log(tag: "CompactIndex", message: "K-way merge complete: \(mergedHashes.count) unique domains (\(AuraDiagnostics.formattedMemory()))")

        return AuraCompactCategoryIndex(categoryNames: catNames, hashes: mergedHashes, categoryMasks: mergedMasks)
    }
}

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
    public static let compactIndexFileName = "compact_categories.bin"

    public static var defaultPreferences: [String: Bool] {
        guard let dir = categoriesDirectoryURL, FileManager.default.fileExists(atPath: dir.path) else {
            return [:]
        }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return [:]
        }
        var prefs: [String: Bool] = [:]
        for item in items where item.hasSuffix(".txt") {
            let lower = item.lowercased()
            if lower == "domains.txt" || lower == "hosts.txt" {
                continue
            }
            let rawId = (item as NSString).deletingPathExtension
            let catName = rawId.capitalized
            prefs[catName] = true
        }
        return prefs
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
        if container.version.hasPrefix("bundled") || container.version == "legacy" || container.version == "synthetic" {
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

    /// URL of the compiled compact category binary index in the active release directory.
    public static var activeCompactIndexURL: URL? {
        guard let dir = categoriesDirectoryURL else { return nil }
        let binURL = dir.appendingPathComponent(compactIndexFileName)
        return FileManager.default.fileExists(atPath: binURL.path) ? binURL : nil
    }

    /// Loads the active category index using the low-memory compact representation.
    /// Prefers the memory-mapped binary index if compiled, otherwise builds dynamically with streaming parser.
    public static func loadActiveCompactIndex() -> AuraCompactCategoryIndex? {
        guard let activeDir = categoriesDirectoryURL, FileManager.default.fileExists(atPath: activeDir.path) else {
            return nil
        }

        let binURL = activeDir.appendingPathComponent(compactIndexFileName)
        if FileManager.default.fileExists(atPath: binURL.path) {
            if let index = AuraCompactCategoryIndex(contentsOf: binURL) {
                AuraDiagnostics.log(tag: "CategoryStore", message: "loadActiveCompactIndex loaded binary index (\(index.count) domains across \(index.categoryNames.count) categories) (mem: \(AuraDiagnostics.formattedMemory()))")
                return index
            } else {
                AuraDiagnostics.log(tag: "CategoryStore", message: "loadActiveCompactIndex: binary index invalid or corrupt, falling back to streaming parser")
            }
        }

        AuraDiagnostics.log(tag: "CategoryStore", message: "loadActiveCompactIndex: binary index not found at \(binURL.path); building with streaming parser...")
        if let index = AuraCompactCategoryIndex.buildFromDirectory(activeDir) {
            // Attempt to persist compiled index to avoid future re-parsing
            try? index.write(to: binURL)
            AuraDiagnostics.log(tag: "CategoryStore", message: "loadActiveCompactIndex built streaming index (\(index.count) domains across \(index.categoryNames.count) categories) (mem: \(AuraDiagnostics.formattedMemory()))")
            return index
        }
        return nil
    }

    /// Ensures the compact binary index exists in the active release directory.
    /// Runs safely in Runner (which has >1GB heap budget) to pre-compile the binary index before extension load.
    public static func ensureCompactIndexExists() {
        guard let activeDir = categoriesDirectoryURL, FileManager.default.fileExists(atPath: activeDir.path) else {
            return
        }
        let binURL = activeDir.appendingPathComponent(compactIndexFileName)
        guard !FileManager.default.fileExists(atPath: binURL.path) else {
            return
        }
        AuraDiagnostics.log(tag: "CategoryStore", message: "ensureCompactIndexExists: generating \(compactIndexFileName) in active release dir...")
        if let index = AuraCompactCategoryIndex.buildFromDirectory(activeDir) {
            try? index.write(to: binURL)
            AuraDiagnostics.log(tag: "CategoryStore", message: "ensureCompactIndexExists: pre-compiled \(compactIndexFileName) with \(index.count) domains across \(index.categoryNames.count) categories")
        }
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

        AuraDiagnostics.log(tag: "CategoryStore", message: "installRelease: starting version=\(version) files=\(files.count) domainCount=\(domainCount)")
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

        // 4b. Pre-compile compact binary category index in staging directory
        if let compactIndex = AuraCompactCategoryIndex.buildFromDirectory(stageDir) {
            let compactBinURL = stageDir.appendingPathComponent(compactIndexFileName)
            try compactIndex.write(to: compactBinURL)
            AuraDiagnostics.log(tag: "CategoryStore", message: "Pre-compiled compact binary index to \(compactBinURL.lastPathComponent) (\(compactIndex.count) domains across \(compactIndex.categoryNames.count) categories)")
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

        if container.version.hasPrefix("bundled") || container.version == "legacy" || container.version == "synthetic" {
            os_log(.info, log: Self.log, "Release version '%{public}@' is a legacy synthetic placeholder — treating as no backend release", container.version)
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
        AuraDiagnostics.log(tag: "CategoryStore", message: "clearInstalledRelease: clearing installed release")
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
        os_log(.info, log: Self.log, "Cleared installed release from App Group; no active categories remain")
    }

    // MARK: - Active Release Category Domain Lists Loader

    /// Loads domains directly from a file URL inside an autoreleasepool.
    public static func loadBundledDomains(from fileURL: URL) -> Set<String> {
        return autoreleasepool {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
            let domains = parseDomains(from: content)
            return domains
        }
    }

    /// Loads the active domains for a given category ("Ads", "Trackers", "Analytics", etc.).
    /// Checks the App Group container active release directory only.
    /// Returns an empty set if no backend release is active or if the category does not exist.
    public static func loadBundledDomains(for category: String) -> Set<String> {
        let fileName = category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlt = fileName.replacingOccurrences(of: " ", with: "_")

        if let customURL = customCategoryDomainFiles?[fileName] ?? customCategoryDomainFiles?[normalizedAlt],
           FileManager.default.fileExists(atPath: customURL.path) {
            return loadBundledDomains(from: customURL)
        }

        // 1. App Group container active release directory (backend-installed release)
        if let activeDir = activeReleaseDirectoryURL {
            let candidate = activeDir.appendingPathComponent("\(fileName).txt")
            let candidateAlt = activeDir.appendingPathComponent("\(normalizedAlt).txt")
            let fileURL = FileManager.default.fileExists(atPath: candidate.path) ? candidate :
                          (FileManager.default.fileExists(atPath: candidateAlt.path) ? candidateAlt : nil)
            if let fileURL = fileURL {
                let domains = loadBundledDomains(from: fileURL)
                os_log(.info, log: Self.log, "Loaded %{public}ld domains from active release directory for category '%{public}@'", domains.count, category)
                return domains
            }
        }

        // 2. Custom categories directory if explicitly set in test environments
        if let customDir = customCategoriesDirectoryURL,
           FileManager.default.fileExists(atPath: customDir.path) {
            let candidate = customDir.appendingPathComponent("\(fileName).txt")
            let candidateAlt = customDir.appendingPathComponent("\(normalizedAlt).txt")
            let fileURL = FileManager.default.fileExists(atPath: candidate.path) ? candidate :
                          (FileManager.default.fileExists(atPath: candidateAlt.path) ? candidateAlt : nil)
            if let fileURL = fileURL {
                return loadBundledDomains(from: fileURL)
            }
        }

        // No active backend release or file not found -> return empty set. No static bundle fallback.
        return []
    }

    private static func parseDomains(from content: String) -> Set<String> {
        var domains = Set<String>()
        // Estimate line count to reserve capacity and prevent multi-stage Set table reallocations
        let estimatedCount = max(16, content.utf8.count / 25)
        domains.reserveCapacity(estimatedCount)

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

    /// Fast domain counter that counts domain entries in a category file using memory-mapped I/O
    /// without heap-allocating full strings or Set collections.
    public static func countDomainsInFile(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return 0
        }
        var count = 0
        var isLineEmptyOrComment = true
        var hasSeenNonWhitespace = false

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let len = rawBuffer.count
            for i in 0..<len {
                let byte = ptr[i]
                if byte == 0x0A || byte == 0x0D { // '\n' or '\r'
                    if !isLineEmptyOrComment && hasSeenNonWhitespace {
                        count += 1
                    }
                    isLineEmptyOrComment = true
                    hasSeenNonWhitespace = false
                } else if !hasSeenNonWhitespace {
                    if byte == 0x20 || byte == 0x09 { // ' ' or '\t'
                        // whitespace
                    } else if byte == 0x23 || byte == 0x2F { // '#' or '/'
                        // comment line
                        isLineEmptyOrComment = true
                        hasSeenNonWhitespace = true
                    } else {
                        isLineEmptyOrComment = false
                        hasSeenNonWhitespace = true
                    }
                }
            }
            if !isLineEmptyOrComment && hasSeenNonWhitespace {
                count += 1
            }
        }
        return count
    }

    /// Fast membership check across active bundled categories without creating a full union Set.
    public static func containsBundledDomain(_ domain: String) -> Bool {
        let normalized = AuraDNSEngine.normalizeDomain(domain)
        guard !normalized.isEmpty else { return false }
        if let index = loadActiveCompactIndex() {
            let h = AuraCompactCategoryIndex.fnv1a64(normalized)
            return index.matchingCategoryMask(for: h) != nil
        }
        for (_, domains) in loadAllBundledCategories() {
            if domains.contains(normalized) {
                return true
            }
        }
        return false
    }

    /// Set of all domains belonging to any category in the active backend release.
    /// Returns an empty set if no backend release is installed.
    public static func allBundledDomains() -> Set<String> {
        var all = Set<String>()
        let cats = loadAllBundledCategories()
        let totalCount = cats.values.reduce(0) { $0 + $1.count }
        all.reserveCapacity(totalCount)
        for domains in cats.values {
            all.formUnion(domains)
        }
        return all
    }

    /// Loads all categories belonging to the currently active backend release.
    /// Returns an empty map if no release is installed or active.
    public static func loadAllBundledCategories() -> [String: Set<String>] {
        var categories: [String: Set<String>] = [:]

        // If an active release directory exists, ONLY load categories that exist in this active release
        if let activeDir = activeReleaseDirectoryURL {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: activeDir.path) {
                for item in items where item.hasSuffix(".txt") {
                    let lower = item.lowercased()
                    if lower == "domains.txt" || lower == "hosts.txt" {
                        continue
                    }
                    let catName = (item as NSString).deletingPathExtension.capitalized
                    let fileURL = activeDir.appendingPathComponent(item)
                    categories[catName] = loadBundledDomains(from: fileURL)
                }
            }
            return categories
        }

        // Custom categories directory if explicitly set in test environments
        if let customDir = customCategoriesDirectoryURL,
           FileManager.default.fileExists(atPath: customDir.path) {
            if let items = try? FileManager.default.contentsOfDirectory(atPath: customDir.path) {
                for item in items where item.hasSuffix(".txt") {
                    let lower = item.lowercased()
                    if lower == "domains.txt" || lower == "hosts.txt" {
                        continue
                    }
                    let catName = (item as NSString).deletingPathExtension.capitalized
                    let fileURL = customDir.appendingPathComponent(item)
                    categories[catName] = loadBundledDomains(from: fileURL)
                }
            }
            return categories
        }

        // No active backend release -> return empty dictionary. No static bundle fallback.
        return [:]
    }

    /// Loads metadata for each category installed in the active backend release.
    /// Returns an empty array if no release is installed.
    public static func loadReleaseCategories() -> [[String: Any]] {
        guard let activeDir = categoriesDirectoryURL, FileManager.default.fileExists(atPath: activeDir.path) else {
            return []
        }
        var results: [[String: Any]] = []
        if let items = try? FileManager.default.contentsOfDirectory(atPath: activeDir.path) {
            for item in items.sorted() where item.hasSuffix(".txt") {
                let lower = item.lowercased()
                if lower == "domains.txt" || lower == "hosts.txt" {
                    continue
                }
                let rawId = (item as NSString).deletingPathExtension
                let catName = rawId.capitalized
                let fileURL = activeDir.appendingPathComponent(item)
                let count = countDomainsInFile(at: fileURL)
                results.append([
                    "id": rawId,
                    "name": catName,
                    "fileName": item,
                    "domainCount": count
                ])
            }
        }
        return results
    }

    /// Loads the domain list for a specific category from the active backend release.
    /// Returns an empty array if no release is installed or category is empty.
    public static func loadCategoryDomains(category: String) -> [String] {
        let domains = loadBundledDomains(for: category)
        return domains.sorted()
    }
}
