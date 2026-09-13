import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'custom_forms.dart';
import 'workspace.dart';

String? emailDraftError(
  String recipient,
  String subject,
  String body,
  bool acknowledged,
) {
  if (recipient.length > 254 ||
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(recipient))
    return 'Enter a valid recipient email.';
  if (subject.trim().isEmpty ||
      subject.length > 160 ||
      subject.contains(RegExp(r'[\r\n]')))
    return 'Add a subject of 1–160 characters on one line.';
  if (body.trim().isEmpty || body.length > 6000)
    return 'Add a message of 1–6000 characters.';
  if (!acknowledged)
    return 'Confirm that you checked the recipient and message.';
  return null;
}

class FormEmailPanel extends StatefulWidget {
  final AppState state;
  final String submissionId;
  final String initialRecipient;
  final VoidCallback onChanged;
  const FormEmailPanel(
    this.state, {
    super.key,
    required this.submissionId,
    this.initialRecipient = '',
    required this.onChanged,
  });
  @override
  State<FormEmailPanel> createState() => _FormEmailPanelState();
}

class _FormEmailPanelState extends State<FormEmailPanel> {
  late Future<Record> request = load();
  Future<Record> load() async {
    final capability = await widget.state.client!
        .rpc(
          'form_email_capability',
          params: {'p_submission_id': widget.submissionId},
        )
        .timeout(const Duration(seconds: 20));
    final related = await Future.wait([
      widget.state.client!
          .from('form_email_incoming')
          .select('id,sender,subject,body,status,created_at')
          .eq('submission_id', widget.submissionId)
          .order('created_at', ascending: false)
          .limit(25),
      widget.state.client!
          .from('form_email_outbox')
          .select('id,recipient,subject,status,created_at')
          .eq('submission_id', widget.submissionId)
          .order('created_at', ascending: false)
          .limit(25),
    ]).timeout(const Duration(seconds: 20));
    return {
      'enabled': capability is Map && capability['enabled'] == true,
      'incoming': related[0],
      'outgoing': related[1],
    };
  }

  void reload() {
    if (mounted) setState(() => request = load());
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Email replies'),
    subtitle: const Text('Optional email sending and incoming review'),
    children: [
      FutureBuilder<Record>(
        future: request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const LinearProgressIndicator();
          if (snapshot.hasError)
            return TextButton(
              onPressed: () => setState(() => request = load()),
              child: const Text('Email service unavailable. Check again'),
            );
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data['enabled'] == true)
                OutlinedButton.icon(
                  icon: const Icon(Icons.outgoing_mail),
                  label: const Text('Write an email'),
                  onPressed: () => showPrivatePage(
                    context,
                    widget.state,
                    FormEmailComposer(
                      widget.state,
                      submissionId: widget.submissionId,
                      initialRecipient: widget.initialRecipient,
                      onSaved: reload,
                    ),
                  ),
                )
              else
                const Text(
                  'Email sending is currently unavailable. You can reply in the conversation above.',
                ),
              const SectionTitle('Incoming review'),
              for (final email in records(data['incoming']))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Email sender is not verified'),
                        Text(
                          '${email['sender']} · ${formatWorkspaceDate(email['created_at'])}',
                        ),
                        Text('${email['subject']}'),
                        SelectableText('${email['body']}'),
                        Text('Review status: ${email['status']}'),
                        if (email['status'] == 'pending')
                          Wrap(
                            spacing: 8,
                            children: [
                              AsyncButton(
                                label: 'Accept into conversation',
                                onPressed: () async {
                                  await widget.state.client!
                                      .rpc(
                                        'review_form_email',
                                        params: {
                                          'p_id': email['id'],
                                          'p_accept': true,
                                        },
                                      )
                                      .timeout(const Duration(seconds: 20));
                                  reload();
                                },
                              ),
                              AsyncButton(
                                label: 'Reject',
                                onPressed: () async {
                                  await widget.state.client!
                                      .rpc(
                                        'review_form_email',
                                        params: {
                                          'p_id': email['id'],
                                          'p_accept': false,
                                        },
                                      )
                                      .timeout(const Duration(seconds: 20));
                                  reload();
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (records(data['incoming']).isEmpty)
                const Text('No incoming emails to review.'),
              const SectionTitle('Outgoing queue'),
              for (final email in records(data['outgoing']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${email['subject']}'),
                  subtitle: Text(
                    '${email['recipient']}\n${formatWorkspaceDate(email['created_at'])} · ${email['status'] == 'sent'
                        ? 'Accepted by email provider'
                        : email['status'] == 'uncertain'
                        ? 'Delivery needs checking'
                        : email['status']}',
                  ),
                ),
              if (records(data['outgoing']).isEmpty)
                const Text('No emails have been queued.'),
              const Text(
                'Provider acceptance does not confirm that the recipient has read or received the email.',
              ),
            ],
          );
        },
      ),
    ],
  );
}

class FormEmailComposer extends StatefulWidget {
  final AppState state;
  final String submissionId, initialRecipient;
  final VoidCallback onSaved;
  const FormEmailComposer(
    this.state, {
    super.key,
    required this.submissionId,
    required this.initialRecipient,
    required this.onSaved,
  });
  @override
  State<FormEmailComposer> createState() => _FormEmailComposerState();
}

class _FormEmailComposerState extends State<FormEmailComposer> {
  late final recipient = TextEditingController(text: widget.initialRecipient);
  final subject = TextEditingController(), body = TextEditingController();
  bool acknowledged = false, busy = false;
  String? error, attemptedSignature;
  String attempt = formAttemptId();
  @override
  void dispose() {
    recipient.dispose();
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  void changed(String _) {
    if (acknowledged) setState(() => acknowledged = false);
  }

  Future<void> queue() async {
    if (busy) return;
    final invalid = emailDraftError(
      recipient.text.trim(),
      subject.text.trim(),
      body.text.trim(),
      acknowledged,
    );
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    final signature =
        '${recipient.text.trim()}\u0000${subject.text.trim()}\u0000${body.text.trim()}';
    if (attemptedSignature != null && attemptedSignature != signature)
      attempt = formAttemptId();
    attemptedSignature = signature;
    setState(() {
      error = null;
      busy = true;
    });
    try {
      await widget.state.client!
          .rpc(
            'queue_form_email',
            params: {
              'p_submission_id': widget.submissionId,
              'p_recipient': recipient.text.trim(),
              'p_subject': subject.text.trim(),
              'p_body': body.text.trim(),
              'p_idempotency_key': attempt,
              'p_acknowledged': acknowledged,
            },
          )
          .timeout(const Duration(seconds: 30));
      widget.onSaved();
      if (mounted) {
        notice(
          context,
          'Email queued. Its status is shown in the outgoing queue.',
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Email was not confirmed. Check the outgoing queue, then retry the same draft if needed.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Write an email',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'This message will also be saved as a reply in the form conversation.',
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (busy) const LinearProgressIndicator(),
        TextField(
          controller: recipient,
          enabled: !busy,
          maxLength: 254,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Recipient email'),
          onChanged: changed,
        ),
        TextField(
          controller: subject,
          enabled: !busy,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Subject'),
          onChanged: changed,
        ),
        TextField(
          controller: body,
          enabled: !busy,
          maxLength: 6000,
          minLines: 5,
          maxLines: 15,
          decoration: const InputDecoration(labelText: 'Message'),
          onChanged: changed,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I checked the recipient address and message'),
          value: acknowledged,
          onChanged: busy
              ? null
              : (v) => setState(() => acknowledged = v == true),
        ),
        FilledButton(
          onPressed: busy ? null : queue,
          child: const Text('Queue email'),
        ),
      ],
    ),
  );
}
