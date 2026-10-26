package com.follow.clash.plugins

// A silent check attempt earns one retry against a possibly restarted service
// process; any answer at all, success or failure, settles the check.
internal object SingBoxCheckGate {
    // Mirrored by singBoxCheckTimeoutSentinel in core_switch.dart.
    const val TIMEOUT_SENTINEL = "sing-box-check-timeout"

    fun awaitResult(attempts: Int, runAttempt: () -> String?): String? {
        repeat(attempts) {
            runAttempt()?.let { return it }
        }
        return null
    }
}
