package com.thejatech.aura.theja_aura

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.annotation.NonNull
import com.thejatech.aura.database.AuraActivityRepository
import com.thejatech.aura.engine.AuraDomainValidationError
import com.thejatech.aura.model.AuraRuleItem
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.storage.AuraCategoryStore
import com.thejatech.aura.storage.AuraRuleException
import com.thejatech.aura.storage.AuraRuleStore
import com.thejatech.aura.tunnel.AuraTunnelManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val VPN_REQUEST_CODE = 0xA01
        private const val CHANNEL_CONTROL = "com.thejatech.aura/tunnel_control"
        private const val CHANNEL_STATUS = "com.thejatech.aura/tunnel_status"
        private const val CHANNEL_ACTIVITY = "com.thejatech.aura/activity"
    }

    private var pendingVpnResult: MethodChannel.Result? = null
    private val backgroundExecutor = Executors.newCachedThreadPool()

    private lateinit var ruleStore: AuraRuleStore
    private lateinit var categoryStore: AuraCategoryStore
    private lateinit var activityRepository: AuraActivityRepository

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ruleStore = AuraRuleStore(applicationContext)
        categoryStore = AuraCategoryStore(applicationContext)
        activityRepository = AuraActivityRepository(applicationContext)

        // 1. Tunnel Control Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CONTROL).setMethodCallHandler { call, result ->
            handleControlCall(call, result)
        }

        // 2. Tunnel Status Event Channel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_STATUS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    AuraTunnelManager.shared.onStatusChanged = { status ->
                        events.success(status.rawValue)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    AuraTunnelManager.shared.onStatusChanged = null
                }
            }
        )

        // 3. Activity Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_ACTIVITY).setMethodCallHandler { call, result ->
            handleActivityCall(call, result)
        }

        // 4. Schedule periodic WorkManager background synchronization
        try {
            com.thejatech.aura.sync.AuraSyncManager.schedulePeriodicSync(applicationContext)
        } catch (_: Exception) {}
    }

    private fun handleControlCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> {
                result.success(AuraTunnelManager.shared.getStatus().rawValue)
            }

            "startTunnel" -> {
                val prepareIntent = VpnService.prepare(this)
                if (prepareIntent != null) {
                    pendingVpnResult = result
                    startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                } else {
                    try {
                        AuraTunnelManager.shared.startTunnel(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("START_FAILED", e.message ?: "Failed to start VPN", null)
                    }
                }
            }

            "stopTunnel" -> {
                try {
                    AuraTunnelManager.shared.stopTunnel(this)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("STOP_FAILED", e.message ?: "Failed to stop VPN", null)
                }
            }

            "getRules" -> {
                backgroundExecutor.execute {
                    val rules = ruleStore.loadRules()
                    val ruleDicts = rules.map { it.toDictionary() }
                    runOnUiThread { result.success(ruleDicts) }
                }
            }

            "syncRules" -> {
                val rawList = call.arguments as? List<*>
                if (rawList == null) {
                    result.error("INVALID_ARGS", "Expected list of rule maps", null)
                    return
                }

                backgroundExecutor.execute {
                    val rules = mutableListOf<AuraRuleItem>()
                    for (item in rawList) {
                        if (item is Map<*, *>) {
                            AuraRuleItem.fromDictionary(item)?.let { rules.add(it) }
                        }
                    }
                    val saved = ruleStore.syncRules(rules)
                    AuraTunnelManager.shared.notifyRulesUpdated(this)
                    runOnUiThread { result.success(saved) }
                }
            }

            "reloadRules" -> {
                AuraTunnelManager.shared.notifyRulesUpdated(this)
                result.success(true)
            }

            "validateDomain" -> {
                val rawDomain = call.argument<String>("domain")
                if (rawDomain == null) {
                    result.error("INVALID_ARGS", "Expected domain string", null)
                    return
                }
                try {
                    val valid = ruleStore.validateDomain(rawDomain)
                    result.success(valid)
                } catch (e: AuraDomainValidationError) {
                    result.error(e.code, e.message, null)
                } catch (e: Exception) {
                    result.error("VALIDATION_FAILED", e.message ?: "Validation failed", null)
                }
            }

            "addRule" -> {
                val domain = call.argument<String>("domain")
                val isBlocked = call.argument<Boolean>("isBlocked")
                val isEnabled = call.argument<Boolean>("isEnabled") ?: true

                if (domain == null || isBlocked == null) {
                    result.error("INVALID_ARGS", "Expected domain and isBlocked", null)
                    return
                }

                backgroundExecutor.execute {
                    try {
                        val newRule = ruleStore.addRule(domain, isBlocked, isEnabled)
                        AuraTunnelManager.shared.notifyRulesUpdated(this)
                        runOnUiThread { result.success(newRule.toDictionary()) }
                    } catch (e: AuraDomainValidationError) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: AuraRuleException) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ADD_RULE_FAILED", e.message, null) }
                    }
                }
            }

            "updateRule" -> {
                val id = call.argument<String>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "Expected rule id", null)
                    return
                }
                val domain = call.argument<String>("domain")
                val isBlocked = call.argument<Boolean>("isBlocked")
                val isEnabled = call.argument<Boolean>("isEnabled")

                backgroundExecutor.execute {
                    try {
                        val updated = ruleStore.updateRule(id, domain, isBlocked, isEnabled)
                        AuraTunnelManager.shared.notifyRulesUpdated(this)
                        runOnUiThread { result.success(updated.toDictionary()) }
                    } catch (e: AuraDomainValidationError) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: AuraRuleException) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("UPDATE_RULE_FAILED", e.message, null) }
                    }
                }
            }

            "deleteRule" -> {
                val id = call.argument<String>("id")
                if (id == null) {
                    result.error("INVALID_ARGS", "Expected rule id", null)
                    return
                }

                backgroundExecutor.execute {
                    try {
                        val deleted = ruleStore.deleteRule(id)
                        AuraTunnelManager.shared.notifyRulesUpdated(this)
                        runOnUiThread { result.success(deleted.toDictionary()) }
                    } catch (e: AuraRuleException) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("DELETE_RULE_FAILED", e.message, null) }
                    }
                }
            }

            "toggleRule" -> {
                val id = call.argument<String>("id")
                val isEnabled = call.argument<Boolean>("isEnabled")
                if (id == null || isEnabled == null) {
                    result.error("INVALID_ARGS", "Expected id and isEnabled", null)
                    return
                }

                backgroundExecutor.execute {
                    try {
                        val updated = ruleStore.toggleRule(id, isEnabled)
                        AuraTunnelManager.shared.notifyRulesUpdated(this)
                        runOnUiThread { result.success(updated.toDictionary()) }
                    } catch (e: AuraRuleException) {
                        runOnUiThread { result.error(e.code, e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("TOGGLE_RULE_FAILED", e.message, null) }
                    }
                }
            }

            "getCategories" -> {
                backgroundExecutor.execute {
                    val prefs = categoryStore.loadPreferences()
                    runOnUiThread { result.success(prefs) }
                }
            }

            "setCategoryPreference" -> {
                val category = call.argument<String>("category")
                val isEnabled = call.argument<Boolean>("isEnabled")
                if (category == null || isEnabled == null) {
                    result.error("INVALID_ARGS", "Expected category and isEnabled", null)
                    return
                }

                backgroundExecutor.execute {
                    val updated = categoryStore.setCategoryPreference(category, isEnabled)
                    AuraTunnelManager.shared.notifyCategoriesUpdated(this)
                    runOnUiThread { result.success(updated) }
                }
            }

            "setAllCategoryPreferences" -> {
                val rawPrefs = call.argument<Map<String, Any>>("preferences")
                if (rawPrefs == null) {
                    result.error("INVALID_ARGS", "Expected preferences map", null)
                    return
                }

                backgroundExecutor.execute {
                    val typed = mutableMapOf<String, Boolean>()
                    for ((k, v) in rawPrefs) {
                        if (v is Boolean) typed[k] = v
                    }
                    categoryStore.savePreferences(typed)
                    AuraTunnelManager.shared.notifyCategoriesUpdated(this)
                    runOnUiThread { result.success(typed) }
                }
            }

            "getDefaultDomainOverrides" -> {
                backgroundExecutor.execute {
                    val disabled = categoryStore.loadDisabledDefaultDomains().toList().sorted()
                    runOnUiThread { result.success(disabled) }
                }
            }

            "toggleDefaultDomain" -> {
                val domain = call.argument<String>("domain")
                val isEnabled = call.argument<Boolean>("isEnabled")
                if (domain == null || isEnabled == null) {
                    result.error("INVALID_ARGS", "Expected domain and isEnabled", null)
                    return
                }

                backgroundExecutor.execute {
                    val updated = categoryStore.toggleDefaultDomain(domain, isEnabled).toList().sorted()
                    AuraTunnelManager.shared.notifyDefaultOverridesUpdated(this)
                    runOnUiThread { result.success(updated) }
                }
            }

            "getInstalledRelease" -> {
                backgroundExecutor.execute {
                    val release = categoryStore.loadInstalledRelease()
                    runOnUiThread { result.success(release) }
                }
            }

            "setApiBaseUrl" -> {
                val url = call.argument<String>("url")
                if (!url.isNullOrEmpty()) {
                    AuraCategoryStore.setApiBaseUrl(applicationContext, url)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "installBlocklistRelease" -> {
                val version = call.argument<String>("version")
                val files = call.argument<Map<String, String>>("files")
                val domainCount = call.argument<Int>("domainCount") ?: 0
                val etag = call.argument<String>("etag")
                val checksum = call.argument<String>("checksum")
                val customApiUrl = call.argument<String>("apiBaseUrl")

                if (version == null || files == null) {
                    result.error("INVALID_ARGS", "Expected version and files", null)
                    return
                }

                if (!customApiUrl.isNullOrEmpty()) {
                    AuraCategoryStore.setApiBaseUrl(applicationContext, customApiUrl)
                }

                backgroundExecutor.execute {
                    // Prevent concurrent race with background WorkManager sync
                    if (!AuraCategoryStore.isSyncInProgress.compareAndSet(false, true)) {
                        runOnUiThread {
                            result.error("SYNC_IN_PROGRESS", "Sync operation already in progress", null)
                        }
                        return@execute
                    }

                    try {
                        val installRes = categoryStore.installRelease(
                            version = version,
                            files = files,
                            domainCount = domainCount,
                            etag = etag,
                            checksum = checksum
                        ).toMutableMap()

                        AuraTunnelManager.shared.notifyCategoriesUpdated(this)
                        installRes["reloaded"] = true
                        runOnUiThread { result.success(installRes) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("INSTALL_RELEASE_FAILED", e.message, null) }
                    } finally {
                        AuraCategoryStore.isSyncInProgress.set(false)
                    }
                }
            }

            "clearInstalledRelease" -> {
                backgroundExecutor.execute {
                    try {
                        categoryStore.clearInstalledRelease()
                        AuraTunnelManager.shared.notifyCategoriesUpdated(this)
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("CLEAR_RELEASE_FAILED", e.message, null) }
                    }
                }
            }

            "getReleaseCategories" -> {
                backgroundExecutor.execute {
                    val categories = categoryStore.loadReleaseCategories()
                    runOnUiThread { result.success(categories) }
                }
            }

            "getCategoryDomains" -> {
                val category = call.argument<String>("category")
                if (category == null) {
                    result.error("INVALID_ARGS", "Expected category", null)
                    return
                }

                backgroundExecutor.execute {
                    val domains = categoryStore.loadCategoryDomains(category)
                    runOnUiThread { result.success(domains) }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun handleActivityCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeDatabase" -> {
                backgroundExecutor.execute {
                    try {
                        activityRepository.initialize()
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "ready" to true,
                                    "databaseFileName" to "dns_activity.sqlite"
                                )
                            )
                        }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("INIT_FAILED", e.message, null) }
                    }
                }
            }

            "getActivity" -> {
                val limit = call.argument<Int>("limit") ?: 25
                val cursorTimestamp = call.argument<Number>("cursorTimestamp")?.toLong()
                val cursorId = call.argument<Number>("cursorId")?.toLong()
                val outcome = call.argument<String>("outcome")
                val searchDomain = call.argument<String>("searchDomain")
                val startTime = call.argument<Number>("startTime")?.toLong()
                val endTime = call.argument<Number>("endTime")?.toLong()

                backgroundExecutor.execute {
                    try {
                        val paginated = activityRepository.queryActivity(
                            limit = limit,
                            cursorTimestamp = cursorTimestamp,
                            cursorId = cursorId,
                            outcome = outcome,
                            searchDomain = searchDomain,
                            startTime = startTime,
                            endTime = endTime
                        )
                        runOnUiThread { result.success(paginated.toDictionary()) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("QUERY_FAILED", e.message, null) }
                    }
                }
            }

            "getDashboardStats" -> {
                val timeWindowMillis = call.argument<Number>("timeWindowMillis")?.toLong() ?: 86_400_000L

                backgroundExecutor.execute {
                    try {
                        val stats = activityRepository.getDashboardStats(timeWindowMillis = timeWindowMillis)
                        runOnUiThread { result.success(stats.toDictionary()) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("STATS_FAILED", e.message, null) }
                    }
                }
            }

            "getTopBlockedDomains" -> {
                val limit = call.argument<Int>("limit") ?: 5
                val timeWindowMillis = call.argument<Number>("timeWindowMillis")?.toLong()

                backgroundExecutor.execute {
                    try {
                        val topList = activityRepository.getTopBlockedDomains(
                            limit = limit,
                            timeWindowMillis = timeWindowMillis
                        )
                        runOnUiThread { result.success(topList.map { it.toDictionary() }) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("TOP_BLOCKED_FAILED", e.message, null) }
                    }
                }
            }

            "checkpoint" -> {
                backgroundExecutor.execute {
                    val success = activityRepository.checkpointPassive()
                    runOnUiThread { result.success(success) }
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val pending = pendingVpnResult
            pendingVpnResult = null

            if (resultCode == Activity.RESULT_OK) {
                try {
                    AuraTunnelManager.shared.startTunnel(this)
                    pending?.success(null)
                } catch (e: Exception) {
                    pending?.error("START_FAILED", e.message ?: "Failed to start VPN service", null)
                }
            } else {
                AuraTunnelManager.shared.updateStatus(AuraTunnelStatus.DISCONNECTED)
                pending?.error("START_FAILED", "VPN permission denied by user", null)
            }
        }
    }
}
