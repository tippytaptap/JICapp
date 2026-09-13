package com.mastir.community_app.wear

import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.*
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.text.SimpleDateFormat
import java.util.*

class PrayerTileService : TileService() {
  override fun onTileRequest(
    requestParams: RequestBuilders.TileRequest
  ): ListenableFuture<TileBuilders.Tile> {
    val store = WatchStore(this)
    val cache = store.timeline()
    val rows = cache?.optJSONArray("prayers")
    val now = System.currentTimeMillis()
    val next =
      (0 until (rows?.length() ?: 0))
        .map { rows!!.getJSONObject(it) }
        .filter { it.optLong("at") > now }
        .minByOrNull { it.optLong("at") }
    val time =
      if (next == null) "Open phone to refresh"
      else
        SimpleDateFormat("HH:mm", Locale.getDefault())
          .apply { timeZone = TimeZone.getTimeZone(cache!!.optString("timeZone", "UTC")) }
          .format(Date(next.optLong("at")))
    fun line(text: String, size: Float) =
      LayoutElementBuilders.Text.Builder()
        .setText(text)
        .setMaxLines(2)
        .setFontStyle(
          LayoutElementBuilders.FontStyle.Builder()
            .setSize(DimensionBuilders.sp(size))
            .setColor(ColorBuilders.argb(0xffefece3.toInt()))
            .build()
        )
        .build()
    val launch =
      ActionBuilders.LaunchAction.Builder()
        .setAndroidActivity(
          ActionBuilders.AndroidActivity.Builder()
            .setPackageName(packageName)
            .setClassName(WatchActivity::class.java.name)
            .build()
        )
        .build()
    val layout =
      LayoutElementBuilders.Column.Builder()
        .addContent(line(cache?.optString("organisation", "Community") ?: "Community", 14f))
        .addContent(line(next?.optString("name") ?: "Prayer times", 22f))
        .addContent(line(time, 22f))
        .addContent(line("Tap to open", 12f))
        .setModifiers(
          ModifiersBuilders.Modifiers.Builder()
            .setClickable(
              ModifiersBuilders.Clickable.Builder().setId("open").setOnClick(launch).build()
            )
            .build()
        )
        .build()
    val timeline =
      TimelineBuilders.Timeline.Builder()
        .addTimelineEntry(
          TimelineBuilders.TimelineEntry.Builder()
            .setLayout(LayoutElementBuilders.Layout.Builder().setRoot(layout).build())
            .build()
        )
        .build()
    return Futures.immediateFuture(
      TileBuilders.Tile.Builder()
        .setResourcesVersion("1")
        .setTileTimeline(timeline)
        .setFreshnessIntervalMillis(
          if (next == null) 900000 else (next.optLong("at") - now + 1000).coerceAtLeast(1000)
        )
        .build()
    )
  }

  override fun onTileResourcesRequest(
    requestParams: RequestBuilders.ResourcesRequest
  ): ListenableFuture<ResourceBuilders.Resources> =
    Futures.immediateFuture(ResourceBuilders.Resources.Builder().setVersion("1").build())
}
