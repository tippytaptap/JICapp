import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'reading_cache.dart';
import 'reading_cache_web.dart'
    if (dart.library.io) 'reading_cache_native.dart'
    as platform;

// Catalogue metadata: https://api.alquran.cloud/v1/surah, checked 2026-09-13.
// Text is downloaded unchanged from the named editions, never generated.
const surahNames = [
  'Al-Fatiha',
  'Al-Baqara',
  'Aal-i-Imran',
  'An-Nisa',
  'Al-Maida',
  "Al-An'am",
  "Al-A'raf",
  'Al-Anfal',
  'At-Tawba',
  'Yunus',
  'Hud',
  'Yusuf',
  "Ar-Ra'd",
  'Ibrahim',
  'Al-Hijr',
  'An-Nahl',
  'Al-Isra',
  'Al-Kahf',
  'Maryam',
  'Ta-Ha',
  'Al-Anbiya',
  'Al-Hajj',
  "Al-Mu'minun",
  'An-Nur',
  'Al-Furqan',
  "Ash-Shu'ara",
  'An-Naml',
  'Al-Qasas',
  'Al-Ankabut',
  'Ar-Rum',
  'Luqman',
  'As-Sajda',
  'Al-Ahzab',
  'Saba',
  'Fatir',
  'Ya-Sin',
  'As-Saffat',
  'Sad',
  'Az-Zumar',
  'Ghafir',
  'Fussilat',
  'Ash-Shura',
  'Az-Zukhruf',
  'Ad-Dukhan',
  'Al-Jathiya',
  'Al-Ahqaf',
  'Muhammad',
  'Al-Fath',
  'Al-Hujurat',
  'Qaf',
  'Adh-Dhariyat',
  'At-Tur',
  'An-Najm',
  'Al-Qamar',
  'Ar-Rahman',
  "Al-Waqi'a",
  'Al-Hadid',
  'Al-Mujadila',
  'Al-Hashr',
  'Al-Mumtahana',
  'As-Saff',
  "Al-Jumu'a",
  'Al-Munafiqun',
  'At-Taghabun',
  'At-Talaq',
  'At-Tahrim',
  'Al-Mulk',
  'Al-Qalam',
  'Al-Haqqa',
  "Al-Ma'arij",
  'Nuh',
  'Al-Jinn',
  'Al-Muzzammil',
  'Al-Muddaththir',
  'Al-Qiyama',
  'Al-Insan',
  'Al-Mursalat',
  'An-Naba',
  "An-Nazi'at",
  'Abasa',
  'At-Takwir',
  'Al-Infitar',
  'Al-Mutaffifin',
  'Al-Inshiqaq',
  'Al-Buruj',
  'At-Tariq',
  "Al-A'la",
  'Al-Ghashiya',
  'Al-Fajr',
  'Al-Balad',
  'Ash-Shams',
  'Al-Layl',
  'Ad-Duha',
  'Ash-Sharh',
  'At-Tin',
  'Al-Alaq',
  'Al-Qadr',
  'Al-Bayyina',
  'Az-Zalzala',
  'Al-Adiyat',
  "Al-Qari'a",
  'At-Takathur',
  'Al-Asr',
  'Al-Humaza',
  'Al-Fil',
  'Quraysh',
  "Al-Ma'un",
  'Al-Kawthar',
  'Al-Kafirun',
  'An-Nasr',
  'Al-Masad',
  'Al-Ikhlas',
  'Al-Falaq',
  'An-Nas',
];
const surahLengths = [
  7,
  286,
  200,
  176,
  120,
  165,
  206,
  75,
  129,
  109,
  123,
  111,
  43,
  52,
  99,
  128,
  111,
  110,
  98,
  135,
  112,
  78,
  118,
  64,
  77,
  227,
  93,
  88,
  69,
  60,
  34,
  30,
  73,
  54,
  45,
  83,
  182,
  88,
  75,
  85,
  54,
  53,
  89,
  59,
  37,
  35,
  38,
  29,
  18,
  45,
  60,
  49,
  62,
  55,
  78,
  96,
  29,
  22,
  24,
  13,
  14,
  11,
  11,
  18,
  12,
  12,
  30,
  52,
  52,
  44,
  28,
  28,
  20,
  56,
  40,
  31,
  50,
  40,
  46,
  42,
  29,
  19,
  36,
  25,
  22,
  17,
  19,
  26,
  30,
  20,
  15,
  21,
  11,
  8,
  8,
  19,
  5,
  8,
  8,
  11,
  11,
  8,
  3,
  9,
  5,
  4,
  7,
  3,
  6,
  3,
  5,
  4,
  5,
  6,
];

String readingSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll(RegExp(r"[\s'’\-]"), '');

class QuranAyah {
  final int surah, number, globalNumber;
  final String arabic, meaning;
  const QuranAyah(
    this.surah,
    this.number,
    this.globalNumber,
    this.arabic,
    this.meaning,
  );
  String get reference => '$surah:$number';
  bool matches(String query) => readingSearch(
    '$reference $arabic $meaning',
  ).contains(readingSearch(query));
}

class QuranReading {
  final int surah;
  final String arabicName;
  final List<QuranAyah> ayahs;
  final Record payload;
  const QuranReading(this.surah, this.arabicName, this.ayahs, this.payload);

  factory QuranReading.parse(dynamic raw, int expectedSurah) {
    if (expectedSurah < 1 ||
        expectedSurah > 114 ||
        raw is! Map ||
        raw['code'] != 200 ||
        raw['data'] is! List) {
      throw const FormatException('Invalid Quran response');
    }
    final editions = records(raw['data']);
    if (editions.length != 2) {
      throw const FormatException('Incomplete Quran editions');
    }
    Record edition(String id) => editions.singleWhere(
      (e) => e['edition'] is Map && e['edition']['identifier'] == id,
      orElse: () => throw const FormatException('Incorrect Quran edition'),
    );
    final arabic = edition('quran-uthmani');
    final english = edition('en.sahih');
    final length = surahLengths[expectedSurah - 1];
    for (final e in [arabic, english]) {
      if (e['number'] != expectedSurah ||
          e['numberOfAyahs'] != length ||
          e['ayahs'] is! List ||
          (e['ayahs'] as List).length != length) {
        throw const FormatException('Incorrect surah or verse count');
      }
    }
    final a = records(arabic['ayahs']);
    final b = records(english['ayahs']);
    if (a.length != length || b.length != length) {
      throw const FormatException('Invalid verse records');
    }
    final offset = surahLengths
        .take(expectedSurah - 1)
        .fold<int>(0, (sum, n) => sum + n);
    final ayahs = <QuranAyah>[];
    for (var index = 0; index < length; index++) {
      for (final row in [a[index], b[index]]) {
        if (row['numberInSurah'] != index + 1 ||
            row['number'] != offset + index + 1 ||
            row['text'] is! String ||
            (row['text'] as String).trim().isEmpty ||
            (row['text'] as String).length > 30000) {
          throw const FormatException('Verse identity or text is invalid');
        }
      }
      if (!RegExp(r'[\u0621-\u064A]').hasMatch(a[index]['text'])) {
        throw const FormatException('Arabic edition is invalid');
      }
      ayahs.add(
        QuranAyah(
          expectedSurah,
          index + 1,
          offset + index + 1,
          a[index]['text'],
          b[index]['text'],
        ),
      );
    }
    if (arabic['name'] is! String) {
      throw const FormatException('Surah name is missing');
    }
    return QuranReading(expectedSurah, arabic['name'], ayahs, Record.from(raw));
  }
}

class ReadingStore {
  final SharedPreferences preferences;
  final ReadingCache cache;
  http.Client _client;
  ReadingStore(this.preferences, {ReadingCache? cache, http.Client? client})
    : cache = cache ?? platform.createReadingCache(preferences),
      _client = client ?? http.Client();
  void dispose() => _client.close();
  void cancelRequests() {
    _client.close();
    _client = http.Client();
  }

  Future<QuranReading?> cached(int surah) async {
    final key = 'quran-$surah';
    final text = await cache.read(key);
    if (text == null) return null;
    try {
      final stored = jsonDecode(text);
      if (stored is! Map || stored['version'] != 1) {
        throw const FormatException('Unknown reading version');
      }
      return QuranReading.parse(stored['response'], surah);
    } catch (_) {
      await cache.remove(key);
      return null;
    }
  }

  Future<QuranReading> read(int surah) async {
    final saved = await cached(surah);
    if (saved != null) return saved;
    final response = await _client
        .get(
          Uri.https(
            'api.alquran.cloud',
            '/v1/surah/$surah/editions/quran-uthmani,en.sahih',
          ),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 || response.bodyBytes.length > 2000000) {
      throw StateError('The reading service is unavailable');
    }
    return QuranReading.parse(
      jsonDecode(utf8.decode(response.bodyBytes)),
      surah,
    );
  }

  Future<void> save(QuranReading reading) => cache.write(
    'quran-${reading.surah}',
    jsonEncode({
      'version': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'source': 'https://alquran.cloud',
      'arabicSource': 'Tanzil Project — https://tanzil.net',
      'translation': 'Sahih International (en.sahih)',
      'response': reading.payload,
    }),
  );
  Future<void> remove(int surah) => cache.remove('quran-$surah');
  Future<Set<int>> downloaded() async => {
    for (final key in await cache.keys())
      if (RegExp(r'^quran-\d+$').hasMatch(key)) int.parse(key.substring(6)),
  };

  Set<String> get bookmarks =>
      (preferences.getStringList('quran.bookmarks') ?? [])
          .where(validReference)
          .take(500)
          .toSet();
  static bool validReference(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final surah = int.tryParse(parts[0]), ayah = int.tryParse(parts[1]);
    return surah != null &&
        surah >= 1 &&
        surah <= 114 &&
        ayah != null &&
        ayah >= 1 &&
        ayah <= surahLengths[surah - 1];
  }

  Future<void> toggleBookmark(String reference) async {
    if (!validReference(reference)) throw ArgumentError('Invalid verse');
    final next = bookmarks;
    if (!next.remove(reference)) {
      if (next.length >= 500) {
        throw StateError('Remove a bookmark to add another');
      }
      next.add(reference);
    }
    if (!await preferences.setStringList('quran.bookmarks', next.toList())) {
      throw StateError('Your bookmark could not be saved');
    }
  }

  String get position {
    final saved =
        '${preferences.getInt('quran.surah') ?? 1}:'
        '${preferences.getInt('quran.ayah') ?? 1}';
    return validReference(saved) ? saved : '1:1';
  }

  Future<void> setPosition(int surah, int ayah) async {
    if (!validReference('$surah:$ayah')) throw ArgumentError('Invalid verse');
    await preferences.setInt('quran.surah', surah);
    await preferences.setInt('quran.ayah', ayah);
  }

  String libraryKey(String organisation) {
    final encoded = base64Url
        .encode(utf8.encode(organisation))
        .replaceAll('=', '');
    if (encoded.length > 140)
      throw ArgumentError('Organisation URL is too long');
    return 'library-$encoded';
  }

  Future<List<Record>> savedLibrary(String organisation) async {
    final text = await cache.read(libraryKey(organisation));
    if (text == null) return [];
    try {
      return validateLibrary(jsonDecode(text));
    } catch (_) {
      await cache.remove(libraryKey(organisation));
      return [];
    }
  }

  Future<void> saveLibrary(String organisation, dynamic value) =>
      cache.write(libraryKey(organisation), jsonEncode(validateLibrary(value)));

  static List<Record> validateLibrary(dynamic value) {
    if (value is! List) throw const FormatException('Invalid reading library');
    const collections = {'dalail', 'dhikr', 'hadith', 'hizb', 'guides'};
    return records(value)
        .where(
          (r) =>
              r['published'] == true &&
              r['title'] is String &&
              (r['title'] as String).isNotEmpty &&
              collections.contains(r['collection']) &&
              [
                'title',
                'arabic',
                'text',
                'body',
                'reference',
                'source',
                'url',
              ].every(
                (key) =>
                    r[key] == null ||
                    (r[key] is String && (r[key] as String).length <= 200000),
              ),
        )
        .take(500)
        .toList();
  }
}
