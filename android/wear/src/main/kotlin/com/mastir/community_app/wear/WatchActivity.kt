package com.mastir.community_app.wear

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.*
import android.location.LocationManager
import android.os.*
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.widget.*
import com.google.android.gms.wearable.Wearable
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.*
import org.json.JSONObject

/** Native watch screen: no Flutter engine, polling, wake locks or background GPS. */
class WatchActivity :
  Activity(), SensorEventListener, SharedPreferences.OnSharedPreferenceChangeListener {
  private lateinit var store: WatchStore
  private lateinit var list: LinearLayout
  private var page = "home"
  private val handler = Handler(Looper.getMainLooper())
  private var cancellation: CancellationSignal? = null
  private var bearing: Double? = null
  private var declination = 0f
  private var compass: TextView? = null
  private val sensors by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }
  private val refresh =
    object : Runnable {
      override fun run() {
        if (page == "home") home()
        handler.postDelayed(this, 60000)
      }
    }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    store = WatchStore(this)
    Wearable.getDataClient(this).dataItems.addOnSuccessListener { buffer ->
      try {
        for (item in buffer) store.receive(item.uri.path, item.data)
      } finally {
        buffer.release()
      }
    }
    home()
  }

  override fun onResume() {
    super.onResume()
    store.prefs.registerOnSharedPreferenceChangeListener(this)
    handler.postDelayed(refresh, 60000)
  }

  override fun onPause() {
    super.onPause()
    stopCompass()
    if (page == "qibla") compass?.text = "Tap Find direction to refresh the compass."
    handler.removeCallbacks(refresh)
    store.prefs.unregisterOnSharedPreferenceChangeListener(this)
  }

  override fun onSharedPreferenceChanged(prefs: SharedPreferences?, key: String?) {
    if (key == "timeline" || key == "incomingCounter")
      runOnUiThread { if (page == "home") home() else if (page == "tasbih") tasbih() }
  }

  private fun screen(name: String) {
    stopCompass()
    page = name
    val scroll = ScrollView(this)
    list =
      LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(26, 30, 26, 35)
      }
    scroll.addView(list)
    setContentView(scroll)
  }

  private fun label(value: String, size: Float = 16f): TextView =
    TextView(this).apply {
      text = value
      textSize = size
      gravity = Gravity.CENTER
      setTextColor(0xffefece3.toInt())
      setPadding(0, 6, 0, 6)
      list.addView(this)
    }

  private fun button(value: String, action: () -> Unit): Button =
    Button(this).apply {
      text = value
      isAllCaps = false
      minHeight = 48
      setOnClickListener { action() }
      list.addView(this, LinearLayout.LayoutParams(-1, -2))
    }

  private fun home() {
    screen("home")
    val timeline = store.timeline()
    label(timeline?.optString("organisation", "Community") ?: "Community", 18f)
    val rows = timeline?.optJSONArray("prayers")
    val upcoming =
      (0 until (rows?.length() ?: 0))
        .map { rows!!.getJSONObject(it) }
        .filter { it.optLong("at") > System.currentTimeMillis() }
        .sortedBy { it.optLong("at") }
    if (upcoming.isEmpty()) label("Open the phone app to refresh prayer times.")
    else {
      val formatter =
        SimpleDateFormat("EEE HH:mm", Locale.getDefault()).apply {
          timeZone = TimeZone.getTimeZone(timeline!!.optString("timeZone", "UTC"))
        }
      val next = upcoming.first()
      label("Next: ${next.optString("name")}", 22f)
      label(formatter.format(Date(next.optLong("at"))), 25f)
      label("Mosque time • saved on watch", 12f)
      if (System.currentTimeMillis() - store.prefs.getLong("receivedAt", 0) > 86400000L)
        label("Saved over a day ago. Open phone to refresh.", 12f)
      button("Prayer times") {
        screen("prayers")
        label("Prayer times")
        upcoming.take(15).forEach {
          label("${it.optString("name")}  ${formatter.format(Date(it.optLong("at")))}")
        }
        button("Back") { home() }
      }
    }
    button("Tasbih") { tasbih() }
    button("Qibla") { qibla() }
  }

  private fun tasbih() {
    screen("tasbih")
    label("Tasbih", 20f)
    val count = button("${store.count}\nTap +1") {}
    count.textSize = 28f
    count.setOnClickListener {
      store.count += 1
      count.text = "${store.count}\nTap +1"
      count.performHapticFeedback(
        if (store.count % store.target == 0) HapticFeedbackConstants.LONG_PRESS
        else HapticFeedbackConstants.CLOCK_TICK
      )
    }
    label("Target ${store.target}")
    button("Undo −1") {
      store.count -= 1
      count.text = "${store.count}\nTap +1"
    }
    button("Change target") {
      AlertDialog.Builder(this)
        .setItems(arrayOf("33", "99", "100")) { _, n ->
          store.target = listOf(33, 99, 100)[n]
          tasbih()
        }
        .show()
    }
    button("Reset") {
      AlertDialog.Builder(this)
        .setMessage("Reset this watch count?")
        .setNegativeButton("Keep", null)
        .setPositiveButton("Reset") { _, _ ->
          store.count = 0
          tasbih()
        }
        .show()
    }
    button("Send to phone") {
      store.send { success ->
        Toast.makeText(
            this,
            if (success) "Saved for phone. Import it in phone Tasbih."
            else "Could not send. Try again.",
            Toast.LENGTH_LONG,
          )
          .show()
      }
    }
    val incoming = store.prefs.getString("incomingCounter", null)
    if (incoming != null)
      button("Import phone count") {
        val obj = JSONObject(incoming)
        AlertDialog.Builder(this)
          .setMessage(
            "Replace ${store.count} with ${obj.getInt("count")}? Counts are not added together."
          )
          .setNegativeButton("Keep", null)
          .setPositiveButton("Replace") { _, _ ->
            store.count = obj.getInt("count")
            store.target = obj.getInt("target")
            if (store.prefs.getString("incomingCounter", null) == incoming)
              store.prefs.edit().remove("incomingCounter").commit()
            tasbih()
          }
          .show()
      }
    button("Back") { home() }
  }

  private fun qibla() {
    screen("qibla")
    label("Qibla", 20f)
    compass = label("Uses your location once. Keep the watch flat, away from metal.")
    button("Find direction") {
      if (
        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
          PackageManager.PERMISSION_GRANTED
      ) {
        requestPermissions(
          arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
          ),
          17,
        )
      } else locate()
    }
    button("Back") { home() }
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    if (requestCode == 17 && page == "qibla") {
      if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) locate()
      else compass?.text = "Location permission is off. You can enable it in watch settings."
    }
  }

  private fun locate() {
    stopCompass()
    compass?.text = "Finding your position…"
    val manager = getSystemService(LOCATION_SERVICE) as LocationManager
    val provider =
      if (
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
          PackageManager.PERMISSION_GRANTED &&
          manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
      )
        LocationManager.GPS_PROVIDER
      else LocationManager.NETWORK_PROVIDER
    if (!manager.isProviderEnabled(provider)) {
      compass?.text = "Enable watch location and try again."
      return
    }
    val request = CancellationSignal()
    cancellation = request
    try {
      manager.getCurrentLocation(provider, request, mainExecutor) { location ->
        if (page != "qibla" || request.isCanceled) return@getCurrentLocation
        if (location == null) {
          compass?.text = "Location unavailable. Try outdoors."
          return@getCurrentLocation
        }
        val phi = Math.toRadians(location.latitude)
        val dest = Math.toRadians(21.422487)
        val d = Math.toRadians(39.826206 - location.longitude)
        bearing =
          (Math.toDegrees(atan2(sin(d), cos(phi) * tan(dest) - sin(phi) * cos(d))) + 360) % 360
        declination =
          GeomagneticField(
              location.latitude.toFloat(),
              location.longitude.toFloat(),
              location.altitude.toFloat(),
              System.currentTimeMillis(),
            )
            .declination
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (sensor == null) {
          compass?.text =
            "Qibla ${bearing!!.roundToInt()}° from true north. This watch has no compass sensor."
        } else {
          compass?.text = "Qibla ${bearing!!.roundToInt()}° from true north. Calibrating…"
          sensors.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
        }
      }
    } catch (_: SecurityException) {
      compass?.text = "Location permission is needed."
    }
    handler.postDelayed(
      {
        if (cancellation === request) {
          request.cancel()
          if (bearing == null && page == "qibla") compass?.text = "Location timed out. Try again."
        }
      },
      20000,
    )
  }

  private fun stopCompass() {
    cancellation?.cancel()
    cancellation = null
    sensors.unregisterListener(this)
    bearing = null
  }

  override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
    if (accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE)
      compass?.text = "Move the watch gently to calibrate. Keep away from metal."
  }

  override fun onSensorChanged(event: SensorEvent) {
    val destination = bearing ?: return
    if (event.accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) return
    val matrix = FloatArray(9)
    val orientation = FloatArray(3)
    SensorManager.getRotationMatrixFromVector(matrix, event.values)
    SensorManager.getOrientation(matrix, orientation)
    val heading = (Math.toDegrees(orientation[0].toDouble()) + declination + 360) % 360
    val turn = ((destination - heading + 540) % 360) - 180
    compass?.text =
      if (abs(turn) < 7) "↑ Facing Qibla\n${destination.roundToInt()}° true north"
      else
        "Turn ${if (turn > 0) "right" else "left"} ${abs(turn).roundToInt()}°\nQibla ${destination.roundToInt()}° true north"
  }
}
