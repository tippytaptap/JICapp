import 'package:shared_preferences/shared_preferences.dart';
import 'reading_cache.dart';

ReadingCache createReadingCache(SharedPreferences preferences) =>
    _BrowserCache(preferences);

class _BrowserCache implements ReadingCache {
  final SharedPreferences preferences;
  _BrowserCache(this.preferences);
  static const prefix = 'reading.cache.';
  // Browser storage is shared with other preferences. Native apps use files.
  static const maxCharacters = 1500000;
  @override
  Future<String?> read(String key) async =>
      preferences.getString('$prefix$key');
  @override
  Future<void> write(String key, String value) async {
    final used = preferences
        .getKeys()
        .where((k) => k.startsWith(prefix) && k != '$prefix$key')
        .fold<int>(
          0,
          (sum, k) => sum + (preferences.getString(k)?.length ?? 0),
        );
    if (used + value.length > maxCharacters) {
      throw StateError('Browser storage is full. Remove a downloaded reading.');
    }
    if (!await preferences.setString('$prefix$key', value)) {
      throw StateError('The reading could not be saved');
    }
  }

  @override
  Future<void> remove(String key) async => preferences.remove('$prefix$key');
  @override
  Future<Set<String>> keys() async => preferences
      .getKeys()
      .where((k) => k.startsWith(prefix))
      .map((k) => k.substring(prefix.length))
      .toSet();
}
