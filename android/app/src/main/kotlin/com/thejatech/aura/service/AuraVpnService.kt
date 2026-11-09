package com.thejatech.aura.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.thejatech.aura.database.AuraActivityDatabase
import com.thejatech.aura.database.AuraActivityWriter
import com.thejatech.aura.engine.AuraDnsEngine
import com.thejatech.aura.engine.AuraPslValidator
import com.thejatech.aura.engine.TcpConnectionManager
import com.thejatech.aura.model.ActivityRecord
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.packet.IpPacketParser
import com.thejatech.aura.packet.ParsedDnsPacket
import com.thejatech.aura.packet.TcpPacketParser
import com.thejatech.aura.storage.AuraCategoryStore
import com.thejatech.aura.storage.AuraPreferences
import com.thejatech.aura.storage.VpnPolicySnapshot
import com.thejatech.aura.storage.AuraRuleStore
import com.thejatech.aura.theja_aura.MainActivity
import com.thejatech.aura.tunnel.AuraTunnelManager
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class AuraVpnService : VpnService() {

    companion object {
        private const val TAG = "AuraVpnService"

        @Volatile
        var isServiceActive: Boolean = false
            private set

        const val ACTION_START = "com.thejatech.aura.ACTION_START"
        const val ACTION_STOP = "com.thejatech.aura.ACTION_STOP"
        const val ACTION_RELOAD_RULES = "com.thejatech.aura.ACTION_RELOAD_RULES"
        const val ACTION_RELOAD_CATEGORIES = "com.thejatech.aura.ACTION_RELOAD_CATEGORIES"
        const val ACTION_RELOAD_DEFAULT_OVERRIDES = "com.thejatech.aura.ACTION_RELOAD_DEFAULT_OVERRIDES"
        const val ACTION_RELOAD_POLICY = "com.thejatech.aura.ACTION_RELOAD_POLICY"

        fun reloadPolicy(context: Context) {
            val intent = Intent(context, AuraVpnService::class.java).apply {
                action = ACTION_RELOAD_POLICY
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {}
        }

        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "aura_firewall_channel"

        private val FALLBACK_RESOLVERS = listOf(
            InetSocketAddress("9.9.9.9", 53),           // Primary Quad9
            InetSocketAddress("1.1.1.1", 53),           // Fallback Cloudflare
            InetSocketAddress("8.8.8.8", 53),           // Fallback Google
            InetSocketAddress("2620:fe::fe", 53),       // Quad9 IPv6
            InetSocketAddress("2606:4700:4700::1111", 53) // Cloudflare IPv6
        )
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private val isRunning = AtomicBoolean(false)
    private var workerThread: Thread? = null
    private var forwardExecutor: ExecutorService? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val tcpConnectionManager = TcpConnectionManager()

    // Timer executor + scheduled future holder for atomic lifecycle management
    private val timerHolder = AtomicReference<TimerHolder?>(null)

    private data class TimerHolder(
        val executor: ScheduledExecutorService,
        val future: ScheduledFuture<*>
    )
    @Volatile
    private var tunOutputStream: FileOutputStream? = null
    private var packetProcessor: AuraDnsPacketProcessor? = null

    private val dnsEngine = AuraDnsEngine()
    private lateinit var ruleStore: AuraRuleStore
    private lateinit var categoryStore: AuraCategoryStore
    private lateinit var pslValidator: AuraPslValidator
    private lateinit var activityDatabase: AuraActivityDatabase
    private lateinit var activityWriter: AuraActivityWriter

    @Volatile
    private var currentPolicy: VpnPolicySnapshot = VpnPolicySnapshot(AuraPreferences.POLICY_ENABLED, 0L)

    override fun onCreate() {
        super.onCreate()
        currentPolicy = AuraPreferences.getPolicySnapshot(this)
        ruleStore = AuraRuleStore(this)
        categoryStore = AuraCategoryStore(this)
        pslValidator = AuraPslValidator.getInstance(this)
        activityDatabase = AuraActivityDatabase.getInstance(this)
        activityWriter = AuraActivityWriter(activityDatabase)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                AuraPreferences.setSystemAlwaysOn(this, isAlwaysOn)
                AuraPreferences.setSystemLockdown(this, isLockdownEnabled)
            } catch (_: Throwable) {}
        }

        if (intent == null) {
            // Restarted by system via START_STICKY
            if (!AuraPreferences.isAutoRecoveryPermitted(this) || !AuraPreferences.isAutoRestartEnabled(this)) {
                Log.i(TAG, "START_STICKY restart detected, but policy does not permit recovery (mode=${AuraPreferences.getPolicyMode(this)}). Stopping.")
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val rawAction = intent?.action
        val action = when (rawAction) {
            null -> ACTION_START
            VpnService.SERVICE_INTERFACE -> {
                // System started service via Always-on VPN
                Log.i(TAG, "VPN service started by system via Always-on VPN")
                var lockdown = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try { lockdown = isLockdownEnabled } catch (_: Throwable) {}
                }

                if (!AuraPreferences.isAutoRecoveryPermitted(this)) {
                    if (lockdown) {
                        Log.w(TAG, "Always-on VPN Lockdown is active in system settings; starting VPN to prevent full device network loss.")
                        ACTION_START
                    } else {
                        Log.i(TAG, "Always-on VPN started service, but user policy is ${AuraPreferences.getPolicyMode(this)}. Stopping.")
                        stopForegroundCompat()
                        stopSelf()
                        return START_NOT_STICKY
                    }
                } else {
                    AuraPreferences.setPolicyEnabled(this)
                    ACTION_START
                }
            }
            else -> rawAction
        }

        if (action == ACTION_START) {
            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                Log.w(TAG, "Cannot start VPN without user consent")
                AuraPreferences.setPolicyManuallyDisabled(this)
                AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            if (AuraPreferences.getPolicyMode(this) != AuraPreferences.POLICY_PAUSED) {
                AuraPreferences.setPolicyEnabled(this)
            }
        }

        when (action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
            ACTION_RELOAD_RULES -> reloadRules()
            ACTION_RELOAD_CATEGORIES -> reloadCategories()
            ACTION_RELOAD_DEFAULT_OVERRIDES -> reloadDefaultOverrides()
            ACTION_RELOAD_POLICY -> reloadPolicy()
        }

        return if (AuraPreferences.isFirewallDesired(this)) START_STICKY else START_NOT_STICKY
    }

    private fun startVpn() {
        if (isRunning.get()) return

        currentPolicy = AuraPreferences.getPolicySnapshot(this)
        createNotificationChannel()
        val notification = buildNotification(currentPolicy.isPaused())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // 1. Prune retention according to configured user preference (7 or 30 days, default 30)
        try {
            val retentionDays = AuraPreferences.getRetentionDays(this)
            val retentionCutoff = System.currentTimeMillis() - (retentionDays.toLong() * 24 * 60 * 60 * 1000)
            val pruned = activityDatabase.pruneRetention(retentionCutoff)
            Log.i(TAG, "Startup retention prune completed: deleted $pruned records older than $retentionDays days")
        } catch (e: Exception) {
            Log.e(TAG, "Startup retention prune failed", e)
        }

        // 2. Start activity writer
        activityWriter.start()

        // 3. Load rules, categories, preferences
        reloadRules()
        reloadCategories()
        reloadDefaultOverrides()

        // 4. Ensure background blocklist sync is scheduled
        try {
            com.thejatech.aura.sync.AuraSyncManager.schedulePeriodicSync(applicationContext)
        } catch (_: Exception) {}

        // 5. Build TUN interface
        val builder = Builder()
            .setSession("Theja Aura")
            .setMtu(1500)
            .addAddress("10.255.255.2", 30)
            .addDnsServer("10.255.255.1")
            .addRoute("10.255.255.1", 32)

        try {
            builder.addAddress("fd00::2", 126)
            builder.addDnsServer("fd00::1")
            builder.addRoute("fd00::1", 128)
        } catch (_: Exception) {}

        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to addDisallowedApplication: $packageName", e)
        }

        builder.setBlocking(true)

        val pfd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to establish VPN interface", e)
            null
        }
        if (pfd == null) {
            isServiceActive = false
            AuraPreferences.setFirewallDesired(this, false)
            AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
            stopForegroundCompat()
            stopSelf()
            return
        }

        vpnInterface = pfd
        isRunning.set(true)
        isServiceActive = true
        AuraPreferences.setFirewallDesired(this, true)
        AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.CONNECTED)

        // Set initial underlying network and register dynamic change callback
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val activeNet = cm?.activeNetwork
        if (activeNet != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            try {
                setUnderlyingNetworks(arrayOf(activeNet))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to set initial underlying networks", e)
            }
        }
        registerNetworkCallback()

        forwardExecutor = Executors.newFixedThreadPool(4) { r ->
            Thread(r, "aura-dns-forwarder").apply { isDaemon = true }
        }

        val processor = AuraDnsPacketProcessor(
            dnsEngine = dnsEngine,
            tcpConnectionManager = tcpConnectionManager,
            pslValidator = pslValidator,
            policyProvider = { currentPolicy },
            onPolicyReconciled = { renewedPolicy ->
                synchronized(this@AuraVpnService) {
                    AuraPreferences.setPolicyEnabled(this@AuraVpnService)
                    currentPolicy = renewedPolicy
                    updateForegroundNotification(false)
                    AuraTunnelManager.shared.updateStatus(this@AuraVpnService, AuraTunnelStatus.CONNECTED)
                }
            },
            upstreamResolver = { requestDns -> resolveUpstream(requestDns) },
            packetWriter = { pkt -> tunOutputStream?.let { sendPacket(it, pkt) } },
            activityLogger = { record -> activityWriter.enqueue(record) },
            executor = forwardExecutor
        )
        packetProcessor = processor

        val timer = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "aura-tcp-timer").apply { isDaemon = true }
        }
        val future = timer.scheduleWithFixedDelay({
            try {
                processor?.checkTimers()
            } catch (t: Throwable) {
                Log.e(TAG, "Error in tcpTimerExecutor", t)
            }
        }, 200, 200, TimeUnit.MILLISECONDS)
        timerHolder.set(TimerHolder(timer, future))

        workerThread = Thread({ processPackets(pfd) }, "aura-vpn-worker").apply {
            start()
        }
    }

    private fun registerNetworkCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        try {
                            setUnderlyingNetworks(arrayOf(network))
                            Log.d(TAG, "Underlying network updated: $network")
                        } catch (_: Exception) {}
                    }
                    override fun onLost(network: Network) {
                        try {
                            val active = cm.activeNetwork
                            if (active != null) {
                                setUnderlyingNetworks(arrayOf(active))
                            } else {
                                setUnderlyingNetworks(null)
                            }
                        } catch (_: Exception) {}
                    }
                }
                cm.registerDefaultNetworkCallback(callback)
                networkCallback = callback
            } catch (e: Exception) {
                Log.w(TAG, "Failed to register network callback", e)
            }
        }
    }

    private fun unregisterNetworkCallback() {
        try {
            networkCallback?.let {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                cm?.unregisterNetworkCallback(it)
            }
        } catch (_: Exception) {}
        networkCallback = null
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun stopVpn() {
        unregisterNetworkCallback()
        isServiceActive = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                AuraPreferences.setSystemAlwaysOn(this, isAlwaysOn)
                AuraPreferences.setSystemLockdown(this, isLockdownEnabled)
                if (isLockdownEnabled) {
                    Log.w(TAG, "VPN Lockdown is enabled in Android Settings. Stopping VPN will disrupt network connectivity.")
                }
            } catch (_: Exception) {}
        }

        if (!isRunning.getAndSet(false)) {
            AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
            stopForegroundCompat()
            stopSelf()
            return
        }

        AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTING)

        try {
            vpnInterface?.close()
        } catch (_: Exception) {}
        vpnInterface = null

        workerThread?.interrupt()
        workerThread = null

        forwardExecutor?.shutdownNow()
        forwardExecutor = null

        // Atomically shut down timer executor and cancel its scheduled task
        timerHolder.getAndSet(null)?.let { holder ->
            holder.future.cancel(true)
            holder.executor.shutdownNow()
        }
        tcpConnectionManager.reset()
        packetProcessor = null

        activityWriter.flushAndClose(500L)

        AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
        stopForegroundCompat()
        stopSelf()
    }

    override fun onRevoke() {
        super.onRevoke()
        Log.w(TAG, "VPN permission revoked by system or another VPN")
        AuraPreferences.setPolicyManuallyDisabled(this)
        stopVpn()
    }

    override fun onDestroy() {
        isServiceActive = false
        stopVpn()
        super.onDestroy()
    }

    private fun reloadRules() {
        val rules = ruleStore.loadRules()
        dnsEngine.setRules(rules)
    }

    private fun reloadCategories() {
        val bundled = categoryStore.loadAllBundledCategories()
        dnsEngine.setCategories(bundled)

        val prefs = categoryStore.loadPreferences()
        dnsEngine.setCategoryPreferences(prefs)
    }

    private fun reloadDefaultOverrides() {
        val overrides = categoryStore.loadDisabledDefaultDomains()
        dnsEngine.setDisabledDefaultDomains(overrides)
    }

    private fun reloadPolicy() {
        val snapshot = AuraPreferences.getPolicySnapshot(this)
        currentPolicy = snapshot
        Log.i(TAG, "Reloaded policy snapshot: mode=${snapshot.mode}, expiry=${snapshot.pauseExpiryUtcMillis}")
        updateForegroundNotification(snapshot.isPaused())
    }

    private fun updateForegroundNotification(isPaused: Boolean) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.notify(NOTIFICATION_ID, buildNotification(isPaused))
        } catch (_: Exception) {}
    }

    // MARK: - Packet Processing Loop

    private fun processPackets(pfd: ParcelFileDescriptor) {
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
        tunOutputStream = outputStream
        val buffer = ByteArray(4096)

        try {
            while (isRunning.get()) {
                val length = try {
                    inputStream.read(buffer)
                } catch (e: IOException) {
                    break // TUN closed
                }

                if (length <= 0) continue

                try {
                    packetProcessor?.processPacket(buffer, length)
                } catch (t: Throwable) {
                    Log.e(TAG, "Error handling packet in processPackets", t)
                }
            }
        } catch (_: Exception) {
        } finally {
            tunOutputStream = null
            try {
                inputStream.close()
                outputStream.close()
            } catch (_: Exception) {}
        }

        // Check if packet processing loop terminated unexpectedly while firewall was still desired
        if (isRunning.get() && AuraPreferences.isAutoRecoveryPermitted(this)) {
            Log.w(TAG, "Packet processing loop terminated unexpectedly while auto-recovery is permitted; attempting tunnel recovery")
            handleUnexpectedDisconnection()
        } else if (isRunning.get()) {
            Log.i(TAG, "Packet processing loop ended while recovery is not permitted (mode=${AuraPreferences.getPolicyMode(this)}). Stopping service.")
            stopVpn()
        }
    }

    private fun handleUnexpectedDisconnection() {
        if (!isRunning.get() || !AuraPreferences.isAutoRecoveryPermitted(this) || !AuraPreferences.isAutoRestartEnabled(this)) {
            Log.i(TAG, "Unexpected disconnection: policy does not permit recovery (mode=${AuraPreferences.getPolicyMode(this)}, autoRestart=${AuraPreferences.isAutoRestartEnabled(this)}). Stopping service.")
            stopVpn()
            return
        }

        try {
            vpnInterface?.close()
        } catch (_: Exception) {}
        vpnInterface = null

        // Check VPN preparation/consent
        if (VpnService.prepare(this) != null) {
            Log.w(TAG, "Cannot recover VPN: user consent is no longer valid")
            AuraPreferences.setPolicyManuallyDisabled(this)
            stopVpn()
            return
        }

        // Ensure forward executor is alive
        if (forwardExecutor == null || forwardExecutor?.isShutdown == true) {
            forwardExecutor = Executors.newFixedThreadPool(4) { r ->
                Thread(r, "aura-dns-forwarder-recovered").apply { isDaemon = true }
            }
        }

        // Atomically replace timer executor: cancel old future, shutdown old executor, create new
        val newTimer = Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "aura-tcp-timer-recovered").apply { isDaemon = true }
        }
        val newFuture = newTimer.scheduleWithFixedDelay({
            try {
                packetProcessor?.checkTimers()
            } catch (t: Throwable) {
                Log.e(TAG, "Error in tcpTimerExecutor", t)
            }
        }, 200, 200, TimeUnit.MILLISECONDS)

        // Swap atomically: cancel old future, shutdown old executor
        timerHolder.getAndSet(TimerHolder(newTimer, newFuture))?.let { oldHolder ->
            oldHolder.future.cancel(true)
            oldHolder.executor.shutdownNow()
        }

        packetProcessor = AuraDnsPacketProcessor(
            dnsEngine = dnsEngine,
            tcpConnectionManager = tcpConnectionManager,
            pslValidator = pslValidator,
            policyProvider = { currentPolicy },
            onPolicyReconciled = { renewedPolicy ->
                synchronized(this@AuraVpnService) {
                    AuraPreferences.setPolicyEnabled(this@AuraVpnService)
                    currentPolicy = renewedPolicy
                    updateForegroundNotification(false)
                    AuraTunnelManager.shared.updateStatus(this@AuraVpnService, AuraTunnelStatus.CONNECTED)
                }
            },
            upstreamResolver = { requestDns -> resolveUpstream(requestDns) },
            packetWriter = { pkt -> tunOutputStream?.let { sendPacket(it, pkt) } },
            activityLogger = { record -> activityWriter.enqueue(record) },
            executor = forwardExecutor
        )

        // Re-establish interface
        val builder = Builder()
            .setSession("Theja Aura")
            .setMtu(1500)
            .addAddress("10.255.255.2", 30)
            .addDnsServer("10.255.255.1")
            .addRoute("10.255.255.1", 32)

        try {
            builder.addAddress("fd00::2", 126)
            builder.addDnsServer("fd00::1")
            builder.addRoute("fd00::1", 128)
        } catch (_: Exception) {}

        try {
            builder.addDisallowedApplication(packageName)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to addDisallowedApplication: $packageName", e)
        }
        builder.setBlocking(true)

        val newPfd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to re-establish VPN interface during recovery", e)
            null
        }

        if (newPfd == null) {
            Log.e(TAG, "Tunnel recovery failed: unable to establish TUN interface")
            stopVpn()
            return
        }

        vpnInterface = newPfd
        AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.CONNECTED)

        // Spawn new worker thread to resume processing
        workerThread = Thread({ processPackets(newPfd) }, "aura-vpn-worker-recovered").apply {
            start()
        }
    }

    private fun handleDnsQuery(queryPacket: ParsedDnsPacket, outputStream: FileOutputStream) {
        packetProcessor?.handleUdpDnsQuery(queryPacket)
    }

    private fun getActiveUpstreamResolvers(): List<InetSocketAddress> {
        val resolvers = mutableListOf<InetSocketAddress>()
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val activeNet = cm?.activeNetwork
            if (activeNet != null) {
                val lp = cm.getLinkProperties(activeNet)
                lp?.dnsServers?.forEach { inetAddr ->
                    val host = inetAddr.hostAddress
                    if (host != null && host != "10.255.255.1" && host != "fd00::1" && host != "10.255.255.2" && host != "fd00::2") {
                        resolvers.add(InetSocketAddress(inetAddr, 53))
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to retrieve active network DNS servers", e)
        }

        // Add fallback resolvers
        for (fallback in FALLBACK_RESOLVERS) {
            if (resolvers.none { it.address == fallback.address }) {
                resolvers.add(fallback)
            }
        }
        return resolvers
    }

    private fun resolveUpstream(requestDns: ByteArray): ByteArray? {
        val startTime = System.currentTimeMillis()
        val maxTotalBudget = 2000L // 2.0s

        val resolvers = getActiveUpstreamResolvers()
        for (resolver in resolvers) {
            val elapsed = System.currentTimeMillis() - startTime
            if (elapsed >= maxTotalBudget) break

            val remainingTimeout = (maxTotalBudget - elapsed).coerceIn(400L, 800L).toInt()
            val responseDns = queryUpstream(resolver, requestDns, remainingTimeout, startTime, maxTotalBudget)
            if (responseDns != null) return responseDns
        }
        return null
    }

    /**
     * Checks if a DNS response has the TC (Truncated) flag set.
     * TC flag is bit 1 (0x02) of the flags byte (byte index 2).
     */
    private fun isTruncatedResponse(response: ByteArray): Boolean {
        return response.size >= 3 && (response[2].toInt() and 0x02) != 0
    }

    /**
     * Queries an upstream DNS resolver over TCP with proper DNS-over-TCP framing.
     * Implements two-byte length prefix, partial read/write handling, and response validation.
     */
    private fun queryUpstreamTcp(
        resolver: InetSocketAddress,
        requestDns: ByteArray,
        timeoutMs: Int
    ): ByteArray? {
        var socket: java.net.Socket? = null
        return try {
            socket = java.net.Socket()
            val isProtected = protect(socket)
            if (!isProtected) {
                Log.w(TAG, "VpnService.protect(socket) failed for upstream TCP ${resolver.address}")
                return null
            }
            socket.soTimeout = timeoutMs
            socket.connect(resolver, timeoutMs)

            val outputStream = socket.getOutputStream()
            val inputStream = socket.getInputStream()

            // DNS-over-TCP framing: 2-byte length prefix (network byte order) + DNS message
            val lengthPrefix = ByteArray(2)
            lengthPrefix[0] = ((requestDns.size shr 8) and 0xFF).toByte()
            lengthPrefix[1] = (requestDns.size and 0xFF).toByte()

            // Write length prefix + DNS query (handle partial writes)
            outputStream.write(lengthPrefix)
            var written = 0
            while (written < requestDns.size) {
                val chunk = minOf(4096, requestDns.size - written)
                outputStream.write(requestDns, written, chunk)
                written += chunk
            }
            outputStream.flush()

            // Read response: first 2 bytes = length
            val lenBuf = ByteArray(2)
            var read = 0
            while (read < 2) {
                val r = inputStream.read(lenBuf, read, 2 - read)
                if (r <= 0) return null // Connection closed prematurely
                read += r
            }
            val responseLength = ((lenBuf[0].toInt() and 0xFF) shl 8) or (lenBuf[1].toInt() and 0xFF)

            // Sanity check: reasonable DNS message size (max 64KB per RFC, but limit to 16KB)
            if (responseLength < 12 || responseLength > 16384) {
                Log.w(TAG, "Invalid TCP DNS response length: $responseLength")
                return null
            }

            // Read exact response length (handle partial reads)
            val responseBuf = ByteArray(responseLength)
            read = 0
            while (read < responseLength) {
                val r = inputStream.read(responseBuf, read, responseLength - read)
                if (r <= 0) return null // Connection closed prematurely
                read += r
            }

            // Validate response
            if (responseBuf.size < 12) return null

            // 1. Transaction ID matching (first 2 bytes)
            if (responseBuf[0] != requestDns[0] || responseBuf[1] != requestDns[1]) {
                Log.d(TAG, "TCP response transaction ID mismatch for ${resolver.address}")
                return null
            }

            // 2. Response QR bit check (Flags byte 2, bit 7 must be 1)
            val flagsByte = responseBuf[2].toInt() and 0xFF
            if ((flagsByte and 0x80) == 0) {
                Log.d(TAG, "TCP response QR bit not set for ${resolver.address}")
                return null
            }

            responseBuf
        } catch (e: Exception) {
            Log.d(TAG, "queryUpstreamTcp failed for ${resolver.address}: ${e.message}")
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {}
        }
    }

    private fun queryUpstream(
        resolver: InetSocketAddress,
        requestDns: ByteArray,
        timeoutMs: Int,
        globalStartTime: Long,
        globalMaxBudgetMs: Long
    ): ByteArray? {
        var socket: DatagramSocket? = null
        return try {
            socket = DatagramSocket()
            val isProtected = protect(socket)
            if (!isProtected) {
                Log.w(TAG, "VpnService.protect(socket) failed for upstream ${resolver.address}")
                return null
            }
            socket.soTimeout = timeoutMs

            val sendPacket = DatagramPacket(
                requestDns,
                requestDns.size,
                resolver.address,
                resolver.port
            )
            socket.send(sendPacket)

            val recvBuf = ByteArray(4096)
            val recvPacket = DatagramPacket(recvBuf, recvBuf.size)
            socket.receive(recvPacket)

            val received = recvPacket.length
            if (received < 12) return null

            // 1. Transaction ID matching (first 2 bytes)
            if (recvBuf[0] != requestDns[0] || recvBuf[1] != requestDns[1]) {
                return null
            }

            // 2. Response QR bit check (Flags byte 2, bit 7 must be 1)
            val flagsByte = recvBuf[2].toInt() and 0xFF
            if ((flagsByte and 0x80) == 0) {
                return null
            }

            val udpResponse = recvBuf.copyOf(received)

            // 3. Check for TC (Truncated) flag - bit 1 of flags byte
            if (isTruncatedResponse(udpResponse)) {
                Log.i(TAG, "Upstream UDP response truncated (TC=1) for ${resolver.address}, retrying over TCP")
                // Pass the remaining time within the global budget, not the full per-resolver timeout.
                val elapsed = System.currentTimeMillis() - globalStartTime
                val remainingForTcp = (globalMaxBudgetMs - elapsed).coerceAtLeast(200).toInt()
                return queryUpstreamTcp(resolver, requestDns, remainingForTcp)
            }

            udpResponse
        } catch (e: Exception) {
            Log.d(TAG, "queryUpstream failed for ${resolver.address}: ${e.message}")
            null
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {}
        }
    }

    private fun sendPacket(outputStream: FileOutputStream, packet: ByteArray) {
        synchronized(outputStream) {
            try {
                outputStream.write(packet)
            } catch (_: Exception) {}
        }
    }

    // MARK: - Notifications

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Firewall Protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifies when Theja's Aura DNS firewall is active"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(isPaused: Boolean = currentPolicy.isPaused()): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val contentText = if (isPaused) {
            "Paused — DNS filtering temporarily bypassed"
        } else {
            "Active — Filtering DNS queries"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Theja's Aura Firewall")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
