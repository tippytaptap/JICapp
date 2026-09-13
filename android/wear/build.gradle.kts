plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "com.mastir.community_app.wear"
  compileSdk = 36
  defaultConfig {
    // Matching package and signing certificate authenticate the Data Layer.
    applicationId = "com.mastir.community_app"
    minSdk = 30
    targetSdk = 36
    versionCode = 1000001
    versionName = "1.0.0"
  }
  sourceSets.getByName("main").java.srcDir("../watch-shared/src/main/kotlin")
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }

dependencies {
  implementation("com.google.android.gms:play-services-wearable:20.0.1")
  implementation("androidx.wear.tiles:tiles:1.6.2")
  implementation("androidx.wear.protolayout:protolayout:1.4.2")
  implementation("com.google.guava:guava:33.4.8-android")
}
