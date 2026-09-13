import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'config.dart';
import 'models.dart';

const _prayerFirstId = 6100;
const _prayerCapacity = 35;
const _accountUpdateId = 6200;
const _bindingKey = 'community.push.binding.v1';
const _prayerPreference = 'community.prayer_reminders.v1';
const _signaturePreference = 'community.prayer_schedule.v1';

class PrayerReminder {
  final String name;
  final tz.TZDateTime at;
  const PrayerReminder(this.name, this.at);
}

class PrayerReminderPlan {
  final List<PrayerReminder> reminders;
  final String signature;
  const PrayerReminderPlan(this.reminders, this.signature);
}

/// Seven centre calendar dates, five begins times per day, and no invented time.
/// The signature includes elapsed prayers so minute refreshes do not repeatedly
/// cancel and rebuild an unchanged day's schedule.
PrayerReminderPlan planPrayerReminders(
  List<Record> days,
  String zone, {
  DateTime? now,
}) {
  final current = centreNow(zone, now);
  final first = tz.TZDateTime(
    current.location,
    current.year,
    current.month,
    current.day,
  );
  final end = tz.TZDateTime(
    current.location,
    current.year,
    current.month,
    current.day + 7,
  );
  final seen = <String>{};
  final timeline = prayerTimeline(days, zone)
      .where((prayer) {
        final at = prayer['at'] as int;
        return at >= first.millisecondsSinceEpoch &&
            at < end.millisecondsSinceEpoch &&
            seen.add('${prayer['name']}:$at');
      })
      .take(_prayerCapacity)
      .toList();
  return PrayerReminderPlan([
    for (final prayer in timeline)
      if ((prayer['at'] as int) > current.millisecondsSinceEpoch)
        PrayerReminder(
          prayer['name'] as String,
          tz.TZDateTime.fromMillisecondsSinceEpoch(
            current.location,
            prayer['at'] as int,
          ),
        ),
  ], jsonEncode({'zone': zone, 'date': dateKey(first), 'prayers': timeline}));
}

class _NotificationIssue implements Exception {
  final String message;
  const _NotificationIssue(this.message);
}

/// Owns explicit notification consent, device/account binding, and local prayer
/// schedules. Push messages never supply display text or a trusted record route.
class NotificationService extends ChangeNotifier {
  final Organisation organisation;
  final SupabaseClient? client;
  final SharedPreferences preferences;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  VoidCallback? onOpenInbox;
  VoidCallback? onOpenPrayers;

  NotificationService(
    this.organisation,
    this.client,
    this.preferences, {
    this.onOpenInbox,
    this.onOpenPrayers,
  });

  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  Future<void> _tail = Future.value();
  bool _localReady = false, _bindingLoaded = false, _disposed = false;
  bool _activeAccount = false, _pushRegistered = false;
  String? _observedUser, _token, _tokenOwner, _pendingOpen;
  int _accountGeneration = 0;
  List<Record> _latestPrayers = [];
  String? error;
  bool busy = false;
  int scheduledPrayerCount = 0;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get pushAvailable =>
      supported && pushEnabled && extensionsEnabled && client != null;
  bool get accountReady =>
      _activeAccount && _observedUser == client?.auth.currentUser?.id;
  bool get pushOptedIn {
    final user = client?.auth.currentUser?.id;
    return user != null &&
        (preferences.getBool('community.push.enabled.$user') ?? false);
  }

  bool get pushRegistered => pushOptedIn && accountReady && _pushRegistered;
  bool get prayerRemindersEnabled =>
      preferences.getBool(_prayerPreference) ?? false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Serialise token rotation, logout and settings updates. Auth observations
  /// themselves invalidate the generation immediately, before entering the queue.
  Future<bool> _run(Future<void> Function() operation) {
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        result.complete(false);
        return;
      }
      busy = true;
      _notify();
      try {
        await operation();
        result.complete(true);
      } catch (failure) {
        error = failure is _NotificationIssue
            ? failure.message
            : 'Notifications could not be updated. Check your connection and try again.';
        result.complete(false);
      } finally {
        busy = false;
        _notify();
      }
    });
    return result.future;
  }

  Future<void> initialise() async {
    if (!supported) return;
    await _run(() async {
      await _ensureLocal();
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          (payload == 'prayers' || payload == 'inbox')) {
        _open(payload!);
      }
      if (pushAvailable) await _loadBinding();
    });
  }

  Future<void> _loadBinding() async {
    if (_bindingLoaded) return;
    final encoded = await _secure.read(key: _bindingKey);
    if (encoded != null) {
      try {
        final binding = jsonDecode(encoded) as Map;
        _token = binding['token'] as String?;
        _tokenOwner = binding['user'] as String?;
      } catch (_) {
        // A damaged or restored binding must rotate the native token before use.
        _tokenOwner = 'unknown';
      }
    }
    _bindingLoaded = true;
  }

  Future<void> _ensureLocal() async {
    if (_localReady) return;
    if (!supported) {
      throw const _NotificationIssue(
        'Notification settings are available in the Android and iPhone app.',
      );
    }
    final ready = await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == 'prayers' || response.payload == 'inbox') {
          _open(response.payload!);
        }
      },
    );
    if (ready != true) {
      throw const _NotificationIssue(
        'Notifications are unavailable on this device.',
      );
    }
    _localReady = true;
  }

  void _open(String destination) {
    _pendingOpen = destination;
    dispatchPendingOpen();
  }

  /// Call after attaching navigator callbacks if launch processing ran earlier.
  void dispatchPendingOpen() {
    final callback = _pendingOpen == 'inbox'
        ? onOpenInbox
        : _pendingOpen == 'prayers'
        ? onOpenPrayers
        : null;
    if (callback == null) return;
    _pendingOpen = null;
    callback();
  }

  Future<void> _ensureFirebase() async {
    if (_messaging != null) return;
    if (!pushAvailable) {
      throw const _NotificationIssue(
        'Account notifications are not available in this build.',
      );
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 12));
      }
      _messaging = FirebaseMessaging.instance;
      // Build-time auto-init is also disabled in AndroidManifest and Info.plist.
      await _messaging!.setAutoInitEnabled(false);
      await _messaging!.setForegroundNotificationPresentationOptions();
      _tokenRefresh = _messaging!.onTokenRefresh.listen(
        (token) {
          final user = _observedUser;
          final generation = _accountGeneration;
          if (user == null || !accountReady || !pushOptedIn) return;
          unawaited(
            _run(() async {
              if (_sameAccount(user, generation) && pushOptedIn) {
                await _registerToken(token, user, generation);
              }
            }),
          );
        },
        onError: (_) {
          error =
              'Account notifications need reconnecting. Open notification settings to retry.';
          _notify();
        },
      );
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(
        (_) => _open('inbox'),
      );
      _foreground = FirebaseMessaging.onMessage.listen((_) {
        if (!accountReady || !pushRegistered) return;
        unawaited(
          _run(() async {
            // Recheck after the queue; sign-out may have started meanwhile.
            if (!accountReady || !pushRegistered) return;
            await _ensureLocal();
            await _local.show(
              id: _accountUpdateId,
              title: organisation.shortName,
              body: 'There is a new update in your account.',
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'community.account',
                  'Account updates',
                  channelDescription: 'New tasks and learning updates',
                  visibility: NotificationVisibility.private,
                ),
                iOS: DarwinNotificationDetails(),
              ),
              payload: 'inbox',
            );
          }),
        );
      });
      if (await _messaging!.getInitialMessage() != null) _open('inbox');
    } catch (_) {
      await _tokenRefresh?.cancel();
      await _opened?.cancel();
      await _foreground?.cancel();
      _tokenRefresh = null;
      _opened = null;
      _foreground = null;
      _messaging = null;
      throw const _NotificationIssue(
        'Account notifications could not connect on this device. Check the app setup and try again.',
      );
    }
  }

  bool _sameAccount(String user, int generation) =>
      generation == _accountGeneration &&
      _observedUser == user &&
      _activeAccount &&
      client?.auth.currentUser?.id == user;

  void _requireSameAccount(String user, int generation) {
    if (!_sameAccount(user, generation)) {
      throw const _NotificationIssue(
        'Your account changed. Check notification settings again.',
      );
    }
  }

  Future<void> _registerToken(String token, String user, int generation) async {
    _requireSameAccount(user, generation);
    if (_tokenOwner != null && _tokenOwner != user) {
      throw const _NotificationIssue(
        'This device must finish disconnecting from its previous account.',
      );
    }
    final previous = _token;
    await client!
        .rpc(
          'register_push_device',
          params: {
            'p_token': token,
            'p_previous_token': previous,
            'p_platform': defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
          },
        )
        .timeout(const Duration(seconds: 12));
    // Preserve which account made the request even if auth changed in flight.
    _token = token;
    _tokenOwner = user;
    await _secure.write(
      key: _bindingKey,
      value: jsonEncode({'token': token, 'user': user}),
    );
    _requireSameAccount(user, generation);
    _pushRegistered = true;
  }

  Future<void> _connect(
    String user,
    int generation, {
    required bool ask,
  }) async {
    await _loadBinding();
    await _ensureFirebase();
    _requireSameAccount(user, generation);
    final settings = ask
        ? await _messaging!.requestPermission(
            alert: true,
            badge: false,
            sound: true,
          )
        : await _messaging!.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw const _NotificationIssue(
        'Allow notifications in your phone settings, then try again.',
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _messaging!.getAPNSToken() == null) {
      throw const _NotificationIssue(
        'Apple notifications are not ready yet. Wait a moment, then tap reconnect.',
      );
    }
    _requireSameAccount(user, generation);
    if (_tokenOwner != user || _token == null) {
      // Rotation is required even if local secure storage was restored or lost.
      // A failed deletion prevents a new account from claiming the old endpoint.
      await _messaging!.setAutoInitEnabled(false);
      await _messaging!.deleteToken().timeout(const Duration(seconds: 12));
      _token = null;
      _tokenOwner = null;
      await _secure.delete(key: _bindingKey);
    }
    _requireSameAccount(user, generation);
    await _messaging!.setAutoInitEnabled(true);
    final token = await _messaging!.getToken().timeout(
      const Duration(seconds: 12),
    );
    if (token == null || token.isEmpty) {
      throw const _NotificationIssue(
        'This phone has not supplied a notification token. Try again shortly.',
      );
    }
    await _registerToken(token, user, generation);
  }

  /// Active profile is supplied by AppState; the server checks access again.
  Future<void> syncAccount({required bool activeAccount}) async {
    final user = activeAccount ? client?.auth.currentUser?.id : null;
    if (_observedUser != user || _activeAccount != activeAccount) {
      ++_accountGeneration;
      _observedUser = user;
      _activeAccount = activeAccount && user != null;
      _pushRegistered = false;
    }
    if (!supported || !pushAvailable) return;
    final generation = _accountGeneration;
    await _run(() async {
      await _loadBinding();
      if (user == null || !pushOptedIn) {
        if (_tokenOwner != null || _messaging != null) await _disconnect();
        return;
      }
      if (!_sameAccount(user, generation) || _pushRegistered) return;
      await _connect(user, generation, ask: false);
    });
  }

  Future<bool> setPushEnabled(bool enabled) => _run(() async {
    error = null;
    final user = client?.auth.currentUser?.id;
    if (user == null || !accountReady) {
      throw const _NotificationIssue(
        'Sign in with an active account to set account notifications.',
      );
    }
    if (!enabled) {
      await preferences.setBool('community.push.enabled.$user', false);
      await _disconnect();
      return;
    }
    final generation = _accountGeneration;
    try {
      await _connect(user, generation, ask: true);
      _requireSameAccount(user, generation);
      await preferences.setBool('community.push.enabled.$user', true);
    } catch (_) {
      // Permission or backend failure must not leave a newly enabled endpoint.
      if (!pushOptedIn) {
        try {
          await _disconnect();
        } catch (_) {
          // Keep the secure binding so rotation is mandatory before next use.
        }
      }
      rethrow;
    }
  });

  Future<void> _disconnect() async {
    _pushRegistered = false;
    await _loadBinding();
    String? failure;
    if (_token != null && _tokenOwner == client?.auth.currentUser?.id) {
      try {
        await client!
            .rpc('unregister_push_device', params: {'p_token': _token})
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        failure =
            'The server could not confirm device removal. The phone token will also be revoked.';
      }
    }
    if (_messaging != null || _tokenOwner != null) {
      try {
        await _ensureFirebase();
        await _messaging!.setAutoInitEnabled(false);
        await _messaging!.deleteToken().timeout(const Duration(seconds: 12));
        _token = null;
        _tokenOwner = null;
        await _secure.delete(key: _bindingKey);
      } catch (_) {
        failure =
            'Device notification removal is pending. Reconnect to finish disconnecting this phone.';
      }
    }
    if (_localReady) await _local.cancel(id: _accountUpdateId);
    if (failure != null) throw _NotificationIssue(failure);
  }

  /// Always call before Supabase signOut while the current JWT can remove its
  /// token. This method records failures and completes, so logout still proceeds.
  Future<void> prepareForSignOut() async {
    error = null;
    ++_accountGeneration;
    _observedUser = null;
    _activeAccount = false;
    _pushRegistered = false;
    if (supported && pushAvailable) await _run(_disconnect);
  }

  Future<bool> setPrayerRemindersEnabled(bool enabled) => _run(() async {
    error = null;
    await _ensureLocal();
    if (!enabled) {
      await _cancelPrayerSchedule();
      await preferences.setBool(_prayerPreference, false);
      scheduledPrayerCount = 0;
      await preferences.remove(_signaturePreference);
      return;
    }
    final allowed = defaultTargetPlatform == TargetPlatform.android
        ? await _local
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()!
              .requestNotificationsPermission()
        : await _local
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()!
              .requestPermissions(alert: true, sound: true);
    if (allowed != true) {
      throw const _NotificationIssue(
        'Allow notifications in your phone settings to receive prayer reminders.',
      );
    }
    await preferences.setBool(_prayerPreference, true);
    await _schedulePrayers(force: true);
  });

  Future<void> refreshPrayerSchedule(List<Record> days) async {
    _latestPrayers = days.map((day) => Record.from(day)).toList();
    if (!supported || !prayerRemindersEnabled) return;
    await _run(() => _schedulePrayers());
  }

  Future<void> _cancelPrayerSchedule() async {
    // Never cancelAll(): radio playback and unrelated notifications have their
    // own IDs and lifecycle. These IDs are reserved exclusively for prayers.
    for (var index = 0; index < _prayerCapacity; index++) {
      await _local.cancel(id: _prayerFirstId + index);
    }
  }

  Future<void> _schedulePrayers({bool force = false}) async {
    if (!prayerRemindersEnabled) return;
    final plan = planPrayerReminders(_latestPrayers, organisation.timeZone);
    scheduledPrayerCount = plan.reminders.length;
    final signature = '${organisation.shortName}:${plan.signature}';
    if (!force && preferences.getString(_signaturePreference) == signature) {
      return;
    }
    await _ensureLocal();
    await preferences.remove(_signaturePreference);
    await _cancelPrayerSchedule();
    try {
      for (var index = 0; index < plan.reminders.length; index++) {
        final reminder = plan.reminders[index];
        await _local.zonedSchedule(
          id: _prayerFirstId + index,
          title: '${reminder.name} begins',
          body: organisation.shortName,
          scheduledDate: reminder.at,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'community.prayer_begins',
              'Prayer begins reminders',
              channelDescription: 'The published prayer begins timetable',
              category: AndroidNotificationCategory.reminder,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: 'prayers',
        );
      }
      await preferences.setString(_signaturePreference, signature);
    } catch (_) {
      scheduledPrayerCount = 0;
      await _cancelPrayerSchedule();
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tokenRefresh?.cancel();
    _opened?.cancel();
    _foreground?.cancel();
    super.dispose();
  }
}
