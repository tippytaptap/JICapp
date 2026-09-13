# Reading and personal worship

Implemented in the native app and web preview:

- A complete 114-surah catalogue, searchable by name and number.
- Uthmani Arabic and Sahih International English meaning, fetched from the named Al Quran Cloud editions. Arabic is preserved exactly as supplied after JSON decoding; search normalisation never changes the displayed or saved text.
- Strict surah/edition/ayah/global-number validation against the 6,236-ayah catalogue. Incomplete or mismatched responses are rejected. Corrupt cached copies are removed and can be downloaded again.
- Explicit per-surah offline downloads, removal, download-all and removal-all on native devices. Download-all uses sequential requests, shows progress, can be stopped and resumes by skipping successfully saved surahs. A cancelled or failed request does not overwrite a completed reading.
- Native downloads use application-support files with temporary-file replacement. Browser preview uses bounded local preference storage; full-corpus download is disabled there to respect browser limits.
- Ayah bookmarks, a saved continue position, per-surah Arabic/English search, ten-ayah reading groups, direct ayah navigation, persistent text size and English toggle.
- Published Dala’il, Hizb/awrad, dhikr/du‘a, hadith and learning collections from the existing `page_content.reading_library` contract. These collections are searched locally and cached by organisation for offline reading. Successful refresh replaces the cache, including removing unpublished readings; unavailable connections retain the last published copy and label it as saved content.
- A link from the reading hub to published talks and reviewed sermon summaries.
- Tasbih retains its existing device counter and 33/99/100 rounds. Haptics are opt-in. Optional daily goals track the user's chosen target, daily counts and consecutive goal days, with up to 90 days of local history. Circle reset preserves daily totals; undo reduces today's total. History can be cleared independently.
- Explicit phone/watch count transfer: the user chooses when to send or import. Import confirms replacement, preserves daily routine history and never adds counts together automatically.
- An encrypted local Salah plan migrates previous remaining counts, supports adding a quantity per prayer, marking completion, undoing the latest entry, an optional daily plan, recent entries and deletion. It does not add missed prayers automatically or share the record with staff.

## Sources

API and edition contract: https://alquran.cloud/api and https://api.alquran.cloud/v1/surah

API/translation attribution terms (checked 13 September 2026): https://alquran.cloud/terms-and-conditions

Arabic text notice: https://tanzil.net/docs/Text_License

The Tanzil copyright/terms notice is preserved in downloaded cache records; the reader names Tanzil and Sahih International and links to the sources. Downloaded readings are for user-chosen offline use. Translation rights remain with the named rights-holder.

No Dala’il, Hizb or hadith edition has been silently bundled or generated. The organisation needs to publish the edition it uses, references and approved text with permission where applicable. The reader and offline/search functionality are ready for that content. A link-only library entry still requires a connection to open its external source.

## Verification

`flutter test test/reading_store_test.dart test/widget_test.dart`

Tests cover catalogue completeness, edition ordering, rejected verse identity/count errors, offline reads without network, corrupt-cache removal, bookmarks/position, Arabic search, published-only collection isolation/removal, optional daily goals/history and Salah migration/completion/undo.

Remaining release checks: review actual Arabic font/rendering on iPhone and Android with the organisation's reader; validate licensed collection content; test full-corpus download/cancellation on a device; verify encrypted storage and paired-watch transfer on physical devices. Source availability is external, so first-time Quran reading requires connectivity until explicitly downloaded.
