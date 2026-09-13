import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'account.dart';
import 'workspace.dart';

class LearningOwnerGate extends StatelessWidget {
  final AppState state;
  final Widget child;
  const LearningOwnerGate(this.state, {super.key, required this.child});
  @override
  Widget build(BuildContext context) => AccountGate(
    state,
    child: ListenableBuilder(
      listenable: state,
      builder: (context, _) => owner(state.profile)
          ? child
          : const ContentPage(
              title: 'Learning management',
              child: Center(child: Text('Owner access is required.')),
            ),
    ),
  );
}

void openLearningAdmin(BuildContext context, AppState state, Widget page) =>
    showPage(context, LearningOwnerGate(state, child: page));

Future<Record?> chooseLearningPerson(
  BuildContext context,
  AppState state, {
  bool student = false,
}) => Navigator.of(context).push<Record>(
  MaterialPageRoute(
    builder: (_) => LearningOwnerGate(
      state,
      child: LearningPersonPicker(state, student: student),
    ),
  ),
);

class LearningPersonPicker extends StatefulWidget {
  final AppState state;
  final bool student;
  const LearningPersonPicker(this.state, {super.key, this.student = false});
  @override
  State<LearningPersonPicker> createState() => _LearningPersonPickerState();
}

class _LearningPersonPickerState extends State<LearningPersonPicker> {
  String search = '';
  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.student ? 'Choose student' : 'Choose account',
    child: PaginatedRecords(
      key: ValueKey(search),
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'Search name and press search',
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => setState(() => search = v.trim()),
        ),
      ),
      loader: (page) async {
        var query = widget.state.client!
            .from(widget.student ? 'learning_students' : 'profiles')
            .select('id,display_name');
        if (!widget.student) query = query.eq('is_active', true);
        if (search.isNotEmpty) {
          query = query.ilike(
            'display_name',
            '%${search.replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
          );
        }
        return records(
          await query
              .order('display_name')
              .order('id')
              .range(page * 25, page * 25 + 24),
        );
      },
      itemBuilder: (row) => ListTile(
        title: Text('${row['display_name']}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pop(context, row),
      ),
    ),
  );
}

class LearningManagementPage extends StatefulWidget {
  final AppState state;
  const LearningManagementPage(this.state, {super.key});
  @override
  State<LearningManagementPage> createState() => _LearningManagementPageState();
}

class _LearningManagementPageState extends State<LearningManagementPage> {
  int tab = 0, revision = 0;
  String department = 'adult';
  void reload() {
    if (mounted) setState(() => revision++);
  }

  void edit([Record? row]) => openLearningAdmin(
    context,
    widget.state,
    tab == 0
        ? CourseManagementPage(
            widget.state,
            course: row,
            department: department,
            onSaved: reload,
          )
        : StudentManagementPage(widget.state, student: row, onSaved: reload),
  );
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Learning management',
    actions: [
      if (tab < 2)
        IconButton(
          tooltip: tab == 0 ? 'Create course' : 'Add student',
          onPressed: edit,
          icon: const Icon(Icons.add),
        ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Courses')),
              ButtonSegment(value: 1, label: Text('Students')),
              ButtonSegment(value: 2, label: Text('Heads')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
        ),
        if (tab == 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DropdownButton<String>(
              value: department,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'adult',
                  child: Text('Adult classes & courses'),
                ),
                DropdownMenuItem(value: 'madrassah', child: Text('Madrasah')),
              ],
              onChanged: (v) => setState(() => department = v!),
            ),
          ),
        Expanded(
          child: tab == 2
              ? DepartmentHeadsPanel(widget.state)
              : PaginatedRecords(
                  key: ValueKey('$tab/$department/$revision'),
                  loader: (page) async {
                    var query = widget.state.client!
                        .from(
                          tab == 0 ? 'learning_courses' : 'learning_students',
                        )
                        .select();
                    if (tab == 0) query = query.eq('department', department);
                    return records(
                      await query
                          .order(tab == 0 ? 'title' : 'display_name')
                          .order('id')
                          .range(page * 25, page * 25 + 24),
                    );
                  },
                  itemBuilder: (row) => ListTile(
                    title: Text(
                      '${tab == 0 ? row['title'] : row['display_name']}',
                    ),
                    subtitle: Text(
                      tab == 0
                          ? row['published'] == true
                                ? 'Published'
                                : 'Draft'
                          : row['user_id'] == null
                          ? 'Student record'
                          : 'Linked to an account',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => edit(row),
                  ),
                ),
        ),
      ],
    ),
  );
}

class CourseManagementPage extends StatefulWidget {
  final AppState state;
  final Record? course;
  final String department;
  final VoidCallback onSaved;
  const CourseManagementPage(
    this.state, {
    super.key,
    this.course,
    required this.department,
    required this.onSaved,
  });
  @override
  State<CourseManagementPage> createState() => _CourseManagementPageState();
}

class _CourseManagementPageState extends State<CourseManagementPage> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
        text: '${widget.course?['title'] ?? ''}',
      ),
      description = TextEditingController(
        text: '${widget.course?['description'] ?? ''}',
      );
  late bool published = widget.course?['published'] == true;
  late String department = widget.course?['department'] ?? widget.department;
  late Future<Record> links = load();
  Future<Record> load() async {
    if (widget.course == null) return {'staff': [], 'enrolments': []};
    final data = await Future.wait([
      widget.state.client!
          .from('learning_staff')
          .select('user_id,role,profiles(display_name)')
          .eq('course_id', widget.course!['id'])
          .limit(500),
      widget.state.client!
          .from('learning_enrolments')
          .select('student_id,active,learning_students(display_name)')
          .eq('course_id', widget.course!['id'])
          .limit(500),
    ]).timeout(const Duration(seconds: 20));
    return {'staff': data[0], 'enrolments': data[1]};
  }

  void refresh() {
    if (mounted) setState(() => links = load());
    widget.onSaved();
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.course == null ? 'Create course' : 'Manage course',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: title,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Course title'),
                validator: (v) =>
                    v?.trim().isEmpty ?? true ? 'Add a title.' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: department,
                decoration: const InputDecoration(labelText: 'Department'),
                items: const [
                  DropdownMenuItem(
                    value: 'adult',
                    child: Text('Adult classes & courses'),
                  ),
                  DropdownMenuItem(value: 'madrassah', child: Text('Madrasah')),
                ],
                onChanged: (v) => department = v!,
              ),
              TextFormField(
                controller: description,
                maxLength: 6000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Published'),
                value: published,
                onChanged: (v) => setState(() => published = v),
              ),
              AsyncButton(
                label: 'Save course',
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final values = {
                    'title': title.text.trim(),
                    'description': description.text.trim(),
                    'department': department,
                    'published': published,
                  };
                  if (widget.course == null) {
                    await widget.state.client!
                        .from('learning_courses')
                        .insert(values)
                        .select('id')
                        .single();
                  } else {
                    await widget.state.client!
                        .from('learning_courses')
                        .update(values)
                        .eq('id', widget.course!['id'])
                        .select('id')
                        .single();
                  }
                  widget.onSaved();
                  if (context.mounted) {
                    notice(context, 'Course saved.');
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
        ),
        if (widget.course != null)
          FutureBuilder<Record>(
            future: links,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: refresh,
                  child: const Text('Could not load course links. Retry'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Teachers'),
                  for (final member in records(snapshot.data!['staff']))
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${member['profiles']?['display_name'] ?? 'Staff member'}',
                            ),
                            Text(
                              member['role'] == 'head_teacher'
                                  ? 'Head teacher'
                                  : 'Teacher',
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                AsyncButton(
                                  label: member['role'] == 'head_teacher'
                                      ? 'Make teacher'
                                      : 'Make head teacher',
                                  onPressed: () async {
                                    await widget.state.client!
                                        .from('learning_staff')
                                        .update({
                                          'role':
                                              member['role'] == 'head_teacher'
                                              ? 'teacher'
                                              : 'head_teacher',
                                        })
                                        .eq('course_id', widget.course!['id'])
                                        .eq('user_id', member['user_id'])
                                        .select('user_id')
                                        .single();
                                    refresh();
                                  },
                                ),
                                AsyncButton(
                                  label: 'Remove course access',
                                  onPressed: () async {
                                    await widget.state.client!
                                        .from('learning_staff')
                                        .delete()
                                        .eq('course_id', widget.course!['id'])
                                        .eq('user_id', member['user_id'])
                                        .select('user_id')
                                        .single();
                                    refresh();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  AsyncButton(
                    label: 'Assign teacher',
                    onPressed: () async {
                      final person = await chooseLearningPerson(
                        context,
                        widget.state,
                      );
                      if (person == null || !mounted || !context.mounted) {
                        return;
                      }
                      if (records(
                        snapshot.data!['staff'],
                      ).any((member) => member['user_id'] == person['id'])) {
                        notice(
                          context,
                          'This person is already assigned to the course.',
                        );
                        return;
                      }
                      await widget.state.client!
                          .from('learning_staff')
                          .upsert({
                            'course_id': widget.course!['id'],
                            'user_id': person['id'],
                            'role': 'teacher',
                          }, onConflict: 'course_id,user_id')
                          .select('user_id')
                          .single();
                      refresh();
                    },
                  ),
                  const SectionTitle('Class enrolments'),
                  for (final enrolment in records(snapshot.data!['enrolments']))
                    Card(
                      child: ListTile(
                        title: Text(
                          '${enrolment['learning_students']?['display_name'] ?? 'Student'}',
                        ),
                        subtitle: Text(
                          enrolment['active'] == true ? 'Active' : 'Inactive',
                        ),
                        trailing: AsyncButton(
                          label: enrolment['active'] == true
                              ? 'Deactivate'
                              : 'Activate',
                          onPressed: () async {
                            await widget.state.client!
                                .from('learning_enrolments')
                                .update({'active': enrolment['active'] != true})
                                .eq('course_id', widget.course!['id'])
                                .eq('student_id', enrolment['student_id'])
                                .select('student_id')
                                .single();
                            refresh();
                          },
                        ),
                      ),
                    ),
                  AsyncButton(
                    label: 'Enrol a student',
                    onPressed: () async {
                      final person = await chooseLearningPerson(
                        context,
                        widget.state,
                        student: true,
                      );
                      if (person == null || !mounted || !context.mounted) {
                        return;
                      }
                      await widget.state.client!
                          .from('learning_enrolments')
                          .upsert({
                            'course_id': widget.course!['id'],
                            'student_id': person['id'],
                            'active': true,
                          }, onConflict: 'course_id,student_id')
                          .select('student_id')
                          .single();
                      refresh();
                    },
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
}

class StudentManagementPage extends StatefulWidget {
  final AppState state;
  final Record? student;
  final VoidCallback onSaved;
  const StudentManagementPage(
    this.state, {
    super.key,
    this.student,
    required this.onSaved,
  });
  @override
  State<StudentManagementPage> createState() => _StudentManagementPageState();
}

class _StudentManagementPageState extends State<StudentManagementPage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: '${widget.student?['display_name'] ?? ''}',
  );
  late String? accountId = widget.student?['user_id'];
  String? accountName;
  late String? primaryGuardian = widget.student?['guardian_id'];
  late Future<List<Record>> guardians = load();
  Future<List<Record>> load() async {
    if (widget.student == null) return [];
    final rows = records(
      await widget.state.client!
          .from('learning_guardians')
          .select('user_id,relationship,profiles(display_name)')
          .eq('student_id', widget.student!['id'])
          .limit(50),
    );
    for (final row in rows) {
      row['link_exists'] = true;
    }
    if (primaryGuardian != null &&
        !rows.any((row) => row['user_id'] == primaryGuardian)) {
      final person = await widget.state.client!
          .from('profiles')
          .select('display_name')
          .eq('id', primaryGuardian!)
          .maybeSingle();
      rows.add({
        'user_id': primaryGuardian,
        'relationship': 'Primary guardian',
        'profiles': person,
        'link_exists': false,
      });
    }
    return rows;
  }

  void refresh() {
    if (mounted) setState(() => guardians = load());
    widget.onSaved();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> addGuardian() async {
    final person = await chooseLearningPerson(context, widget.state);
    if (person == null || !mounted || !context.mounted) return;
    final relationship = TextEditingController(text: 'Guardian');
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Guardian relationship'),
        content: TextField(
          controller: relationship,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Relationship'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (relationship.text.trim().isNotEmpty) {
                Navigator.pop(c, relationship.text.trim());
              }
            },
            child: const Text('Link guardian'),
          ),
        ],
      ),
    );
    relationship.dispose();
    if (value == null || !mounted) return;
    await widget.state.client!
        .from('learning_guardians')
        .insert({
          'student_id': widget.student!['id'],
          'user_id': person['id'],
          'relationship': value,
        })
        .select('user_id')
        .single();
    refresh();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.student == null ? 'Add student' : 'Manage student',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Form(
          key: form,
          child: TextFormField(
            controller: name,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Student name'),
            validator: (v) => v?.trim().isEmpty ?? true ? 'Add a name.' : null,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Student sign-in account'),
          subtitle: Text(
            accountId == null
                ? 'Not linked'
                : accountName ?? 'An account is linked',
          ),
          trailing: TextButton(
            onPressed: () async {
              final person = await chooseLearningPerson(context, widget.state);
              if (person != null && mounted) {
                setState(() {
                  accountId = '${person['id']}';
                  accountName = '${person['display_name']}';
                });
              }
            },
            child: const Text('Choose'),
          ),
        ),
        if (accountId != null)
          TextButton(
            onPressed: () => setState(() {
              accountId = null;
              accountName = null;
            }),
            child: const Text('Unlink student account'),
          ),
        AsyncButton(
          label: 'Save student',
          onPressed: () async {
            if (!form.currentState!.validate()) return;
            final values = {
              'display_name': name.text.trim(),
              'user_id': accountId,
            };
            if (widget.student == null) {
              await widget.state.client!
                  .from('learning_students')
                  .insert(values)
                  .select('id')
                  .single();
            } else {
              await widget.state.client!
                  .from('learning_students')
                  .update(values)
                  .eq('id', widget.student!['id'])
                  .select('id')
                  .single();
            }
            widget.onSaved();
            if (context.mounted) {
              notice(context, 'Student saved.');
              Navigator.pop(context);
            }
          },
        ),
        if (widget.student != null) ...[
          const SectionTitle(
            'Guardians',
            subtitle:
                'Linked adults can see this student’s published progress and learning information.',
          ),
          FutureBuilder<List<Record>>(
            future: guardians,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: refresh,
                  child: const Text('Could not load guardians. Retry'),
                );
              }
              return Column(
                children: [
                  for (final person in snapshot.data!)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${person['profiles']?['display_name'] ?? 'Guardian'}',
                        ),
                        subtitle: Text('${person['relationship']}'),
                        trailing: AsyncButton(
                          label: 'Remove access',
                          onPressed: () async {
                            if (primaryGuardian == person['user_id']) {
                              await widget.state.client!
                                  .from('learning_students')
                                  .update({'guardian_id': null})
                                  .eq('id', widget.student!['id'])
                                  .select('id')
                                  .single();
                              primaryGuardian = null;
                            }
                            if (person['link_exists'] == true) {
                              await widget.state.client!
                                  .from('learning_guardians')
                                  .delete()
                                  .eq('student_id', widget.student!['id'])
                                  .eq('user_id', person['user_id'])
                                  .select('user_id')
                                  .single();
                            }
                            refresh();
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          AsyncButton(label: 'Link guardian', onPressed: addGuardian),
        ],
      ],
    ),
  );
}

class DepartmentHeadsPanel extends StatefulWidget {
  final AppState state;
  const DepartmentHeadsPanel(this.state, {super.key});
  @override
  State<DepartmentHeadsPanel> createState() => _DepartmentHeadsPanelState();
}

class _DepartmentHeadsPanelState extends State<DepartmentHeadsPanel> {
  String department = 'adult';
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async => records(
    await widget.state.client!
        .from('learning_department_heads')
        .select('user_id,department,profiles(display_name)')
        .eq('department', department)
        .limit(100),
  );
  void refresh() => setState(() => request = load());
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      DropdownButton<String>(
        value: department,
        isExpanded: true,
        items: const [
          DropdownMenuItem(
            value: 'adult',
            child: Text('Adult classes & courses'),
          ),
          DropdownMenuItem(value: 'madrassah', child: Text('Madrasah')),
        ],
        onChanged: (v) {
          department = v!;
          refresh();
        },
      ),
      const Text(
        'Department heads can manage teaching records across all courses in this department.',
      ),
      FutureBuilder<List<Record>>(
        future: request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: refresh,
              child: const Text('Could not load department heads. Retry'),
            );
          }
          return Column(
            children: [
              for (final head in snapshot.data!)
                ListTile(
                  title: Text(
                    '${head['profiles']?['display_name'] ?? 'Department head'}',
                  ),
                  trailing: AsyncButton(
                    label: 'Remove',
                    onPressed: () async {
                      await widget.state.client!
                          .from('learning_department_heads')
                          .delete()
                          .eq('department', department)
                          .eq('user_id', head['user_id'])
                          .select('user_id')
                          .single();
                      if (mounted) refresh();
                    },
                  ),
                ),
            ],
          );
        },
      ),
      AsyncButton(
        label: 'Assign department head',
        onPressed: () async {
          final selectedDepartment = department;
          final person = await chooseLearningPerson(context, widget.state);
          if (person == null || !mounted || !context.mounted) return;
          await widget.state.client!
              .from('learning_department_heads')
              .insert({
                'department': selectedDepartment,
                'user_id': person['id'],
              })
              .select('user_id')
              .single();
          if (mounted) refresh();
        },
      ),
    ],
  );
}
