import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'account.dart';
import 'learning.dart';

const taskStatuses = {
  'open': 'Open',
  'in_progress': 'In progress',
  'waiting': 'Waiting',
  'done': 'Completed',
};

/// Every private route gets its own live account gate, including nested routes.
void showPrivatePage(BuildContext context, AppState state, Widget child) =>
    showPage(context, AccountGate(state, child: child));

String formatWorkspaceDate(dynamic value) {
  final date = DateTime.tryParse('$value');
  return date == null
      ? 'Not scheduled'
      : DateFormat('EEE d MMM, h:mm a').format(date.toLocal());
}

Future<DateTime?> pickWorkspaceDate(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final firstYear = initial != null && initial.year < now.year - 2
      ? initial.year
      : now.year - 2;
  final lastYear = initial != null && initial.year > now.year + 5
      ? initial.year
      : now.year + 5;
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(firstYear),
    lastDate: DateTime(lastYear, 12, 31),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial ?? now),
  );
  return time == null
      ? null
      : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Bounded data pages. A reload clears old records immediately, including errors.
class PaginatedRecords extends StatefulWidget {
  final Future<List<Record>> Function(int page) loader;
  final Widget Function(Record) itemBuilder;
  final String emptyText;
  final Widget? header;
  const PaginatedRecords({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.emptyText = 'There is nothing here yet.',
    this.header,
  });
  @override
  State<PaginatedRecords> createState() => _PaginatedRecordsState();
}

class _PaginatedRecordsState extends State<PaginatedRecords> {
  int page = 0;
  late Future<List<Record>> request = load();
  Future<List<Record>> load() =>
      widget.loader(page).timeout(const Duration(seconds: 20));
  void reload() => setState(() {
    request = load();
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.header != null) widget.header!,
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Record>>(
          future: request,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: reload,
                  child: const Text('Could not load this page. Retry'),
                ),
              );
            }
            final rows = snapshot.data ?? [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(widget.emptyText),
                  ),
                ...rows.map(widget.itemBuilder),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: page == 0
                          ? null
                          : () {
                              page--;
                              reload();
                            },
                      child: const Text('Previous'),
                    ),
                    Text('Page ${page + 1}'),
                    TextButton(
                      onPressed: rows.length < 25
                          ? null
                          : () {
                              page++;
                              reload();
                            },
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class TasksPage extends StatefulWidget {
  final AppState state;
  final String? taskId;
  const TasksPage(this.state, {super.key, this.taskId});
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  String status = 'all';
  bool mine = false;
  int revision = 0;
  late Future<List<int>> summary = loadSummary();
  Future<List<int>> loadSummary() => Future.wait([
    widget.state.client!.from('work_tasks').count(),
    widget.state.client!.from('work_tasks').count().neq('status', 'done'),
    widget.state.client!
        .from('work_tasks')
        .count()
        .neq('status', 'done')
        .lt('due_at', DateTime.now().toUtc().toIso8601String()),
  ]).timeout(const Duration(seconds: 20));
  void refresh() => setState(() {
    revision++;
    summary = loadSummary();
  });
  Future<List<Record>> load(int page) async {
    var query = widget.state.client!.from('work_tasks').select();
    if (widget.taskId != null) query = query.eq('id', widget.taskId!);
    if (status != 'all') query = query.eq('status', status);
    if (mine) query = query.eq('assigned_to', widget.state.userId!);
    return records(
      await query
          .order('created_at', ascending: false)
          .range(page * 25, page * 25 + 24),
    );
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.taskId == null ? 'Tasks' : 'Task',
    actions: [
      IconButton(
        tooltip: 'New task',
        icon: const Icon(Icons.add),
        onPressed: () => showPrivatePage(
          context,
          widget.state,
          CreateTaskPage(widget.state, onSaved: refresh),
        ),
      ),
    ],
    child: PaginatedRecords(
      key: ValueKey('$status/$mine/$revision'),
      loader: load,
      emptyText: 'No tasks match this view.',
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            FutureBuilder<List<int>>(
              future: summary,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    !snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final counts = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '${counts[0]} total · ${counts[1]} outstanding · ${counts[2]} overdue',
                  ),
                );
              },
            ),
            if (widget.taskId == null)
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: status,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All statuses'),
                        ),
                        ...taskStatuses.entries.map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => status = value!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilterChip(
                    label: const Text('Assigned to me'),
                    selected: mine,
                    onSelected: (v) => setState(() => mine = v),
                  ),
                ],
              ),
          ],
        ),
      ),
      itemBuilder: (task) => TaskCard(
        task: task,
        assignedToMe: task['assigned_to'] == widget.state.userId,
        onStatus: (value) async {
          await widget.state.client!
              .from('work_tasks')
              .update({'status': value})
              .eq('id', task['id'])
              .select('id')
              .single()
              .timeout(const Duration(seconds: 20));
          if (mounted) refresh();
        },
      ),
    ),
  );
}

class TaskCard extends StatelessWidget {
  final Record task;
  final bool assignedToMe;
  final Future<void> Function(String) onStatus;
  const TaskCard({
    super.key,
    required this.task,
    required this.assignedToMe,
    required this.onStatus,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${task['title']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if ('${task['description'] ?? ''}'.isNotEmpty)
            Text('${task['description']}'),
          Text(assignedToMe ? 'Assigned to you' : 'Delegated task'),
          if (task['form_id'] != null) const Text('Linked to a form response'),
          if (task['due_at'] != null)
            Text('Due ${formatWorkspaceDate(task['due_at'])}'),
          const SizedBox(height: 8),
          Text('Status: ${taskStatuses[task['status']] ?? task['status']}'),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in taskStatuses.entries)
                if (entry.key != task['status'])
                  AsyncButton(
                    label: entry.value,
                    onPressed: () => onStatus(entry.key),
                  ),
            ],
          ),
        ],
      ),
    ),
  );
}

class CreateTaskPage extends StatefulWidget {
  final AppState state;
  final Record? form;
  final VoidCallback? onSaved;
  const CreateTaskPage(this.state, {super.key, this.form, this.onSaved});
  @override
  State<CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<CreateTaskPage> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  String? assignee;
  DateTime? due;
  late Future<List<Record>> people = loadPeople();
  Future<List<Record>> loadPeople() async => records(
    await widget.state.client!
        .rpc('task_assignees', params: {'p_form_id': widget.form?['id']})
        .timeout(const Duration(seconds: 20)),
  );
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.form == null ? 'New task' : 'Assign form action',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.form != null)
          Text('Action for ${widget.form!['kind']} form response'),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Action template'),
                items:
                    [
                          'Call back',
                          'Chase payment',
                          'Confirm payment',
                          'Request an image',
                          'Reply to enquiry',
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => title.text = v!,
              ),
              TextFormField(
                controller: title,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Task title'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Add a title.' : null,
              ),
              TextFormField(
                controller: description,
                maxLength: 6000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Instructions'),
              ),
              FutureBuilder<List<Record>>(
                future: people,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(() {
                        people = loadPeople();
                      }),
                      child: const Text('Could not load recipients. Retry'),
                    );
                  }
                  final rows = snapshot.data ?? [];
                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: assignee,
                    decoration: const InputDecoration(
                      labelText: 'Responsible person',
                    ),
                    items: rows
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: '${p['id']}',
                            child: Text('${p['display_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => assignee = v,
                    validator: (v) =>
                        v == null ? 'Choose a responsible person.' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text(
                  due == null ? 'Add a due date' : formatWorkspaceDate(due),
                ),
                onPressed: () async {
                  final value = await pickWorkspaceDate(context, initial: due);
                  if (mounted && value != null) setState(() => due = value);
                },
              ),
              if (due != null)
                TextButton(
                  onPressed: () => setState(() => due = null),
                  child: const Text('Remove due date'),
                ),
              AsyncButton(
                label: 'Create task',
                onPressed: () async {
                  if (!formKey.currentState!.validate() || assignee == null) {
                    return;
                  }
                  await widget.state.client!
                      .rpc(
                        'create_work_task',
                        params: {
                          'p_title': title.text.trim(),
                          'p_description': description.text.trim(),
                          'p_assigned_to': assignee,
                          'p_form_id': widget.form?['id'],
                          'p_due_at': due?.toUtc().toIso8601String(),
                        },
                      )
                      .timeout(const Duration(seconds: 20));
                  if (context.mounted) {
                    widget.onSaved?.call();
                    notice(context, 'Task created.');
                    Navigator.of(context).pop();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class UpdatesPage extends StatefulWidget {
  final AppState state;
  const UpdatesPage(this.state, {super.key});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool unreadOnly = false;
  int revision = 0;
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Updates',
    child: PaginatedRecords(
      key: ValueKey('$unreadOnly/$revision'),
      header: SwitchListTile(
        title: const Text('Unread only'),
        value: unreadOnly,
        onChanged: (v) => setState(() => unreadOnly = v),
      ),
      emptyText: 'You are up to date.',
      loader: (page) async {
        var query = widget.state.client!.from('user_notifications').select();
        if (unreadOnly) query = query.isFilter('read_at', null);
        return records(
          await query
              .order('created_at', ascending: false)
              .range(page * 25, page * 25 + 24),
        );
      },
      itemBuilder: (update) => UpdateCard(
        update: update,
        onOpen: () => showPrivatePage(
          context,
          widget.state,
          update['kind'] == 'task'
              ? TasksPage(widget.state, taskId: '${update['entity_id']}')
              : LearningPage(widget.state),
        ),
        onRead: () async {
          await widget.state.client!
              .from('user_notifications')
              .update({'read_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', update['id'])
              .select('id')
              .single()
              .timeout(const Duration(seconds: 20));
          if (mounted) setState(() => revision++);
        },
      ),
    ),
  );
}

class UpdateCard extends StatelessWidget {
  final Record update;
  final VoidCallback onOpen;
  final Future<void> Function() onRead;
  const UpdateCard({
    super.key,
    required this.update,
    required this.onOpen,
    required this.onRead,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            update['kind'] == 'task' ? 'Task update' : 'Learning update',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(formatWorkspaceDate(update['created_at'])),
          Text(update['read_at'] == null ? 'Unread' : 'Read'),
          Wrap(
            spacing: 12,
            children: [
              TextButton(onPressed: onOpen, child: const Text('Open')),
              if (update['read_at'] == null)
                AsyncButton(label: 'Mark read', onPressed: onRead),
            ],
          ),
        ],
      ),
    ),
  );
}
