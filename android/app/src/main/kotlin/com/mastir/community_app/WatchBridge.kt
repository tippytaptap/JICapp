package com.mastir.community_app

import android.content.Context
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.mastir.community_app.shared.WatchPayload
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class WatchBridge(context: Context, messenger: BinaryMessenger) {
  init {
    val app = context.applicationContext
    val prefs = app.getSharedPreferences(WatchPayload.PREFS, Context.MODE_PRIVATE)
    MethodChannel(messenger, "community/watch").setMethodCallHandler { call, result ->
      when (call.method) {
        "getIncomingCounter" -> result.success(prefs.getString("incomingCounter", null))
        "clearIncomingCounter" -> {
          // Clear only the imported snapshot; a newer arrival remains available.
          if (prefs.getString("incomingCounter", null) == call.arguments as? String) {
            prefs.edit().remove("incomingCounter").apply()
          }
          result.success(null)
        }
        "publishTimeline",
        "publishCounter" -> {
          val payload = call.arguments as? String ?: ""
          val timeline = call.method == "publishTimeline"
          if (
            if (timeline) !WatchPayload.validTimeline(payload)
            else !WatchPayload.validCounter(payload)
          ) {
            result.error("payload", "The watch data could not be read.", null)
          } else {
            val path = if (timeline) WatchPayload.PRAYERS else WatchPayload.PHONE_COUNTER
            val request = PutDataRequest.create(path).setData(payload.toByteArray())
            if (!timeline) request.setUrgent()
            Wearable.getDataClient(app)
              .putDataItem(request)
              .addOnSuccessListener { result.success(null) }
              .addOnFailureListener {
                result.error("watch_unavailable", "Connect your paired watch and try again.", null)
              }
          }
        }
        else -> result.notImplemented()
      }
    }
  }
}

class PhoneWatchDataService : WearableListenerService() {
  override fun onDataChanged(events: DataEventBuffer) {
    for (event in events) {
      if (
        event.type != DataEvent.TYPE_CHANGED ||
          event.dataItem.uri.path != WatchPayload.WATCH_COUNTER
      )
        continue
      val bytes = event.dataItem.data ?: continue
      if (bytes.size <= 2000) WatchPayload.receiveCounter(this, bytes.toString(Charsets.UTF_8))
    }
  }
}
