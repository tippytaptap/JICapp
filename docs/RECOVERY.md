# Recovery status — 13 September 2026

Automatic workspace maintenance removed the unpublished Flutter app and companion website branch before source upload completed. The repository initial commit survived. Some image blobs were uploaded but the application tree and source commit were not created remotely. The previous local test results describe that lost working copy; they are not verification of code in this repository.

A saved JIC-App-Recovery.zip was checked. It contains analysis and assets from the old APK, not the new Dart source. The existing jicuser/website repository remains the baseline. Do not claim the app is uploaded, native builds work, the companion migration is deployed, or notifications are live.

## Established approach

Keep the existing React/Vite website and Supabase identity/data model. Flutter supplies Android/iPhone interfaces with the same approved navy/stone/gold branding. Keep organisation identity in configuration/assets/platform display names, not generic module/class names. Use a separate Supabase deployment when reusing for another organisation; no implicit multi-tenant safety.

Baseline examined: jicuser/website commit 52dcfda. Recheck current main before changes because another chat is editing the website. Supabase project reference pwhtguaevhlnzytneemp. No service-role or Firebase credentials belong in this repo.

## Existing contracts to verify during reconstruction

- get_my_profile: id, display_name, is_active, is_owner, permissions, staff_kinds. Deny disabled users, including disabled owners. Labels are not capabilities.
- Capability IDs: content, media, events, announcements, prayer_times, team, livestream, tv, broadcast, forms_contact, forms_madrassah, forms_itikaaf, users, audit, delete_content.
- Existing manage-user function owns invitation/user permission changes. Reuse server checks.
- forms: id, kind (contact/madrassah/itikaaf), payload, status (new/done), created_at. Existing per-kind RLS must stay authoritative.
- submit-form accepts {kind,payload}. Contact payload name/email/question; madrasah name/email/phone/query. Existing gateway verify_jwt=true needs a compatible legacy anon JWT until explicitly migrated; modern publishable keys are not a drop-in for that gateway configuration.
- prayer_times uses d_date, fajr_begins/fajr_jamah, zuhr_begins/zuhr_jamah, asr, maghrib, isha and sunrise. Use Europe/London including DST.
- livestream uses enabled (not is_live).
- page_content content_key/content_value stores public JSON programme_posters, site_images and pages. Never put private student/form data there.

## First app implementation to reconstruct

1. Flutter Android/iOS/web preview scaffold; organisation configuration and approved existing assets; secure native auth persistence and no persistent web-preview auth.
2. Home with published prayers, announcements, events, posters and broadcast link. Never fabricate unavailable timetable/content.
3. Adult courses and weekly schedule separately from madrasah. Poster audience plus ISO weekday/time or after-Maghrib metadata. Inherit default legacy metadata only for known posters with unchanged schedules.
4. Reading hub and Qur’an Arabic Uthmani/English reader through the existing website provider. Font size and surah bookmarks; admin-published referenced Dalail, dhikr, hadith and guides. Do not invent sacred text or references.
5. Persistent Tasbih target/count/undo/reset confirmation/haptics; device-private missed-Salah counts in secure storage. Qibla from on-demand location/compass.
6. Radio through the existing Streamerr stream: background media session, actual stop and sleep timer. Validate background/battery behaviour on hardware.
7. Same-account login; native existing-user access editing; private paginated forms inbox with filter/search, complete/reopen, CSV of displayed records with spreadsheet formula escaping, call/email draft actions, native contact/madrasah submission. No automatic email replies.
8. Feature-gated shared tasks, notification inbox and student/staff/parent portals; adult and madrasah courses remain separate. Task assignment, due dates/status/counts; class-scoped registers, published progress/plans/assessment records and meeting requests.
9. Opt-in FCM registration, token refresh, account cleanup and notification-open handling. Local prayer reminders from the next seven published days, with timezone and platform limits. Android prayer widget and Tasbih shortcut.

## Website/backend reconstruction

Create a separate draft branch, not a main-branch overwrite. Add adult education routes/weekly poster metadata; member login that preserves the existing admin guards; app image/reading editor using public page_content keys; feature-gated /portal and form-to-task links.

Prepare a new additive migration (do not apply production implicitly): learning_courses, learning_staff, learning_students, learning_enrolments, learning_sessions, learning_attendance, learning_records, learning_meetings, work_tasks, user_notifications, push_devices, push_outbox, form_workflows. Enable RLS for every table. Active owners manage courses and links; teachers/head teachers operate assigned classes; parents/students see only linked students’ published records. Teacher labels alone never grant access. Attendance validates enrolment and atomic batch rollback. Record actors/timestamps are server-stamped.

Tasks must validate actor and recipient access, including the form’s capability. Configurable routing for the three existing form kinds creates task/inbox/outbox transactionally; skip routing when owner/assignee loses access without discarding the original submission. Read notification state is separate from task completion.

Device token storage is server-private. Authenticated register/unregister RPCs must prevent another account taking an existing token. Push worker uses a dedicated server secret, bounded leases/retries and generic lock-screen payloads with stable IDs. Sender ignores caller-supplied private content and uses FCM HTTP v1. Supabase retains inbox truth. Configure Firebase/APNs and a scheduler only in an explicit rollout step; no live notification has been sent.

## Remaining larger scope

Dynamic form builder/conditional fields/versioning; secure photo/file requests and ZIP exports; reply threads; payment reconciliation/webhooks; escalations; full native school administration, gradebooks/homework and granular head-teacher roles; student poetry/contribution moderation; offline reading/search/recitation/Dalail daily divisions; optional personal sync; iOS WidgetKit home/lock-screen extensions; Apple Watch companion/complications/Tasbih; Wear OS app/tiles; physical counter integration after protocol is known; existing secure mosque TV/device pairing and local-camera relay support; server-side authorised radio transcription, timestamped summaries, retrieved/verified scripture references and human approval before quote images/digests.

Final company spelling (proposed Mastir), bundle identifiers, signing, store accounts/privacy/support details remain to be settled before publication.

## Verification to repeat

The lost working copy had 8 Flutter tests, a clean analyser, a successful web build and browser checks of Home/Education/Reading/Tasbih. The lost companion website had 200 passing Node tests, production build and a Deno type check. These checks MUST be rerun on reconstructed source; they are not current completion evidence.

Use meaningful tests for RLS parent/teacher isolation, disabled accounts, draft privacy, atomic registers, form permission routing, token ownership, generic push payloads and bounded retries. Test at 320px and larger text. No Android SDK or Xcode was present locally. A GitHub Actions debug APK must actually succeed before linking an installable build. Use Android Studio Emulator; iPhone Simulator requires Xcode on macOS.

Persist each recovered source checkpoint remotely before large downloads or further extended testing. Shell GitHub push lacked credentials; the connected GitHub create_tree/create_commit/update_ref tools were available. For an empty repository the initial README commit is 02d7d8ce7a240e95591dc8294b927b0d581cd236. Never force-overwrite subsequent user changes.
