import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'models.dart';

/// Paired watches receive only public prayer times and explicitly shared counters.
/// A handoff replaces a confirmed snapshot; it never adds two devices' counts.
class WatchCounterSnapshot {
  const WatchCounterSnapshot({
    required this.count,
    required this.target,
    required this.raw,
  });
  final int count;
  final int target;
  final String raw;
  static WatchCounterSnapshot? parse(String? raw) {
    if (raw == null || raw.length > 2000) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      final count = value['count'];
      final target = value['target'];
      if (count is! int ||
          count < 0 ||
          count > 99999999 ||
          target is! int ||
          ![33, 99, 100].contains(target) ||
          value['sourceId'] is! String ||
          value['sessionId'] is! String ||
          value['revision'] is! int ||
          (value['revision'] as int) < 0 ||
          (value['sourceId'] as String).isEmpty ||
          (value['sourceId'] as String).length > 100 ||
          (value['sessionId'] as String).isEmpty ||
          (value['sessionId'] as String).length > 100) {
        return null;
      }
      return WatchCounterSnapshot(count: count, target: target, raw: raw);
    } catch (_) {
      return null;
    }
  }
}

class WatchService {
  static const _channel = MethodChannel('community/watch');
  static String? _lastTimeline;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static Future<void> update(
    Organisation organisation,
    List<Record> days,
  ) async {
    if (!supported) return;
    final raw = jsonEncode({
      'organisation': organisation.shortName,
      'timeZone': organisation.timeZone,
      'prayers': prayerTimeline(days, organisation.timeZone),
    });
    if (raw == _lastTimeline) return;
    await _channel.invokeMethod<void>('publishTimeline', raw);
    _lastTimeline = raw;
  }

  static Future<void> _counterQueue = Future<void>.value();
  static Future<void> sendCounter(int count, int target) {
    final request = _counterQueue.then((_) => _sendCounter(count, target));
    _counterQueue = request.catchError((Object _) {});
    return request;
  }

  static Future<void> _sendCounter(int count, int target) async {
    if (!supported) {
      throw UnsupportedError('Use a paired Android phone or iPhone.');
    }
    if (count < 0 || count > 99999999 || ![33, 99, 100].contains(target)) {
      throw ArgumentError('Invalid counter');
    }
    final preferences = await SharedPreferences.getInstance();
    var source = preferences.getString('watch.source');
    if (source == null) {
      source = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await preferences.setString('watch.source', source);
    }
    final revision = (preferences.getInt('watch.revision') ?? 0) + 1;
    await preferences.setInt('watch.revision', revision);
    final raw = jsonEncode({
      'sourceId': source,
      'sessionId': 'local',
      'revision': revision,
      'count': count,
      'target': target,
    });
    await _channel.invokeMethod<void>('publishCounter', raw);
  }

  static Future<WatchCounterSnapshot?> incomingCounter() async => supported
      ? WatchCounterSnapshot.parse(
          await _channel.invokeMethod<String>('getIncomingCounter'),
        )
      : null;
  static Future<void> markImported(WatchCounterSnapshot snapshot) async {
    if (supported) {
      await _channel.invokeMethod<void>('clearIncomingCounter', snapshot.raw);
    }
  }
}
