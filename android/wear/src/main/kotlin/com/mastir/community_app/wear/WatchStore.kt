package com.mastir.community_app.wear

import android.content.Context
import com.google.android.gms.wearable.*
import com.mastir.community_app.shared.WatchPayload
import java.util.UUID
import org.json.JSONObject

class WatchStore(val context: Context) {
  val prefs = context.getSharedPreferences(WatchPayload.PREFS, Context.MODE_PRIVATE)
  var count: Int
    get() = prefs.getInt("count", 0)
    set(value) {
      prefs.edit().putInt("count", value.coerceIn(0, 99999999)).commit()
    }

  var target: Int
    get() = prefs.getInt("target", 33)
    set(value) {
      if (value in listOf(33, 99, 100)) prefs.edit().putInt("target", value).commit()
    }

  fun timeline(): JSONObject? = runCatching {
    JSONObject(prefs.getString("timeline", "") ?: "")
  }.getOrNull()

  fun snapshot(): String {
    var source = prefs.getString("sourceId", null)
    if (source == null) {
      source = UUID.randomUUID().toString()
      prefs.edit().putString("sourceId", source).commit()
    }
    val revision = prefs.getLong("revision", 0) + 1
    prefs.edit().putLong("revision", revision).commit()
    return JSONObject()
      .put("sourceId", source)
      .put("sessionId", "local")
      .put("revision", revision)
      .put("count", count)
      .put("target", target)
      .toString()
  }

  fun send(done: (Boolean) -> Unit) {
    Wearable.getDataClient(context)
      .putDataItem(
        PutDataRequest.create(WatchPayload.WATCH_COUNTER)
          .setData(snapshot().toByteArray())
          .setUrgent()
      )
      .addOnSuccessListener { done(true) }
      .addOnFailureListener { done(false) }
  }

  fun receive(path: String?, bytes: ByteArray?) {
    if (bytes == null || bytes.size > 24000) return
    val raw = bytes.toString(Charsets.UTF_8)
    when (path) {
      WatchPayload.PRAYERS ->
        if (WatchPayload.validTimeline(raw)) {
          prefs
            .edit()
            .putString("timeline", raw)
            .putLong("receivedAt", System.currentTimeMillis())
            .commit()
          androidx.wear.tiles.TileService.getUpdater(context)
            .requestUpdate(PrayerTileService::class.java)
        }
      WatchPayload.PHONE_COUNTER -> WatchPayload.receiveCounter(context, raw)
    }
  }
}

class WatchDataService : WearableListenerService() {
  override fun onDataChanged(events: DataEventBuffer) {
    val store = WatchStore(this)
    for (event in events) if (event.type == DataEvent.TYPE_CHANGED)
      store.receive(event.dataItem.uri.path, event.dataItem.data)
  }
}
