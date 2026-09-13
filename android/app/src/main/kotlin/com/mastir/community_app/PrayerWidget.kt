package com.mastir.community_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Displays only the public timetable already downloaded by the app. */
class PrayerWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload = runCatching {
            JSONObject(widgetData.getString("prayer_timeline", "{}") ?: "{}")
        }.getOrDefault(JSONObject())
        val prayers = payload.optJSONArray("prayers")
        val now = System.currentTimeMillis()
        val upcoming = (0 until (prayers?.length() ?: 0)).mapNotNull { index ->
            prayers?.optJSONObject(index)?.takeIf { it.optLong("at") > now }
        }.minByOrNull { it.optLong("at") }
        val zone = TimeZone.getTimeZone(payload.optString("timeZone", "UTC"))
        val time = SimpleDateFormat("h:mm a", Locale.getDefault()).apply { timeZone = zone }
        val date = SimpleDateFormat("EEE d MMM", Locale.getDefault()).apply { timeZone = zone }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.prayer_widget)
            views.setTextViewText(R.id.widget_organisation, payload.optString("organisation", "Prayer times"))
            views.setTextViewText(R.id.widget_prayer, upcoming?.optString("name") ?: "Prayer times")
            views.setTextViewText(R.id.widget_time, upcoming?.let { time.format(Date(it.optLong("at"))) } ?: "Open app to refresh")
            views.setTextViewText(R.id.widget_date, upcoming?.let { date.format(Date(it.optLong("at"))) } ?: "Timetable unavailable")
            views.setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("community://prayers?homeWidget=1")))
            views.setOnClickPendingIntent(R.id.widget_tasbih, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("community://tasbih?homeWidget=1")))
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
