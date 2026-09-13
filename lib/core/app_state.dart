import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'models.dart';
import 'widget_service.dart';
import 'notification_service.dart';
import 'radio_controller.dart';

class AppState extends ChangeNotifier {
  final Organisation organisation;
  final SupabaseClient? client;
  final SharedPreferences preferences;
  AppState(this.organisation, this.client, this.preferences);
  RadioController? _radio;
  RadioController get radio => _radio ??= RadioController(organisation);
  late final notifications = NotificationService(
    organisation,
    client,
    preferences,
  );
  Record? profile;
  bool profileLoading = false, loading = true, stale = false;
  List<Record> programmes = [],
      defaults = [],
      prayers = [],
      events = [],
      announcements = [],
      library = [];
  Record branding = {}, livestream = {};
  StreamSubscription<AuthState>? _auth;
  int _authGeneration = 0;
  bool _refreshing = false;
  String? _observedAuthUser;
  bool get dark => preferences.getBool('dark') ?? false;
  String? get userId => client?.auth.currentUser?.id;
  String get today => dateKey(centreNow(organisation.timeZone));
  Record? get todayPrayers =>
      prayers.where((r) => r['d_date'] == today).firstOrNull;
  Future<void> initialise() async {
    defaults = records(
      jsonDecode(await rootBundle.loadString('assets/programmes.json')),
    );
    programmes = defaults;
    await notifications.initialise();
    _observedAuthUser = userId;
    _auth = client?.auth.onAuthStateChange.listen((event) {
      final identityChanged = _observedAuthUser != event.session?.user.id;
      if (identityChanged || event.session == null) {
        unawaited(notifications.syncAccount(activeAccount: false));
      }
      _observedAuthUser = event.session?.user.id;
      final generation = ++_authGeneration;
      // Keep unfinished forms mounted during a routine same-account refresh.
      // Identity changes still clear private data before another frame renders.
      if (identityChanged || event.session == null) profile = null;
      profileLoading = profile == null && event.session != null;
      notifyListeners();
      // Avoid awaiting Supabase calls inside its synchronous auth notification.
      unawaited(Future(() => refreshProfile(generation)));
    });
    await refresh();
  }

  Future<void> setDark(bool value) async {
    await preferences.setBool('dark', value);
    notifyListeners();
  }

  Future<void> refreshProfile([int? generation]) async {
    final current = generation ?? _authGeneration;
    if (client == null || userId == null) {
      profile = null;
      profileLoading = false;
      notifyListeners();
      return;
    }
    try {
      final result = await client!
          .rpc('get_my_profile')
          .timeout(const Duration(seconds: 20));
      if (current != _authGeneration) return;
      profile = result is List
          ? records(result).firstOrNull
          : result is Map
          ? Record.from(result)
          : null;
    } catch (_) {
      if (current == _authGeneration) profile = null;
    }
    if (current == _authGeneration) {
      profileLoading = false;
      unawaited(notifications.syncAccount(activeAccount: active(profile)));
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    stale = false;
    if (client != null) {
      Future<void> load(
        Future<dynamic> request,
        void Function(dynamic) accept,
      ) async {
        try {
          accept(await request.timeout(const Duration(seconds: 20)));
        } catch (_) {
          stale = true;
        }
      }

      await Future.wait([
        load(
          client!
              .from('prayer_times')
              .select()
              .gte('d_date', today)
              .order('d_date')
              .limit(8),
          (r) => prayers = records(r),
        ),
        load(
          client!
              .from('events')
              .select()
              .eq('published', true)
              .gte('event_date', today)
              .order('event_date')
              .limit(20),
          (r) => events = records(r),
        ),
        load(
          client!
              .from('announcements')
              .select()
              .eq('published', true)
              .lte('starts_at', DateTime.now().toUtc().toIso8601String())
              .order('created_at', ascending: false)
              .limit(10),
          (r) {
            announcements = records(r)
                .where(
                  (a) =>
                      a['expires_at'] == null ||
                      (DateTime.tryParse(
                            '${a['expires_at']}',
                          )?.isAfter(DateTime.now()) ??
                          false),
                )
                .toList();
          },
        ),
        load(
          client!
              .from('livestream_settings')
              .select()
              .eq('id', 1)
              .maybeSingle(),
          (r) => livestream = r == null ? {} : Record.from(r),
        ),
        load(
          client!
              .from('page_content')
              .select('content_key,content_value')
              .inFilter('content_key', [
                'programme_posters',
                'mobile_branding',
                'reading_library',
              ]),
          (r) {
            for (final row in records(r)) {
              dynamic value = row['content_value'];
              try {
                if (value is String) value = jsonDecode(value);
              } catch (_) {
                continue;
              }
              switch (row['content_key']) {
                case 'programme_posters':
                  programmes = records(value)
                      .where((p) => p['id'] is String && p['title'] is String)
                      .take(100)
                      .map((p) {
                        final original = defaults
                            .where(
                              (d) =>
                                  d['id'] == p['id'] &&
                                  d['schedule'] == p['schedule'],
                            )
                            .firstOrNull;
                        return {
                          if (original != null)
                            'audience': original['audience'],
                          if (original != null)
                            'sessions': original['sessions'],
                          ...p,
                        };
                      })
                      .toList();
                case 'mobile_branding':
                  if (value is Map) branding = Record.from(value);
                case 'reading_library':
                  library = records(
                    value,
                  ).where((r) => r['published'] == true).take(500).toList();
              }
            }
          },
        ),
        refreshProfile(),
      ]);
    }
    loading = false;
    _refreshing = false;
    try {
      await PrayerWidgetService.update(organisation, prayers);
    } catch (_) {
      // Widget configuration must not prevent the in-app timetable loading.
    }
    unawaited(notifications.refreshPrayerSchedule(prayers));
    notifyListeners();
  }

  String? image(dynamic value) {
    final resolved = organisation.resolveImage(value);
    if (resolved == null) return null;
    if (value is String &&
        value.startsWith('/posters/') &&
        defaults.any((p) => p['image'] == value)) {
      return 'assets$value';
    }
    return resolved;
  }

  @override
  void dispose() {
    _auth?.cancel();
    notifications.dispose();
    _radio?.dispose();
    super.dispose();
  }
}
