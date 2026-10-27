package com.kfusion.singbox

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

// Every update crosses this lane one at a time, in arrival order, before
// reaching Go, whose monitor lock does not cover the enumeration and router
// callback stretches; mirrors the actor loop in SFA's DefaultNetworkListener.
class SingBoxInterfaceUpdates<T : Any>(
    private val lane: (Runnable) -> Unit,
    private val deliver: (T?) -> Unit,
) {
    private var current: T? = null

    fun seed(network: T?) {
        lane(Runnable { current = network })
    }

    fun attach() {
        lane(Runnable { deliver(current) })
    }

    fun prime(network: T?) {
        lane(
            Runnable {
                current = network
                deliver(network)
            },
        )
    }

    fun available(network: T) {
        lane(
            Runnable {
                current = network
                deliver(network)
            },
        )
    }

    fun changed(network: T) {
        lane(Runnable { if (current == network) deliver(network) })
    }

    fun lost(network: T) {
        lane(
            Runnable {
                if (current == network) {
                    current = null
                    deliver(null)
                }
            },
        )
    }
}

// Claimed once per service lifetime, however many instances ask; the count is the test seam.
class SingBoxMonitorRegistration {
    var registrations: Int = 0
        private set

    private var active = false

    fun begin(): Boolean {
        if (active) return false
        active = true
        registrations++
        return true
    }

    fun end(): Boolean {
        if (!active) return false
        active = false
        return true
    }
}

// Service-scoped default-network monitor, aligned with SFA: the system
// callback registers once with the service; instances only swap its listener.
class SingBoxNetworkMonitor(private val connectivity: ConnectivityManager) {
    private val registration = SingBoxMonitorRegistration()
    private var worker: HandlerThread? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var updates: SingBoxInterfaceUpdates<Network>? = null

    @Volatile
    private var listener: InterfaceUpdateListener? = null

    val registrationCount: Int
        get() = registration.registrations

    @Synchronized
    fun start() {
        if (!registration.begin()) return
        val thread = HandlerThread("singbox-network-callback")
        thread.start()
        worker = thread
        val handler = Handler(thread.looper)
        val lane =
            SingBoxInterfaceUpdates<Network>(
                lane = { runnable -> handler.post(runnable) },
                deliver = { network -> deliver(network) },
            )
        updates = lane
        val systemCallback =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = lane.available(network)

                override fun onLinkPropertiesChanged(
                    network: Network,
                    linkProperties: LinkProperties,
                ) = lane.changed(network)

                override fun onLost(network: Network) = lane.lost(network)
            }
        callback = systemCallback
        lane.seed(connectivity.activeNetwork)
        registerCallback(systemCallback, handler)
    }

    @Synchronized
    fun stop() {
        if (!registration.end()) return
        listener = null
        callback?.let { current ->
            runCatching { connectivity.unregisterNetworkCallback(current) }
        }
        callback = null
        updates = null
        worker?.quitSafely()
        worker = null
    }

    fun attachListener(next: InterfaceUpdateListener) {
        start()
        listener = next
        // Queried at attach, not at registration: a snapshot taken while the
        // previous core's VPN was still coming down may name a dead network.
        updates?.prime(connectivity.activeNetwork)
    }

    fun detachListener() {
        listener = null
    }

    private fun registerCallback(
        callback: ConnectivityManager.NetworkCallback,
        handler: Handler,
    ) {
        // The request form keeps the VPN itself out of the answer (Android P reports it as default).
        val request =
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
                .build()
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                connectivity.registerBestMatchingNetworkCallback(request, callback, handler)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ->
                connectivity.requestNetwork(request, callback, handler)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                connectivity.registerDefaultNetworkCallback(callback, handler)
            else -> connectivity.registerDefaultNetworkCallback(callback)
        }
    }

    private fun deliver(network: Network?) {
        val target = listener ?: return
        if (network == null) {
            target.updateDefaultInterface("", -1, false, false)
            return
        }
        val name = connectivity.getLinkProperties(network)?.interfaceName
        if (name == null) {
            // Never drop an update in silence: Go fills its interface list
            // only when an update arrives, so no default beats nothing.
            target.updateDefaultInterface("", -1, false, false)
            return
        }
        val index =
            runCatching { NetworkInterface.getByName(name)?.index ?: -1 }.getOrDefault(-1)
        // SFA always reports the default interface as not expensive.
        target.updateDefaultInterface(name, index, false, false)
    }
}
