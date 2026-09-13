import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/core/reading_store.dart';
import 'package:community_app/core/reading_cache.dart';
import 'package:community_app/core/worship_store.dart';

class MemoryCache implements ReadingCache {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Set<String>> keys() async => values.keys.toSet();
}

// Artificial text fixtures exercise identity checks; no scripture is generated.
Map<String, dynamic> response([int surah = 1]) {
  final offset = surahLengths.take(surah - 1).fold<int>(0, (sum, n) => sum + n);
  return {
    'code': 200,
    'data': [
      for (final id in ['quran-uthmani', 'en.sahih'])
        {
          'number': surah,
          'numberOfAyahs': surahLengths[surah - 1],
          'name': 'اختبار',
          'edition': {'identifier': id},
          'ayahs': [
            for (var i = 1; i <= surahLengths[surah - 1]; i++)
              {
                'number': offset + i,
                'numberInSurah': i,
                'text': id == 'quran-uthmani' ? 'اختبار $i' : 'Test fixture $i',
              },
          ],
        },
    ],
  };
}

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  test('catalogue has 114 surahs and the expected complete verse count', () {
    expect(surahNames.length, 114);
    expect(surahLengths.length, 114);
    expect(surahLengths.fold<int>(0, (a, b) => a + b), 6236);
    expect(surahNames[17], 'Al-Kahf');
  });
  test('Quran editions are matched by identifier even when order changes', () {
    final value = response(114);
    value['data'] = (value['data'] as List).reversed.toList();
    final reading = QuranReading.parse(value, 114);
    expect(reading.ayahs.last.reference, '114:6');
    expect(reading.ayahs.last.globalNumber, 6236);
    expect(reading.ayahs.first.meaning, 'Test fixture 1');
  });
  test(
    'rejects a wrong surah, missing verse, duplicate identity and wrong edition',
    () {
      expect(() => QuranReading.parse(response(), 2), throwsFormatException);
      final missing = response();
      missing['data'][0]['ayahs'].removeLast();
      expect(() => QuranReading.parse(missing, 1), throwsFormatException);
      final identity = response();
      identity['data'][1]['ayahs'][2]['number'] = 2;
      expect(() => QuranReading.parse(identity, 1), throwsFormatException);
      final edition = response();
      edition['data'][1]['edition']['identifier'] = 'en.other';
      expect(() => QuranReading.parse(edition, 1), throwsFormatException);
    },
  );
  test(
    'explicit offline save avoids all subsequent network requests',
    () async {
      var requests = 0;
      final cache = MemoryCache();
      final store = ReadingStore(
        preferences,
        cache: cache,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(utf8.encode(jsonEncode(response())), 200);
        }),
      );
      final value = await store.read(1);
      expect(await store.downloaded(), isEmpty);
      await store.save(value);
      expect((await store.read(1)).ayahs.length, 7);
      expect(requests, 1);
      expect(await store.downloaded(), {1});
      await store.remove(1);
      expect(await store.downloaded(), isEmpty);
      store.dispose();
    },
  );
  test(
    'corrupt or mismatched cached reading is removed before fetching',
    () async {
      final cache = MemoryCache();
      cache.values['quran-1'] = '{broken';
      final store = ReadingStore(preferences, cache: cache);
      expect(await store.cached(1), isNull);
      expect(cache.values, isEmpty);
      cache.values['quran-1'] = jsonEncode({
        'version': 1,
        'response': response(114),
      });
      expect(await store.cached(1), isNull);
      expect(cache.values, isEmpty);
      store.dispose();
    },
  );
  test(
    'bookmarks and position reject invalid verse references and persist',
    () async {
      final store = ReadingStore(preferences, cache: MemoryCache());
      await store.toggleBookmark('2:286');
      await store.setPosition(2, 286);
      expect(store.bookmarks, {'2:286'});
      expect(store.position, '2:286');
      await expectLater(store.toggleBookmark('2:287'), throwsArgumentError);
      await expectLater(store.setPosition(115, 1), throwsArgumentError);
      await store.toggleBookmark('2:286');
      expect(store.bookmarks, isEmpty);
      store.dispose();
    },
  );
  test('search tolerates Arabic marks and transliteration punctuation', () {
    expect(readingSearch('ٱلْفَاتِحَةِ'), readingSearch('الفاتحة'));
    expect(readingSearch('Al-Fatiha'), readingSearch('al fatiha'));
  });
  test(
    'published collection cache drops drafts and clears withdrawn readings',
    () async {
      final store = ReadingStore(preferences, cache: MemoryCache());
      await store.saveLibrary('https://example.org', [
        {
          'title': 'Approved reading',
          'collection': 'hizb',
          'published': true,
          'body': 'Reviewed content',
        },
        {'title': 'Draft', 'collection': 'hizb', 'published': false},
        {'title': 42, 'collection': 'hizb', 'published': true},
      ]);
      expect((await store.savedLibrary('https://example.org')).length, 1);
      expect(await store.savedLibrary('https://another.org'), isEmpty);
      await store.saveLibrary('https://example.org', []);
      expect(await store.savedLibrary('https://example.org'), isEmpty);
      store.dispose();
    },
  );
  test('daily dhikr goals are optional and preserve historical goals', () {
    final first = DateTime(2026, 9, 12), second = DateTime(2026, 9, 13);
    expect(const DhikrRoutine().count(100, first).days, isEmpty);
    var routine = const DhikrRoutine().setGoal(2, first).count(2, first);
    routine = routine.setGoal(3, second).count(3, second);
    expect(routine.streak(second), 2);
    expect(routine.days['2026-09-12']?['goal'], 2);
    expect(DhikrRoutine.decode(routine.encode()).todayCount(second), 3);
    expect(routine.count(-1, second).streak(second), 1);
    expect(DhikrRoutine.decode('{broken').goal, 0);
  });
  test('private Salah records migrate without losing prior counts', () {
    final record = SalahRecord.decode('{"fajr":12,"isha":4}');
    expect(record.total, 16);
    expect(record.history, isEmpty);
    expect(SalahRecord.decode(record.encode()).total, 16);
    expect(() => SalahRecord.decode('{"fajr":-1}'), throwsFormatException);
  });
  test(
    'private plan completion and undo keep remaining and history consistent',
    () {
      final now = DateTime(2026, 9, 13, 12);
      final record = const SalahRecord()
          .change('fajr', 5, now)
          .withGoal(2)
          .change('fajr', -1, now);
      expect(record.remaining['fajr'], 4);
      expect(record.completedToday(now), 1);
      expect(record.dailyGoal, 2);
      final undone = record.undo();
      expect(undone.remaining['fajr'], 5);
      expect(undone.completedToday(now), 0);
      expect(() => record.change('fajr', -5, now), throwsArgumentError);
      expect(SalahRecord.decode(record.encode()).history.length, 2);
    },
  );
}
