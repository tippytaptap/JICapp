# Reviewable rollout package

The app feature branch and website PR5 contain the same shared contracts. Website main through `876e8fa` is integrated. Do not publish a Flutter web build over the React website.

## Database and services

The connected JIC website project is `pwhtguaevhlnzytneemp` (London). The latest existing live migration is `20260913114724_team_member_groups`, applied by the current website update; no new app workspace tables exist there yet. The website branch aligns that team migration filename with the verified live history. The source additions, in order:

1. `20260913100552_community_workspace.sql` — scoped learning, tasks, notifications, device registration/outbox and legacy form routing.
2. `20260913111401_custom_forms.sql` — versioned custom fields, private uploads, membership, replies and collated inbox.
3. `20260913111515_sermon_archive.sql` — private processing queue, reviewed publications and recording storage.
4. `20260913111741_learning_resources_and_progress.sql` — extra guardians, department heads, numeric marks/plans and private course resources.
5. `20260913113124_fee_ledger.sql` — source-scoped fees, immutable receipt/audit records and provider reconciliation.
6. `20260913113136_optional_form_email.sql` — optional reviewed email delivery and quarantined replies.

SQL tests apply this exact order together, plus the separate existing team update. The new workspace versions predate that latest team migration: a linked CLI rollout must review `supabase db push --dry-run --include-all` before applying the approved pending migrations. They check anonymous/ordinary/teacher/guardian/owner/revoked access and transactional duplicate protections. These tests use PGlite; managed Storage, Auth and HTTP gateways still require post-deployment checks.

New Edge Functions: `custom-forms`, `push-worker`, `payment-webhook`. Deploy the existing `manage-user` function with the updated shared access catalog so new form capability keys can be assigned. Keep existing `submit-form` and TV contracts; no replacement account database. Apply `verify_jwt` settings from the companion config; handlers perform explicit current-user or dedicated worker/provider authentication.

The website uses `VITE_ENABLE_WORKSPACE=true` after the backend is ready. App `ENABLE_EXTENSIONS=true` activates the shared workspace. Keep `ENABLE_PUSH=false` until real Firebase/APNs configuration and server scheduling pass a delivery test. Existing public app configuration uses a public anon key, with no server secret.

Sermon/email workers are optional separate server containers. See companion `docs/MEDIA.md` and `docs/EMAIL.md`. They are disabled without explicit server configuration. The payment webhook records a verified existing provider event; it is not a checkout/charge or refund endpoint.

## Post-deployment checks

Use authorised test accounts/records to exercise one form response→assigned action→portal reply, private file download, course/student/guardian linkage, class register, marks, and a manual ledger confirmation/correction. Verify another account cannot read those records. Do not send a real email, take a payment or capture a live sermon for a smoke test without the organisation choosing that action.

Run Supabase security advisors. Existing TV tables with RLS and no client policies are intentional service-controlled tables; do not grant broad policies to remove informational advice. Existing leaked-password protection is currently disabled and can be enabled in Auth settings when configuring account release policy.

## Native release

- Android Studio Emulator with a Google Play image supports development; use physical phone/watch pairs for radio, sensors, background notifications and battery checks.
- Xcode Simulator on a Mac builds/tests iPhone and watch UI. Supply the chosen Apple development team, matching App Groups and APNs credentials for real devices/store builds.
- Phone/Wear must use the same release signing certificate and application ID. Apple companion identifiers and entitlements are documented in WATCHES.md/WIDGETS.md.
- Replace development company identifiers/packaging with the final approved spelling. Configure auth reset/invite redirect URLs for the final app/site.
- Supply approved Dalail/Hizb/hadith book editions and the actual local camera/counter device protocol where required; no such corpus/protocol is recoverable from the uploaded APK.

Developer account, signing and provider credentials remain server/platform secrets. Never commit them to configuration assets, logs or app bundles.
