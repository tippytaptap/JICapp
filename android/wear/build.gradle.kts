import java.util.Properties

plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
}

val flutterVersion = Properties().apply {
  rootProject.file("local.properties").inputStream().use { load(it) }
}
val phoneVersionCode = (flutterVersion.getProperty("flutter.versionCode") ?: "1").toInt()
require(phoneVersionCode in 1..999999) { "Phone build number must be between 1 and 999999 for the separate Wear version range." }

android {
  namespace = "com.mastir.community_app.wear"
  compileSdk = 36
  defaultConfig {
    // Matching package and signing certificate authenticate the Data Layer.
    applicationId = "com.mastir.community_app"
    minSdk = 30
    targetSdk = 36
    versionCode = 1000000 + phoneVersionCode
    versionName = flutterVersion.getProperty("flutter.versionName") ?: "1.0.0"
  }
  sourceSets.getByName("main").java.srcDir("../watch-shared/src/main/kotlin")
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

apply(from = rootProject.file("release-signing.gradle"))

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

dependencies {
  implementation("com.google.android.gms:play-services-wearable:20.0.1")
  implementation("androidx.wear.tiles:tiles:1.6.2")
  implementation("androidx.wear.protolayout:protolayout:1.4.2")
  implementation("com.google.guava:guava:33.4.8-android")
}
