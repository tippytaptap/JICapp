import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

typedef Record = Map<String, dynamic>;
const prayerNames = {
  'fajr': 'Fajr',
  'zuhr': 'Dhuhr',
  'asr': 'Asr',
  'maghrib': 'Maghrib',
  'isha': 'Isha',
};
const capabilities = [
  'content',
  'media',
  'events',
  'announcements',
  'prayer_times',
  'team',
  'livestream',
  'tv',
  'broadcast',
  'forms_contact',
  'forms_madrassah',
  'forms_itikaaf',
  'users',
  'audit',
  'delete_content',
];

bool can(Record? profile, String permission) =>
    profile?['is_active'] == true &&
    (profile?['is_owner'] == true ||
        (profile?['permissions'] as List? ?? []).contains(permission));
bool active(Record? profile) => profile?['is_active'] == true;
bool owner(Record? profile) => active(profile) && profile?['is_owner'] == true;

List<Record> records(dynamic data) => data is List
    ? data.whereType<Map>().map((r) => Record.from(r)).toList()
    : [];

bool safeWebUrl(String value) {
  final url = Uri.tryParse(value);
  return url != null &&
      url.scheme == 'https' &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty &&
      !value.contains(RegExp(r'[\s\\]'));
}

bool adultProgramme(Record p) {
  if (p['audience'] != null) return ['adult', 'all'].contains(p['audience']);
  final groups = List<String>.from(p['groups'] ?? []);
  return groups.contains('education') &&
      !groups.contains('youth') &&
      !groups.contains('madrassah');
}

List<Record> weeklySessions(List<Record> programmes) => [
  for (final p in programmes.where(adultProgramme))
    for (final s in records(p['sessions']))
      if (s['day'] is int &&
          s['day'] >= 1 &&
          s['day'] <= 7 &&
          (RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch('${s['time']}') ||
              s['relativeTo'] == 'maghrib'))
        {...s, 'title': s['label'] ?? p['title'], 'programmeId': p['id']},
]..sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));

tz.TZDateTime centreNow(String zone, [DateTime? now]) =>
    tz.TZDateTime.from(now ?? DateTime.now(), zone == 'UTC' ? tz.UTC : tz.getLocation(zone));
String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
tz.TZDateTime? prayerMoment(String date, dynamic value, String zone) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$',
    caseSensitive: false,
  ).firstMatch('$value'.trim());
  final day = DateTime.tryParse(date);
  if (match == null || day == null || dateKey(day) != date) return null;
  var hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (minute > 59 || hour > 23 || (match[3] != null && (hour < 1 || hour > 12))) {
    return null;
  }
  if (match[3] != null) {
    hour = hour % 12 + (match[3]!.toUpperCase() == 'PM' ? 12 : 0);
  }
  return tz.TZDateTime(
    zone == 'UTC' ? tz.UTC : tz.getLocation(zone),
    day.year,
    day.month,
    day.day,
    hour,
    minute,
  );
}

String displayTime(dynamic value) {
  final moment = prayerMoment('2026-01-01', value, 'UTC');
  return moment == null ? '—' : DateFormat('h:mm a').format(moment);
}

List<Record> prayerTimeline(List<Record> days, String zone) => [
  for (final day in days)
    for (final p in prayerNames.entries)
      if (prayerMoment('${day['d_date']}', day['${p.key}_begins'], zone)
          case final moment?)
        {'name': p.value, 'at': moment.millisecondsSinceEpoch},
]..sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));

double qiblaBearing(double latitude, double longitude) {
  final lat = latitude * math.pi / 180;
  final kaaba = 21.422487 * math.pi / 180;
  final delta = (39.826206 - longitude) * math.pi / 180;
  return (math.atan2(
                math.sin(delta),
                math.cos(lat) * math.tan(kaaba) -
                    math.sin(lat) * math.cos(delta),
              ) *
              180 /
              math.pi +
          360) %
      360;
}

String csvCell(dynamic value) {
  var text = '$value';
  if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

String formsCsv(List<Record> rows) => [
  ['id', 'kind', 'status', 'created_at', 'response'].map(csvCell).join(','),
  for (final row in rows)
    [
      row['id'],
      row['kind'],
      row['status'],
      row['created_at'],
      row['payload'],
    ].map(csvCell).join(','),
].join('\r\n');
