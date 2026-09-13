package com.mastir.community_app.shared

import android.content.Context
import org.json.JSONObject

/** Small paired-device payloads. No auth tokens, accounts or private records. */
object WatchPayload {
    const val PRAYERS = "/community/prayers"
    const val PHONE_COUNTER = "/community/phone-counter"
    const val WATCH_COUNTER = "/community/watch-counter"
    const val PREFS = "community_watch"
    fun validTimeline(raw: String): Boolean = runCatching {
        require(raw.toByteArray().size <= 24000)
        val obj = JSONObject(raw)
        require(obj.getString("organisation").length in 1..120)
        require(obj.getString("timeZone").length in 1..80)
        val rows = obj.getJSONArray("prayers")
        require(rows.length() <= 100)
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            require(row.getString("name").length in 1..80)
            require(row.getLong("at") in 0..4102444800000L)
        }
        true
    }.getOrDefault(false)
    fun validCounter(raw: String): Boolean = runCatching {
        require(raw.toByteArray().size <= 2000)
        val obj = JSONObject(raw)
        require(obj.getString("sessionId").length in 1..100)
        require(obj.getString("sourceId").length in 1..100)
        require(obj.getLong("revision") >= 0)
        require(obj.getInt("count") in 0..99999999)
        require(obj.getInt("target") in listOf(33, 99, 100))
        true
    }.getOrDefault(false)
    @Synchronized
    fun receiveCounter(context: Context, raw: String): Boolean {
        if (!validCounter(raw)) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val obj = JSONObject(raw)
        val stamp = "seen.${obj.getString("sourceId")}.${obj.getString("sessionId")}"
        val revision = obj.getLong("revision")
        if (revision <= prefs.getLong(stamp, -1)) return false
        return prefs.edit().putLong(stamp, revision).putString("incomingCounter", raw).commit()
    }
}
