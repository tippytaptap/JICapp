# Watch companions

The repository contains two native watch apps, not a Flutter screen copied onto a watch:

| Target | Minimum | Build |
| --- | --- | --- |
| Android `:wear` | Wear OS 3 / Android API 30 | `cd android && ./gradlew :wear:assembleDebug` |
| Xcode `CommunityWatch` | watchOS 10 | Select the shared CommunityWatch scheme and a paired watch simulator |
| Xcode `WatchWidgets` | watchOS 10 | Built and embedded by CommunityWatch |

The existing Android phone app, iPhone app and phone prayer widgets are preserved. CI is configured separately by the app integration work; check the actual CI run before treating a binary as tested.

## Working features

- Tasbih count and targets 33/99/100 persist locally on each watch. Taps and completed rounds provide haptics. Undo and confirmed reset are available offline.
- The public mosque timetable travels from the phone through the authenticated paired-device transport. The watch displays the next prayer and upcoming times in the mosque’s timezone. Expired/absent data asks the user to refresh the phone; no timetable is invented.
- A Wear OS Tile and Apple Watch face complication display the cached next prayer. They launch the companion app. The Apple complication schedules transitions at cached prayer boundaries; the Wear Tile asks the OS to refresh at the next prayer. The OS controls exact refresh timing.
- Qibla requests location only after tapping Find direction. It uses one location fix and a foreground compass sensor, applies true-north correction, and stops on leaving the screen/backgrounding. Devices without a compass show the true-north bearing with an explicit explanation. Permissions denied, missing sensors and location timeout are visible states.
- Public prayer sync is automatic when the phone refreshes. It sends organisation name, timezone and prayer timestamps only.
- Tasbih sync is an explicit handoff. Tap Send to phone/watch, then Import on the other device and confirm replacement. The two counts are never silently added together or overwritten by background delivery.

## Handoff contract

Channel: `community/watch`.

- `publishTimeline(String json)`: `{organisation, timeZone, prayers:[{name,at}]}`; `at` is epoch milliseconds.
- `publishCounter(String json)`: `{sourceId,sessionId,revision,count,target}`.
- `getIncomingCounter()`: an optional pending JSON snapshot.
- `clearIncomingCounter(String json)`: clear only that exact imported snapshot; preserve a newer delivery.

Each sender persists a random source ID and monotonically increasing revision. Receivers discard duplicate/older revisions from that source/session. Retries cannot double-increment a count. A snapshot is pending until the user chooses to replace their current local counter. Pending and public data are locally cached for disconnected use. A successful send means accepted locally for transport, not confirmed receipt.

Android uses `play-services-wearable` DataClient/DataItems with identical application ID and signing certificate on phone and watch. The platform limits access to the paired app. iOS/watchOS uses WCSession application context for the paired companion. Never add Supabase sessions, notification tokens, staff tasks, student records, private forms or location coordinates to these payloads. App Group defaults share only between watch app and complication on the watch; WatchConnectivity performs the phone transfer.

## Identity and release

Current development identifiers:

- Android phone and watch: `com.mastir.community_app` (must match, including signing certificate).
- iPhone: `com.mastir.communityApp`.
- Apple Watch: `com.mastir.communityApp.watchapp`.
- Watch complication: `com.mastir.communityApp.watchapp.widgets`.
- App Group: `group.com.mastir.communityApp`.

Before a signed release, register these identifiers under the chosen developer account, enable App Groups for all relevant Apple targets, select the signing team, and use a matching Android release signing key for phone and Wear builds. Display branding is supplied by the phone; the independent launcher name is generic Community until final organisation packaging. The watch targets do not require Firebase credentials or any backend login.

## Validation

Locally verified: Dart analysis, three transport/handoff tests, Xcode project graph and plist/scheme parsing. Native watch builds require the Android CI and macOS Xcode CI outputs. This Linux workspace cannot claim an Apple device test or store-ready signing. Physical paired-device checks remain necessary for delivery after disconnection, watch replacement, foreground compass calibration, haptic feel, complication refresh and small/round displays.

## Official references

- [Wear Data Layer synchronization](https://developer.android.com/training/wearables/data/sync)
- [Wear Data Layer listeners](https://developer.android.com/training/wearables/data/events)
- [Wear Tiles versions and APIs](https://developer.android.com/jetpack/androidx/releases/wear-tiles)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Apple WidgetKit complications](https://developer.apple.com/documentation/widgetkit/widgets-and-complications-collection)
- [Core Location heading updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatingheading())
