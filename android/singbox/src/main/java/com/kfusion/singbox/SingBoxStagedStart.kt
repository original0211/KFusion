package com.kfusion.singbox

import android.app.ApplicationExitInfo
import org.json.JSONArray
import org.json.JSONObject

object SingBoxStagedStart {
    const val NORMAL_LEVEL = -1

    // A death an attempt owns cannot predate its mark (same wall clock); 5s still separates taps 46s apart.
    const val ASSOCIATION_SLACK_MS = 5_000L

    enum class Decision { NORMAL, STAGED, REPORT }

    // Codes are persisted in the attempt ledger, so they name stages, not plan positions.
    enum class Stage(val code: Int) {
        BARE(0),
        OUTBOUNDS(1),
        RULE_SETS(2),
        INBOUNDS(3),
        FULL(4),
        CACHE_REDIRECT(5),
        NEAR_EMPTY(6),
    }

    data class Level(
        val index: Int,
        val stage: Stage,
        val name: String,
        val last: Boolean,
    )

    data class Facts(
        val hasRuleSets: Boolean,
        val hasInbounds: Boolean,
        val hasExperimental: Boolean,
    )

    fun isAttemptDeath(attemptOpen: Boolean, exitAt: Long, attemptSince: Long): Boolean =
        attemptOpen && exitAt >= attemptSince - ASSOCIATION_SLACK_MS

    fun decide(
        attemptOpen: Boolean,
        attemptLevel: Int,
        exitReason: Int?,
        exitAt: Long,
        attemptSince: Long,
    ): Decision {
        if (!isAttemptDeath(attemptOpen, exitAt, attemptSince)) return Decision.NORMAL
        if (exitReason != ApplicationExitInfo.REASON_CRASH_NATIVE &&
            exitReason != ApplicationExitInfo.REASON_LOW_MEMORY
        ) {
            return Decision.NORMAL
        }
        return if (attemptLevel >= 0) Decision.REPORT else Decision.STAGED
    }

    fun levels(facts: Facts): List<Level> {
        val stages =
            mutableListOf(Stage.CACHE_REDIRECT, Stage.NEAR_EMPTY, Stage.BARE, Stage.OUTBOUNDS)
        if (facts.hasRuleSets) stages += Stage.RULE_SETS
        if (facts.hasInbounds) stages += Stage.INBOUNDS
        if (facts.hasExperimental) stages += Stage.FULL
        return stages.mapIndexed { position, stage ->
            Level(stage.code, stage, stageName(stage), position == stages.lastIndex)
        }
    }

    private fun stageName(stage: Stage): String =
        when (stage) {
            Stage.BARE -> "bare direct"
            Stage.OUTBOUNDS -> "outbounds and dns"
            Stage.RULE_SETS -> "rule sets"
            Stage.INBOUNDS -> "inbounds"
            Stage.FULL -> "full config"
            Stage.CACHE_REDIRECT -> "cache redirect"
            Stage.NEAR_EMPTY -> "near-empty config"
        }

    fun labelForIndex(index: Int): String =
        when (index) {
            Stage.CACHE_REDIRECT.code -> "L-1"
            Stage.NEAR_EMPTY.code -> "L-2"
            else -> "L$index"
        }

    fun verdict(exitReason: Int?, index: Int, name: String): String {
        val action =
            if (exitReason == ApplicationExitInfo.REASON_LOW_MEMORY) {
                "low-memory killed"
            } else {
                "crashed"
            }
        val label = labelForIndex(index)
        return if (name.isBlank()) {
            "staged start: $action at $label"
        } else {
            "staged start: $action at $label ($name)"
        }
    }

    fun factsOf(full: JSONObject): Facts {
        val route = full.optJSONObject("route")
        val ruleSets = route?.optJSONArray("rule_set")
        val inbounds = full.optJSONArray("inbounds")
        return Facts(
            hasRuleSets = (ruleSets?.length() ?: 0) > 0,
            hasInbounds = (inbounds?.length() ?: 0) > 0,
            hasExperimental = full.has("experimental"),
        )
    }

    const val NEAR_EMPTY_CONTENT =
        """{"log":{"level":"info"},"outbounds":[{"type":"direct","tag":"direct"}]}"""

    fun build(content: String, level: Level, probeNonce: Long = 0L): String {
        if (level.last) return content
        if (level.stage == Stage.NEAR_EMPTY) return NEAR_EMPTY_CONTENT
        val full = JSONObject(content)
        val out = JSONObject()
        full.optJSONObject("log")?.let { out.put("log", it) }
        when (level.stage) {
            Stage.BARE -> putBareShape(out)
            Stage.CACHE_REDIRECT -> {
                putBareShape(out)
                // Same bare instance, but its cache lands on a file nothing has ever opened.
                val cacheFile = JSONObject()
                    .put("enabled", true)
                    .put("path", SingBoxCacheGuard.probeCacheName(probeNonce))
                out.put("experimental", JSONObject().put("cache_file", cacheFile))
            }
            Stage.OUTBOUNDS -> {
                putBody(full, out, fullDns = false)
                out.put("route", routeSkeleton(full))
            }
            Stage.RULE_SETS -> {
                putBody(full, out, fullDns = true)
                full.optJSONObject("route")?.let { out.put("route", it) }
            }
            Stage.INBOUNDS -> {
                putBody(full, out, fullDns = true)
                full.optJSONObject("route")?.let { out.put("route", it) }
                full.optJSONArray("inbounds")?.let { out.put("inbounds", it) }
            }
            Stage.FULL -> return content
        }
        return out.toString()
    }

    private fun putBareShape(out: JSONObject) {
        val direct = JSONObject().put("type", "direct").put("tag", "direct")
        out.put("outbounds", JSONArray().put(direct))
        out.put("route", JSONObject().put("final", "direct"))
    }

    private fun putBody(full: JSONObject, out: JSONObject, fullDns: Boolean) {
        full.optJSONArray("outbounds")?.let { out.put("outbounds", it) }
        full.optJSONArray("endpoints")?.let { out.put("endpoints", it) }
        val dns = full.optJSONObject("dns") ?: return
        if (fullDns) {
            out.put("dns", dns)
            return
        }
        val trimmed = JSONObject(dns.toString())
        val rules = dns.optJSONArray("rules")
        if (rules != null) {
            val kept = JSONArray()
            for (i in 0 until rules.length()) {
                val rule = rules.optJSONObject(i) ?: continue
                if (!rule.has("rule_set")) kept.put(rule)
            }
            trimmed.put("rules", kept)
        }
        out.put("dns", trimmed)
    }

    private fun routeSkeleton(full: JSONObject): JSONObject {
        val route = full.optJSONObject("route") ?: return JSONObject().put("final", "direct")
        val out = JSONObject()
        for (key in listOf("final", "auto_detect_interface", "default_domain_resolver")) {
            if (route.has(key)) out.put(key, route.get(key))
        }
        return out
    }
}
