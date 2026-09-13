import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/core/app_state.dart';
import 'package:community_app/core/config.dart';
import 'package:community_app/core/models.dart';
import 'package:community_app/features/account.dart';
import 'package:community_app/features/custom_forms.dart';
import 'package:community_app/features/user_management.dart';
import 'package:community_app/features/learning_management.dart';

void main() {
  test('Hidden answers are omitted and visible numeric answers are typed', () {
    final fields = <Record>[
      {'id': 'contact', 'type': 'checkbox'},
      {
        'id': 'phone',
        'type': 'phone',
        'required': true,
        'show_when': {'field': 'contact', 'operator': 'equals', 'value': true},
      },
      {'id': 'places', 'type': 'number'},
    ];
    expect(
      visibleAnswers(fields, {
        'contact': false,
        'phone': '07123456789',
        'places': '2',
      }),
      {'contact': false, 'places': 2},
    );
    expect(fieldVisible(fields[1], {'contact': true}), isTrue);
    expect(fieldError(fields[1], ''), isNotNull);
    expect(
      fieldVisible(
        {
          ...fields[1],
          'show_when': {
            'field': 'contact',
            'operator': 'equals',
            'value': 'true',
          },
        },
        {'contact': true},
      ),
      isFalse,
    );
  });
  test(
    'Validation rejects impossible dates, nonfinite numbers, invalid choices and unchecked consent',
    () {
      expect(fieldError({'type': 'date'}, '2026-02-30'), isNotNull);
      expect(fieldError({'type': 'date'}, '2028-02-29'), isNull);
      expect(fieldError({'type': 'number'}, 'NaN'), isNotNull);
      expect(fieldError({'type': 'number'}, '1000000000001'), isNotNull);
      expect(
        fieldError({'type': 'checkbox', 'required': true}, false),
        isNotNull,
      );
      expect(fieldError({'type': 'checkbox', 'required': true}, true), isNull);
      expect(
        fieldError(
          {
            'type': 'multiselect',
            'options': ['A', 'B'],
          },
          ['A', 'A'],
        ),
        isNotNull,
      );
      expect(
        fieldError(
          {
            'type': 'multiselect',
            'options': ['A', 'B'],
          },
          ['C'],
        ),
        isNotNull,
      );
      expect(
        fieldError({
          'type': 'select',
          'options': ['A'],
        }, 'A'),
        isNull,
      );
    },
  );
  test(
    'Uploads reject unsupported files, empty bytes and oversized selections before reading',
    () {
      expect(uploadError('portrait.PNG', 1024, 'image'), isNull);
      expect(uploadError('details.pdf', 1024, 'image'), isNotNull);
      expect(uploadError('script.js', 1024, 'file'), isNotNull);
      expect(uploadError('notes.pdf', 0, 'file'), isNotNull);
      expect(uploadError('notes.pdf', 10 * 1024 * 1024 + 1, 'file'), isNotNull);
      expect(uploadError('notes.zip', 10 * 1024 * 1024, 'file'), isNull);
    },
  );
  test('CSV protects formula names and preserves structured answers', () {
    final csv = responsesCsv([
      {
        'id': 'id',
        'kind': 'custom',
        'schema_snapshot': {'title': '=IMPORTXML("x")'},
        'status': 'new',
        'created_at': '2026-09-13',
        'form_version': 2,
        'payload': {
          'message': 'first\nsecond',
          'choices': ['A', 'B'],
        },
      },
    ]);
    expect(csv, contains("'=IMPORTXML"));
    expect(csv, contains('choices'));
    expect(csv, contains('first\nsecond'));
  });
  test(
    'CSV neutralises formula prefixes after invisible control characters',
    () {
      expect(formCsvCell('\u0000=1+1'), startsWith("\"'"));
      expect(formCsvCell('Normal text'), '"Normal text"');
    },
  );
  test(
    'Delegated managers cannot edit owners, self or more privileged accounts',
    () {
      final manager = <String, dynamic>{
        'id': 'manager',
        'is_active': true,
        'is_owner': false,
        'permissions': ['users', 'forms_contact'],
      };
      expect(
        canManagePerson(manager, {
          'id': 'peer',
          'permissions': ['forms_contact'],
        }),
        isTrue,
      );
      expect(
        canManagePerson(manager, {
          'id': 'peer',
          'permissions': ['forms_manage'],
        }),
        isFalse,
      );
      expect(
        canManagePerson(manager, {'id': 'manager', 'permissions': []}),
        isFalse,
      );
      expect(
        canManagePerson(manager, {
          'id': 'owner',
          'is_owner': true,
          'permissions': [],
        }),
        isFalse,
      );
      expect(
        canManagePerson(
          {...manager, 'is_active': false},
          {'id': 'peer', 'permissions': []},
        ),
        isFalse,
      );
    },
  );
  testWidgets('Required checkbox shows validation until consent is checked', (
    tester,
  ) async {
    final form = GlobalKey<FormState>();
    dynamic value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: CustomFieldInput(
                field: {
                  'id': 'agree',
                  'type': 'checkbox',
                  'label': 'I agree',
                  'required': true,
                },
                value: value,
                onChanged: (v) => setState(() => value = v),
                onUpload: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('This answer is required.'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    expect(value, isTrue);
  });
  testWidgets('Invalid select answer cannot submit a form', (tester) async {
    final form = GlobalKey<FormState>();
    dynamic value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Form(
              key: form,
              child: CustomFieldInput(
                field: {
                  'id': 'session',
                  'type': 'select',
                  'label': 'Session',
                  'required': true,
                  'options': ['Monday', 'Tuesday'],
                },
                value: value,
                onChanged: (v) => setState(() => value = v),
                onUpload: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(form.currentState!.validate(), isFalse);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tuesday').last);
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    expect(value, 'Tuesday');
  });
  testWidgets(
    'Revoking user management permission removes an open access editor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
        Organisation({'website': 'https://example.org'}),
        null,
        await SharedPreferences.getInstance(),
      );
      state.profile = {
        'id': 'manager',
        'is_active': true,
        'permissions': ['users'],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: AccountGate(
            state,
            permission: 'users',
            child: const Scaffold(body: Text('Private account editor')),
          ),
        ),
      );
      expect(find.text('Private account editor'), findsOneWidget);
      state.profile = {'id': 'manager', 'is_active': true, 'permissions': []};
      state.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Private account editor'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('Removing owner access hides learning relationship management', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      Organisation({'website': 'https://example.org'}),
      null,
      await SharedPreferences.getInstance(),
    );
    state.profile = {
      'id': 'manager',
      'is_active': true,
      'is_owner': true,
      'permissions': ['users'],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: LearningOwnerGate(
          state,
          child: const Scaffold(body: Text('Private guardian links')),
        ),
      ),
    );
    expect(find.text('Private guardian links'), findsOneWidget);
    state.profile = {
      'id': 'manager',
      'is_active': true,
      'is_owner': false,
      'permissions': ['users'],
    };
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Private guardian links'), findsNothing);
    expect(find.text('Owner access is required.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
