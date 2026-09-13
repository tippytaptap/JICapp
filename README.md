# Community app

A configurable Flutter app sharing the existing React/Vite website and Supabase accounts. This installation uses Jamatia Islamic Centre branding. Feature/class names are generic; organisation identity belongs in configuration/assets and platform packaging.

## Run

Flutter 3.47.4 / Dart 3.13.3. Android Studio Emulator for Android; Xcode Simulator on macOS for iPhone and Apple Watch.

```sh
flutter pub get
flutter run --dart-define-from-file=config/public.json
flutter analyze
flutter test
```

`config/public.json` contains the current installation's public URL and anon client key. These identify the public backend; they grant no staff authority. The legacy `submit-form` gateway still requires this JWT-format anon key. Never put a service-role, provider secret or signing key in a client configuration.

The public build connects to the existing timetable/content/login/forms. Extended workspace and remote push flags remain off until the additive backend migrations and provider configuration are deployed. For another organisation or a staging backend, copy `config/example.json` to ignored `config/local.json`, supply that deployment's public settings, then run with `--dart-define-from-file=config/local.json`.

## Features

- Published prayers and reminders, events/announcements, approved images, adult programme posters and weekly schedule; separate adult/madrasah course spaces.
- Quran 114-surah reading/search, per-ayah bookmarks/position and explicit native offline downloads; approved Dalail/Hizb/hadith/dhikr collections with offline text; Tasbih goals/history/haptics and private encrypted Salah plans; on-demand Qibla.
- Radio and sermon archive using one background media player, lock-screen controls and sleep settings; reviewed speech summaries, source-linked quotations and approved quote cards.
- Shared accounts and owner/delegated user administration; custom conditional form builder, responsible people/watchers, photo/file uploads, replies, filtered collated inbox, CSV/ZIP and assigned actions.
- Fee ledger with due/outstanding balances, audited manual receipts and corrections; optional verified payment webhook. Optional reviewed email dispatch and quarantined inbound replies complement push.
- Native learning management, linked guardians, department heads, enrolments/teachers, registers, numeric assessments, progress/plans, resources, meeting requests and moderated student poetry.
- Android/iOS prayer widgets, Wear OS and Apple Watch companion apps with prayer surfaces, Tasbih handoffs and Qibla. Watches receive public prayer data and explicitly transferred counters.

The website companion lives on `jicuser/website`, branch `feat/community-workspace`. It owns shared migrations, edge functions and server workers. Existing private mosque-screen/pairing/poster/YouTube/local-camera gateway source is retained. `docs/STATUS.md` records source and release verification; `docs/PLAN.md` retains the scope; `docs/READING.md`, `docs/WATCHES.md` and `docs/NOTIFICATIONS.md` explain content and platform setup.

## Build and release

CI runs Dart analysis/tests, builds Flutter web and an Android debug APK, compiles Wear OS, and builds iPhone/watch simulators on macOS. A passing build is required before using its artifact; simulator compilation does not sign an App Store release or verify paired-device behaviour.

Deploy/test the companion migrations before setting `ENABLE_EXTENSIONS=true`; configure Firebase/APNs and the server push worker before `ENABLE_PUSH=true`. Store signing, developer account identifiers, managed-backend rollout, optional provider secrets and hardware verification remain explicit release setup. No production schema change, real email send, paid AI request or store submission is performed by this source change.

## Reuse

Edit `assets/organisation.json`, replace branding and `config/public.json`, then set platform display names, bundle identifiers and App Groups for the chosen developer account. `com.mastir.community_app` is a development identifier. Use a separate backend for each organisation; the code does not provide shared-database multi-tenant isolation.

Verified source `03a8f024`: all four native targets passed in [CI run34755740646](https://github.com/tippytaptap/JICapp/actions/runs/34755740646). Download `android-preview` for the phone APK or `wear-os-preview` for the watch APK. App analysis/51 tests and the shared website/269 tests passed. The preview uses existing public backend settings; new workspace and remote-push flags remain off pending the documented rollout.
