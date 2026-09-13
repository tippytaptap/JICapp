import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart';
import 'package:community_app/core/models.dart';

void main() {
  setUpAll(initializeTimeZones);
  test('Disabled owners and cosmetic labels never grant access', () {
    expect(can({'is_active': false, 'is_owner': true}, 'users'), false);
    expect(
      can({
        'is_active': true,
        'staff_kinds': ['admin'],
      }, 'users'),
      false,
    );
    expect(
      can({
        'is_active': true,
        'permissions': ['forms_contact'],
      }, 'forms_contact'),
      true,
    );
    expect(
      can({
        'is_active': true,
        'permissions': ['forms_contact'],
      }, 'forms_madrassah'),
      false,
    );
  });
  test('Adult courses exclude pupil and youth programmes', () {
    expect(
      adultProgramme({
        'groups': ['education', 'madrassah'],
      }),
      false,
    );
    expect(
      adultProgramme({
        'audience': 'adult',
        'groups': ['education'],
      }),
      true,
    );
    expect(
      weeklySessions([
        {
          'audience': 'adult',
          'groups': ['education'],
          'title': 'Lesson',
          'sessions': [
            {'day': 8, 'time': '12:00'},
            {'day': 1, 'time': '28:00'},
            {'day': 5, 'after': 'Maghrib'},
          ],
        },
      ]).length,
      1,
    );
  });
  test('Prayer times use the centre timezone through BST', () {
    expect(
      prayerMoment('2026-07-01', '13:00', 'Europe/London')!.toUtc().hour,
      12,
    );
    expect(
      prayerMoment('2026-12-01', '13:00', 'Europe/London')!.toUtc().hour,
      13,
    );
    expect(prayerMoment('2026-02-30', '13:00', 'Europe/London'), isNull);
    expect(displayTime('24:30'), '—');
    expect(displayTime('00:30'), '12:30 AM');
    expect(displayTime('1:30 PM'), '1:30 PM');
  });
  test(
    'Birmingham Qibla points southeast',
    () => expect(qiblaBearing(52.4862, -1.8904), closeTo(119, 3)),
  );
  test('Content cannot launch script URLs or credential URLs', () {
    expect(safeWebUrl('javascript:alert(1)'), false);
    expect(safeWebUrl('https://name:password@example.com'), false);
    expect(safeWebUrl('https://example.com/read'), true);
  });
  test('CSV quotes answers and neutralises formulas', () {
    expect(csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
    expect(csvCell('a,b'), '"a,b"');
    expect(csvCell(' +SUM(A1)'), startsWith('"\''));
  });
}
