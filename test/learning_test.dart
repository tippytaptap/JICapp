import 'package:flutter_test/flutter_test.dart';
import 'package:community_app/features/learning.dart';

void main() {
  test('register changes leave every unselected student untouched', () {
    final changes = buildAttendanceChanges(
      {'selected-student': 'late'},
      {
        'selected-student': 'Arrived after the start',
        'unselected-student': 'Existing note',
      },
    );
    expect(changes, [
      {
        'student_id': 'selected-student',
        'status': 'late',
        'note': 'Arrived after the start',
      },
    ]);
    expect(buildAttendanceChanges({}, {'unselected-student': 'Note'}), isEmpty);
  });
  test('register batch rejects unsupported marks instead of defaulting', () {
    expect(
      () => buildAttendanceChanges({'student': 'unknown'}, {}),
      throwsArgumentError,
    );
    expect(
      () => buildAttendanceChanges(
        {'student': 'present'},
        {'student': 'x' * 2001},
      ),
      throwsArgumentError,
    );
    expect(
      () => buildAttendanceChanges({
        for (var n = 0; n < 201; n++) '$n': 'absent',
      }, {}),
      throwsArgumentError,
    );
  });
}
