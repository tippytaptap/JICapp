# Deployment guide

The app main branch and [website PR5](https://github.com/jicuser/website/pull/5) contain the shared release. Website main through `c057d8f` is integrated, including the latest editable team profiles. Keep the React website on Hostinger; Flutter supplies the mobile apps.

## Start here

The release preparation is saved, but the extended backend, website release and store publication have not been activated. No signed store build can be produced until the organisation supplies its signing identity.

1. **Backend:** follow the companion [BACKEND-RELEASE.md](https://github.com/jicuser/website/blob/feat/community-workspace/docs/BACKEND-RELEASE.md). Check the existing backup/history, rehearse the six missing migrations, deploy the three required handlers, and test real Auth/Storage access in the intended test environment. Configure the final website callback and custom SMTP for account setup/recovery.
2. **Website:** check the existing Hostinger site's deployment type before merging PR5. Follow [WEBSITE-RELEASE.md](https://github.com/jicuser/website/blob/feat/community-workspace/docs/WEBSITE-RELEASE.md). Set the public repository variables and use **Actions → Prepare website release → Run workflow** after that workflow reaches the default branch. Upload the resulting static artifact to the existing site's `public_html`, or use its already-configured Vite build deployment. Static Git copying alone does not build Vite. Keep workspace off until the backend checks pass; the public website can ship independently.
3. **Android:** add the four signing secrets in [MOBILE-RELEASE.md](MOBILE-RELEASE.md), then use [Actions → Prepare Android store release](https://github.com/tippytaptap/JICapp/actions/workflows/android-release.yml). Choose a unique build number and the reviewed feature flags. Download the signed phone/Wear bundles and upload to Google Play **internal testing**. The workflow prepares files; it does not publish them.
4. **iPhone/Apple Watch:** on a Mac, select the organisation's Apple team for all four targets in Xcode, archive with `flutter build ipa`, validate, and distribute through **App Store Connect → TestFlight**. Exact commands and App Group/signing setup are in [MOBILE-RELEASE.md](MOBILE-RELEASE.md).
5. **Push and public release:** configure Firebase/APNs and the server push scheduler, then validate delivery with a chosen test account. Test signed apps on real phone/watch pairs. Finish the approved store artwork, privacy/support and account-deletion route, book editions and reviewer access before submitting for public store review.

Use the organisation's new developer accounts. The current `com.mastir…` identifiers are provisional; confirm the final company spelling and identifiers before the first store upload. Do not put passwords, upload keys, APNs or service credentials into this public repository. Store listing completion, a verified deletion/support process and the chosen Dalail/Hizb editions are still release inputs; source compilation does not establish them.

Each platform guide includes verification and rollback. Hostinger hPanel deployment mode, SMTP/Firebase credentials and store account ownership could not be verified from the connected repository. No automatic Hostinger or store deployment is configured by this change.

## Database and services

The connected JIC website project is `pwhtguaevhlnzytneemp` (London). The latest existing live migration is `20260913114724_team_member_groups`, applied by the current website update; no new app workspace tables exist there yet. The website branch aligns that team migration filename with the verified live history. The source additions, in order:

1. `20260913100552_community_workspace.sql` — scoped learning, tasks, notifications, device registration/outbox and legacy form routing.
2. `20260913111401_custom_forms.sql` — versioned custom fields, private uploads, membership, replies and collated inbox.
3. `20260913111515_sermon_archive.sql` — private processing queue, reviewed publications and recording storage.
4. `20260913111741_learning_resources_and_progress.sql` — extra guardians, department heads, numeric marks/plans and private course resources.
5. `20260913113124_fee_ledger.sql` — source-scoped fees, immutable receipt/audit records and provider reconciliation.
6. `20260913113136_optional_form_email.sql` — optional reviewed email delivery and quarantined replies.

SQL tests apply this exact order together, plus the separate existing team update. The new workspace versions predate that latest team migration: a linked CLI rollout must review `supabase db push --dry-run --include-all` before applying the approved pending migrations. They check anonymous/ordinary/teacher/guardian/owner/revoked access and transactional duplicate protections. These tests use PGlite; managed Storage, Auth and HTTP gateways still require post-deployment checks.

Deploy `custom-forms`, the updated `manage-user` and the reviewed `submit-form` using the companion `config.toml`. These handlers support public client keys and perform explicit authorization for every private action; the public submission endpoint retains its validated, rate-limited contract. `push-worker` and `payment-webhook` are optional deployments for their configured providers. Keep the existing TV function and account database.

The website uses `VITE_ENABLE_WORKSPACE=true` after the backend is ready. App `ENABLE_EXTENSIONS=true` activates the shared workspace. Keep `ENABLE_PUSH=false` until real Firebase/APNs configuration and server scheduling pass a delivery test. Existing public app configuration uses a public anon key, with no server secret.

Sermon/email workers are optional separate server containers. See companion `docs/MEDIA.md` and `docs/EMAIL.md`. They are disabled without explicit server configuration. The payment webhook records a verified existing provider event; it is not a checkout/charge or refund endpoint.

## Post-deployment checks

Use authorised test accounts/records to exercise one form response→assigned action→portal reply, private file download, course/student/guardian linkage, class register, marks, and a manual ledger confirmation/correction. Verify another account cannot read those records. Do not send a real email, take a payment or capture a live sermon for a smoke test without the organisation choosing that action.

Run Supabase security advisors. Existing TV tables with RLS and no client policies are intentional service-controlled tables; do not grant broad policies to remove informational advice. Existing leaked-password protection is currently disabled; review [Supabase's password protection settings](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) when configuring the account release.

## Native release

- Android Studio Emulator with a Google Play image supports development; use physical phone/watch pairs for radio, sensors, background notifications and battery checks.
- Xcode Simulator on a Mac builds/tests iPhone and watch UI. Supply the chosen Apple development team, matching App Groups and APNs credentials for real devices/store builds.
- Phone/Wear must use the same release signing certificate and application ID. Apple companion identifiers and entitlements are documented in WATCHES.md/WIDGETS.md.
- Replace development company identifiers/packaging with the final approved spelling. Configure auth reset/invite redirect URLs for the final app/site.
- Supply approved Dalail/Hizb/hadith book editions and the actual local camera/counter device protocol where required; no such corpus/protocol is recoverable from the uploaded APK.

Developer account, signing and provider credentials remain server/platform secrets. Never commit them to configuration assets, logs or app bundles.
