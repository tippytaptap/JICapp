import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/core/app_state.dart';
import 'package:community_app/core/config.dart';
import 'package:community_app/core/models.dart';
import 'package:community_app/features/account.dart';

class SessionState extends AppState {
  String? identity = 'account-a';
  SessionState(SharedPreferences preferences)
    : super(
        Organisation({
          'name': 'Centre',
          'radio': 'https://example.org/radio',
          'website': 'https://example.org',
        }),
        null,
        preferences,
      ) {
    profile = {
      'is_active': true,
      'is_owner': false,
      'permissions': ['forms_custom', 'content'],
    };
  }
  @override
  String? get userId => identity;
  void change({String? user, Record? nextProfile}) {
    identity = user;
    profile = nextProfile;
    notifyListeners();
  }
}

void main() {
  late SessionState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = SessionState(await SharedPreferences.getInstance());
  });
  testWidgets(
    'captured private record is never mounted for another signed-in account',
    (tester) async {
      // Real affected routes pass a student/fee record through a widget constructor.
      final captured = {
        'name': 'Private student A',
        'balance': 'Private fee £25.00',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AccountGate(
            state,
            child: Column(
              children: [Text(captured['name']!), Text(captured['balance']!)],
            ),
          ),
        ),
      );
      expect(find.text('Private student A'), findsOneWidget);
      state.change(user: 'account-b', nextProfile: {...state.profile!});
      await tester.pump();
      expect(find.text('Private student A'), findsNothing);
      expect(find.text('Private fee £25.00'), findsNothing);
      expect(find.text('Return to account'), findsOneWidget);
      // Returning to the old identity does not reactivate an obsolete private route.
      state.change(user: 'account-a', nextProfile: {...state.profile!});
      await tester.pump();
      expect(find.text('Private student A'), findsNothing);
    },
  );
  testWidgets('generic route closes when owner or permissions scope changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGate(state, child: const Text('Captured staff-only note')),
      ),
    );
    state.change(
      user: 'account-a',
      nextProfile: {
        'is_active': true,
        'is_owner': false,
        'permissions': ['content'],
      },
    );
    await tester.pump();
    expect(find.text('Captured staff-only note'), findsNothing);
    expect(find.text('Return to account'), findsOneWidget);
  });
  testWidgets(
    'routine same-account refresh and reordered permissions preserve the page',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountGate(
            state,
            child: const Scaffold(
              body: TextField(decoration: InputDecoration(labelText: 'Draft')),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Unfinished work');
      state.change(
        user: 'account-a',
        nextProfile: {
          'is_active': true,
          'is_owner': false,
          'permissions': ['content', 'forms_custom'],
        },
      );
      await tester.pump();
      expect(find.text('Unfinished work'), findsOneWidget);
      expect(find.text('Return to account'), findsNothing);
    },
  );
  testWidgets('sign-out followed by sign-in cannot reopen a captured page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountGate(state, child: const Text('Captured record')),
      ),
    );
    state.change(user: null, nextProfile: null);
    await tester.pump();
    state.change(
      user: 'account-a',
      nextProfile: {
        'is_active': true,
        'is_owner': false,
        'permissions': ['forms_custom', 'content'],
      },
    );
    await tester.pump();
    expect(find.text('Captured record'), findsNothing);
  });
}
