import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'forms.dart';
import 'custom_forms.dart';
import 'user_management.dart';
import 'notification_settings.dart';
import 'workspace.dart';
import 'learning.dart';

class AccountGate extends StatelessWidget {
  final AppState state;
  final Widget child;
  final String? permission;
  const AccountGate(
    this.state, {
    super.key,
    required this.child,
    this.permission,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      if (state.profileLoading) {
        return const ContentPage(
          title: 'Your account',
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (!active(state.profile) ||
          (permission != null && !can(state.profile, permission!))) {
        return ContentPage(
          title: 'Your account',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  'Sign in with an active account that has access to this area.',
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Return to account'),
                ),
              ],
            ),
          ),
        );
      }
      final permissions = List<String>.from(state.profile?['permissions'] ?? [])
        ..sort();
      return KeyedSubtree(
        key: ValueKey(
          '${state.userId}/${state.profile?['is_owner']}/${permissions.join(',')}',
        ),
        child: child,
      );
    },
  );
}

class AccountView extends StatefulWidget {
  final AppState state;
  const AccountView(this.state, {super.key});
  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  final email = TextEditingController(), password = TextEditingController();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        const SectionTitle(
          'Your community',
          subtitle: 'One account for the website and app',
        ),
        if (s.client == null)
          const Text('Account connection is not configured in this preview.')
        else if (s.userId == null) ...[
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AsyncButton(
            label: 'Sign in',
            onPressed: () async {
              await s.client!.auth.signInWithPassword(
                email: email.text.trim(),
                password: password.text,
              );
              password.clear();
              await s.refreshProfile();
            },
          ),
          TextButton(
            onPressed: () =>
                openLink(context, '${s.organisation.website}/admin/login'),
            child: const Text('Password help'),
          ),
        ] else ...[
          if (s.profileLoading)
            const LinearProgressIndicator()
          else if (!active(s.profile)) ...[
            const Text('Your account access could not be confirmed.'),
            TextButton(
              onPressed: s.refreshProfile,
              child: const Text('Check again'),
            ),
          ] else ...[
            Text(
              '${s.profile?['display_name'] ?? 'Welcome'}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (!extensionsEnabled &&
                [
                  'contact',
                  'madrassah',
                  'itikaaf',
                ].any((k) => can(s.profile, 'forms_$k')))
              ActionTile(
                icon: Icons.inbox_outlined,
                title: 'Forms inbox',
                subtitle: 'Enquiries and registrations you can manage',
                onTap: () => showPrivatePage(
                  context,
                  s,
                  FormsPage(
                    s,
                    assign: extensionsEnabled
                        ? (form) => showPrivatePage(
                            context,
                            s,
                            CreateTaskPage(s, form: form),
                          )
                        : null,
                  ),
                ),
              ),
            if (extensionsEnabled) ...[
              ActionTile(
                icon: Icons.dynamic_form_outlined,
                title: 'Forms & responses',
                subtitle:
                    'Registrations, replies, assigned actions and form creation',
                onTap: () => showPrivatePage(context, s, FormsWorkspacePage(s)),
              ),
              ActionTile(
                icon: Icons.task_alt,
                title: 'Tasks',
                subtitle: 'Your actions, deadlines and outstanding work',
                onTap: () => showPrivatePage(context, s, TasksPage(s)),
              ),
              ActionTile(
                icon: Icons.notifications_outlined,
                title: 'Updates',
                subtitle: 'Task and learning notifications',
                onTap: () => showPrivatePage(context, s, UpdatesPage(s)),
              ),
              ActionTile(
                icon: Icons.school_outlined,
                title: 'Student & staff portal',
                subtitle: 'Courses, progress and class registers',
                onTap: () => showPrivatePage(context, s, LearningPage(s)),
              ),
            ],
            if (owner(s.profile) || can(s.profile, 'users'))
              ActionTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Manage people & access',
                subtitle: 'Create accounts and assign permissions',
                onTap: () => showPage(
                  context,
                  AccountGate(s, permission: 'users', child: PeoplePage(s)),
                ),
              ),
          ],
          const SizedBox(height: 20),
          AsyncButton(
            label: 'Sign out',
            onPressed: () async {
              await s.notifications.prepareForSignOut();
              await s.client!.auth.signOut(scope: SignOutScope.local);
              await s.refreshProfile();
              if (context.mounted && s.notifications.error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(s.notifications.error!)));
              }
            },
          ),
        ],
        if (extensionsEnabled)
          ActionTile(
            icon: Icons.description_outlined,
            title: 'Forms & registrations',
            subtitle: 'Open community forms',
            onTap: () => showPage(context, PublicFormsPage(s)),
          ),
        const SectionTitle('Preferences'),
        ActionTile(
          icon: Icons.notifications_active_outlined,
          title: 'Notifications & prayer reminders',
          subtitle: 'Choose which updates reach your phone',
          onTap: () =>
              showPage(context, NotificationSettingsPage(s, s.notifications)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark appearance'),
          value: s.dark,
          onChanged: s.setDark,
        ),
        ActionTile(
          icon: Icons.mail_outline,
          title: 'Get in touch',
          subtitle: 'Questions and enquiries',
          onTap: () => showPage(context, EnquiryPage(s)),
        ),
        ActionTile(
          icon: Icons.child_care_outlined,
          title: 'Madrasah enquiries',
          subtitle: 'Pupil admissions and parent questions',
          onTap: () => showPage(context, EnquiryPage(s, kind: 'madrassah')),
        ),
      ],
    );
  }
}
