# Completion and release status — 13 September 2026

The app and shared website source are saved to GitHub in `tippytaptap/JICapp` (`main`; development history in `feat/complete-app`) and `jicuser/website` (`feat/community-workspace`, PR5). The current website main UI changes are merged into the companion branch. The live Supabase project still has its existing website schema; the new workspace migrations have not been deployed.

## Implemented

| Area | Delivered behaviour |
| --- | --- |
| Public app | Configurable branding and published timetable, announcements/events, livestream, real programme posters, adult education overview and weekly schedule. Cached published prayer days survive offline restarts. |
| Reading | 114-surah Quran, Arabic/English, search, per-ayah bookmarks and position; explicit offline native download/removal/cancellation; approved library text/reference caching. |
| Worship | Haptic Tasbih with local goals/history; explicit paired-watch counter handoff; private encrypted Salah plans, completion history and undo; on-demand Qibla. |
| Audio | One background player for Streamerr and published sermon recordings; lock-screen media, seek where available and sleep settings. |
| Forms | Conditional builder/versioned schema, private photos/files, responsible people/watchers, existing/custom collated inbox, server search/counts, CSV/ZIP, shared replies/notes and assigned actions. |
| Identity | Existing Supabase accounts, native invite/access/activation management, server capability checks, private route gates and current-account task/notification inbox. |
| Learning | Separate adult/madrasah courses; native owner course/student/enrolment/teacher management; primary/additional guardians and scoped department heads; atomic registers, numerical marks, progress/plans, private course files, meetings and moderated poetry. |
| Payments | Source-scoped charges, due/outstanding totals separated by currency, audited manual confirmations/corrections, immutable receipt history and optional signature-verified Stripe event reconciliation. No card collection or money transfer. |
| Email | Optional explicitly reviewed outbound queue and delivery-state history; signed incoming webhooks, quarantined sender claims, staff acceptance and shared reply threads. Push-only is the default. |
| Speech summaries | Server capture/import worker, transcription, timed source segments, draft summaries/references, human approval, quote cards, public archive and withdrawal. No invented scripture citation is automatically published. |
| Notifications | Secure device registration, server outbox/FCM worker, generic private update text, opt-in prayer start reminders using the centre's published timetable. |
| Phone widgets | Android prayer/Tasbih shortcuts and embedded iOS home/lock-screen WidgetKit target. Published prayer data only. |
| Watches | Native Wear OS app/Tile and Apple Watch app/complication; prayer timetable, local Tasbih/haptics, explicit counter transfer and sensor-aware Qibla. |
| Mosque screens | Existing website private display/pairing/scene/poster/livestream/local-camera gateway source is preserved. Installation uses its web display URL; no duplicated public student content. |

## Source verification

- First full native checkpoint `9e70a7b`: Flutter analysis/tests/web, Android phone APK and Wear OS APK passed in GitHub run34754702602. Apple initially required an explicit simulator ID; that workflow requirement was corrected.
- Website: all 269 tests, ESLint and workspace-enabled Vite production build passed after integrating current main through `876e8fa`. Targeted form flows also passed real mobile browser tests with mocked writes.
- Actual SQL tests apply all six current workspace migrations together and check role isolation, file visibility, transactions, receipt idempotency and shared replies/email queue.
- Provider code uses mocks/synthetic audio for verification. Real FFmpeg conversion was exercised; no real sermon recording, email, payment or paid AI request was initiated.
- Final app analysis and 51 tests passed; the extensions-enabled web build and Home/Education/Reading/Tasbih browser smoke passed with no console errors.
- Final source `03a8f024` passed Android phone/Wear OS APK builds, iPhone simulator with embedded watch, and standalone Apple Watch simulator in [run34755740646](https://github.com/tippytaptap/JICapp/actions/runs/34755740646). Both Android artifacts are uploaded. Successful compilation is separate from signing, provider delivery and physical-device testing.

## Release setup still required

1. Apply the six reviewed additive workspace migrations and deploy the new/updated Edge Functions on an approved backend. Check staging owner/staff/student/guardian/revoked-account flows, then enable website/app workspace flags.
2. Supply the chosen developer identities, Android release signing and Apple team/App Groups. Configure Firebase project files, APNs key, push worker secret/service account and scheduler before enabling push.
3. Choose/install the sermon worker and optional email worker with server-only credentials/domains; configure payment webhook only if the provider is used. Email and AI integrations remain disabled without that setup.
4. Supply the organisation's chosen approved Dalail/Hizb/hadith editions. The old APK contains no book corpus and current website CMS has no published reading_library rows. The full reader supports approved supplied content; it must not silently invent religious text.
5. Test paired physical watches/phones, radio interruption/sleep, notification permissions/delivery, offline downloads, prayer reminders and accessible text sizes. Pair the actual mosque screens and local camera gateway on the mosque network.
6. Publish signed releases through the new organisation accounts. No store submission or live database migration has been performed.

Final company spelling/identifiers, a physical counter's protocol, chosen private camera source and approved book editions are external inputs, not recoverable app source.
