import 'package:community_app/core/models.dart';
import 'package:community_app/core/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart';

void main() {
  setUpAll(initializeTimeZones);

  List<Record> timetable(String date, int days) => [
    for (var offset = 0; offset < days; offset++)
      {
        'd_date': dateKey(DateTime.parse(date).add(Duration(days: offset))),
        'fajr_begins': '05:00',
        'zuhr_begins': '13:00',
        'asr_begins': '16:30',
        'maghrib_begins': '18:00',
        'isha_begins': '20:00',
      },
  ];

  test('Schedules only seven published dates and at most 35 future alerts', () {
    final plan = planPrayerReminders(
      timetable('2026-09-14', 10),
      'Europe/London',
      now: DateTime.utc(2026, 9, 14),
    );
    expect(plan.reminders.length, 35);
    expect(dateKey(plan.reminders.last.at), '2026-09-20');
    expect(
      plan.reminders.every(
        (reminder) => reminder.at.isAfter(DateTime.utc(2026, 9, 14)),
      ),
      isTrue,
    );
  });

  test('DST change schedules centre time rather than fixed UTC offsets', () {
    final plan = planPrayerReminders(
      timetable('2026-10-24', 2),
      'Europe/London',
      now: DateTime.utc(2026, 10, 24),
    );
    final fajr = plan.reminders
        .where((reminder) => reminder.name == 'Fajr')
        .toList();
    expect(fajr[0].at.toUtc().hour, 4);
    expect(fajr[1].at.toUtc().hour, 5);
  });

  test('Missing, malformed, duplicate and elapsed times never add alerts', () {
    final day = {
      'd_date': '2026-09-14',
      'fajr_begins': '05:00',
      'zuhr_begins': '25:00',
      'asr_begins': '16:30',
    };
    final plan = planPrayerReminders(
      [
        day,
        day,
        {'d_date': 'not-a-date', 'fajr_begins': '05:00'},
      ],
      'Europe/London',
      now: DateTime.utc(2026, 9, 14, 9),
    );
    expect(plan.reminders.length, 1);
    expect(plan.reminders.single.name, 'Asr');
    expect(planPrayerReminders([], 'Europe/London').reminders, isEmpty);
  });

  test('Passing a prayer does not change an unchanged timetable signature', () {
    final rows = timetable('2026-09-14', 7);
    final early = planPrayerReminders(
      rows,
      'Europe/London',
      now: DateTime.utc(2026, 9, 14, 1),
    );
    final later = planPrayerReminders(
      rows,
      'Europe/London',
      now: DateTime.utc(2026, 9, 14, 9),
    );
    expect(early.signature, later.signature);
    expect(later.reminders.length, early.reminders.length - 1);
    final edited = rows.map((row) => Record.from(row)).toList();
    edited.first['isha_begins'] = '20:15';
    expect(
      planPrayerReminders(
        edited,
        'Europe/London',
        now: DateTime.utc(2026, 9, 14, 9),
      ).signature,
      isNot(later.signature),
    );
  });
}
