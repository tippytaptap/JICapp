import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:community_app/core/reading_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline reminder asset has readable, attributed English meanings',
    () async {
      final raw = await rootBundle.loadString(
        'assets/reading/hadith-reminders.json',
      );
      final entries = ReadingStore.validateLibrary(jsonDecode(raw));
      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(entry['collection'], 'hadith');
        expect(entry['published'], isTrue);
        expect(entry['text'], startsWith('Meaning / paraphrase:'));
        expect('${entry['reference']}'.trim(), isNotEmpty);
        expect(Uri.parse(entry['source']).scheme, 'https');
        expect(entry.containsKey('arabic'), isFalse);
      }
    },
  );
}
