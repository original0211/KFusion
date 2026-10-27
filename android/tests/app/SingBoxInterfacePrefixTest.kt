package com.follow.clash

import com.kfusion.singbox.interfacePrefix
import java.net.Inet6Address
import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SingBoxInterfacePrefixTest {
    @Test
    fun zonedLinkLocalPrefixDropsTheZone() {
        val bytes =
            byteArrayOf(
                0xfe.toByte(), 0x80.toByte(), 0, 0, 0, 0, 0, 0,
                0x14, 0xc9.toByte(), 0xcb.toByte(), 0xff.toByte(),
                0xfe.toByte(), 0xc4.toByte(), 0x2c, 0xac.toByte(),
            )
        val scoped = Inet6Address.getByAddress(null, bytes, 7)
        assertTrue(scoped.hostAddress.orEmpty().contains('%'))
        val result = interfacePrefix(scoped, 64)
        assertFalse(result.contains('%'))
        assertEquals("${InetAddress.getByAddress(bytes).hostAddress}/64", result)
    }

    @Test
    fun zonedPrefixKeepsItsPrefixLength() {
        val bytes =
            byteArrayOf(
                0xfd.toByte(), 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 1,
            )
        val scoped = Inet6Address.getByAddress(null, bytes, 3)
        assertTrue(scoped.hostAddress.orEmpty().contains('%'))
        val result = interfacePrefix(scoped, 8)
        assertFalse(result.contains('%'))
        assertEquals("${InetAddress.getByAddress(bytes).hostAddress}/8", result)
    }

    @Test
    fun unzonedIPv6PrefixIsUnchanged() {
        val bytes =
            byteArrayOf(
                0x20, 0x01, 0x0d, 0xb8.toByte(), 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 1,
            )
        val address = InetAddress.getByAddress(bytes)
        assertEquals("${address.hostAddress}/64", interfacePrefix(address, 64))
    }

    @Test
    fun loopbackIPv6PrefixIsUnchanged() {
        val bytes = ByteArray(16)
        bytes[15] = 1
        val address = InetAddress.getByAddress(bytes)
        assertEquals("${address.hostAddress}/128", interfacePrefix(address, 128))
    }

    @Test
    fun iPv4PrefixIsUnchanged() {
        val address =
            InetAddress.getByAddress(byteArrayOf(192.toByte(), 168.toByte(), 1, 5))
        assertEquals("${address.hostAddress}/24", interfacePrefix(address, 24))
    }
}
