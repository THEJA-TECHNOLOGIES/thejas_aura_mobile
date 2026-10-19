package com.thejatech.aura.sync

import android.content.Context
import android.util.Log
import androidx.work.ListenableWorker
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.thejatech.aura.storage.AuraCategoryStore
import com.thejatech.aura.tunnel.AuraTunnelManager
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class BlocklistSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    override fun doWork(): ListenableWorker.Result {
        // Concurrency guard: prevent background sync from racing with foreground Flutter sync
        if (!AuraCategoryStore.isSyncInProgress.compareAndSet(false, true)) {
            Log.i(TAG, "Blocklist synchronization already in progress, retrying later")
            return ListenableWorker.Result.retry()
        }

        try {
            val categoryStore = AuraCategoryStore(applicationContext)
            val baseUrl = AuraCategoryStore.getApiBaseUrl(applicationContext)
            val currentRelease = categoryStore.loadInstalledRelease()

            val currentEtag = currentRelease?.get("etag") as? String
                ?: currentRelease?.get("version") as? String

            // 1. Fetch manifest with If-None-Match ETag
            val manifestUrl = resolveUrl(baseUrl, "/api/public/blocklist/manifest")
            val manifestConnection = (URL(manifestUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000
                readTimeout = 15000
                requestMethod = "GET"
                setRequestProperty("Accept", "application/json")
                if (!currentEtag.isNullOrEmpty()) {
                    setRequestProperty("If-None-Match", currentEtag)
                }
            }

            val responseCode = manifestConnection.responseCode
            if (responseCode == HttpURLConnection.HTTP_NOT_MODIFIED) {
                Log.i(TAG, "Manifest not modified (304), local release is up to date")
                return ListenableWorker.Result.success()
            }

            if (responseCode != HttpURLConnection.HTTP_OK) {
                Log.w(TAG, "Manifest request failed with HTTP $responseCode")
                return ListenableWorker.Result.retry()
            }

            val manifestBody = manifestConnection.inputStream.bufferedReader().use { it.readText() }
            val manifest = JSONObject(manifestBody)

            val version = manifest.getString("version")
            val domainCount = manifest.optInt("domainCount", 0)
            val manifestChecksum = manifest.optString("checksum").takeIf { it.isNotEmpty() }

            // Version check
            val currentVersion = currentRelease?.get("version") as? String
            val hasExistingFiles = categoryStore.loadAllBundledCategories().isNotEmpty()
            if (currentVersion == version && hasExistingFiles) {
                Log.i(TAG, "Already on latest version $version, skipping download")
                return ListenableWorker.Result.success()
            }

            // 2. Discover category files to download
            val filesToDownload = mutableMapOf<String, String>() // destinationFileName -> URL
            val expectedChecksums = mutableMapOf<String, String?>()

            val categories = manifest.optJSONObject("categories")
            if (categories != null && categories.length() > 0) {
                val keys = categories.keys()
                while (keys.hasNext()) {
                    val catKey = keys.next()
                    val catObj = categories.optJSONObject(catKey) ?: continue
                    val normKey = catKey.lowercase().trim()
                    val destName = if (normKey.endsWith(".txt")) normKey else "$normKey.txt"

                    val url = catObj.optString("domainsUrl").takeIf { it.isNotEmpty() }
                        ?: catObj.optJSONObject("files")?.optString("domains")?.takeIf { it.isNotEmpty() }
                        ?: catObj.optString("hostsUrl").takeIf { it.isNotEmpty() }
                        ?: catObj.optJSONObject("files")?.optString("hosts")?.takeIf { it.isNotEmpty() }

                    if (!url.isNullOrEmpty()) {
                        filesToDownload[destName] = url
                        val checksum = catObj.optString("checksum").takeIf { it.isNotEmpty() }
                            ?: manifestChecksum
                        expectedChecksums[destName] = checksum
                    }
                }
            }

            // Fallback to manifest.files if manifest.categories is empty
            if (filesToDownload.isEmpty()) {
                val files = manifest.optJSONObject("files")
                if (files != null && files.length() > 0) {
                    val keys = files.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val normKey = key.lowercase().trim()
                        val url = files.getString(key)

                        val destName = when {
                            normKey.contains("categories/") -> {
                                val cat = normKey.split("/").getOrNull(1) ?: normKey
                                if (cat.endsWith(".txt")) cat else "$cat.txt"
                            }
                            normKey == "domains" || normKey == "domains.txt" -> "domains.txt"
                            normKey == "hosts" || normKey == "hosts.txt" -> "hosts.txt"
                            else -> if (normKey.endsWith(".txt")) normKey else "$normKey.txt"
                        }
                        filesToDownload[destName] = url
                        expectedChecksums[destName] = manifestChecksum
                    }
                }
            }

            if (filesToDownload.isEmpty()) {
                Log.e(TAG, "No downloadable blocklist files found in manifest")
                return ListenableWorker.Result.retry()
            }

            // 3. Download and validate each category file
            val downloadedFiles = mutableMapOf<String, String>()
            var totalDomainsValidated = 0

            for ((destName, fileUrlOrPath) in filesToDownload) {
                val resolvedUrl = resolveUrl(baseUrl, fileUrlOrPath)

                // Host authorization check
                val targetHost = URL(resolvedUrl).host
                val baseHost = URL(baseUrl).host
                if (!targetHost.equals(baseHost, ignoreCase = true)) {
                    Log.e(TAG, "Untrusted destination host: $targetHost (expected $baseHost)")
                    return ListenableWorker.Result.retry()
                }

                val conn = (URL(resolvedUrl).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 30000
                    requestMethod = "GET"
                }

                if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                    Log.e(TAG, "Failed to download $destName: HTTP ${conn.responseCode}")
                    return ListenableWorker.Result.retry()
                }

                val content = conn.inputStream.bufferedReader().use { it.readText() }

                // Checksum verification
                val expectedSha = expectedChecksums[destName]
                if (!expectedSha.isNullOrEmpty()) {
                    val actualSha = computeSha256(content)
                    if (!actualSha.equals(expectedSha, ignoreCase = true)) {
                        Log.e(TAG, "Checksum mismatch for $destName: expected $expectedSha, got $actualSha")
                        return ListenableWorker.Result.retry()
                    }
                }

                // Domain line validation
                var domainCount = 0
                content.lineSequence().forEach { line ->
                    val trimmed = line.trim()
                    if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && !trimmed.startsWith("//")) {
                        domainCount++
                    }
                }

                downloadedFiles[destName] = content
                totalDomainsValidated += domainCount
            }

            if (totalDomainsValidated == 0) {
                Log.e(TAG, "Validated 0 domains across all category files, rejecting release")
                return ListenableWorker.Result.retry()
            }

            // 4. Atomically install release through the native AuraCategoryStore
            val effectiveCount = if (domainCount > 0) domainCount else totalDomainsValidated
            val installResult = categoryStore.installRelease(
                version = version,
                files = downloadedFiles,
                domainCount = effectiveCount,
                etag = version,
                checksum = manifestChecksum
            )

            if (installResult["success"] == true) {
                Log.i(TAG, "Successfully installed blocklist release $version with $effectiveCount domains")
                // Notify running tunnel to reload categories atomically without restarting VPN
                AuraTunnelManager.shared.notifyCategoriesUpdated(applicationContext)
                return ListenableWorker.Result.success()
            } else {
                Log.e(TAG, "Failed to install release $version in AuraCategoryStore")
                return ListenableWorker.Result.retry()
            }

        } catch (e: Exception) {
            Log.w(TAG, "Background blocklist sync failed: ${e.message}")
            return ListenableWorker.Result.retry()
        } finally {
            AuraCategoryStore.isSyncInProgress.set(false)
        }
    }

    private fun resolveUrl(baseUrl: String, pathOrUrl: String): String {
        return if (pathOrUrl.startsWith("http://") || pathOrUrl.startsWith("https://")) {
            pathOrUrl
        } else {
            val base = baseUrl.trimEnd('/')
            val path = if (pathOrUrl.startsWith('/')) pathOrUrl else "/$pathOrUrl"
            "$base$path"
        }
    }

    private fun computeSha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hashBytes = digest.digest(input.toByteArray(Charsets.UTF_8))
        return hashBytes.joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "BlocklistSyncWorker"
    }
}
