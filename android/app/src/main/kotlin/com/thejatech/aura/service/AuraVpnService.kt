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
import com.thejatech.aura.model.ActivityRecord
import com.thejatech.aura.model.AuraTunnelStatus
import com.thejatech.aura.packet.IpPacketParser
import com.thejatech.aura.packet.ParsedDnsPacket
import com.thejatech.aura.storage.AuraCategoryStore
import com.thejatech.aura.storage.AuraPreferences
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
import java.util.concurrent.atomic.AtomicBoolean

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

    private val dnsEngine = AuraDnsEngine()
    private lateinit var ruleStore: AuraRuleStore
    private lateinit var categoryStore: AuraCategoryStore
    private lateinit var pslValidator: AuraPslValidator
    private lateinit var activityDatabase: AuraActivityDatabase
    private lateinit var activityWriter: AuraActivityWriter

    override fun onCreate() {
        super.onCreate()
        ruleStore = AuraRuleStore(this)
        categoryStore = AuraCategoryStore(this)
        pslValidator = AuraPslValidator.getInstance(this)
        activityDatabase = AuraActivityDatabase.getInstance(this)
        activityWriter = AuraActivityWriter(activityDatabase)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            // Restarted by system via START_STICKY
            if (!AuraPreferences.isFirewallDesired(this)) {
                Log.i(TAG, "START_STICKY restart detected, but firewall desired state is OFF. Stopping.")
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        val action = intent?.action ?: ACTION_START

        if (action == ACTION_START) {
            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                Log.w(TAG, "Cannot start VPN without user consent")
                AuraPreferences.setFirewallDesired(this, false)
                AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        when (action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
            ACTION_RELOAD_RULES -> reloadRules()
            ACTION_RELOAD_CATEGORIES -> reloadCategories()
            ACTION_RELOAD_DEFAULT_OVERRIDES -> reloadDefaultOverrides()
        }

        return if (AuraPreferences.isFirewallDesired(this)) START_STICKY else START_NOT_STICKY
    }

    private fun startVpn() {
        if (isRunning.get()) return

        createNotificationChannel()
        val notification = buildNotification()

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

        // 1. Prune 30-day retention
        val thirtyDaysAgo = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
        activityDatabase.pruneRetention(thirtyDaysAgo)

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

        val pfd = builder.establish()
        if (pfd == null) {
            isServiceActive = false
            AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
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

        activityWriter.flushAndClose(500L)

        AuraTunnelManager.shared.updateStatus(this, AuraTunnelStatus.DISCONNECTED)
        stopForegroundCompat()
        stopSelf()
    }

    override fun onRevoke() {
        super.onRevoke()
        Log.w(TAG, "VPN permission revoked by system or another VPN")
        AuraPreferences.setFirewallDesired(this, false)
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

    // MARK: - Packet Processing Loop

    private fun processPackets(pfd: ParcelFileDescriptor) {
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
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
                    val packet = buffer.copyOf(length)
                    val parsed = IpPacketParser.parse(packet, length)
                    if (parsed != null) {
                        handleDnsQuery(parsed, outputStream)
                    } else {
                        // If it's a TCP probe (e.g. Android Private DNS probing port 853 or port 53),
                        // reply with TCP RST so the system doesn't stall waiting for DoT handshake
                        val rst = IpPacketParser.buildTcpResetPacket(packet, length)
                        if (rst != null) {
                            sendPacket(outputStream, rst)
                        }
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "Error handling packet in processPackets", t)
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                inputStream.close()
                outputStream.close()
            } catch (_: Exception) {}
        }
    }

    private fun handleDnsQuery(queryPacket: ParsedDnsPacket, outputStream: FileOutputStream) {
        val question = AuraDnsEngine.parseQuestion(queryPacket.dnsPayload, 12)
        val qTypeStr = when (question?.qType) {
            1 -> "A"
            28 -> "AAAA"
            5 -> "CNAME"
            15 -> "MX"
            16 -> "TXT"
            65 -> "HTTPS"
            else -> if (question != null) "TYPE${question.qType}" else "UNKNOWN"
        }

        if (question != null) {
            val decision = dnsEngine.evaluate(question.name, pslValidator)

            if (decision.isBlocked) {
                val blockedDns = AuraDnsEngine.createBlockedResponse(queryPacket.dnsPayload)
                if (blockedDns != null) {
                    val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, blockedDns)
                    sendPacket(outputStream, responsePacket)

                    val record = ActivityRecord(
                        domain = question.name,
                        queryType = qTypeStr,
                        outcome = "blocked",
                        matchedSource = decision.matchedSource,
                        matchedRuleId = decision.matchedRule,
                        matchedCategories = decision.matchedCategories,
                        reason = decision.reason
                    )
                    activityWriter.enqueue(record)
                    return
                }
            }

            // Allowed: forward upstream
            forwardExecutor?.execute {
                resolveAndForward(queryPacket, outputStream, question.name, qTypeStr, decision)
            }
        } else {
            // Unparseable DNS payload: forward upstream without evaluation
            forwardExecutor?.execute {
                resolveAndForward(queryPacket, outputStream, null, "UNKNOWN", null)
            }
        }
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

    private fun resolveAndForward(
        queryPacket: ParsedDnsPacket,
        outputStream: FileOutputStream,
        domain: String?,
        queryType: String,
        decision: AuraDnsEngine.MatchDecision?
    ) {
        try {
            val startTime = System.currentTimeMillis()
            var responseDns: ByteArray? = null
            val maxTotalBudget = 2000L // 2.0s

            val resolvers = getActiveUpstreamResolvers()
            for (resolver in resolvers) {
                val elapsed = System.currentTimeMillis() - startTime
                if (elapsed >= maxTotalBudget) break

                val remainingTimeout = (maxTotalBudget - elapsed).coerceIn(400L, 800L).toInt()
                responseDns = queryUpstream(resolver, queryPacket.dnsPayload, remainingTimeout)
                if (responseDns != null) break
            }

            if (responseDns != null) {
                val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, responseDns)
                sendPacket(outputStream, responsePacket)

                if (domain != null) {
                    val record = ActivityRecord(
                        domain = domain,
                        queryType = queryType,
                        outcome = "allowed",
                        matchedSource = decision?.matchedSource ?: "none",
                        matchedRuleId = decision?.matchedRule,
                        matchedCategories = decision?.matchedCategories ?: emptyList(),
                        reason = null
                    )
                    activityWriter.enqueue(record)
                }
            } else {
                // All upstream resolvers failed or timed out: return valid RFC SERVFAIL response
                val servFail = AuraDnsEngine.synthesizeServFailResponse(queryPacket.dnsPayload)
                if (servFail != null) {
                    try {
                        val responsePacket = IpPacketParser.buildResponsePacket(queryPacket, servFail)
                        sendPacket(outputStream, responsePacket)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send SERVFAIL packet", e)
                    }
                }

                if (domain != null) {
                    val record = ActivityRecord(
                        domain = domain,
                        queryType = queryType,
                        outcome = "failed",
                        matchedSource = decision?.matchedSource ?: "none",
                        matchedRuleId = decision?.matchedRule,
                        matchedCategories = decision?.matchedCategories ?: emptyList(),
                        reason = "Upstream resolution failed or timed out"
                    )
                    activityWriter.enqueue(record)
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Unhandled error during resolveAndForward", t)
        }
    }

    private fun queryUpstream(
        resolver: InetSocketAddress,
        requestDns: ByteArray,
        timeoutMs: Int
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

            recvBuf.copyOf(received)
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

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Theja's Aura Firewall")
            .setContentText("Active — Filtering DNS queries")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
