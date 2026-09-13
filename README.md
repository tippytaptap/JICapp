# Community app

A configurable Flutter app using the existing React/Vite website and Supabase accounts. This installation uses Jamatia Islamic Centre’s approved branding. Feature names are generic; organisation identity lives in configuration and assets.

## Run

Flutter 3.47.4 / Dart 3.13.3. Android Studio provides the Android emulator; iPhone Simulator requires Xcode on macOS.

```sh
flutter pub get
cp config/example.json config/local.json
# Fill in the public Supabase URL and client key.
flutter run --dart-define-from-file=config/local.json
flutter analyze
flutter test
flutter build web --no-web-resources-cdn --no-tree-shake-icons
```

The existing `submit-form` gateway uses legacy JWT verification: use the compatible anon client key until that gateway is explicitly migrated. Never use a service-role or secret key in a client. Local connection settings and signing/Firebase secrets are ignored by git.

An unconfigured build is a public preview with bundled posters. It does not invent live prayers, student data or submissions. The web target previews Flutter UI; the React website remains the public website.

## Current source checkpoint

Home and published prayer times, adult courses and weekly schedule, Qur’an Arabic/English reader with font size/bookmark, referenced reading collections, persistent Tasbih, private device Salah record, on-demand Qibla, radio media-session/sleep controls, same-account login, native contact/madrasah enquiry, private paginated forms inbox and CSV/share/call/email-draft actions.

The optional shared workspace adds form-linked tasks, deadlines, status totals, a separate updates inbox, course registers, progress/plans/assessments, meetings and moderated student poetry/reflections. Website owners configure courses, enrolments, teaching assignments and automatic form routing. Student and staff access uses server row-level security.

Android prayer widgets and the embedded iOS WidgetKit target share only published prayer times and open prayer/Tasbih views. Notification settings provide explicit per-account FCM consent and local prayer reminders from the published timetable. See `docs/NOTIFICATIONS.md` and `docs/WIDGETS.md` for setup and physical-device checks.

Apply and test the companion website migration before enabling `ENABLE_EXTENSIONS`; enable `ENABLE_PUSH` only after Firebase/APNs setup. The companion source is on `jicuser/website` branch `feat/community-workspace`, with its API contract in `docs/community-workspace-api.md`. No production database changes or push delivery were performed by this source change.

`docs/PLAN.md` retains the full scope and `docs/STATUS.md` distinguishes implemented source from remaining work. `docs/RECOVERY.md` records the earlier lost working copy; its test results must not be mistaken for validation of this code.

Native radio/notifications/location need physical-device testing. Store signing and Firebase/APNs setup are not complete. The CI workflow attempts a debug Android build and produces an artifact only if successful; its preview build has no production connection settings.

## Reuse

Edit `assets/organisation.json`, replace the bundled branding, and set your own backend/public settings. Update platform display names and bundle identifiers before publishing. The current `com.mastir.community_app` identifier is developmental; final company spelling and store identity remain to be confirmed. Reuse with a separate backend per organisation. This is not a shared-database multi-tenant system.
