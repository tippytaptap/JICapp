# Mobile release

Deploy the shared backend and website first using `docs/RELEASE.md`. Then distribute signed phone/watch builds to testers. The existing GitHub `android-preview` and `wear-os-preview` artifacts are debug builds. They are useful for previews; they are not Play Store or App Store submissions.

## Prepare once

1. Use the chosen company's Google Play Console and Apple Developer accounts. Confirm the final company spelling and app identifiers before the first upload. Current development identifiers are recorded in `docs/WATCHES.md`; the iPhone widget also uses `com.mastir.communityApp.PrayerWidget`. Rename identifiers, App Groups and native references together if changing them.
2. Copy `config/public.json` to ignored `config/local.json`. Keep only its four public settings. After backend deployment and account/form smoke tests, set `ENABLE_EXTENSIONS` to `true`. Keep `ENABLE_PUSH` `false` until Firebase/APNs and a physical delivery test are ready.
3. Invitations and password setup use the website's `/admin/setup` flow. In Supabase Auth URL Configuration, allow the exact final website setup URL used by `manage-user`; its server setting is `JIC_SITE_URL`. Password help in the app opens the website's `/account/recovery` page. Test an invitation, forgotten-password email and password setup, then sign into the app with that account. Native `community://` links currently open widgets; they are not an implemented password-recovery flow.
4. Complete the store listings: approved launcher artwork, screenshots, support/privacy URLs, contact details, account/data-deletion route and accurate data-use declarations. Supply a restricted reviewer account and instructions for the private portal. Confirm the published library editions and rights. Test the signed app on real phone/watch pairs, including radio background/sleep, reminders, permission denial, sign-out, private uploads and counter transfer.

Run the non-publishing input check from the repository root:

```sh
python3 tool/release_preflight.py --source-only --config config/public.json
```

`--source-only` deliberately does not require signing. Remove it for the intended release platform after configuring credentials. Passing means inputs are present, not that Apple/Google have accepted the signing identity or app.

## Android and Wear OS

1. Securely retain the organisation's upload keystore. Copy `android/key.properties.example` to ignored `android/key.properties` and fill in `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Prefer an absolute keystore path; do not paste passwords into shell commands or commit the file.
2. Both modules read that one signing file. Release tasks now fail if it or its keystore is absent; they cannot silently use the debug key. Google Play App Signing must also use the same app signing certificate for phone and Wear. Sharing an upload key alone does not establish the installed-app certificate.
3. Choose a new monotonically increasing build number. Phone uses `N` and Wear uses `1000000 + N`; keep `N` between 1 and 999999. Both use the Flutter version name. Build the phone first so Flutter updates `android/local.properties` before the Wear build:

```sh
flutter pub get
python3 tool/release_preflight.py --platform android --config config/local.json
flutter build appbundle --release --build-number 2 --dart-define-from-file=config/local.json
cd android
./gradlew :wear:bundleRelease
```

The phone bundle is under `build/app/outputs/bundle/release/`; the watch bundle is under `build/wear/outputs/bundle/release/`. Upload them to the same app's appropriate phone and Wear OS testing tracks in Play Console, with the Wear OS form factor enabled. Install both through that track and check the pair before expanding distribution. This keeps the package/certificate relationship required by the [Wear Data Layer](https://developer.android.com/training/wearables/data/overview) and the separate version codes required for [Wear packaging](https://developer.android.com/training/wearables/packaging).

Alternatively, run GitHub Actions **Prepare Android store release** manually after setting repository Actions secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` and, if enabling push, `GOOGLE_SERVICES_JSON_BASE64`. Choose the build number and workspace/push flags. The workflow prepares the ignored files, runs this preflight and builds both signed bundles. It uploads build artifacts for review; it does not publish to Google Play. Never store an APNs or Supabase service key in those client configuration inputs.

For a new **personal** developer account, Google currently requires at least 12 testers continuously opted into a closed test for 14 days before applying for production access. This rule is account-dependent; check what your new account requires. [Google's testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)

## iPhone and Apple Watch

Use a Mac with Xcode and the pinned Flutter version. In `ios/Runner.xcworkspace`, select your Apple team and automatic signing for **Runner, PrayerWidget, CommunityWatch and WatchWidgets**. Register their bundle IDs and enable the configured App Group for every target that uses it. The watch/complication build and version now inherit Flutter's version, including `--build-number`; they cannot remain at version 1 when the phone changes.

After configuring signing:

```sh
flutter pub get
python3 tool/release_preflight.py --platform ios --config config/local.json
flutter build ipa --release --build-number 2 --dart-define-from-file=config/local.json
```

Open the archive under `build/ios/archive/` in Xcode Organizer, use **Validate App**, then **Distribute App → App Store Connect**. Enable the processed build for a TestFlight group and test the embedded watch app on a paired Apple Watch. After testing, complete the listing and submit for App Review. A simulator build does not produce a signed TestFlight installer. [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios), [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

The local preflight detects an absent saved development team. If your signing is supplied entirely through CI/Xcode command-line settings, run source checks there and let the signed archive/Validate App step verify those settings.

## Enable account push

Register the final Android and iOS IDs in one organisation-owned Firebase project. Add downloaded native configuration to ignored `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`. The Android Google services plugin is already conditional. The iOS build now copies the optional plist automatically, checks its bundle ID, and removes any stale copy when the local file is removed. Do not also add a duplicate Copy Bundle Resources entry.

For Runner in Xcode, enable Push Notifications and the required remote-notification background capability, provision the resulting `aps-environment` entitlement, and upload the team's APNs authentication key to Firebase. Existing audio background mode must remain enabled. Configure the Supabase worker's Firebase service account and scheduler on the server, then test an explicitly chosen test-account notification. The FCM/APNs/server private keys never enter this repository or app bundle. [Firebase's Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started)

Only then build with `ENABLE_PUSH=true`. The preflight rejects missing/mismatched native Firebase files or an absent iOS APNs entitlement when push is enabled. With push disabled, these optional inputs are not release blockers. Public prayer reminders use the local timetable and remain separate from account push.

## Release evidence to retain

Record the Git commit, backend migration versions, feature flags, app version/build number and test-track/TestFlight build. Keep the upload keystore and Apple signing credentials in the organisation's protected account/secret storage. CI may prepare signed bundles using protected secrets; store upload and public release are separate actions.
