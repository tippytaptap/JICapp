import 'dart:convert';
import 'models.dart';

String personalDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class DhikrRoutine {
  final int goal;
  final Map<String, Record> days;
  const DhikrRoutine({this.goal = 0, this.days = const {}});
  factory DhikrRoutine.decode(String? raw) {
    try {
      final value = jsonDecode(raw ?? '{}');
      if (value is! Map) return const DhikrRoutine();
      final goal = value['goal'];
      final days = <String, Record>{};
      if (value['days'] is Map) {
        for (final entry in (value['days'] as Map).entries) {
          final row = entry.value;
          if (entry.key is String &&
              DateTime.tryParse(entry.key) != null &&
              row is Map &&
              row['count'] is int &&
              row['goal'] is int &&
              row['count'] >= 0 &&
              row['count'] <= 99999999 &&
              row['goal'] > 0 &&
              row['goal'] <= 999999) {
            days[entry.key] = Record.from(row);
          }
        }
      }
      return DhikrRoutine(
        goal: goal is int && goal >= 0 && goal <= 999999 ? goal : 0,
        days: _recent(days),
      );
    } catch (_) {
      return const DhikrRoutine();
    }
  }
  static Map<String, Record> _recent(Map<String, Record> days) {
    final keys = days.keys.toList()..sort((a, b) => b.compareTo(a));
    return {for (final key in keys.take(90)) key: days[key]!};
  }

  int todayCount(DateTime now) =>
      (days[personalDate(now)]?['count'] as int?) ?? 0;
  DhikrRoutine setGoal(int value, DateTime now) {
    if (value < 0 || value > 999999) throw ArgumentError('Invalid goal');
    final key = personalDate(now);
    return DhikrRoutine(
      goal: value,
      days: _recent({
        ...days,
        if (value > 0) key: {'count': todayCount(now), 'goal': value},
      }),
    );
  }

  DhikrRoutine count(int delta, DateTime now) {
    if (goal == 0) return this;
    final key = personalDate(now);
    return DhikrRoutine(
      goal: goal,
      days: _recent({
        ...days,
        key: {
          'count': (todayCount(now) + delta).clamp(0, 99999999),
          'goal': goal,
        },
      }),
    );
  }

  int streak(DateTime now) {
    var day = DateTime.utc(now.year, now.month, now.day);
    bool reached(DateTime date) {
      final row = days[personalDate(date)];
      return row != null && row['count'] >= row['goal'];
    }

    if (!reached(day)) day = day.subtract(const Duration(days: 1));
    var result = 0;
    while (reached(day) && result < 90) {
      result++;
      day = day.subtract(const Duration(days: 1));
    }
    return result;
  }

  String encode() => jsonEncode({'goal': goal, 'days': days});
}

class SalahRecord {
  final Map<String, int> remaining;
  final List<Record> history;
  final int dailyGoal;
  const SalahRecord({
    this.remaining = const {},
    this.history = const [],
    this.dailyGoal = 0,
  });
  int get total => remaining.values.fold(0, (a, b) => a + b);
  factory SalahRecord.decode(String? raw) {
    final value = jsonDecode(raw ?? '{}');
    if (value is! Map) throw const FormatException('Invalid private record');
    final counts = value.containsKey('version') ? value['remaining'] : value;
    if (counts is! Map ||
        (value.containsKey('version') && value['version'] != 1)) {
      throw const FormatException('Unsupported private record');
    }
    final remaining = <String, int>{};
    for (final key in prayerNames.keys) {
      final count = counts[key] ?? 0;
      if (count is! int || count < 0 || count > 999999) {
        throw const FormatException('Invalid prayer count');
      }
      remaining[key] = count;
    }
    final history = records(value['history'])
        .where(
          (e) =>
              prayerNames.containsKey(e['prayer']) &&
              e['delta'] is int &&
              (e['delta'] as int).abs() <= 999999 &&
              e['at'] is String &&
              DateTime.tryParse(e['at']) != null,
        )
        .take(200)
        .toList();
    final goal = value['dailyGoal'] ?? 0;
    if (goal is! int || goal < 0 || goal > 50) {
      throw const FormatException('Invalid personal goal');
    }
    return SalahRecord(remaining: remaining, history: history, dailyGoal: goal);
  }
  SalahRecord change(String prayer, int delta, DateTime now) {
    if (!prayerNames.containsKey(prayer) || delta == 0) {
      throw ArgumentError('Invalid prayer change');
    }
    final next = (remaining[prayer] ?? 0) + delta;
    if (next < 0 || next > 999999) {
      throw ArgumentError('Prayer count is out of range');
    }
    return SalahRecord(
      remaining: {...remaining, prayer: next},
      dailyGoal: dailyGoal,
      history: [
        {'prayer': prayer, 'delta': delta, 'at': now.toIso8601String()},
        ...history,
      ].take(200).toList(),
    );
  }

  SalahRecord undo() {
    if (history.isEmpty) return this;
    final entry = history.first;
    final next = (remaining[entry['prayer']] ?? 0) - (entry['delta'] as int);
    if (next < 0 || next > 999999) {
      throw StateError('This entry cannot be undone');
    }
    return SalahRecord(
      remaining: {...remaining, entry['prayer']: next},
      history: history.skip(1).toList(),
      dailyGoal: dailyGoal,
    );
  }

  SalahRecord withGoal(int goal) {
    if (goal < 0 || goal > 50) throw ArgumentError('Invalid daily goal');
    return SalahRecord(remaining: remaining, history: history, dailyGoal: goal);
  }

  int completedToday(DateTime now) => history
      .where(
        (entry) =>
            entry['delta'] < 0 &&
            personalDate(DateTime.parse(entry['at']).toLocal()) ==
                personalDate(now),
      )
      .fold<int>(0, (total, entry) => total - (entry['delta'] as int));
  String encode() => jsonEncode({
    'version': 1,
    'remaining': remaining,
    'history': history,
    'dailyGoal': dailyGoal,
  });
}
