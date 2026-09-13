# Delivery plan

Rebuild started 13 September 2026. Persist each source stage to GitHub before moving to extended testing. Historical recovery notes are not proof of current implementation.

## Architecture

Flutter Android/iOS app; keep the React/Vite public website. One Supabase project provides accounts, capability checks, content, private form_submissions, education records, tasks and inbox. FCM delivers push from Supabase Edge Functions; it is not a second authentication database. Use generic feature names and organisation configuration. Current website main UI through668b194 is integrated in the companion branch.

## Ordered checkpoints

1. Configurable Flutter scaffold and public home/reading/education/Tasbih screens with existing approved assets, public Supabase reads and same-account login.
2. Worship functions: Qur’an reading/bookmarks, reviewed reading collections, Qibla, private missed-Salah tracker, radio background media/sleep, prayer reminders.
3. Shared work: native form submission and permission-filtered inbox, CSV and optional phone/email drafts; additive backend tasks, assignment/routing, notification inbox/outbox and push registration/sender.
4. Education: adult classes/weekly poster schedule separate from madrasah; student/parent/teacher records, progress/plans/assessments, meetings, register; website administration and student contributions/poetry moderation.
5. Native extensions: Android prayer/Tasbih widget, iOS WidgetKit home/lock-screen implementation, Apple Watch/Wear OS native apps, complications/Tiles and documented platform setup.
6. Verification: analyser/tests/build and browser preview; SQL isolation/transaction tests; native CI build where available. Save clear tested/untested and feature/deployment status with each checkpoint.

## Full requested scope

Dynamic forms and conditional fields, secure photo/file uploads and ZIP export, response threads, payment reconciliation and chasing, delegated user administration, student course resources/marking/head-teacher roles, private appointments, larger offline Quran/Dalail/hadith/dhikr reading, optional personal practice sync, watch Tasbih and physical counter integration (protocol required), mosque screens and local camera relay, authorised server radio transcription/summary/reference retrieval and reviewed quote images, push/digest preferences, new store accounts and company identity.

Most of this scope is implemented; STATUS.md records delivered modules and external release/content dependencies. Physical counter integration still needs the device protocol. Optional personal practice sync has not been added: practice data stays private on the device.

## Rules

No duplicate account store or form inbox. Disabled accounts cannot access private features. Server permissions govern each record, never user-editable role labels. Private submissions/learning details never appear in lock-screen text. Reading an alert does not complete a task. Notification delivery retries must not repeat task creation. Adult education must not reuse pupil-focused madrasah information. Public reading text is reviewed and referenced. Missing live timetable is displayed honestly.

Production migrations, Firebase/APNs credentials, scheduling, signed builds and store publication are separate rollout steps. Do not mark these complete from source compilation alone.

## Emulator choices

Android: Android Studio Emulator with a Google Play system image for push testing. iPhone: Xcode Simulator on macOS; use a real iPhone for release checks of notifications, radio, location and widgets.

References: https://supabase.com/docs/guides/functions/examples/push-notifications and https://firebase.google.com/docs/cloud-messaging/flutter/get-started.
