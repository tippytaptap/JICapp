import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionStore extends LocalStorage {
  const SessionStore() : super();
  static const storage = FlutterSecureStorage();
  static const key = 'community.auth';
  static String? memory;
  @override Future<void> initialize() async {}
  @override Future<bool> hasAccessToken() async => (await accessToken()) != null;
  @override Future<String?> accessToken() async => kIsWeb ? memory : storage.read(key: key);
  @override Future<void> persistSession(String persistSessionString) async {
    if (kIsWeb) { memory = persistSessionString; } else { await storage.write(key: key, value: persistSessionString); }
  }
  @override Future<void> removePersistedSession() async {
    memory = null;
    if (!kIsWeb) await storage.delete(key: key);
  }
}
