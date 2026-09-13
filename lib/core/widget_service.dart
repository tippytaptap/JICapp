import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'config.dart';
import 'models.dart';

/// Native widgets share public prayer times only, never accounts or student data.
class PrayerWidgetService {
  static const appGroup = 'group.com.mastir.communityApp';
  static String? _lastPayload;
  static Future<void> _queue = Future<void>.value();
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> update(Organisation organisation, List<Record> days) {
    final request = _queue.then((_) => _update(organisation, days));
    // A failed platform call remains retryable and must not block later refreshes.
    _queue = request.catchError((Object _) {});
    return request;
  }

  static Future<void> _update(
    Organisation organisation,
    List<Record> days,
  ) async {
    if (!supported) return;
    final prayers = prayerTimeline(days, organisation.timeZone);
    final payload = jsonEncode({
      'organisation': organisation.shortName,
      'timeZone': organisation.timeZone,
      'prayers': prayers,
    });
    if (payload == _lastPayload) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(appGroup);
    }
    await HomeWidget.saveWidgetData('prayer_timeline', payload);
    await HomeWidget.updateWidget(
      androidName: 'PrayerWidget',
      iOSName: 'PrayerWidget',
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      await HomeWidget.scheduleWidgetUpdates(
        prayers
            .map(
              (p) => DateTime.fromMillisecondsSinceEpoch(
                p['at'] as int,
              ).add(const Duration(seconds: 1)),
            )
            .toList(),
        androidName: 'PrayerWidget',
      );
    }
    _lastPayload = payload;
  }

  static Future<Uri?> initialLink() async =>
      supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
  static Stream<Uri?> get links =>
      supported ? HomeWidget.widgetClicked : const Stream<Uri?>.empty();
}
