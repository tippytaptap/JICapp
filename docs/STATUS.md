# Source delivery status — 13 September 2026

Source is saved incrementally in `tippytaptap/JICapp`. The website companion is in `jicuser/website`, branch `feat/community-workspace`. Production database and website deployment are unchanged.

## Implemented source

| Area | Current behaviour |
| --- | --- |
| Shared identity | Existing Supabase login and active profile/capability checks; private routes clear when accounts or permissions change. Owner-managed access remains on the website. |
| Public app | Configured branding, published prayer begins/jamaah times, announcements, events, livestream link, adult courses and a real poster-based weekly schedule. |
| Reading and worship | Quran Arabic/English with a Surah bookmark and text sizing; admin-published Dalail/dhikr/hadith/Hizb collections; persistent haptic Tasbih; private device Salah counts; on-demand Qibla. Quran loading requires internet; no complete offline corpus is bundled. |
| Radio | Existing stream, background media integration, lock-screen playback controls and sleep setting. Battery and sleep behaviour require physical-device checks. |
| Forms | Existing validated contact/madrasah submission, authorised inbox for all existing kinds, paging/filter/sort, visible-row CSV, call/email drafts, status and form-linked task creation. |
| Actions | Assignee selection, deadlines, open/in-progress/waiting/done, totals and personal inbox. Owner routing rules create a task and notification when a supported form is submitted. |
| Education portal | Adult and madrasah departments remain separate; enrolled students/guardians and assigned teachers see permitted courses, progress/plans/assessments, meetings and contributions. Teachers mark an atomic class register and moderate poetry/reflections. Owner sets up people, courses and enrolments on the website. |
| Notifications | Persistent updates inbox, independent read status, secure device registration, server push outbox and FCM worker, opt-in local prayer reminders from the published timetable. Native credentials, scheduler and staging verification are still required. |
| Widgets | Android prayer/Tasbih shortcut widget plus embedded iOS WidgetKit home/lock-screen target. Public prayer data only; OS scheduled updates. Native signing and hardware verification remain. |
| Admin content | Website editor for appropriate programme posters/audiences/sessions and approved app images/readings. |

## Full scope still retained

- Custom form builder with conditional fields, arbitrary file/photo uploads, ZIP export, reply threads and extra workflow rules. Current workflows cover the three existing validated form types.
- Payment provider/webhook reconciliation, payment chasing and confirmed-payment records. A task label is not proof of payment.
- Rich course resources, explicit numeric marking and reporting, configurable head-teacher scopes, multiple guardians, comprehensive student progress plans and richer appointments.
- Full offline reading library, reading-position/bookmark sync and verified licensed source editions.
- Apple Watch/Wear OS companion apps and watch complications/Tasbih; physical counter integration requires the device protocol. Watch features are not implemented by a phone widget.
- Server-side authorised Streamerr recording/transcription, reviewed summaries and verified quotations/references. Quote image generation follows source review; an image generator must not invent scripture citations.
- Existing website mosque-TV displays, pairing, scene templates, posters and stream-control code are preserved. Connecting the chosen smart screens and mosque-local IP camera gateway, and verifying the installation's live YouTube behaviour, remain rollout work. The app does not duplicate those web display controls. Browsers cannot play arbitrary RTSP camera URLs directly.
- Email forwarding/reply ingestion and digest delivery. Current email actions open drafts; they do not deliver or track email inside the portal.

## Rollout order

1. Review the website branch, apply its additive migration to staging, exercise owner/staff/student/guardian/revoked accounts and inspect Supabase advisors.
2. Build the app against staging with `ENABLE_EXTENSIONS=true`. Keep the existing website auth/form contracts compatible.
3. Configure the new Firebase/APNs and store accounts, final bundle identifiers/App Group, and server-only worker secrets. Test notification registration, account switching, disabled users and queue delivery before enabling push.
4. Verify iPhone/Android radio interruption/sleep, permissions, reminders, widgets, offline/error flows and accessibility on devices. Compile/sign the iOS extension in Xcode.
5. Deploy reviewed changes and publish through the organisation's store accounts. No store submission or production migration has been performed in this session.

## Verified checkpoint

Both the initial public checkpoint `e1eb6c3` and workspace/widgets/notification checkpoint `ed4468d` passed GitHub Flutter analysis, tests, web build and Android debug APK build. [The workspace preview APK](https://github.com/tippytaptap/JICapp/actions/runs/34751634783) is available as the `android-preview` artifact. It has no production connection settings and its workspace feature flag is off; this is a UI/device preview. Subsequent authentication/token-rotation corrections are saved in `7f12633` and have their own build run. Compilation does not establish live notification delivery or device behaviour.

Website companion: 214 tests, lint, enabled Vite production build and four mobile-browser routes passed. Flutter workspace checkpoint: 16 tests, analysis and an extensions-enabled web build passed. Backend tests execute PostgreSQL policies and transactions in PGlite; they do not replace managed Supabase staging checks. Native device/APNs delivery and Xcode builds are unverified in this Linux workspace.
