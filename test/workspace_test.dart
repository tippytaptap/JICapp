import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/core/app_state.dart';
import 'package:community_app/core/config.dart';
import 'package:community_app/core/models.dart';
import 'package:community_app/features/account.dart';
import 'package:community_app/features/workspace.dart';

void main() {
  testWidgets('Reading an update does not open or complete its task', (
    tester,
  ) async {
    var reads = 0, opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateCard(
            update: {
              'kind': 'task',
              'created_at': '2026-09-13T12:00:00Z',
              'read_at': null,
            },
            onOpen: () => opens++,
            onRead: () async {
              reads++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(opens, 0);
    expect(find.text('Completed'), findsNothing);
    await tester.tap(find.text('Open'));
    expect(opens, 1);
    expect(reads, 1);
  });

  testWidgets('A revoked account immediately loses an open private screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      Organisation({'website': 'https://example.org'}),
      null,
      await SharedPreferences.getInstance(),
    );
    state.profile = {'is_active': true, 'is_owner': true};
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGate(
          state,
          child: const Scaffold(body: Text('Private student detail')),
        ),
      ),
    );
    expect(find.text('Private student detail'), findsOneWidget);
    state.profile = {'is_active': false, 'is_owner': true};
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Private student detail'), findsNothing);
    expect(find.textContaining('active account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'Pagination hides previous private records during refresh and failure',
    (tester) async {
      var count = 0;
      final delayed = Completer<List<Record>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginatedRecords(
              loader: (_) {
                count++;
                return count == 1
                    ? Future.value([
                        {'title': 'Private answer'},
                      ])
                    : delayed.future;
              },
              itemBuilder: (row) => Text('${row['title']}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private answer'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(find.text('Private answer'), findsNothing);
      delayed.completeError(StateError('Access revoked'));
      await tester.pumpAndSettle();
      expect(find.text('Private answer'), findsNothing);
      expect(find.text('Could not load this page. Retry'), findsOneWidget);
    },
  );
}
