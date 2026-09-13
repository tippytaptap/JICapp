import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'account.dart';
import 'workspace.dart';

const permissionLabels = {
  'content': 'Pages, reading and branding',
  'media': 'Upload pictures',
  'events': 'Events and posters',
  'announcements': 'Notices',
  'prayer_times': 'Prayer timetable',
  'team': 'Public team page',
  'livestream': 'Livestream settings',
  'tv': 'TV screens',
  'broadcast': 'Recording and broadcasting',
  'forms_contact': 'Contact messages',
  'forms_madrassah': 'Madrasah enquiries',
  'forms_itikaaf': 'I’tikaf registrations',
  'forms_manage': 'Create and manage forms',
  'forms_custom': 'All custom form responses',
  'users': 'Invite people and manage access',
  'audit': 'Activity history',
  'delete_content': 'Delete content in permitted areas',
};
const staffLabels = {
  'imam': 'Imam',
  'teacher': 'Teacher',
  'volunteer': 'Volunteer',
  'office': 'Office team',
  'media': 'Media team',
  'tv_team': 'TV team',
};

bool canManagePerson(Record? actor, Record target) =>
    can(actor, 'users') &&
    target['is_owner'] != true &&
    actor?['id'] != target['id'] &&
    (owner(actor) ||
        (target['permissions'] as List? ?? []).every((p) => can(actor, '$p')));

class PeoplePage extends StatefulWidget {
  final AppState state;
  const PeoplePage(this.state, {super.key});
  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  int revision = 0;
  void edit([Record? person]) => showPage(
    context,
    AccountGate(
      widget.state,
      permission: 'users',
      child: PersonAccessPage(
        widget.state,
        person: person,
        onSaved: () {
          if (mounted) setState(() => revision++);
        },
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'People & access',
    actions: [
      IconButton(
        tooltip: 'Invite someone',
        onPressed: edit,
        icon: const Icon(Icons.person_add_outlined),
      ),
    ],
    child: PaginatedRecords(
      key: ValueKey(revision),
      loader: (page) async => records(
        await widget.state.client!
            .from('profiles')
            .select(
              'id,display_name,is_owner,is_active,permissions,staff_kinds',
            )
            .order('created_at')
            .order('id')
            .range(page * 25, page * 25 + 24),
      ),
      itemBuilder: (person) => ListTile(
        title: Text('${person['display_name'] ?? 'Community member'}'),
        subtitle: Text(
          '${person['is_owner'] == true ? 'Owner' : '${(person['permissions'] as List? ?? []).length} permissions'} · ${person['is_active'] == true ? 'Enabled' : 'Disabled'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => edit(person),
      ),
    ),
  );
}

class PersonAccessPage extends StatefulWidget {
  final AppState state;
  final Record? person;
  final VoidCallback onSaved;
  const PersonAccessPage(
    this.state, {
    super.key,
    this.person,
    required this.onSaved,
  });
  @override
  State<PersonAccessPage> createState() => _PersonAccessPageState();
}

class _PersonAccessPageState extends State<PersonAccessPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), name = TextEditingController();
  late final permissions = Set<String>.from(
    widget.person?['permissions'] ?? [],
  );
  late final kinds = Set<String>.from(widget.person?['staff_kinds'] ?? []);
  late bool enabled = widget.person?['is_active'] == true;
  bool busy = false;
  String? error;
  Future<void> action(Record body, String success, {bool close = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await widget.state.client!.functions
          .invoke('manage-user', body: body)
          .timeout(const Duration(seconds: 30));
      if (response.data is! Map || response.data['ok'] != true) {
        throw StateError('Not saved');
      }
      widget.onSaved();
      if (mounted) {
        notice(context, success);
        if (close) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The request could not be completed. Refresh this account before trying again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person, s = widget.state;
    final editable = person == null || canManagePerson(s.profile, person);
    final own = person?['id'] == s.userId;
    return ContentPage(
      title: person == null
          ? 'Invite someone'
          : '${person['display_name'] ?? 'Account access'}',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (busy) const LinearProgressIndicator(),
          Form(
            key: form,
            child: Column(
              children: [
                if (person == null) ...[
                  TextFormField(
                    controller: name,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextFormField(
                    controller: email,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) =>
                        RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid email.',
                  ),
                ],
                if (person?['is_owner'] == true)
                  const Text('Owner access is protected.')
                else ...[
                  const SectionTitle(
                    'Permissions',
                    subtitle: 'Choose what this person can manage.',
                  ),
                  for (final item in permissionLabels.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.value),
                      value: permissions.contains(item.key),
                      onChanged: !editable || busy || !can(s.profile, item.key)
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                permissions.add(item.key);
                              } else {
                                permissions.remove(item.key);
                              }
                            }),
                    ),
                  const SectionTitle(
                    'Team labels',
                    subtitle: 'Labels do not grant permissions.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final item in staffLabels.entries)
                        FilterChip(
                          label: Text(item.value),
                          selected: kinds.contains(item.key),
                          onSelected: !editable || busy
                              ? null
                              : (v) => setState(() {
                                  if (v) {
                                    kinds.add(item.key);
                                  } else {
                                    kinds.remove(item.key);
                                  }
                                }),
                        ),
                    ],
                  ),
                ],
                if (!editable && person['is_owner'] != true)
                  Text(
                    own
                        ? 'Another authorised manager must change your access.'
                        : 'You can manage only accounts whose permissions you also hold.',
                  ),
                const SizedBox(height: 20),
                if (editable)
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (!form.currentState!.validate()) return;
                            action(
                              {
                                'action': person == null
                                    ? 'invite'
                                    : 'set_permissions',
                                if (person == null) ...{
                                  'email': email.text.trim(),
                                  'display_name': name.text.trim(),
                                } else
                                  'user_id': person['id'],
                                'permissions': permissions.toList(),
                                'staff_kinds': kinds.toList(),
                              },
                              person == null
                                  ? 'Invitation sent. They can set a password using the email.'
                                  : 'Access saved.',
                              close: true,
                            );
                          },
                    child: Text(
                      person == null ? 'Send invitation' : 'Save access',
                    ),
                  ),
                if (person != null && editable)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text(
                                  enabled
                                      ? 'Disable account access?'
                                      : 'Enable account access?',
                                ),
                                content: Text(
                                  enabled
                                      ? 'This person will lose access to private app and website areas.'
                                      : 'This person will regain their assigned access.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Confirm'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true || !mounted) return;
                            await action(
                              {
                                'action': 'set_active',
                                'user_id': person['id'],
                                'is_active': !enabled,
                              },
                              enabled
                                  ? 'Account disabled.'
                                  : 'Account enabled.',
                              close: true,
                            );
                          },
                    child: Text(enabled ? 'Disable access' : 'Enable access'),
                  ),
                if (person != null && enabled && (editable || own))
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => action({
                            'action': 'send_setup',
                            'user_id': person['id'],
                          }, 'Setup email sent.'),
                    child: const Text('Send password setup email'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
