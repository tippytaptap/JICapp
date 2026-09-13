abstract class ReadingCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<Set<String>> keys();
}
