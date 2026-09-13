import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'learning_resources.dart';
import 'workspace.dart';

const _requestTimeout = Duration(seconds: 20);
const _pageSize = 25;
const attendanceStatuses = ['present', 'absent', 'late', 'excused'];

/// Only explicitly selected changes are sent; an unmarked pupil stays unmarked.
List<Record> buildAttendanceChanges(
  Map<String, String> selected,
  Map<String, String> notes,
) {
  if (selected.length > 200) throw ArgumentError('Too many register changes.');
  return selected.entries.map((entry) {
    if (!attendanceStatuses.contains(entry.value)) {
      throw ArgumentError('Invalid attendance status.');
    }
    final note = notes[entry.key] ?? '';
    if (note.length > 2000) throw ArgumentError('Attendance note is too long.');
    return {'student_id': entry.key, 'status': entry.value, 'note': note};
  }).toList();
}

String _label(dynamic value) => '${value ?? ''}'.replaceAll('_', ' ');

class LearningPage extends StatelessWidget {
  final AppState state;
  const LearningPage(this.state, {super.key});

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Learning portal',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('learning_courses')
            .select()
            .order('title')
            .order('id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No courses are available to your account yet.',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your classes, learning records and meetings. Adult courses '
            'and madrasah classes have separate course spaces.',
          ),
          if (owner(state.profile))
            TextButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text(
                'Set up courses, pupils and teachers on the website',
              ),
              onPressed: () =>
                  openLink(context, '${state.organisation.website}/portal'),
            ),
        ],
      ),
      itemBuilder: (course) => ActionTile(
        icon: course['department'] == 'adult'
            ? Icons.school_outlined
            : Icons.menu_book_outlined,
        title: '${course['title']}',
        subtitle: course['department'] == 'adult'
            ? 'Adult course'
            : 'Madrasah class',
        onTap: () =>
            showPrivatePage(context, state, _CoursePage(state, course['id'])),
      ),
    ),
  );
}

class _CoursePage extends StatefulWidget {
  final AppState state;
  final String courseId;
  const _CoursePage(this.state, this.courseId);
  @override
  State<_CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<_CoursePage> {
  Record? course;
  bool teacher = false, loading = true, failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
      course = null;
      teacher = false;
    });
    try {
      final fresh = await widget.state.client!
          .from('learning_courses')
          .select()
          .eq('id', widget.courseId)
          .single()
          .timeout(_requestTimeout);
      final canTeach =
          await widget.state.client!
              .rpc('can_teach_course', params: {'p_course_id': widget.courseId})
              .timeout(_requestTimeout) ==
          true;
      if (!mounted) return;
      setState(() {
        course = fresh;
        teacher = canTeach;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final id = widget.courseId;
    return ContentPage(
      title: course?['title'] ?? 'Course',
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
          ? _Retry(_load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  course!['department'] == 'adult'
                      ? 'Adult course'
                      : 'Madrasah class',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if ('${course!['description']}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${course!['description']}'),
                  ),
                if (teacher)
                  const Text(
                    'You can manage teaching and records for this course.',
                  ),
                ActionTile(
                  icon: Icons.folder_open,
                  title: 'Course resources',
                  subtitle: 'Lesson files, recordings and useful links',
                  onTap: () => showPrivatePage(
                    context,
                    state,
                    CourseResourcesPage(state, id, teacher),
                  ),
                ),
                ActionTile(
                  icon: Icons.calendar_month_outlined,
                  title: 'Class sessions',
                  subtitle: teacher
                      ? 'Schedule sessions and mark registers'
                      : 'Session times and your register',
                  onTap: () => showPrivatePage(
                    context,
                    state,
                    _SessionsPage(state, id, teacher),
                  ),
                ),
                ActionTile(
                  icon: Icons.person_outline,
                  title: teacher ? 'Students' : 'My learning',
                  subtitle: 'Progress, plans, assessments and meetings',
                  onTap: () => showPrivatePage(
                    context,
                    state,
                    _StudentsPage(state, id, teacher),
                  ),
                ),
                ActionTile(
                  icon: Icons.edit_note,
                  title: 'Poetry and reflections',
                  subtitle: teacher
                      ? 'Read and moderate student contributions'
                      : 'Approved writing and your submissions',
                  onTap: () => showPrivatePage(
                    context,
                    state,
                    _ContributionsPage(state, id, teacher),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Retry extends StatelessWidget {
  final VoidCallback retry;
  const _Retry(this.retry);
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This information could not be loaded. Check your connection or account access.',
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _SessionsPage extends StatefulWidget {
  final AppState state;
  final String courseId;
  final bool teacher;
  const _SessionsPage(this.state, this.courseId, this.teacher);
  @override
  State<_SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<_SessionsPage> {
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Class sessions',
    child: PaginatedRecords(
      loader: (page) async => records(
        await widget.state.client!
            .from('learning_sessions')
            .select()
            .eq('course_id', widget.courseId)
            .order('starts_at', ascending: false)
            .order('id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No sessions have been scheduled.',
      header: widget.teacher
          ? FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Schedule a session'),
              onPressed: () => showPrivatePage(
                context,
                widget.state,
                _SessionEditor(widget.state, widget.courseId),
              ),
            )
          : null,
      itemBuilder: (session) => ActionTile(
        icon: Icons.event_outlined,
        title: '${session['title']}'.isEmpty
            ? 'Class session'
            : '${session['title']}',
        subtitle: formatWorkspaceDate(session['starts_at']),
        onTap: () => showPrivatePage(
          context,
          widget.state,
          _RegisterPage(
            widget.state,
            widget.courseId,
            session['id'],
            widget.teacher,
          ),
        ),
      ),
    ),
  );
}

class _SessionEditor extends StatefulWidget {
  final AppState state;
  final String courseId;
  const _SessionEditor(this.state, this.courseId);
  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  final title = TextEditingController();
  DateTime? start, end;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Schedule a session',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: title,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Session title'),
        ),
        _DateButton(
          label: 'Start',
          value: start,
          onChanged: (v) => setState(() => start = v),
        ),
        _DateButton(
          label: 'End (optional)',
          value: end,
          onChanged: (v) => setState(() => end = v),
        ),
        const SizedBox(height: 20),
        AsyncButton(
          label: 'Save session',
          onPressed: () async {
            if (start == null || (end != null && !end!.isAfter(start!))) {
              notice(
                context,
                'Choose a start time and an end after the start.',
              );
              return;
            }
            await widget.state.client!
                .from('learning_sessions')
                .insert({
                  'course_id': widget.courseId,
                  'title': title.text.trim(),
                  'starts_at': start!.toUtc().toIso8601String(),
                  'ends_at': end?.toUtc().toIso8601String(),
                })
                .select('id')
                .single()
                .timeout(_requestTimeout);
            if (context.mounted) {
              notice(
                context,
                'Session saved. Refresh the sessions list to see it.',
              );
              Navigator.pop(context);
            }
          },
        ),
      ],
    ),
  );
}

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  const _DateButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.schedule),
    label: Text(
      '$label: ${value == null ? 'Choose date and time' : formatWorkspaceDate(value!.toIso8601String())}',
    ),
    onPressed: () async {
      final date = await pickWorkspaceDate(context, initial: value);
      if (date != null && context.mounted) onChanged(date);
    },
  );
}

class _RegisterPage extends StatefulWidget {
  final AppState state;
  final String courseId, sessionId;
  final bool teacher;
  const _RegisterPage(this.state, this.courseId, this.sessionId, this.teacher);
  @override
  State<_RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<_RegisterPage> {
  int page = 0;
  bool loading = true, failed = false, saving = false;
  List<Record> students = [];
  Map<String, Record> attendance = {};
  final Map<String, String> selected = {}, notes = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
      students = [];
      attendance = {};
      selected.clear();
      notes.clear();
    });
    try {
      final enrolments = records(
        await widget.state.client!
            .from('learning_enrolments')
            .select('student_id,learning_students!inner(id,display_name)')
            .eq('course_id', widget.courseId)
            .eq('active', true)
            .order('student_id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      );
      final pupils = enrolments
          .map((row) => Record.from(row['learning_students']))
          .toList();
      final marks = pupils.isEmpty
          ? <Record>[]
          : records(
              await widget.state.client!
                  .from('learning_attendance')
                  .select()
                  .eq('session_id', widget.sessionId)
                  .inFilter(
                    'student_id',
                    pupils.map((row) => row['id']).toList(),
                  )
                  .limit(_pageSize)
                  .timeout(_requestTimeout),
            );
      if (!mounted) return;
      setState(() {
        students = pupils;
        attendance = {for (final mark in marks) '${mark['student_id']}': mark};
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final changes = buildAttendanceChanges(selected, notes);
    if (changes.isEmpty) {
      notice(context, 'Choose at least one attendance mark.');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.state.client!
          .rpc(
            'mark_class_register',
            params: {'p_session_id': widget.sessionId, 'p_marks': changes},
          )
          .timeout(_requestTimeout);
      if (!mounted) return;
      notice(context, '${changes.length} register marks saved.');
      await _load();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Class register',
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : failed
        ? _Retry(_load)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (widget.teacher)
                const Text(
                  'Only selected marks are saved. Unselected students keep their existing status. Save or clear changes before changing pages.',
                ),
              if (students.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No enrolled students are available on this page.',
                  ),
                ),
              for (final student in students) _studentCard(student),
              if (widget.teacher && selected.isNotEmpty) ...[
                AsyncButton(
                  label: 'Save ${selected.length} selected marks',
                  onPressed: _save,
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () => setState(() {
                          selected.clear();
                          notes.clear();
                        }),
                  child: const Text('Clear selections'),
                ),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page == 0 || selected.isNotEmpty
                        ? null
                        : () {
                            page--;
                            _load();
                          },
                    child: const Text('Previous'),
                  ),
                  Text('Page ${page + 1}'),
                  TextButton(
                    onPressed:
                        students.length < _pageSize || selected.isNotEmpty
                        ? null
                        : () {
                            page++;
                            _load();
                          },
                    child: const Text('Next'),
                  ),
                ],
              ),
              TextButton(
                onPressed: selected.isEmpty ? _load : null,
                child: const Text('Refresh register'),
              ),
            ],
          ),
  );
  Widget _studentCard(Record student) {
    final id = '${student['id']}';
    final mark = attendance[id];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${student['display_name']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              mark == null ? 'Not marked' : 'Saved: ${_label(mark['status'])}',
            ),
            if (mark != null && '${mark['note']}'.isNotEmpty)
              Text('${mark['note']}'),
            if (widget.teacher) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('$id:${selected[id]}'),
                initialValue: selected[id],
                decoration: const InputDecoration(
                  labelText: 'Select a new mark',
                ),
                items: attendanceStatuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_label(status)),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (status) {
                        if (status != null) {
                          setState(() {
                            selected[id] = status;
                            notes.putIfAbsent(
                              id,
                              () => '${mark?['note'] ?? ''}',
                            );
                          });
                        }
                      },
              ),
              if (selected.containsKey(id))
                TextFormField(
                  key: ValueKey('note:$id'),
                  initialValue: notes[id],
                  enabled: !saving,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Attendance note (optional)',
                  ),
                  onChanged: (value) => notes[id] = value,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudentsPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final bool teacher;
  const _StudentsPage(this.state, this.courseId, this.teacher);
  @override
  Widget build(BuildContext context) => ContentPage(
    title: teacher ? 'Students' : 'My learning',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('learning_enrolments')
            .select(
              'student_id,learning_students!inner(id,display_name,user_id,guardian_id)',
            )
            .eq('course_id', courseId)
            .eq('active', true)
            .order('student_id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No active student enrolments are available to your account.',
      itemBuilder: (row) {
        final student = Record.from(row['learning_students']);
        return ActionTile(
          icon: Icons.person_outline,
          title: '${student['display_name']}',
          subtitle: 'Learning records, plans and meetings',
          onTap: () => showPrivatePage(
            context,
            state,
            _StudentPage(state, courseId, student, teacher),
          ),
        );
      },
    ),
  );
}

class _StudentPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final Record student;
  final bool teacher;
  const _StudentPage(this.state, this.courseId, this.student, this.teacher);
  @override
  Widget build(BuildContext context) => ContentPage(
    title: '${student['display_name']}',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ActionTile(
          icon: Icons.auto_stories_outlined,
          title: 'Progress, plans and assessments',
          subtitle: teacher
              ? 'Write and share learning records'
              : 'Published updates from your teachers',
          onTap: () => showPrivatePage(
            context,
            state,
            _RecordsPage(state, courseId, student, teacher),
          ),
        ),
        ActionTile(
          icon: Icons.people_outline,
          title: 'Meetings',
          subtitle: 'Request a meeting and track its status',
          onTap: () => showPrivatePage(
            context,
            state,
            _MeetingsPage(state, courseId, student, teacher),
          ),
        ),
        ActionTile(
          icon: Icons.edit_note,
          title: 'Submit poetry or a reflection',
          subtitle:
              'A teacher reviews your writing before it is shared with the course',
          onTap: () => showPrivatePage(
            context,
            state,
            _WritingEditor(state, courseId, student, contribution: true),
          ),
        ),
      ],
    ),
  );
}

class _RecordsPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final Record student;
  final bool teacher;
  const _RecordsPage(this.state, this.courseId, this.student, this.teacher);
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Learning records',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('learning_records')
            .select()
            .eq('course_id', courseId)
            .eq('student_id', student['id'])
            .order('created_at', ascending: false)
            .order('id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No learning records are available yet.',
      header: teacher
          ? FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add a learning record'),
              onPressed: () => showPrivatePage(
                context,
                state,
                _WritingEditor(state, courseId, student),
              ),
            )
          : null,
      itemBuilder: (row) => ActionTile(
        icon: Icons.article_outlined,
        title: '${row['title']}',
        subtitle:
            '${_label(row['kind'])} · ${row['published'] == true ? 'Published' : 'Draft'} · ${formatWorkspaceDate(row['created_at'])}',
        onTap: () => showPrivatePage(
          context,
          state,
          _WritingDetail(
            state,
            'learning_records',
            row['id'],
            teacher,
            courseId: courseId,
            student: student,
          ),
        ),
      ),
    ),
  );
}

class _WritingEditor extends StatefulWidget {
  final AppState state;
  final String courseId;
  final Record student;
  final bool contribution;
  final Record? existing;
  const _WritingEditor(
    this.state,
    this.courseId,
    this.student, {
    this.contribution = false,
    this.existing,
  });
  @override
  State<_WritingEditor> createState() => _WritingEditorState();
}

class _WritingEditorState extends State<_WritingEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, body, score, maximum;
  DateTime? dueOn;
  late String kind;
  bool published = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.existing?['title'] ?? '');
    body = TextEditingController(text: widget.existing?['body'] ?? '');
    score = TextEditingController(text: '${widget.existing?['score'] ?? ''}');
    maximum = TextEditingController(
      text: '${widget.existing?['max_score'] ?? ''}',
    );
    dueOn = DateTime.tryParse('${widget.existing?['due_on'] ?? ''}');
    kind =
        widget.existing?['kind'] ??
        (widget.contribution ? 'poetry' : 'progress');
    published = widget.existing?['published'] == true;
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    score.dispose();
    maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.contribution ? 'Student writing' : 'Learning record',
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('For ${widget.student['display_name']}'),
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items:
                (widget.contribution
                        ? ['poetry', 'reflection']
                        : ['progress', 'plan', 'assessment'])
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_label(value)),
                      ),
                    )
                    .toList(),
            onChanged: widget.existing == null
                ? (value) => setState(() => kind = value!)
                : null,
          ),
          TextFormField(
            controller: title,
            maxLength: 160,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Enter a title.' : null,
          ),
          TextFormField(
            controller: body,
            minLines: 6,
            maxLines: 16,
            maxLength: 16000,
            decoration: const InputDecoration(
              labelText: 'Writing or learning notes',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter your text.'
                : null,
          ),
          if (!widget.contribution)
            Column(
              children: [
                if (kind == 'assessment') ...[
                  TextFormField(
                    controller: score,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Mark (optional)',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty &&
                          maximum.text.trim().isEmpty) {
                        return null;
                      }
                      final n = double.tryParse(value ?? '');
                      final max = double.tryParse(maximum.text);
                      return n == null ||
                              max == null ||
                              !n.isFinite ||
                              !max.isFinite ||
                              n < 0 ||
                              max <= 0 ||
                              max > 1000000 ||
                              n > max
                          ? 'Enter a mark between zero and the maximum.'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: maximum,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum mark',
                    ),
                  ),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    dueOn == null
                        ? 'Target date (optional)'
                        : 'Target: ${dateKey(dueOn!)}',
                  ),
                  trailing: dueOn == null
                      ? const Icon(Icons.calendar_month)
                      : IconButton(
                          tooltip: 'Clear target date',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => dueOn = null),
                        ),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: dueOn ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (selected != null && mounted) {
                      setState(() => dueOn = selected);
                    }
                  },
                ),
              ],
            ),
          if (!widget.contribution)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Share with the student and guardian'),
              subtitle: const Text(
                'Published records become visible to the linked student accounts.',
              ),
              value: published,
              onChanged: (value) => setState(() => published = value),
            ),
          if (widget.contribution)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Your writing is saved for teacher review. It is not published automatically.',
              ),
            ),
          AsyncButton(
            label: widget.contribution ? 'Submit for review' : 'Save record',
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              if (widget.contribution) {
                await widget.state.client!
                    .rpc(
                      'submit_student_contribution',
                      params: {
                        'p_student_id': widget.student['id'],
                        'p_course_id': widget.courseId,
                        'p_title': title.text.trim(),
                        'p_body': body.text.trim(),
                        'p_kind': kind,
                      },
                    )
                    .timeout(_requestTimeout);
              } else {
                final values = {
                  'title': title.text.trim(),
                  'body': body.text.trim(),
                  'published': published,
                  'score': kind == 'assessment'
                      ? double.tryParse(score.text)
                      : null,
                  'max_score': kind == 'assessment'
                      ? double.tryParse(maximum.text)
                      : null,
                  'due_on': dueOn == null ? null : dateKey(dueOn!),
                };
                if (widget.existing == null) {
                  await widget.state.client!
                      .from('learning_records')
                      .insert({
                        ...values,
                        'course_id': widget.courseId,
                        'student_id': widget.student['id'],
                        'kind': kind,
                      })
                      .select('id')
                      .single()
                      .timeout(_requestTimeout);
                } else {
                  await widget.state.client!
                      .from('learning_records')
                      .update(values)
                      .eq('id', widget.existing!['id'])
                      .select('id')
                      .single()
                      .timeout(_requestTimeout);
                }
              }
              if (context.mounted) {
                notice(
                  context,
                  widget.contribution
                      ? 'Writing submitted for review.'
                      : 'Learning record saved. Refresh the list to see it.',
                );
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    ),
  );
}

class _WritingDetail extends StatefulWidget {
  final AppState state;
  final String table, id;
  final bool teacher;
  final String? courseId;
  final Record? student;
  const _WritingDetail(
    this.state,
    this.table,
    this.id,
    this.teacher, {
    this.courseId,
    this.student,
  });
  @override
  State<_WritingDetail> createState() => _WritingDetailState();
}

class _WritingDetailState extends State<_WritingDetail> {
  Record? row;
  bool loading = true, failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      row = null;
      loading = true;
      failed = false;
    });
    try {
      final value = await widget.state.client!
          .from(widget.table)
          .select()
          .eq('id', widget.id)
          .single()
          .timeout(_requestTimeout);
      if (mounted) {
        setState(() {
          row = value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: row?['title'] ?? 'Writing',
    actions: [
      IconButton(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh',
      ),
    ],
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : failed
        ? _Retry(_load)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${_label(row!['kind'])} · ${row!['published'] == true ? 'Published' : 'Awaiting publication'}',
              ),
              const SizedBox(height: 20),
              SelectableText('${row!['body']}'),
              if (row!['score'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('Mark: ${row!['score']} / ${row!['max_score']}'),
                ),
              if (row!['due_on'] != null)
                Text('Target date: ${row!['due_on']}'),
              if (widget.table == 'learning_records' && row!['kind'] == 'plan')
                AsyncButton(
                  label: row!['completed_at'] == null
                      ? 'Mark plan complete'
                      : 'Reopen plan',
                  onPressed: () async {
                    await widget.state.client!
                        .rpc(
                          'set_learning_plan_complete',
                          params: {
                            'p_id': row!['id'],
                            'p_complete': row!['completed_at'] == null,
                          },
                        )
                        .timeout(_requestTimeout);
                    await _load();
                  },
                ),
              const SizedBox(height: 24),
              if (widget.teacher) ...[
                AsyncButton(
                  label: row!['published'] == true ? 'Unpublish' : 'Publish',
                  onPressed: () async {
                    await widget.state.client!
                        .from(widget.table)
                        .update({'published': row!['published'] != true})
                        .eq('id', widget.id)
                        .select('id')
                        .single()
                        .timeout(_requestTimeout);
                    await _load();
                  },
                ),
                if (widget.table == 'learning_records' &&
                    widget.student != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit record'),
                    onPressed: () => showPrivatePage(
                      context,
                      widget.state,
                      _WritingEditor(
                        widget.state,
                        widget.courseId!,
                        widget.student!,
                        existing: row,
                      ),
                    ),
                  ),
              ],
            ],
          ),
  );
}

class _ContributionsPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final bool teacher;
  const _ContributionsPage(this.state, this.courseId, this.teacher);
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Poetry and reflections',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('student_contributions')
            .select()
            .eq('course_id', courseId)
            .order('created_at', ascending: false)
            .order('id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No student writing is available yet.',
      header: const Text(
        'To submit writing, open a student in My learning. Teachers review submissions before they are visible to other course members.',
      ),
      itemBuilder: (row) => ActionTile(
        icon: Icons.edit_note,
        title: '${row['title']}',
        subtitle:
            '${_label(row['kind'])} · ${row['published'] == true ? 'Published' : 'Awaiting teacher review'}',
        onTap: () => showPrivatePage(
          context,
          state,
          _WritingDetail(state, 'student_contributions', row['id'], teacher),
        ),
      ),
    ),
  );
}

class _MeetingsPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final Record student;
  final bool teacher;
  const _MeetingsPage(this.state, this.courseId, this.student, this.teacher);
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Meetings',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('learning_meetings')
            .select()
            .eq('course_id', courseId)
            .eq('student_id', student['id'])
            .order('requested_at', ascending: false)
            .order('id')
            .range(page * _pageSize, page * _pageSize + _pageSize - 1)
            .timeout(_requestTimeout),
      ),
      emptyText: 'No meetings have been requested.',
      header: FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Request a meeting'),
        onPressed: () => showPrivatePage(
          context,
          state,
          _MeetingEditor(state, courseId, student),
        ),
      ),
      itemBuilder: (row) => ActionTile(
        icon: Icons.people_outline,
        title: 'Meeting · ${_label(row['status'])}',
        subtitle: row['proposed_at'] == null
            ? 'Time to be arranged'
            : formatWorkspaceDate(row['proposed_at']),
        onTap: () => showPrivatePage(
          context,
          state,
          _MeetingDetail(state, row['id'], teacher),
        ),
      ),
    ),
  );
}

class _MeetingEditor extends StatefulWidget {
  final AppState state;
  final String courseId;
  final Record student;
  const _MeetingEditor(this.state, this.courseId, this.student);
  @override
  State<_MeetingEditor> createState() => _MeetingEditorState();
}

class _MeetingEditorState extends State<_MeetingEditor> {
  final notes = TextEditingController();
  DateTime? proposed;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Request a meeting',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('For ${widget.student['display_name']}'),
        TextField(
          controller: notes,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'What would you like to discuss?',
          ),
        ),
        _DateButton(
          label: 'Suggested time (optional)',
          value: proposed,
          onChanged: (value) => setState(() => proposed = value),
        ),
        const Text('The teacher will confirm the time in your meeting record.'),
        const SizedBox(height: 20),
        AsyncButton(
          label: 'Send meeting request',
          onPressed: () async {
            if (notes.text.trim().isEmpty) {
              notice(context, 'Add a short note for the teacher.');
              return;
            }
            await widget.state.client!
                .rpc(
                  'request_learning_meeting',
                  params: {
                    'p_student_id': widget.student['id'],
                    'p_course_id': widget.courseId,
                    'p_notes': notes.text.trim(),
                    'p_proposed_at': proposed?.toUtc().toIso8601String(),
                  },
                )
                .timeout(_requestTimeout);
            if (context.mounted) {
              notice(
                context,
                'Meeting requested. Refresh the list to see its status.',
              );
              Navigator.pop(context);
            }
          },
        ),
      ],
    ),
  );
}

class _MeetingDetail extends StatefulWidget {
  final AppState state;
  final String id;
  final bool teacher;
  const _MeetingDetail(this.state, this.id, this.teacher);
  @override
  State<_MeetingDetail> createState() => _MeetingDetailState();
}

class _MeetingDetailState extends State<_MeetingDetail> {
  Record? row;
  DateTime? proposed;
  String status = 'requested';
  bool loading = true, failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
      row = null;
    });
    try {
      final value = await widget.state.client!
          .from('learning_meetings')
          .select()
          .eq('id', widget.id)
          .single()
          .timeout(_requestTimeout);
      if (mounted) {
        setState(() {
          row = value;
          status = '${value['status']}';
          proposed = DateTime.tryParse('${value['proposed_at']}')?.toLocal();
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Meeting',
    actions: [
      IconButton(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh',
      ),
    ],
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : failed
        ? _Retry(_load)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Status: ${_label(row!['status'])}'),
              Text(
                row!['proposed_at'] == null
                    ? 'Time to be arranged'
                    : formatWorkspaceDate(row!['proposed_at']),
              ),
              const SizedBox(height: 16),
              SelectableText('${row!['notes']}'),
              if (widget.teacher) ...[
                const SizedBox(height: 24),
                _DateButton(
                  label: 'Meeting time',
                  value: proposed,
                  onChanged: (value) => setState(() => proposed = value),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('${row!['status']}:$status'),
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Update status'),
                  items: ['requested', 'confirmed', 'completed', 'cancelled']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => status = value!),
                ),
                const SizedBox(height: 20),
                AsyncButton(
                  label: 'Save meeting',
                  onPressed: () async {
                    if (status == 'confirmed' && proposed == null) {
                      notice(
                        context,
                        'Choose a meeting time before confirming.',
                      );
                      return;
                    }
                    await widget.state.client!
                        .from('learning_meetings')
                        .update({
                          'status': status,
                          'proposed_at': proposed?.toUtc().toIso8601String(),
                        })
                        .eq('id', widget.id)
                        .select('id')
                        .single()
                        .timeout(_requestTimeout);
                    await _load();
                  },
                ),
              ],
            ],
          ),
  );
}
