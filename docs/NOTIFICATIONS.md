# App notifications

This source implements local prayer reminders and account device registration for the shared Supabase workspace. No production push credentials, sender schedule, notification send or physical-device delivery test was performed while writing it. Web previews deliberately do not initialise Firebase or ask for notification permission.

## Behaviour

- Prayer reminders have separate, device-local consent and work without signing in. Only the centre's published `*_begins` times are used. Seven centre calendar dates produce at most 35 alerts; absent and malformed times produce no alerts. The centre timezone, including daylight-saving changes, determines each instant.
- Opening the app refreshes the schedule. An unchanged timetable has a stable signature, so the minute refresh does not continually cancel and schedule alerts. No background timetable fetch is promised. Users should open the app at least weekly to refresh the next seven dates.
- Android uses `inexactAllowWhileIdle`; no exact-alarm permission is requested. Battery restrictions, notification permissions and operating-system policy can delay or suppress alerts. These reminders are not an exact alarm clock or a replacement for the displayed timetable.
- Prayer IDs 6100–6134 and foreground account alert ID 6200 are reserved. Disabling reminders cancels only the prayer IDs. The radio notification is never cancelled by notification preferences.
- Account push requires both `ENABLE_EXTENSIONS=true` and `ENABLE_PUSH=true`, an active shared Supabase account, deployed registration RPCs, and native Firebase configuration. Consent is saved per account on this phone. Native FCM auto-init and Android analytics collection start disabled. The service only enables FCM auto-init after consent, notification permission and an active-account check.
- iOS checks that an APNs token exists before requesting its FCM token. An unavailable token gives a retry message rather than crashing the app.
- The registered FCM token and its account owner are kept in secure device storage. Registration uses `register_push_device(p_token, p_platform, p_previous_token)`, never a user-supplied recipient. Token refresh replaces the caller's previous token atomically, including at the device limit. A failed replacement preserves the old registration. The server rejects rebinding a token from another account.
- Explicit sign-out unregisters while its Supabase session still exists, disables auto-init and deletes the FCM token. Account changes invalidate in-flight work immediately. A device changing accounts must delete its previous native token before registering another account. Removal failures remain visible and do not prevent signing out; a retained secure binding requires another cleanup attempt. A stale server row can remain after an offline sign-out until the sender removes its invalid endpoint.
- Foreground account alerts replace message text with a generic update. Background alerts use the push worker's generic notification payload; never send private text in an FCM notification payload, because the operating system may display it directly. The app does not trust a push payload to choose a private record, external URL or current user.
- Tapping either a local foreground alert or a remote alert opens the account updates inbox behind the live account gate. Tapping a prayer reminder opens current prayer times. Taps do not mark a task done. Server RLS remains authoritative after sign-in and on every inbox read.

## Dart wiring

`NotificationService(organisation, client, preferences, onOpenInbox: ..., onOpenPrayers: ...)` is a `ChangeNotifier`.

| Call | When |
| --- | --- |
| `initialise()` | After Flutter/plugin startup; initialises local notifications without asking permission and captures notification launch intent. |
| `syncAccount(activeAccount: active(profile))` | Immediately when account ID changes, then after the current profile is confirmed. Do not interpret a temporary loading indicator as a confirmed disabled account. |
| `refreshPrayerSchedule(prayers)` | After public timetable refresh, including an empty result. |
| `prepareForSignOut()` | Before `auth.signOut(scope: SignOutScope.local)`; errors are recorded on the service and logout can continue. |
| `dispatchPendingOpen()` | After attaching navigator callbacks if initial launch processing ran first. |
| `dispose()` | When the application service is destroyed. |

`NotificationSettingsPage(state, service)` exposes both switches, connection retry, scheduled reminder count and visible errors. Its prayer settings remain accessible while signed out. Inbox callbacks must use `showPrivatePage(context, state, UpdatesPage(state))` or an equivalent current-session gate. Never navigate directly to a payload's entity ID.

## Native setup before enabling push

Use the new organisation's Firebase and Apple developer accounts. The display name is configuration; Android application ID, Apple bundle ID and widget App Group must be chosen together before provisioning.

1. Register the Android application and iOS bundle in the organisation's Firebase project. Download Android `google-services.json` to `android/app/` and add iOS `GoogleService-Info.plist` to the Runner target with target membership and Copy Bundle Resources. This service calls `Firebase.initializeApp()` using those native defaults. If choosing FlutterFire-generated `firebase_options.dart` instead, deliberately change that one initialisation call to pass `DefaultFirebaseOptions.currentPlatform`; do not initialise Firebase unconditionally in `main.dart`.
2. For native Android default configuration, add the Google services Gradle plugin. At the time checked, the official setup lists version 4.5.0. In `android/settings.gradle.kts`'s `plugins` block add `id("com.google.gms.google-services") version "4.5.0" apply false`. In `android/app/build.gradle.kts`, after the `plugins` block, apply `if (file("google-services.json").exists()) { apply(plugin = "com.google.gms.google-services") }`. This conditional keeps an unconfigured preview build usable. Flutter's pinned Firebase plugins already provide their native dependencies; do not add Firebase Auth or a second account database.
3. Keep `firebase_messaging_auto_init_enabled=false` and `firebase_analytics_collection_enabled=false` in the Android application metadata. Keep `FirebaseMessagingAutoInitEnabled=false` in iOS Info.plist. Do not disable Apple method swizzling.
4. Enable Push Notifications and remote-notification background capability for the Runner target in Xcode. Provision the resulting `aps-environment` entitlement using the chosen Apple team. Upload that team's APNs authentication key to Firebase. Test with a physical iPhone signed for that team.
5. Apply and test the additive Supabase workspace migration in staging. Configure the server-side push worker's secrets and scheduler as described in the website's `docs/community-workspace-api.md`. Its service account, service-role key and worker secret belong only to the server. Enable the two app feature flags only for a build configured against that tested deployment.

Firebase project configuration identifies a project; it is not the Firebase service-account private key. Provisioning keys, APNs keys, service-role keys and server credentials must never be included in Dart defines, bundled files, client source or screenshots.

## Local notification platform integration

Android must retain `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED`. Inside `<application>`, the local notification plugin requires:

```xml
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED" />
    <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
    <action android:name="android.intent.action.QUICKBOOT_POWERON" />
    <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
  </intent-filter>
</receiver>
```

Java 17 and core-library desugaring are already configured in this app. No full-screen intent, exact-alarm, notification-action or additional foreground-service declaration is needed for this feature.

For local notification presentation on iOS, import `UserNotifications` and set `UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate` in AppDelegate's `didFinishLaunchingWithOptions` before calling `super`. Keep Flutter's implicit-engine plugin registration and the audio background mode intact.

## Verification

The reminder planner tests exercise the seven-day/35-alert cap, invalid/elapsed/duplicate times, the autumn daylight-saving transition and timetable signatures. Dart analysis checks the installed plugin APIs. These checks do not demonstrate actual push delivery, native permission prompts, notification tap navigation or reboot restoration.

Before release, use two staging accounts to exercise enable/disable, token refresh, denied permission, offline sign-out, account switching and tapping an older account's alert. Confirm that the old account cannot receive newly created alerts on the new account's endpoint and cannot expose private content through a tap. Check foreground/background/terminated behaviour, iOS APNs readiness, Android reboot/Doze and daylight-saving prayer scheduling on devices. The sender must enforce generic text even if a task contains a student's name or payment details.

Android Studio Emulator with a Google Play system image is suitable for Android development. Use Xcode Simulator on a Mac for iOS UI work, and physical devices for notification and release behaviour.

## Sources checked

- [Supabase push notifications example](https://supabase.com/docs/guides/functions/examples/push-notifications)
- [FCM Flutter setup, APNs and auto-init](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)
- [Firebase Flutter project configuration](https://firebase.google.com/docs/flutter/setup)
- [Firebase Android setup and Google services plugin](https://firebase.google.com/docs/android/setup)
- Installed `flutter_local_notifications` 22.3.1 README and Dart API source, which use named `initialize`, `show`, `cancel` and `zonedSchedule` parameters.
