package com.thejatech.aura.storage

import android.content.Context
import com.thejatech.aura.engine.AuraDnsEngine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

class AuraCategoryStore(private val context: Context) {

    private val preferencesFile: File
        get() = File(context.filesDir, "aura_category_preferences.json")

    private val overridesFile: File
        get() = File(context.filesDir, "aura_default_domain_overrides.json")

    private val releaseFile: File
        get() = File(context.filesDir, "installed_release.json")

    private val releasesDir: File
        get() = File(context.filesDir, "releases")

    private val stagingDir: File
        get() = File(context.filesDir, "staging")

    private val lock = Any()

    fun cleanupStaging() {
        try {
            val root = stagingDir
            if (root.exists()) {
                root.listFiles()?.forEach { it.deleteRecursively() }
            }
        } catch (_: Exception) {}
    }

    // MARK: - Preferences

    fun loadPreferences(): Map<String, Boolean> = synchronized(lock) {
        val releaseCategories = loadReleaseCategories()
        val defaults = mutableMapOf<String, Boolean>()
        for (cat in releaseCategories) {
            val name = cat["name"] as? String
            if (name != null) {
                defaults[name] = true
            }
        }

        val file = preferencesFile
        if (!file.exists()) return defaults

        return try {
            val content = file.readText(Charsets.UTF_8)
            val json = JSONObject(content)
            val categoriesObj = json.optJSONObject("categories") ?: JSONObject()
            val merged = HashMap(defaults)
            for (key in categoriesObj.keys()) {
                merged[key] = categoriesObj.getBoolean(key)
            }
            merged
        } catch (e: Exception) {
            defaults
        }
    }

    fun savePreferences(preferences: Map<String, Boolean>): Unit = synchronized(lock) {
        val json = JSONObject()
        json.put("version", 1)
        val catObj = JSONObject()
        for ((k, v) in preferences) {
            catObj.put(k, v)
        }
        json.put("categories", catObj)

        val target = preferencesFile
        val temp = File(context.filesDir, "aura_category_preferences.json.tmp")
        temp.writeText(json.toString(2), Charsets.UTF_8)
        if (target.exists()) target.delete()
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
    }

    fun setCategoryPreference(category: String, isEnabled: Boolean): Map<String, Boolean> = synchronized(lock) {
        val current = loadPreferences().toMutableMap()
        current[category] = isEnabled
        savePreferences(current)
        return current
    }

    // MARK: - Overrides

    fun loadDisabledDefaultDomains(): Set<String> = synchronized(lock) {
        val file = overridesFile
        if (!file.exists()) return emptySet()

        return try {
            val content = file.readText(Charsets.UTF_8)
            val json = JSONObject(content)
            val array = json.optJSONArray("disabledDomains") ?: JSONArray()
            val set = mutableSetOf<String>()
            for (i in 0 until array.length()) {
                val norm = AuraDnsEngine.normalizeDomain(array.getString(i))
                if (norm.isNotEmpty()) {
                    set.add(norm)
                }
            }
            set
        } catch (_: Exception) {
            emptySet()
        }
    }

    fun saveDisabledDefaultDomains(domains: Set<String>): Unit = synchronized(lock) {
        val json = JSONObject()
        json.put("version", 1)
        val array = JSONArray()
        for (domain in domains.sorted()) {
            array.put(domain)
        }
        json.put("disabledDomains", array)

        val target = overridesFile
        val temp = File(context.filesDir, "aura_default_domain_overrides.json.tmp")
        temp.writeText(json.toString(2), Charsets.UTF_8)
        if (target.exists()) target.delete()
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
    }

    fun toggleDefaultDomain(domain: String, isEnabled: Boolean): Set<String> = synchronized(lock) {
        val norm = AuraDnsEngine.normalizeDomain(domain)
        val current = loadDisabledDefaultDomains().toMutableSet()
        if (isEnabled) {
            current.remove(norm)
        } else {
            current.add(norm)
        }
        saveDisabledDefaultDomains(current)
        return current
    }

    // MARK: - Active Release

    fun activeReleaseDirectory(): File? {
        val target = releaseFile
        if (!target.exists()) return null
        return try {
            val content = target.readText(Charsets.UTF_8)
            val json = JSONObject(content)
            val dirName = json.optString("releaseDirectory")
            if (dirName.isNullOrBlank()) return null
            val dir = File(releasesDir, dirName)
            if (dir.exists() && dir.isDirectory) dir else null
        } catch (_: Exception) {
            null
        }
    }

    fun installRelease(
        version: String,
        files: Map<String, String>,
        domainCount: Int = 0,
        etag: String? = null,
        checksum: String? = null
    ): Map<String, Any> = synchronized(lock) {
        if (files.isEmpty()) {
            throw IllegalArgumentException("Cannot install empty release with no files")
        }

        cleanupStaging()
        val stageRoot = stagingDir
        stageRoot.mkdirs()
        releasesDir.mkdirs()

        val releaseToken = UUID.randomUUID().toString().take(8)
        val sanitizedVersion = version.replace(Regex("[^a-zA-Z0-9.-]"), "_")
        val releaseDirName = "rel_${sanitizedVersion}_$releaseToken"
        val stageDir = File(stageRoot, "stage_$releaseDirName")
        val finalReleaseDir = File(releasesDir, releaseDirName)

        if (stageDir.exists()) stageDir.deleteRecursively()
        stageDir.mkdirs()

        var activationSucceeded = false
        try {
            val installedFilesMap = mutableMapOf<String, String>()
            for ((name, content) in files) {
                val normalizedName = if (name.lowercase().endsWith(".txt")) name.lowercase() else "${name.lowercase()}.txt"
                val file = File(stageDir, normalizedName)
                file.writeText(content, Charsets.UTF_8)
                installedFilesMap[name] = normalizedName
            }

            // Verify integrity
            for ((name, _) in files) {
                val normalizedName = if (name.lowercase().endsWith(".txt")) name.lowercase() else "${name.lowercase()}.txt"
                val file = File(stageDir, normalizedName)
                if (!file.exists() || file.length() == 0L) {
                    throw IllegalStateException("Staged file $normalizedName is missing or empty")
                }
            }

            // Move stage to final
            if (finalReleaseDir.exists()) finalReleaseDir.deleteRecursively()
            if (!stageDir.renameTo(finalReleaseDir)) {
                stageDir.copyRecursively(finalReleaseDir, overwrite = true)
                stageDir.deleteRecursively()
            }

            // Write metadata
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val isoDate = isoFormat.format(Date())

            val metaJson = JSONObject()
            metaJson.put("version", version)
            metaJson.put("installedAt", isoDate)
            metaJson.put("domainCount", domainCount)
            metaJson.put("releaseDirectory", releaseDirName)
            if (etag != null) metaJson.put("etag", etag)
            if (checksum != null) metaJson.put("checksum", checksum)

            val filesObj = JSONObject()
            for ((k, v) in installedFilesMap) {
                filesObj.put(k, v)
            }
            metaJson.put("files", filesObj)

            val target = releaseFile
            val temp = File(context.filesDir, "installed_release.json.tmp")
            temp.writeText(metaJson.toString(2), Charsets.UTF_8)
            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }

            activationSucceeded = true

            // Prune older releases
            releasesDir.listFiles()?.forEach { file ->
                if (file.name != releaseDirName) {
                    file.deleteRecursively()
                }
            }
            cleanupStaging()

            val resultMap = mutableMapOf<String, Any>(
                "success" to true,
                "version" to version,
                "installedAt" to isoDate,
                "domainCount" to domainCount,
                "files" to installedFilesMap,
                "releaseDirectory" to releaseDirName
            )
            return resultMap
        } finally {
            if (!activationSucceeded) {
                stageDir.deleteRecursively()
                finalReleaseDir.deleteRecursively()
            }
        }
    }

    fun loadInstalledRelease(): Map<String, Any>? = synchronized(lock) {
        val target = releaseFile
        if (!target.exists()) return null
        return try {
            val content = target.readText(Charsets.UTF_8)
            val json = JSONObject(content)
            val dirName = json.optString("releaseDirectory")
            val releaseDir = File(releasesDir, dirName)
            if (!releaseDir.exists() || !releaseDir.isDirectory) return null

            val filesObj = json.optJSONObject("files") ?: JSONObject()
            val filesMap = mutableMapOf<String, String>()
            for (key in filesObj.keys()) {
                filesMap[key] = filesObj.getString(key)
            }

            val map = mutableMapOf<String, Any>(
                "version" to json.optString("version", "unknown"),
                "installedAt" to json.optString("installedAt", ""),
                "domainCount" to json.optInt("domainCount", 0),
                "files" to filesMap,
                "releaseDirectory" to dirName
            )
            val etag = json.optString("etag")
            if (etag.isNotEmpty()) map["etag"] = etag
            val checksum = json.optString("checksum")
            if (checksum.isNotEmpty()) map["checksum"] = checksum
            map
        } catch (_: Exception) {
            null
        }
    }

    fun clearInstalledRelease(): Unit = synchronized(lock) {
        releasesDir.deleteRecursively()
        stagingDir.deleteRecursively()
        if (releaseFile.exists()) releaseFile.delete()
    }

    fun loadReleaseCategories(): List<Map<String, Any>> {
        val activeDir = activeReleaseDirectory() ?: return emptyList()
        val files = activeDir.listFiles { _, name -> name.lowercase().endsWith(".txt") } ?: return emptyList()

        val results = mutableListOf<Map<String, Any>>()
        for (file in files.sortedBy { it.name }) {
            val lower = file.name.lowercase()
            if (lower == "domains.txt" || lower == "hosts.txt") continue

            val rawId = file.nameWithoutExtension
            val catName = rawId.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }
            val domains = loadDomainsFromFile(file)
            results.add(
                mapOf(
                    "id" to rawId,
                    "name" to catName,
                    "fileName" to file.name,
                    "domainCount" to domains.size
                )
            )
        }
        return results
    }

    fun loadCategoryDomains(category: String): List<String> {
        val activeDir = activeReleaseDirectory() ?: return emptyList()
        val fileName = category.lowercase().trim()
        val targetFile = File(activeDir, if (fileName.endsWith(".txt")) fileName else "$fileName.txt")
        if (!targetFile.exists()) return emptyList()
        return loadDomainsFromFile(targetFile).sorted()
    }

    fun loadAllBundledCategories(): Map<String, Set<String>> {
        val activeDir = activeReleaseDirectory() ?: return emptyMap()
        val files = activeDir.listFiles { _, name -> name.lowercase().endsWith(".txt") } ?: return emptyMap()

        val map = mutableMapOf<String, Set<String>>()
        for (file in files) {
            val lower = file.name.lowercase()
            if (lower == "domains.txt" || lower == "hosts.txt") continue
            val catName = file.nameWithoutExtension.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }
            map[catName] = loadDomainsFromFile(file)
        }
        return map
    }

    fun allBundledDomains(): Set<String> {
        val set = mutableSetOf<String>()
        for ((_, domains) in loadAllBundledCategories()) {
            set.addAll(domains)
        }
        return set
    }

    private fun loadDomainsFromFile(file: File): Set<String> {
        val domains = mutableSetOf<String>()
        if (!file.exists()) return domains

        file.forEachLine(Charsets.UTF_8) { line ->
            val trimmed = line.trim()
            if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && !trimmed.startsWith("//")) {
                val norm = AuraDnsEngine.normalizeDomain(trimmed)
                if (norm.isNotEmpty()) {
                    domains.add(norm)
                }
            }
        }
        return domains
    }

    companion object {
        const val DEFAULT_API_BASE_URL = "https://mobileapi.theja.in"
        private const val SYNC_PREFS = "aura_sync_prefs"
        private const val KEY_API_BASE_URL = "api_base_url"

        val isSyncInProgress = java.util.concurrent.atomic.AtomicBoolean(false)

        fun getApiBaseUrl(context: Context): String {
            val prefs = context.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
            return prefs.getString(KEY_API_BASE_URL, DEFAULT_API_BASE_URL) ?: DEFAULT_API_BASE_URL
        }

        fun setApiBaseUrl(context: Context, url: String) {
            val trimmed = url.trim().trimEnd('/')
            if (trimmed.isNotEmpty()) {
                val prefs = context.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
                prefs.edit().putString(KEY_API_BASE_URL, trimmed).apply()
            }
        }
    }
}
