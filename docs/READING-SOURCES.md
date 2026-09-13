# Bundled reading sources

The initial hadith reminder catalogue is copied from the existing website’s `src/content/reminders.js`. Its ten English entries are concise meanings/paraphrases with their original references. They are explicitly labelled as such and are not presented as full narrations or as newly generated scripture. No Arabic text, hadith grading or additional religious claims were added. Existing source links are retained; the three older entries’ links follow their existing Bukhari/Muslim references.

`assets/reading/hadith-reminders.json` is available offline. The configured reading collection takes precedence according to the reader’s documented refresh rules.

The supplied old Android app was checked through `recovery/JIC-App-Recovery.zip`. Its Flutter asset manifest contains images/SVGs and icon fonts, with prayer/radio/Qibla screen clues. No Dala’il, Hizb or hadith book text was found. A read-only check of the existing public `page_content` table on 13 September 2026 found no `reading_library` row. Dala’il/Hizb editions therefore still need approved source content from the organisation.

## Arabic font

`assets/fonts/NotoNaskhArabic-Regular.ttf` is the existing Noto Naskh Arabic Regular 1.07 font supplied with the Flutter SDK at `engine/src/flutter/txt/third_party/fonts/`. Its embedded metadata declares Copyright 2014 Google Inc. All Rights Reserved, under SIL Open Font License 1.1. The full licence and correct copyright notice are included in `assets/fonts/NotoNaskhArabic-OFL.txt`.

The font is 255,280 bytes, SHA-256 `6b999662f669b2c9b00c10ce4a110b6f5179c20f3f77e5ccb897e3ab965cf9f5`. Its character map includes 253 characters in the Arabic U+0600–U+06FF block. It provides offline Arabic rendering; specialised Quranic glyph coverage and shaping should still be visually checked against the edition in use on both platforms.
