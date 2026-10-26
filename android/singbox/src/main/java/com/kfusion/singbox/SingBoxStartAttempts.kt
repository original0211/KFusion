package com.kfusion.singbox

// Retires an in-flight start on stop: its late return publishes nothing.
class SingBoxStartAttempts {
    private var activeId = 0L
    private var invalidatedId = 0L

    @Synchronized
    fun begin(): Long {
        activeId += 1
        return activeId
    }

    @Synchronized
    fun invalidate() {
        invalidatedId = activeId
    }

    @Synchronized
    fun isLive(id: Long): Boolean = id == activeId && id != invalidatedId

    @Synchronized
    fun ownsGate(id: Long): Boolean = id == activeId
}
