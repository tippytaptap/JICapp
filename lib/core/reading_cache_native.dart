import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reading_cache.dart';

ReadingCache createReadingCache(SharedPreferences preferences) => _FileCache();

class _FileCache implements ReadingCache {
  Future<Directory> get directory async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/readings-v1').create(recursive: true);
  }

  Future<File> file(String key) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(key)) {
      throw ArgumentError('Invalid cache key');
    }
    return File('${(await directory).path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final item = await file(key);
    if (!await item.exists()) return null;
    if (await item.length() > 5000000) {
      await item.delete();
      return null;
    }
    return item.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    if (value.length > 2500000) throw StateError('Reading is too large');
    final target = await file(key);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(target.path);
  }

  @override
  Future<void> remove(String key) async {
    final item = await file(key);
    if (await item.exists()) await item.delete();
  }

  @override
  Future<Set<String>> keys() async => {
    await for (final item in (await directory).list())
      if (item is File && item.path.endsWith('.json'))
        item.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
  };
}
