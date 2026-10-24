package com.kfusion.singbox

import io.nekohasekai.libbox.NetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.StringIterator

internal class StringIteratorAdapter(values: List<String>) : StringIterator {
    private val iterator = values.iterator()
    private val size = values.size

    override fun len(): Int = size

    override fun hasNext(): Boolean = iterator.hasNext()

    override fun next(): String = iterator.next()
}

internal class NetworkInterfaceIteratorAdapter(
    values: List<NetworkInterface>,
) : NetworkInterfaceIterator {
    private val iterator = values.iterator()

    override fun hasNext(): Boolean = iterator.hasNext()

    override fun next(): NetworkInterface = iterator.next()
}
