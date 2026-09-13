import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';

class EnquiryPage extends StatefulWidget {
  final AppState state;
  final String kind;
  const EnquiryPage(this.state, {super.key, this.kind = 'contact'});
  @override
  State<EnquiryPage> createState() => _EnquiryPageState();
}

class _EnquiryPageState extends State<EnquiryPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      message = TextEditingController();
  bool sent = false;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.kind == 'contact' ? 'Get in touch' : 'Madrasah enquiry',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (sent)
          const Text(
            'Your enquiry has been received. The centre will respond using the details you supplied.',
          )
        else
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  maxLength: 120,
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'Enter your name.' : null,
                ),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  maxLength: 254,
                  validator: (v) =>
                      RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Enter a valid email.',
                ),
                if (widget.kind == 'madrassah')
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    maxLength: 30,
                    validator: (v) => (v?.trim().length ?? 0) < 7
                        ? 'Enter a contact number.'
                        : null,
                  ),
                TextFormField(
                  controller: message,
                  decoration: const InputDecoration(labelText: 'Your question'),
                  maxLength: 4000,
                  minLines: 4,
                  maxLines: 10,
                  validator: (v) => (v?.trim().length ?? 0) < 5
                      ? 'Please add your question.'
                      : null,
                ),
                const SizedBox(height: 16),
                if (widget.state.client == null)
                  const Text('Forms are unavailable in this preview.')
                else
                  AsyncButton(
                    label: 'Send enquiry',
                    onPressed: () async {
                      if (!form.currentState!.validate()) return;
                      final payload = {
                        'name': name.text.trim(),
                        'email': email.text.trim(),
                        if (widget.kind == 'madrassah')
                          'phone': phone.text.trim(),
                        widget.kind == 'contact' ? 'question' : 'query': message
                            .text
                            .trim(),
                      };
                      final response = await widget.state.client!.functions
                          .invoke(
                            'submit-form',
                            body: {'kind': widget.kind, 'payload': payload},
                          );
                      if (response.data is! Map ||
                          response.data['ok'] != true) {
                        throw StateError('Not saved');
                      }
                      if (mounted) setState(() => sent = true);
                    },
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class FormsPage extends StatefulWidget {
  final AppState state;
  final void Function(Record)? assign;
  const FormsPage(this.state, {super.key, this.assign});
  @override
  State<FormsPage> createState() => _FormsPageState();
}

class _FormsPageState extends State<FormsPage> {
  String status = 'new', kind = 'all', search = '';
  int page = 0;
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async {
    var query = widget.state.client!
        .from('form_submissions')
        .select('id,kind,payload,status,created_at')
        .eq('status', status);
    if (kind != 'all') query = query.eq('kind', kind);
    return records(
      await query
          .order('created_at', ascending: false)
          .range(page * 25, page * 25 + 24)
          .timeout(const Duration(seconds: 20)),
    );
  }

  void reload() => setState(() {
    request = load();
  });
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Forms inbox',
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: status,
                  items: const [
                    DropdownMenuItem(
                      value: 'new',
                      child: Text('Needs a reply'),
                    ),
                    DropdownMenuItem(value: 'done', child: Text('Completed')),
                  ],
                  onChanged: (v) {
                    status = v!;
                    page = 0;
                    reload();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: kind,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All forms'),
                    ),
                    for (final k in ['contact', 'madrassah', 'itikaaf'])
                      if (can(widget.state.profile, 'forms_$k'))
                        DropdownMenuItem(value: k, child: Text(k)),
                  ],
                  onChanged: (v) {
                    kind = v!;
                    page = 0;
                    reload();
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search this page',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Record>>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: reload,
                    child: const Text('Could not load forms. Retry'),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final visible = all
                  .where(
                    (r) =>
                        jsonEncode(r['payload']).toLowerCase().contains(search),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Text('Page ${page + 1} · ${visible.length} shown'),
                      const Spacer(),
                      TextButton(
                        onPressed: visible.isEmpty
                            ? null
                            : () async {
                                await SharePlus.instance.share(
                                  ShareParams(
                                    files: [
                                      XFile.fromData(
                                        Uint8List.fromList(
                                          utf8.encode(formsCsv(visible)),
                                        ),
                                        mimeType: 'text/csv',
                                        name: 'forms.csv',
                                      ),
                                    ],
                                    fileNameOverrides: ['forms.csv'],
                                    sharePositionOrigin: const Rect.fromLTWH(
                                      0,
                                      0,
                                      100,
                                      100,
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Export CSV'),
                      ),
                    ],
                  ),
                  if (visible.isEmpty) const Text('No forms here yet.'),
                  for (final r in visible)
                    Card(
                      child: ExpansionTile(
                        title: Text(
                          '${r['payload']['name'] ?? r['payload']['attendee_name'] ?? r['kind']}',
                        ),
                        subtitle: Text(
                          '${r['kind']} · ${r['created_at'].toString().split('T').first}',
                        ),
                        childrenPadding: const EdgeInsets.all(18),
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in (r['payload'] as Map).entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SelectableText(
                                '${entry.key.toString().replaceAll('_', ' ')}\n${entry.value}',
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (r['payload']['email'] is String)
                                TextButton.icon(
                                  onPressed: () => openLink(
                                    context,
                                    Uri(
                                      scheme: 'mailto',
                                      path: r['payload']['email'],
                                    ).toString(),
                                  ),
                                  icon: const Icon(Icons.mail_outline),
                                  label: const Text('Email draft'),
                                ),
                              if (r['payload']['phone'] is String)
                                TextButton.icon(
                                  onPressed: () => openLink(
                                    context,
                                    Uri(
                                      scheme: 'tel',
                                      path: r['payload']['phone'],
                                    ).toString(),
                                  ),
                                  icon: const Icon(Icons.call_outlined),
                                  label: const Text('Call'),
                                ),
                              if (widget.assign != null)
                                TextButton(
                                  onPressed: () => widget.assign!(r),
                                  child: const Text('Assign action'),
                                ),
                            ],
                          ),
                          AsyncButton(
                            label: status == 'new'
                                ? 'Mark completed'
                                : 'Reopen',
                            onPressed: () async {
                              await widget.state.client!
                                  .from('form_submissions')
                                  .update({
                                    'status': status == 'new' ? 'done' : 'new',
                                  })
                                  .eq('id', r['id'])
                                  .select('id')
                                  .single()
                                  .timeout(const Duration(seconds: 20));
                              reload();
                            },
                          ),
                        ],
                      ),
                    ),
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
                      TextButton(
                        onPressed: all.length < 25
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
    ),
  );
}
