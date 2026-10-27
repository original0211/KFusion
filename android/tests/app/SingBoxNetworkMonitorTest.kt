package com.follow.clash

import com.kfusion.singbox.SingBoxInterfaceUpdates
import com.kfusion.singbox.SingBoxMonitorRegistration
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SingBoxNetworkMonitorTest {
    @Test
    fun updatesSerializeUnderACallbackStorm() {
        val executor = Executors.newSingleThreadExecutor()
        try {
            val inFlight = AtomicInteger(0)
            val maxInFlight = AtomicInteger(0)
            val delivered = AtomicInteger(0)
            val updates =
                SingBoxInterfaceUpdates<String>(
                    lane = { runnable -> executor.execute(runnable) },
                    deliver = {
                        val now = inFlight.incrementAndGet()
                        maxInFlight.updateAndGet { peak -> maxOf(peak, now) }
                        Thread.sleep(1)
                        delivered.incrementAndGet()
                        inFlight.decrementAndGet()
                    },
                )
            val threads =
                (1..8).map { threadIndex ->
                    Thread {
                        repeat(25) { index ->
                            val token = "net-$threadIndex-$index"
                            updates.available(token)
                            updates.changed(token)
                            updates.lost(token)
                        }
                    }
                }
            threads.forEach { it.start() }
            threads.forEach { it.join() }
            executor.shutdown()
            assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS))
            assertEquals(1, maxInFlight.get())
            assertEquals(0, inFlight.get())
            assertTrue(delivered.get() > 0)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun deliveriesKeepArrivalOrderOnTheLane() {
        val executor = Executors.newSingleThreadExecutor()
        try {
            val delivered = Collections.synchronizedList(mutableListOf<String?>())
            val done = CountDownLatch(100)
            val updates =
                SingBoxInterfaceUpdates<String>(
                    lane = { runnable -> executor.execute(runnable) },
                    deliver = {
                        delivered.add(it)
                        done.countDown()
                    },
                )
            repeat(100) { index -> updates.available("net-$index") }
            assertTrue(done.await(30, TimeUnit.SECONDS))
            assertEquals((0 until 100).map { "net-$it" }, delivered.toList())
        } finally {
            executor.shutdown()
            executor.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun changedAndLostOnlyApplyToTheTrackedNetwork() {
        val delivered = mutableListOf<String?>()
        val updates =
            SingBoxInterfaceUpdates<String>(
                lane = { runnable -> runnable.run() },
                deliver = { delivered.add(it) },
            )
        updates.available("wifi")
        updates.changed("cell")
        updates.lost("cell")
        updates.changed("wifi")
        updates.lost("wifi")
        updates.changed("wifi")
        assertEquals(listOf("wifi", "wifi", null), delivered)
    }

    @Test
    fun attachReplaysTheTrackedState() {
        val delivered = mutableListOf<String?>()
        val updates =
            SingBoxInterfaceUpdates<String>(
                lane = { runnable -> runnable.run() },
                deliver = { delivered.add(it) },
            )
        updates.attach()
        updates.seed("wifi")
        updates.attach()
        updates.available("cell")
        updates.attach()
        assertEquals(listOf(null, "wifi", "cell", "cell"), delivered)
    }

    @Test
    fun primeReplaysTheFreshNetworkInsteadOfTheStaleSeed() {
        val delivered = mutableListOf<String?>()
        val updates =
            SingBoxInterfaceUpdates<String>(
                lane = { runnable -> runnable.run() },
                deliver = { delivered.add(it) },
            )
        updates.seed("stale")
        updates.prime("wifi")
        updates.attach()
        assertEquals(listOf("wifi", "wifi"), delivered)
    }

    @Test
    fun primeWithNoNetworkStillReplaysEmpty() {
        val delivered = mutableListOf<String?>()
        val updates =
            SingBoxInterfaceUpdates<String>(
                lane = { runnable -> runnable.run() },
                deliver = { delivered.add(it) },
            )
        updates.seed("wifi")
        updates.prime(null)
        updates.attach()
        assertEquals(listOf(null, null), delivered)
    }

    @Test
    fun primeStaysSerializedUnderACallbackStorm() {
        val executor = Executors.newSingleThreadExecutor()
        try {
            val inFlight = AtomicInteger(0)
            val maxInFlight = AtomicInteger(0)
            val delivered = AtomicInteger(0)
            val updates =
                SingBoxInterfaceUpdates<String>(
                    lane = { runnable -> executor.execute(runnable) },
                    deliver = {
                        val now = inFlight.incrementAndGet()
                        maxInFlight.updateAndGet { peak -> maxOf(peak, now) }
                        Thread.sleep(1)
                        delivered.incrementAndGet()
                        inFlight.decrementAndGet()
                    },
                )
            val threads =
                (1..8).map { threadIndex ->
                    Thread {
                        repeat(25) { index ->
                            val token = "net-$threadIndex-$index"
                            updates.prime(token)
                            updates.available(token)
                            updates.changed(token)
                            updates.lost(token)
                        }
                    }
                }
            threads.forEach { it.start() }
            threads.forEach { it.join() }
            executor.shutdown()
            assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS))
            assertEquals(1, maxInFlight.get())
            assertEquals(0, inFlight.get())
            assertTrue(delivered.get() > 0)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun registrationIsClaimedOnceUntilReleased() {
        val registration = SingBoxMonitorRegistration()
        assertTrue(registration.begin())
        assertFalse(registration.begin())
        assertFalse(registration.begin())
        assertEquals(1, registration.registrations)
        assertTrue(registration.end())
        assertFalse(registration.end())
        assertTrue(registration.begin())
        assertEquals(2, registration.registrations)
    }
}
