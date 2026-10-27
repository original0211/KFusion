package com.kfusion.singbox

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.ProxyInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Debug
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.provider.Settings
import android.system.OsConstants
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import com.follow.clash.common.GlobalState
import com.follow.clash.common.ensureNotificationChannel
import com.follow.clash.common.startForeground
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import org.json.JSONObject
import android.net.VpnService as SystemVpnService
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

class SingBoxVpnService : SystemVpnService(), PlatformInterface, CommandServerHandler {
    private val connectivity by lazy { getSystemService<ConnectivityManager>() }
    private val notificationManager by lazy { getSystemService<NotificationManager>() }

    @Volatile
    private var commandServer: CommandServer? = null
    private val serverLock = Any()
    private val startGate = AtomicBoolean(false)
    private val startAttempts = SingBoxStartAttempts()
    private var tunDescriptor: ParcelFileDescriptor? = null
    private var myInterfaceName: String? = null
    private var networkMonitor: SingBoxNetworkMonitor? = null

    override fun onBind(intent: Intent): IBinder? =
        if (intent.action == SERVICE_INTERFACE) super.onBind(intent) else null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        startForeground(
            NotificationCompat.Builder(this, GlobalState.NOTIFICATION_CHANNEL)
                .setContentTitle("KFusion · sing-box")
                .setContentText(
                    if (commandServer != null) "sing-box VPN 运行中" else "sing-box VPN 正在启动",
                )
                .setSmallIcon(R.drawable.ic_stat_disc)
                .setOngoing(true)
                .build(),
        )
        surfaceLastDeath()
        when (intent?.action) {
            ACTION_CHECK_CONFIG -> {
                val requestId = intent.getLongExtra(EXTRA_REQUEST_ID, 0)
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                thread(name = "singbox-check") { runCheck(configPath, requestId) }
                return START_NOT_STICKY
            }
            ACTION_STOP -> {
                startAttempts.invalidate()
                clearAttempt()
                startGate.set(false)
                SingBoxLog.append(this, "stop received; in-flight start retired")
                clearSavedConfigPath(this)
                stopBox()
                SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "")
                stopSelf()
                return START_NOT_STICKY
            }
        }
        val configPath = intent?.getStringExtra(EXTRA_CONFIG_PATH)
            ?: preferences().getString(PREF_CONFIG_PATH, null)
        if (configPath == null) {
            failStart("sing-box 配置路径缺失")
            return START_NOT_STICKY
        }
        preferences().edit().putString(PREF_CONFIG_PATH, configPath).apply()
        SingBoxStatus.write(this, SingBoxStatus.State.STARTING, "")
        if (!startGate.compareAndSet(false, true)) {
            GlobalState.log("sing-box start ignored: another start is in flight")
            SingBoxLog.append(this, "start ignored: another start is in flight")
            return START_NOT_STICKY
        }
        val attempt = startAttempts.begin()
        thread(name = "singbox-start") {
            try {
                startBox(configPath, attempt)
            } finally {
                if (startAttempts.ownsGate(attempt)) {
                    startGate.set(false)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun surfaceLastDeath() {
        val prefs = preferences()
        val exit = SingBoxExitInfo.latest(this)
        if (exit != null && exit.timestamp > prefs.getLong(PREF_EXIT_SURFACED, 0L)) {
            prefs.edit().putLong(PREF_EXIT_SURFACED, exit.timestamp).apply()
            val attemptNote = if (SingBoxStagedStart.isAttemptDeath(
                    prefs.getBoolean(PREF_ATTEMPT_OPEN, false),
                    exit.timestamp,
                    prefs.getLong(PREF_ATTEMPT_SINCE, 0L),
                )
            ) {
                " · attempt #${prefs.getLong(PREF_ATTEMPT_SEQ, 0L)}"
            } else {
                ""
            }
            SingBoxLog.append(this, SingBoxExitInfo.summaryLine(exit) + attemptNote)
            if (exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                val probe = SingBoxExitInfo.probeCrashHeadline(this)
                if (probe.headline != null) {
                    SingBoxLog.append(this, "exit signal: ${probe.headline}")
                } else {
                    probe.miss?.let { miss ->
                        SingBoxLog.append(this, SingBoxExitInfo.headlineMissLine(miss))
                    }
                }
            }
            SingBoxExitInfo.traceExcerpt(this)?.let { trace ->
                SingBoxLog.append(this, "exit trace excerpt:")
                trace.lineSequence().take(12).forEach { line ->
                    SingBoxLog.append(this, "exit trace: " + line.take(300))
                }
            }
        }
        val crash =
            SingBoxCrashReport.unreadLines(
                File(filesDir, "singbox"),
                prefs.getLong(PREF_CRASH_SURFACED, 0L),
            )
        if (crash != null) {
            prefs.edit().putLong(PREF_CRASH_SURFACED, crash.first).apply()
            // A bare mtime bump from this process's own setup rotation has no lines.
            if (crash.second.isNotEmpty()) {
                val head = SingBoxCrashReport.headLines(File(filesDir, "singbox"))
                if (head.isNullOrEmpty()) {
                    SingBoxLog.append(this, "crash head: report unreadable")
                } else {
                    head.forEach { line ->
                        SingBoxLog.append(this, "crash head: " + line.take(300))
                    }
                }
                SingBoxLog.append(this, "go crash report tail:")
                crash.second.forEach { line -> SingBoxLog.append(this, line.take(300)) }
            }
        }
    }

    private fun runCheck(configPath: String?, requestId: Long) {
        try {
            val configFile = File(configPath ?: "")
            check(configFile.isFile) { "sing-box 配置文件不存在：$configPath" }
            val content = configFile.readText()
            setupLibbox()
            Libbox.checkConfig(content)
            SingBoxStatus.writeCheckResult(this, requestId, true, "")
        } catch (error: Throwable) {
            SingBoxLog.append(this, "check failed: ${error.message ?: error}")
            SingBoxStatus.writeCheckResult(
                this,
                requestId,
                false,
                error.message ?: error.toString(),
            )
        } finally {
            // A check that borrowed an idle service leaves nothing running.
            if (commandServer == null && !startGate.get()) stopSelf()
        }
    }

    override fun onRevoke() {
        GlobalState.log("sing-box VPN permission revoked")
        stopBox()
        SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "VPN 权限被系统撤销")
        stopSelf()
    }

    override fun onDestroy() {
        startAttempts.invalidate()
        stopNetworkMonitor()
        stopBox()
        if (SingBoxStatus.read(this)?.state == SingBoxStatus.State.RUNNING) {
            SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "")
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun preferences() =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    private fun startBox(configPath: String, attempt: Long) {
        try {
            SingBoxLog.append(this, "start: begin")
            val configFile = File(configPath)
            check(configFile.isFile) { "sing-box 配置文件不存在：$configPath" }
            val content = configFile.readText()
            val decision = startDecision()
            if (decision.kind == SingBoxStagedStart.Decision.REPORT) {
                val verdict = SingBoxStagedStart.verdict(
                    decision.exitReason,
                    decision.level,
                    decision.levelName,
                )
                SingBoxLog.append(this, verdict)
                failStart(verdict)
                return
            }
            isolateCacheIfDue()
            setupLibbox()
            ensureNetworkMonitor()
            SingBoxLog.append(this, "start: libbox ready")
            Libbox.checkConfig(content)
            SingBoxLog.append(this, "start: config checked")
            val server = synchronized(serverLock) {
                commandServer ?: CommandServer(this, this).also {
                    it.start()
                    commandServer = it
                }
            }
            SingBoxLog.append(this, "start: command server ready")
            if (decision.kind == SingBoxStagedStart.Decision.STAGED) {
                runStagedStart(server, content, attempt)
            } else {
                startFull(server, content, attempt)
            }
        } catch (error: Throwable) {
            GlobalState.log("sing-box start failed: $error")
            if (startAttempts.isLive(attempt)) {
                failStart(error.message ?: error.toString())
            } else {
                SingBoxLog.append(this, "start: failed after retire: ${error.message ?: error}")
            }
        }
    }

    private fun failStart(message: String) {
        clearAttempt()
        SingBoxLog.append(this, "start failed: $message")
        SingBoxStatus.write(this, SingBoxStatus.State.FAILED, message)
        stopSelf()
    }

    private fun startFull(server: CommandServer, content: String, attempt: Long) {
        markAttempt(SingBoxStagedStart.NORMAL_LEVEL, "")
        SingBoxLog.append(this, memorySnapshotLine())
        SingBoxLog.append(this, "start: startOrReloadService begin")
        if (startOnce(server, content, attempt)) settleRunning()
    }

    private fun memorySnapshotLine(): String {
        val info = ActivityManager.MemoryInfo()
        getSystemService<ActivityManager>()?.getMemoryInfo(info)
        return SingBoxMemory.snapshotLine(Debug.getPss(), info.availMem / 1024, info.lowMemory)
    }

    private fun runStagedStart(server: CommandServer, content: String, attempt: Long) {
        val plan = runCatching {
            SingBoxStagedStart.levels(SingBoxStagedStart.factsOf(JSONObject(content)))
        }.getOrNull()
        if (plan == null) {
            startFull(server, content, attempt)
            return
        }
        val swept = SingBoxCacheGuard.sweepProbeCaches(File(filesDir, "singbox"))
        if (swept > 0) {
            SingBoxLog.append(this, "staged: swept $swept stale probe cache files")
        }
        for (level in plan) {
            val label = SingBoxStagedStart.labelForIndex(level.index)
            val levelContent = if (level.last) {
                content
            } else {
                val built = runCatching {
                    SingBoxStagedStart.build(content, level, nextAttemptSeq())
                }
                    .getOrNull()
                    ?.takeIf { runCatching { Libbox.checkConfig(it) }.isSuccess }
                if (built == null) {
                    SingBoxLog.append(
                        this,
                        "staged: $label trim rejected; falling back to full start",
                    )
                    startFull(server, content, attempt)
                    return
                }
                built
            }
            markAttempt(level.index, level.name)
            SingBoxLog.append(
                this,
                "staged: $label (${level.name}) begin; " +
                    SingBoxMemory.pssFragment(Debug.getPss()),
            )
            SingBoxLog.append(this, "start: startOrReloadService begin")
            if (!startOnce(server, levelContent, attempt)) return
            SingBoxLog.append(this, "staged: $label (${level.name}) returned")
        }
        settleRunning()
    }

    // The sequence markAttempt is about to assign; probe cache names key on it.
    private fun nextAttemptSeq(): Long =
        preferences().getLong(PREF_ATTEMPT_SEQ, 0L) + 1

    private fun startOnce(server: CommandServer, content: String, attempt: Long): Boolean {
        server.startOrReloadService(content, OverrideOptions())
        SingBoxLog.append(this, "start: startOrReloadService returned")
        if (!startAttempts.isLive(attempt)) {
            SingBoxLog.append(this, "start: attempt retired in flight; tearing down")
            stopBox()
            return false
        }
        return true
    }

    private fun settleRunning() {
        SingBoxStatus.write(this, SingBoxStatus.State.RUNNING, "")
        clearAttempt()
        SingBoxLog.append(this, "start: running")
        GlobalState.log("sing-box service started")
    }

    private fun markAttempt(level: Int, levelName: String) {
        // The ledger exists to survive this process dying mid-start: commit.
        val prefs = preferences()
        val seq = prefs.getLong(PREF_ATTEMPT_SEQ, 0L) + 1
        val since = System.currentTimeMillis()
        prefs.edit()
            .putBoolean(PREF_ATTEMPT_OPEN, true)
            .putInt(PREF_ATTEMPT_LEVEL, level)
            .putString(PREF_ATTEMPT_LEVEL_NAME, levelName)
            .putLong(PREF_ATTEMPT_SINCE, since)
            .putLong(PREF_ATTEMPT_SEQ, seq)
            .commit()
        SingBoxStatus.writeAttempt(
            this,
            SingBoxStatus.Attempt(seq, level, levelName, since),
        )
    }

    private fun clearAttempt() {
        preferences().edit()
            .putBoolean(PREF_ATTEMPT_OPEN, false)
            .putInt(PREF_ATTEMPT_LEVEL, SingBoxStagedStart.NORMAL_LEVEL)
            .commit()
        SingBoxStatus.clearAttemptMirror(this)
    }

    private data class StartDecision(
        val kind: SingBoxStagedStart.Decision,
        val level: Int,
        val levelName: String,
        val exitReason: Int?,
    )

    private fun startDecision(): StartDecision {
        val prefs = preferences()
        val exit = SingBoxExitInfo.latest(this)
        val level = prefs.getInt(PREF_ATTEMPT_LEVEL, SingBoxStagedStart.NORMAL_LEVEL)
        val kind = SingBoxStagedStart.decide(
            attemptOpen = prefs.getBoolean(PREF_ATTEMPT_OPEN, false),
            attemptLevel = level,
            exitReason = exit?.reason,
            exitAt = exit?.timestamp ?: 0L,
            attemptSince = prefs.getLong(PREF_ATTEMPT_SINCE, 0L),
        )
        val name = prefs.getString(PREF_ATTEMPT_LEVEL_NAME, "") ?: ""
        return StartDecision(kind, level, name, exit?.reason)
    }

    private fun isolateCacheIfDue() {
        val exit = SingBoxExitInfo.latest(this) ?: return
        if (!SingBoxCacheGuard.isolationDue(exit.reason)) return
        val prefs = preferences()
        val attemptDeath = SingBoxStagedStart.isAttemptDeath(
            prefs.getBoolean(PREF_ATTEMPT_OPEN, false),
            exit.timestamp,
            prefs.getLong(PREF_ATTEMPT_SINCE, 0L),
        )
        if (!attemptDeath) return
        if (exit.timestamp <= prefs.getLong(PREF_CACHE_ISOLATED_FOR, 0L)) return
        val size = SingBoxCacheGuard.isolate(File(filesDir, "singbox")) ?: return
        prefs.edit().putLong(PREF_CACHE_ISOLATED_FOR, exit.timestamp).apply()
        val cause =
            if (exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                "native crash"
            } else {
                "signaled death"
            }
        SingBoxLog.append(
            this,
            "stale cache isolated: cache.db ($size bytes) renamed after $cause",
        )
    }

    private fun stopBox() {
        val server = commandServer
        commandServer = null
        runCatching { server?.closeService() }
        runCatching { server?.close() }
        val descriptor = tunDescriptor
        tunDescriptor = null
        runCatching { descriptor?.close() }
    }

    override fun serviceStop() {
        SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "")
        stopSelf()
    }

    override fun serviceReload() {
        val configPath = preferences().getString(PREF_CONFIG_PATH, null)
            ?: error("sing-box config path is missing")
        val server = commandServer ?: error("sing-box command server is not running")
        ensureNetworkMonitor()
        SingBoxLog.append(this, "reload: startOrReloadService begin")
        try {
            server.startOrReloadService(File(configPath).readText(), OverrideOptions())
            SingBoxLog.append(this, "reload: startOrReloadService returned")
        } catch (error: Throwable) {
            SingBoxLog.append(this, "reload: startOrReloadService failed: ${error.message ?: error}")
            throw error
        }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        status.available = false
        status.enabled = false
        return status
    }

    override fun setSystemProxyEnabled(enabled: Boolean) {
        throw UnsupportedOperationException("system proxy is managed by the VPN tunnel")
    }

    override fun triggerNativeCrash() {
        throw UnsupportedOperationException("native crash trigger is not supported")
    }

    override fun writeDebugMessage(message: String?) {
        GlobalState.log("sing-box: $message")
        SingBoxLog.append(this, "sing-box: $message")
    }

    override fun connectSSHAgent(): Int = -1

    private fun setupLibbox() {
        synchronized(setupLock) {
            if (setupDone) return
            val options = SetupOptions()
            options.basePath = filesDir.absolutePath
            options.workingPath = File(filesDir, "singbox").apply { mkdirs() }.absolutePath
            options.tempPath = cacheDir.absolutePath
            options.fixAndroidStack = true
            options.logMaxLines = 1024
            // Without this, box log lines die in the daemon's ring buffer.
            options.debug = true
            Libbox.setup(options)
            setupDone = true
        }
    }

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        SingBoxLog.append(this, "tun: openTun begin")
        if (prepare(this) != null) error("android: missing vpn permission")
        val builder = Builder()
            .setSession("sing-box")
            .setMtu(options.mtu.takeIf { it > 0 } ?: 9000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }
        if (options.autoRoute) {
            if (options.dnsMode?.value != Libbox.DNSModeDisabled) {
                runCatching {
                    val dnsServers = options.dnsServerAddress
                    while (dnsServers.hasNext()) {
                        builder.addDnsServer(dnsServers.next())
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4Routes = options.inet4RouteAddress
                if (inet4Routes.hasNext()) {
                    while (inet4Routes.hasNext()) {
                        builder.addRoute(inet4Routes.next().toIpPrefix())
                    }
                } else if (options.inet4Address.hasNext()) {
                    builder.addRoute("0.0.0.0", 0)
                }
                val inet6Routes = options.inet6RouteAddress
                if (inet6Routes.hasNext()) {
                    while (inet6Routes.hasNext()) {
                        builder.addRoute(inet6Routes.next().toIpPrefix())
                    }
                } else if (options.inet6Address.hasNext()) {
                    builder.addRoute("::", 0)
                }
                val inet4Excluded = options.inet4RouteExcludeAddress
                while (inet4Excluded.hasNext()) {
                    builder.excludeRoute(inet4Excluded.next().toIpPrefix())
                }
                val inet6Excluded = options.inet6RouteExcludeAddress
                while (inet6Excluded.hasNext()) {
                    builder.excludeRoute(inet6Excluded.next().toIpPrefix())
                }
            } else {
                val inet4Ranges = options.inet4RouteRange
                while (inet4Ranges.hasNext()) {
                    val range = inet4Ranges.next()
                    builder.addRoute(range.address(), range.prefix())
                }
                val inet6Ranges = options.inet6RouteRange
                while (inet6Ranges.hasNext()) {
                    val range = inet6Ranges.next()
                    builder.addRoute(range.address(), range.prefix())
                }
            }
            val includePackage = options.includePackage
            while (includePackage.hasNext()) {
                val name = includePackage.next()
                try {
                    builder.addAllowedApplication(name)
                } catch (_: PackageManager.NameNotFoundException) {
                    GlobalState.log("sing-box skipped an uninstalled package: $name")
                }
            }
            val excludePackage = options.excludePackage
            while (excludePackage.hasNext()) {
                val name = excludePackage.next()
                try {
                    builder.addDisallowedApplication(name)
                } catch (_: PackageManager.NameNotFoundException) {
                    GlobalState.log("sing-box skipped an uninstalled package: $name")
                }
            }
        }
        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    options.httpProxyServer,
                    options.httpProxyServerPort,
                    options.httpProxyBypassDomain.toList(),
                ),
            )
        }
        val descriptor = builder.establish()
            ?: error("android: the application is not prepared or is revoked")
        tunDescriptor = descriptor
        return descriptor.fd
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return Libbox.findConnectionOwner(
                ipProtocol,
                sourceAddress,
                sourcePort,
                destinationAddress,
                destinationPort,
            )
        }
        val uid = connectivity?.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        ) ?: -1
        if (uid < 0) error("android: connection owner not found")
        val packages = packageManager.getPackagesForUid(uid)?.toList().orEmpty()
        val owner = ConnectionOwner()
        owner.userId = uid
        owner.userName = packages.firstOrNull().orEmpty()
        owner.setAndroidPackageNames(StringIteratorAdapter(packages))
        return owner
    }

    // The monitor registers with the service, before any startOrReloadService.
    @Synchronized
    private fun ensureNetworkMonitor(): SingBoxNetworkMonitor? {
        networkMonitor?.let { return it }
        val manager = connectivity ?: return null
        val monitor = SingBoxNetworkMonitor(manager)
        networkMonitor = monitor
        monitor.start()
        return monitor
    }

    @Synchronized
    private fun stopNetworkMonitor() {
        networkMonitor?.stop()
        networkMonitor = null
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        ensureNetworkMonitor()?.attachListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkMonitor?.detachListener()
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val manager = connectivity ?: return NetworkInterfaceIteratorAdapter(emptyList())
        val systemInterfaces = runCatching {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        }.getOrDefault(emptyList())
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        for (network in manager.allNetworks) {
            val linkProperties = manager.getLinkProperties(network) ?: continue
            val capabilities = manager.getNetworkCapabilities(network) ?: continue
            val name = linkProperties.interfaceName ?: continue
            if (name == myInterfaceName) continue
            val systemInterface = systemInterfaces.find { it.name == name } ?: continue
            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = name
            boxInterface.index = systemInterface.index
            boxInterface.mtu = runCatching { systemInterface.mtu }.getOrDefault(0)
            boxInterface.addresses = StringIteratorAdapter(
                systemInterface.interfaceAddresses.map { address ->
                    "${address.address.hostAddress}/${address.networkPrefixLength}"
                },
            )
            boxInterface.dnsServer = StringIteratorAdapter(
                linkProperties.dnsServers.mapNotNull { it.hostAddress },
            )
            boxInterface.gateway = StringIteratorAdapter(
                linkProperties.routes
                    .filter { it.destination.prefixLength == 0 }
                    .mapNotNull { it.gateway }
                    .filter { !it.isAnyLocalAddress }
                    .mapNotNull { it.hostAddress },
            )
            boxInterface.type = when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            var flags = 0
            if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                flags = flags or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (systemInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
            if (systemInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
            if (runCatching { systemInterface.supportsMulticast() }.getOrDefault(false)) {
                flags = flags or OsConstants.IFF_MULTICAST
            }
            boxInterface.flags = flags
            boxInterface.metered =
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            interfaces.add(boxInterface)
        }
        return NetworkInterfaceIteratorAdapter(interfaces)
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? {
        @Suppress("DEPRECATION")
        val wifiInfo = getSystemService<WifiManager>()?.connectionInfo ?: return null
        var ssid = wifiInfo.ssid ?: return null
        if (ssid == "<unknown ssid>") return WIFIState("", "")
        if (ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length - 1)
        }
        return WIFIState(ssid, wifiInfo.bssid ?: "")
    }

    override fun clearDNSCache() = Unit

    override fun sendNotification(notification: Notification) {
        val manager = notificationManager ?: return
        val text = listOf(notification.subtitle, notification.body)
            .filter { it.isNotEmpty() }
            .joinToString("\n")
        val built = NotificationCompat.Builder(this, GlobalState.NOTIFICATION_CHANNEL)
            .setContentTitle(notification.title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setSmallIcon(R.drawable.ic_stat_disc)
            .build()
        runCatching { manager.notify(notification.identifier.hashCode(), built) }
    }

    override fun cancelNotification(identifier: String, typeID: Int) {
        notificationManager?.cancel(identifier.hashCode())
    }

    override fun startNeighborMonitor(listener: NeighborUpdateListener?) = Unit

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) = Unit

    override fun registerMyInterface(name: String?) {
        myInterfaceName = name
    }

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {
        throw UnsupportedOperationException("platform shell is not supported")
    }

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession {
        throw UnsupportedOperationException("platform shell is not supported")
    }

    override fun lookupUser(username: String?): PlatformUser {
        throw UnsupportedOperationException("user lookup is not supported")
    }

    override fun lookupSFTPServer(): String {
        throw UnsupportedOperationException("sftp server lookup is not supported")
    }

    override fun readSystemSSHHostKey(): String {
        throw UnsupportedOperationException("system ssh host key is not available")
    }

    override fun tailscaleHostname(): String =
        Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
            ?.takeIf { it.isNotBlank() }
            ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions?): BridgeSession {
        throw UnsupportedOperationException("platform bridge is not supported")
    }

    private fun RoutePrefix.toIpPrefix(): IpPrefix =
        IpPrefix(InetAddress.getByName(address()), prefix())

    private fun StringIterator.toList(): List<String> {
        val values = mutableListOf<String>()
        while (hasNext()) values.add(next())
        return values
    }

    companion object {
        const val EXTRA_CONFIG_PATH = "com.kfusion.singbox.extra.CONFIG_PATH"
        const val EXTRA_REQUEST_ID = "com.kfusion.singbox.extra.REQUEST_ID"
        const val ACTION_STOP = "com.kfusion.singbox.action.STOP"
        const val ACTION_CHECK_CONFIG = "com.kfusion.singbox.action.CHECK_CONFIG"
        private const val PREF_CONFIG_PATH = "config_path"
        private const val PREF_EXIT_SURFACED = "exit_surfaced_at"
        private const val PREF_CRASH_SURFACED = "crash_surfaced_at"
        private const val PREF_ATTEMPT_OPEN = "attempt_open"
        private const val PREF_ATTEMPT_LEVEL = "attempt_level"
        private const val PREF_ATTEMPT_LEVEL_NAME = "attempt_level_name"
        private const val PREF_ATTEMPT_SINCE = "attempt_since"
        private const val PREF_ATTEMPT_SEQ = "attempt_seq"
        private const val PREF_CACHE_ISOLATED_FOR = "cache_isolated_for"
        private const val PREFS_NAME = "singbox_service"

        // An explicit stop drops the saved path: no later resurrection on it.
        fun clearSavedConfigPath(context: Context) {
            context.getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .edit()
                .remove(PREF_CONFIG_PATH)
                .apply()
        }

        private val setupLock = Any()
        private var setupDone = false

        init {
            // This process hosts only the libbox runtime: loading libbox.so
            // before anything touches go.Seq makes Seq's natives bind to it
            // rather than to the mihomo library the same class loads by name.
            System.loadLibrary("box")
        }
    }
}
