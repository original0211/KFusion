package com.kfusion.singbox

import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.ProxyInfo
import android.net.wifi.WifiManager
import android.os.Build
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
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import kotlin.concurrent.thread
import android.net.VpnService as SystemVpnService
import io.nekohasekai.libbox.BoxService as LibboxService
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface

class SingBoxVpnService : SystemVpnService(), PlatformInterface {
    private val connectivity by lazy { getSystemService<ConnectivityManager>() }
    private val notificationManager by lazy { getSystemService<NotificationManager>() }

    @Volatile
    private var boxService: LibboxService? = null
    private var tunDescriptor: ParcelFileDescriptor? = null
    private var myInterfaceName: String? = null
    private var interfaceListener: InterfaceUpdateListener? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onBind(intent: Intent): IBinder? =
        if (intent.action == SERVICE_INTERFACE) super.onBind(intent) else null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        startForeground(
            NotificationCompat.Builder(this, GlobalState.NOTIFICATION_CHANNEL)
                .setContentTitle("KFusion · sing-box")
                .setContentText("sing-box VPN 正在启动")
                .setSmallIcon(applicationInfo.icon)
                .setOngoing(true)
                .build(),
        )
        val configPath = intent?.getStringExtra(EXTRA_CONFIG_PATH)
            ?: preferences().getString(PREF_CONFIG_PATH, null)
        if (configPath == null) {
            failStart("sing-box 配置路径缺失")
            return START_NOT_STICKY
        }
        preferences().edit().putString(PREF_CONFIG_PATH, configPath).apply()
        thread(name = "singbox-start") { startBox(configPath) }
        return START_STICKY
    }

    override fun onRevoke() {
        GlobalState.log("sing-box VPN permission revoked")
        stopBox()
        SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "VPN 权限被系统撤销")
        stopSelf()
    }

    override fun onDestroy() {
        stopBox()
        if (SingBoxStatus.read(this)?.state == SingBoxStatus.State.RUNNING) {
            SingBoxStatus.write(this, SingBoxStatus.State.STOPPED, "")
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun preferences() =
        getSharedPreferences("singbox_service", MODE_PRIVATE)

    private fun startBox(configPath: String) {
        try {
            val configFile = File(configPath)
            check(configFile.isFile) { "sing-box 配置文件不存在：$configPath" }
            val content = configFile.readText()
            setupLibbox()
            Libbox.checkConfig(content)
            stopBox()
            val service = Libbox.newService(content, this)
            boxService = service
            service.start()
            SingBoxStatus.write(this, SingBoxStatus.State.RUNNING, "")
            GlobalState.log("sing-box service started")
        } catch (error: Exception) {
            GlobalState.log("sing-box start failed: $error")
            failStart(error.message ?: error.toString())
        }
    }

    private fun failStart(message: String) {
        SingBoxStatus.write(this, SingBoxStatus.State.FAILED, message)
        stopSelf()
    }

    private fun stopBox() {
        val service = boxService
        boxService = null
        runCatching { service?.close() }
        val descriptor = tunDescriptor
        tunDescriptor = null
        runCatching { descriptor?.close() }
    }

    private fun setupLibbox() {
        synchronized(setupLock) {
            if (setupDone) return
            val options = SetupOptions()
            options.basePath = filesDir.absolutePath
            options.workingPath = File(filesDir, "singbox").apply { mkdirs() }.absolutePath
            options.tempPath = cacheDir.absolutePath
            options.fixAndroidStack = true
            options.logMaxLines = 1024
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

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = listener
        val manager = connectivity ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = reportDefaultInterface(network)

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) =
                reportDefaultInterface(network)

            override fun onLost(network: Network) {
                interfaceListener?.updateDefaultInterface("", -1, false, false)
            }
        }
        networkCallback = callback
        manager.registerDefaultNetworkCallback(callback)
        manager.activeNetwork?.let { reportDefaultInterface(it) }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        interfaceListener = null
        val callback = networkCallback
        networkCallback = null
        if (callback != null) {
            runCatching { connectivity?.unregisterNetworkCallback(callback) }
        }
    }

    private fun reportDefaultInterface(network: Network) {
        val listener = interfaceListener ?: return
        val linkProperties = connectivity?.getLinkProperties(network) ?: return
        val name = linkProperties.interfaceName ?: return
        val index = runCatching { NetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)
        val capabilities = connectivity?.getNetworkCapabilities(network)
        val metered = capabilities?.let {
            !it.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } ?: false
        listener.updateDefaultInterface(name, index, metered, false)
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
            .setSmallIcon(applicationInfo.icon)
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
        private const val PREF_CONFIG_PATH = "config_path"

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
