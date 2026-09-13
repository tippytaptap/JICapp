# Prayer widgets

Native source is included for Android and iOS. Widgets show the next published **prayer start time** in the organisation's timezone. They do not display private accounts, tasks, student records, or missed-prayer counts.

| Platform | Included source | Verification still required |
| --- | --- | --- |
| Android | Home-screen widget, prayer link, Tasbih link, OS-scheduled updates from cached times | Emulator/device build, launcher sizing, reboot, battery saver, tap routing |
| iOS 16+ | WidgetKit extension and target: small/medium home-screen and inline/circular/rectangular lock-screen families | Xcode build, signing, App Group registration, simulator/device timeline and tap routing |
| Apple Watch | Planned: next prayer complication, reminders, Tasbih with haptics, Qibla where sensors support it | Watch app and target are not implemented |
| Wear OS | Planned: next prayer tile/complication, Tasbih and reminders | Watch app and target are not implemented |

Android lock-screen placement depends on the OS and device launcher. Declaring the `keyguard` category does not make it available on every phone. Apple Watch support is a separate native deliverable; an iPhone lock-screen widget is not a watch app.

## Data and update behaviour

`PrayerWidgetService.update(organisation, days)` converts public timetable rows into this shared JSON value:

```json
{"organisation":"Community centre","timeZone":"Europe/London","prayers":[{"name":"Fajr","at":1790000000000}]}
```

The storage key is `prayer_timeline`. `at` is epoch milliseconds. The example is a format illustration, not a timetable to publish. The Flutter app refreshes the cache when it downloads the public timetable, then requests an immediate widget update. Identical payloads are skipped within the running app, so foreground minute refreshes do not repeatedly write data or reschedule alarms. Failed native updates remain retryable.

Android uses `home_widget`'s scheduled-update receiver and native alarms; iOS supplies future entries to WidgetKit. Neither widget continuously polls a server, runs a radio stream, or keeps Flutter alive. Updates are best effort and may be delayed by the OS; widgets are not exact prayer alarms. When the cached timetable runs out, the widget says to open the app to refresh instead of presenting an old time as current.

The whole widget opens `community://prayers`. Android's Tasbih link and the iOS medium widget's Tasbih link open `community://tasbih`. Native links include `?homeWidget=1`, required by the iOS plugin to forward widget taps. The app must handle `PrayerWidgetService.initialLink()` and `PrayerWidgetService.links` and reject unrecognised routes.

## Apple setup

The `PrayerWidget` target is embedded by Runner. No Apple team or signing certificate is stored here. Before a device or App Store build:

1. Open `ios/Runner.xcworkspace` on a Mac with Xcode after Flutter dependency setup.
2. Select the same development team for Runner and PrayerWidget.
3. Register **group.com.mastir.communityApp** in the team's App Groups and enable it for both targets. It must match `Runner.entitlements`, `PrayerWidget.entitlements`, the Swift source and `PrayerWidgetService.appGroup`.
4. Register the app bundle `com.mastir.communityApp` and extension bundle `com.mastir.communityApp.PrayerWidget`, or change them together for the organisation/company's final identifiers. The extension bundle must be prefixed by the app bundle.
5. Build/run Runner, download its timetable, then add the widget. Test cold-start and already-running links. Test in the organisation's timezone and with the phone set to a different timezone.

The host currently supports iOS 15; this WidgetKit extension requires iOS 16 for lock-screen accessory families. There is no widget on iOS 15. The widget has no independent network or Firebase credentials.

## Release checks

- Home/lock layouts with large text, light/dark appearance and different widget sizes.
- Correct next prayer across midnight and a daylight-saving transition; both the day and time use the organisation's timezone.
- Exhausted/missing/corrupt cache shows an honest refresh state.
- Refreshing the timetable replaces pending Android update times and the iOS timeline.
- Android reboot and app update restore scheduled updates; removing all widgets does not poll in the background.
- Locked-phone widgets reveal no private information.
- Test prayer reminders independently; widget timeline updates are not notifications.

References: [Android widget update guidance](https://developer.android.com/develop/ui/views/appwidgets/advanced), [Apple WidgetKit timelines](https://developer.apple.com/documentation/widgetkit/timelineprovider), and the installed `home_widget` 0.9.4 provider/scheduling APIs.

## Checks completed in this workspace

Dart analysis passes for the widget bridge. Android XML and iOS property lists/entitlements parse successfully. An Xcode project parser verifies that Runner depends on and embeds the PrayerWidget target and that every target build configuration resolves. These are source/structure checks, not an Xcode or device build.
