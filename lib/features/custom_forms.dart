import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'account.dart';
import 'workspace.dart';
import 'fees.dart';
import 'form_email.dart';

const customFieldTypes = [
  'text',
  'textarea',
  'email',
  'phone',
  'number',
  'date',
  'select',
  'multiselect',
  'checkbox',
  'image',
  'file',
];
const uploadMime = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
};
String formAttemptId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

bool fieldVisible(Record field, Record answers) {
  if (field['show_when'] is! Map) return true;
  final rule = Record.from(field['show_when']);
  final equal = answers[rule['field']] == rule['value'];
  return rule['operator'] == 'not_equals' ? !equal : equal;
}

bool emptyAnswer(dynamic value) =>
    value == null ||
    (value is String && value.trim().isEmpty) ||
    (value is List && value.isEmpty);
String? fieldError(Record field, dynamic value) {
  final type = '${field['type']}';
  if (field['required'] == true &&
      (emptyAnswer(value) || (type == 'checkbox' && value != true))) {
    return 'This answer is required.';
  }
  if (emptyAnswer(value)) return null;
  final text = '$value';
  if (type == 'checkbox') return value is bool ? null : 'Choose yes or no.';
  if (type == 'number') {
    final number = value is num ? value : num.tryParse(text);
    return number != null && number.isFinite && number.abs() <= 1e12
        ? null
        : 'Enter a number between −1 trillion and 1 trillion.';
  }
  if (type == 'date') {
    final date = DateTime.tryParse(text);
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) &&
            date != null &&
            dateKey(date) == text
        ? null
        : 'Use a valid date: YYYY-MM-DD.';
  }
  if (type == 'email' &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return 'Enter a valid email.';
  }
  final limit = type == 'textarea'
      ? 6000
      : type == 'email'
      ? 254
      : type == 'phone'
      ? 40
      : 500;
  if (['text', 'textarea', 'email', 'phone'].contains(type) &&
      text.length > limit) {
    return 'Use $limit characters or fewer.';
  }
  final options = List<String>.from(field['options'] ?? []);
  if (type == 'select' && !options.contains(value)) {
    return 'Choose an available option.';
  }
  if (type == 'multiselect' &&
      (value is! List ||
          value.length > 50 ||
          value.toSet().length != value.length ||
          value.any((v) => !options.contains(v)))) {
    return 'Choose available options.';
  }
  if (['image', 'file'].contains(type) &&
      !RegExp(r'^[a-f0-9-]{36}$').hasMatch(text)) {
    return 'Upload this file again.';
  }
  return null;
}

Record visibleAnswers(List<Record> fields, Record answers) => {
  for (final field in fields)
    if (fieldVisible(field, answers) && !emptyAnswer(answers[field['id']]))
      '${field['id']}': field['type'] == 'number'
          ? num.tryParse('${answers[field['id']]}')
          : answers[field['id']],
};
String? uploadError(String name, int size, String type) {
  final ext = name.split('.').last.toLowerCase();
  if (!uploadMime.containsKey(ext) ||
      (type == 'image' && !['jpg', 'jpeg', 'png', 'webp'].contains(ext))) {
    return type == 'image'
        ? 'Choose a JPEG, PNG or WebP image.'
        : 'Choose a JPEG, PNG, WebP, PDF or ZIP file.';
  }
  if (size <= 0 || size > 10 * 1024 * 1024) {
    return 'Files must be between 1 byte and 10 MB.';
  }
  return null;
}

Future<Record> formsAction(AppState state, Record body) async {
  final response = await state.client!.functions
      .invoke('custom-forms', body: body)
      .timeout(const Duration(seconds: 40));
  if (response.data is! Map) throw StateError('Invalid response');
  return Record.from(response.data);
}

Future<void> shareFormBytes(Uint8List bytes, String name, String mime) =>
    SharePlus.instance
        .share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: mime, name: name)],
            fileNameOverrides: [name],
            sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
          ),
        )
        .then((_) {});

class PublicFormsPage extends StatelessWidget {
  final AppState state;
  const PublicFormsPage(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Forms & registrations',
    child: state.client == null
        ? const Center(child: Text('Forms are not connected in this preview.'))
        : _PublicFormsList(state),
  );
}

class _PublicFormsList extends StatefulWidget {
  final AppState state;
  const _PublicFormsList(this.state);
  @override
  State<_PublicFormsList> createState() => _PublicFormsListState();
}

class _PublicFormsListState extends State<_PublicFormsList> {
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async => records(
    await widget.state.client!
        .rpc('list_public_forms')
        .timeout(const Duration(seconds: 20)),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Record>>(
    future: request,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () => setState(() => request = load()),
            child: const Text('Could not load forms. Retry'),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (snapshot.data!.isEmpty)
            const Text('There are no open forms at the moment.'),
          for (final definition in snapshot.data!)
            ActionTile(
              icon: Icons.description_outlined,
              title: '${definition['title']}',
              subtitle: '${definition['description'] ?? ''}',
              onTap: () => showPage(
                context,
                CustomFormPage(widget.state, slug: '${definition['slug']}'),
              ),
            ),
        ],
      );
    },
  );
}

class CustomFormPage extends StatefulWidget {
  final AppState state;
  final String slug;
  const CustomFormPage(this.state, {super.key, required this.slug});
  @override
  State<CustomFormPage> createState() => _CustomFormPageState();
}

class _CustomFormPageState extends State<CustomFormPage> {
  final key = GlobalKey<FormState>();
  Record answers = {}, uploaded = {};
  final attempt = formAttemptId();
  late Future<Record?> request = load();
  bool sent = false, busy = false;
  String? error, submissionId;
  String? submittingUser;
  @override
  void initState() {
    super.initState();
    submittingUser = widget.state.userId;
  }

  Future<Record?> load() async {
    final data = await widget.state.client!
        .rpc('get_public_form', params: {'p_slug': widget.slug})
        .timeout(const Duration(seconds: 20));
    if (data is Map) {
      final result = Record.from(data);
      for (final field in records(result['schema']?['fields'])) {
        if (field['type'] == 'checkbox') {
          answers.putIfAbsent('${field['id']}', () => false);
        }
      }
      return result;
    }
    return null;
  }

  Future<void> upload(Record field, Record definition) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: field['type'] == 'image'
          ? ['jpg', 'jpeg', 'png', 'webp']
          : uploadMime.keys.toList(),
    );
    if (file == null || !mounted) return;
    final declaredSize = file.lengthSync();
    final invalid = uploadError(
      file.name,
      declaredSize ?? 1,
      '${field['type']}',
    );
    if (invalid != null) {
      notice(context, invalid);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final mime = uploadMime[file.name.split('.').last.toLowerCase()]!;
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (buffer.length + chunk.length > 10 * 1024 * 1024) {
          throw StateError('File too large');
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      if (bytes.isEmpty ||
          (declaredSize != null && bytes.length != declaredSize)) {
        throw StateError('File changed');
      }
      final prepared = await formsAction(widget.state, {
        'action': 'upload_prepare',
        'slug': widget.slug,
        'version': definition['version'],
        'field_id': field['id'],
        'idempotency_key': attempt,
        'file_name': file.name,
        'mime_type': mime,
        'size_bytes': bytes.length,
      });
      await widget.state.client!.storage
          .from('form-attachments')
          .uploadBinaryToSignedUrl(
            '${prepared['path']}',
            '${prepared['token']}',
            bytes,
            FileOptions(contentType: mime),
          )
          .timeout(const Duration(seconds: 60));
      final finished = await formsAction(widget.state, {
        'action': 'upload_finish',
        'upload_id': prepared['upload_id'],
        'upload_token': prepared['upload_token'],
      });
      if (finished['ok'] != true) throw StateError('Not uploaded');
      if (mounted) {
        setState(() {
          answers['${field['id']}'] = prepared['upload_id'];
          uploaded['${field['id']}'] = {
            'id': prepared['upload_id'],
            'upload_token': prepared['upload_token'],
            'name': file.name,
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'The file could not be uploaded. Please choose it again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit(Record definition) async {
    if (!key.currentState!.validate()) return;
    if (widget.state.userId != submittingUser) {
      notice(context, 'Your account changed. Reopen this form before sending.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final fields = records(definition['schema']['fields']);
      final values = visibleAnswers(fields, answers);
      final result = await formsAction(widget.state, {
        'action': 'submit',
        'slug': widget.slug,
        'version': definition['version'],
        'answers': values,
        'idempotency_key': attempt,
        'uploads': [
          for (final entry in uploaded.entries)
            if (values.containsKey(entry.key))
              {
                'id': entry.value['id'],
                'upload_token': entry.value['upload_token'],
              },
        ],
      });
      if (result['ok'] != true) throw StateError('Not submitted');
      if (mounted) {
        setState(() {
          sent = true;
          submissionId = '${result['id']}';
          answers.clear();
          uploaded.clear();
        });
      }
    } on FunctionException catch (e) {
      if (mounted) {
        setState(
          () => error = e.status == 409
              ? 'This attempt was already used or the form has changed. Check My responses, then reopen the form if you need to send a new response.'
              : e.status == 429
              ? 'Too many requests. Wait a few minutes and try again.'
              : 'Your response could not be sent. Your answers are still here; try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Your response could not be sent. Your answers are still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Complete form',
    child: FutureBuilder<Record?>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => request = load()),
              child: const Text('Could not load this form. Retry'),
            ),
          );
        }
        final definition = snapshot.data;
        if (definition == null) {
          return const Center(child: Text('This form is no longer open.'));
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${definition['title']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${definition['description'] ?? ''}'),
            const SizedBox(height: 20),
            if (sent) ...[
              const Text('Your response has been received.'),
              if (widget.state.userId != null)
                TextButton(
                  onPressed: () => showPrivatePage(
                    context,
                    widget.state,
                    FormConversationPage(
                      widget.state,
                      submissionId: submissionId!,
                      staff: false,
                    ),
                  ),
                  child: const Text('View response and replies'),
                ),
            ] else ...[
              if (widget.state.userId == null)
                const Text(
                  'You can send without an account. Sign in before completing the form to keep your response and replies in your account.',
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (busy) const LinearProgressIndicator(),
              Form(
                key: key,
                child: AbsorbPointer(
                  absorbing: busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final field in records(
                        definition['schema']['fields'],
                      ))
                        if (fieldVisible(field, answers))
                          Padding(
                            key: ValueKey(field['id']),
                            padding: const EdgeInsets.only(bottom: 20),
                            child: CustomFieldInput(
                              field: field,
                              value: answers[field['id']],
                              fileName: uploaded[field['id']]?['name'],
                              onChanged: (value) => setState(
                                () => answers['${field['id']}'] =
                                    field['type'] == 'number'
                                    ? num.tryParse('$value') ?? value
                                    : value,
                              ),
                              onUpload: () => upload(field, definition),
                            ),
                          ),
                      FilledButton(
                        onPressed: busy ? null : () => submit(definition),
                        child: const Text('Send response'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class CustomFieldInput extends StatelessWidget {
  final Record field;
  final dynamic value;
  final String? fileName;
  final ValueChanged<dynamic> onChanged;
  final VoidCallback onUpload;
  const CustomFieldInput({
    super.key,
    required this.field,
    required this.value,
    this.fileName,
    required this.onChanged,
    required this.onUpload,
  });
  @override
  Widget build(BuildContext context) {
    final label = '${field['label']}${field['required'] == true ? ' *' : ''}',
        type = '${field['type']}';
    final options = List<String>.from(field['options'] ?? []);
    if (type == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value as String : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: onChanged,
        validator: (v) => fieldError(field, v),
      );
    }
    if (type == 'checkbox') {
      return FormField<bool>(
        initialValue: value == true,
        validator: (_) => fieldError(field, value),
        builder: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: value == true,
              onChanged: (v) {
                onChanged(v);
                s.didChange(v);
              },
            ),
            if (s.hasError)
              Text(
                s.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (type == 'multiselect') {
      return FormField<List>(
        validator: (_) => fieldError(field, value),
        builder: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            for (final option in options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(option),
                value: (value as List? ?? []).contains(option),
                onChanged: (v) {
                  final next = List<String>.from(value ?? []);
                  if (v == true) {
                    next.add(option);
                  } else {
                    next.remove(option);
                  }
                  onChanged(next);
                  s.didChange(next);
                },
              ),
            if (s.hasError)
              Text(
                s.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if (['image', 'file'].contains(type)) {
      return FormField<String>(
        validator: (_) => fieldError(field, value),
        builder: (s) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            OutlinedButton.icon(
              onPressed: onUpload,
              icon: Icon(
                type == 'image'
                    ? Icons.add_photo_alternate_outlined
                    : Icons.attach_file,
              ),
              label: Text(
                fileName ?? 'Choose ${type == 'image' ? 'image' : 'file'}',
              ),
            ),
            if (value != null)
              TextButton(
                onPressed: () {
                  onChanged(null);
                  s.didChange(null);
                },
                child: const Text('Remove file'),
              ),
            const Text('Maximum 10 MB.'),
            if (s.hasError)
              Text(
                s.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    return TextFormField(
      initialValue: value?.toString(),
      decoration: InputDecoration(
        labelText: label,
        hintText: type == 'date' ? 'YYYY-MM-DD' : null,
      ),
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(signed: true, decimal: true)
          : type == 'email'
          ? TextInputType.emailAddress
          : type == 'phone'
          ? TextInputType.phone
          : type == 'date'
          ? TextInputType.datetime
          : TextInputType.multiline,
      minLines: type == 'textarea' ? 3 : 1,
      maxLines: type == 'textarea' ? 8 : 1,
      maxLength: type == 'textarea'
          ? 6000
          : type == 'email'
          ? 254
          : type == 'phone'
          ? 40
          : type == 'date'
          ? 10
          : 500,
      validator: (v) => fieldError(field, v),
      onChanged: onChanged,
    );
  }
}

class FormsWorkspacePage extends StatefulWidget {
  final AppState state;
  const FormsWorkspacePage(this.state, {super.key});
  @override
  State<FormsWorkspacePage> createState() => _FormsWorkspacePageState();
}

class _FormsWorkspacePageState extends State<FormsWorkspacePage> {
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async => records(
    await widget.state.client!
        .from('custom_forms')
        .select('id,title,slug,published_version,enabled')
        .order('title')
        .limit(100),
  );
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Forms workspace',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ActionTile(
          icon: Icons.edit_document,
          title: 'Complete a form',
          subtitle: 'Open registrations and enquiries',
          onTap: () => showPage(context, PublicFormsPage(widget.state)),
        ),
        ActionTile(
          icon: Icons.chat_bubble_outline,
          title: 'My responses',
          subtitle: 'Your submitted forms and replies',
          onTap: () => showPrivatePage(
            context,
            widget.state,
            CustomInboxPage(widget.state, mine: true),
          ),
        ),
        FutureBuilder<List<Record>>(
          future: request,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() => request = load()),
                child: const Text('Could not check managed forms. Retry'),
              );
            }
            final forms = snapshot.data ?? [];
            final hasInbox =
                forms.isNotEmpty ||
                [
                  'forms_contact',
                  'forms_madrassah',
                  'forms_itikaaf',
                  'forms_custom',
                  'forms_manage',
                ].any((p) => can(widget.state.profile, p));
            return Column(
              children: [
                if (hasInbox)
                  ActionTile(
                    icon: Icons.inbox_outlined,
                    title: 'Staff inbox',
                    subtitle:
                        'All permitted enquiries, files, replies and actions',
                    onTap: () => showPrivatePage(
                      context,
                      widget.state,
                      CustomInboxPage(widget.state),
                    ),
                  ),
                ActionTile(
                  icon: Icons.dynamic_form_outlined,
                  title: 'Manage forms',
                  subtitle: 'Build forms and choose who receives them',
                  onTap: () => showPrivatePage(
                    context,
                    widget.state,
                    FormDefinitionsPage(widget.state),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

String formCsvCell(dynamic value) {
  var text = value == null ? '' : '$value';
  if (RegExp(r'^[\s\x00-\x1f]*[=+\-@]').hasMatch(text) ||
      RegExp(r'^[\t\r]').hasMatch(text)) {
    text = "'$text";
  }
  return '"${text.replaceAll('"', '""')}"';
}

String responsesCsv(List<Record> rows) {
  final columns = <String, String>{};
  String source(Record row) => '${row['custom_form_id'] ?? row['kind']}';
  for (final row in rows) {
    final fields = records(row['schema_snapshot']?['fields']);
    final labels = {
      for (final field in fields) '${field['id']}': '${field['label']}',
    };
    for (final key in (row['payload'] as Map? ?? {}).keys) {
      columns.putIfAbsent(
        '${source(row)}:$key',
        () =>
            '${row['schema_snapshot']?['title'] ?? row['kind']} / ${labels[key] ?? key}',
      );
    }
  }
  dynamic cell(dynamic value) =>
      value is List || value is Map ? jsonEncode(value) : value ?? '';
  return '\ufeff${[
    ['ID', 'Form', 'Status', 'Submitted', 'Version', ...columns.values].map(formCsvCell).join(','),
    for (final row in rows) [row['id'], row['schema_snapshot']?['title'] ?? row['kind'], row['status'], row['created_at'], row['form_version'] ?? '', for (final key in columns.keys) key.startsWith('${source(row)}:') ? cell(row['payload']?[key.substring(source(row).length + 1)]) : ''].map(formCsvCell).join(','),
  ].join('\r\n')}';
}

class CustomInboxPage extends StatefulWidget {
  final AppState state;
  final bool mine;
  const CustomInboxPage(this.state, {super.key, this.mine = false});
  @override
  State<CustomInboxPage> createState() => _CustomInboxPageState();
}

class _CustomInboxPageState extends State<CustomInboxPage> {
  String search = '', status = 'all', kind = 'all';
  String? formId;
  DateTime? from, to;
  bool oldest = false;
  int page = 0;
  final searchController = TextEditingController();
  late Future<Record> request = load();
  late Future<List<Record>> definitions = loadDefinitions();
  Future<List<Record>> loadDefinitions() async => records(
    await widget.state.client!
        .from('custom_forms')
        .select('id,title')
        .order('title')
        .limit(100),
  );
  Record filterParameters() => {
    'p_search': search,
    'p_kind': widget.mine
        ? 'custom'
        : kind == 'all'
        ? null
        : kind,
    'p_form_id': formId,
    'p_status': status == 'all' ? null : status,
    'p_from': from?.toUtc().toIso8601String(),
    'p_to': to == null
        ? null
        : DateTime(to!.year, to!.month, to!.day + 1).toUtc().toIso8601String(),
    'p_oldest': oldest,
    'p_mine': widget.mine,
  };
  Future<Record> load({int? offset, int limit = 25, Record? filters}) async =>
      Record.from(
        await widget.state.client!
            .rpc(
              'search_form_submissions',
              params: {
                ...filters ?? filterParameters(),
                'p_offset': offset ?? page * 25,
                'p_limit': limit,
              },
            )
            .timeout(const Duration(seconds: 25)),
      );
  void reload({bool reset = false}) => setState(() {
    if (reset) page = 0;
    request = load();
  });
  Future<List<Record>> allMatching(Record filters) async {
    final identity = widget.state.userId;
    final rows = <Record>[];
    var totalBytes = 0;
    for (var offset = 0; offset <= 25000; offset += 100) {
      if (!mounted || widget.state.userId != identity) {
        throw StateError('Account changed');
      }
      final result = await load(offset: offset, limit: 100, filters: filters);
      if ((result['total'] as num? ?? 0) > 25000) {
        throw StateError(
          'More than 25,000 responses match. Narrow the date or form filters before exporting.',
        );
      }
      totalBytes += utf8.encode(jsonEncode(result['rows'])).length;
      if (totalBytes > 25 * 1024 * 1024)
        throw StateError(
          'This export is too large for one file. Narrow the date or form filters.',
        );
      rows.addAll(records(result['rows']));
      if (rows.length >= (result['total'] as num? ?? 0) ||
          records(result['rows']).length < 100) {
        break;
      }
    }
    return rows;
  }

  Future<void> export(bool zip) async {
    final filters = filterParameters();
    filters['p_to'] ??= DateTime.now().toUtc().toIso8601String();
    final identity = widget.state.userId;
    List<Record> rows;
    if (zip) {
      if (filters['p_form_id'] == null) {
        notice(context, 'Choose one custom form before downloading its files.');
        return;
      }
      final result = await load(offset: 0, limit: 100, filters: filters);
      if (!mounted || widget.state.userId != identity) return;
      if ((result['total'] as num? ?? 0) > 100) {
        notice(
          context,
          'Narrow the filters to 100 responses or fewer for ZIP.',
        );
        return;
      }
      rows = records(result['rows']);
    } else {
      try {
        rows = await allMatching(filters);
      } on StateError catch (error) {
        if (mounted) notice(context, error.message);
        return;
      }
    }
    if (rows.isEmpty || !mounted || widget.state.userId != identity) return;
    if (!zip) {
      await shareFormBytes(
        Uint8List.fromList(utf8.encode(responsesCsv(rows))),
        'form-responses.csv',
        'text/csv',
      );
      return;
    }
    if (filters['p_form_id'] == null || rows.length > 100) {
      if (mounted) {
        notice(
          context,
          'Choose one custom form and narrow the filters to 100 responses or fewer for ZIP.',
        );
      }
      return;
    }
    final response = await widget.state.client!.functions
        .invoke(
          'custom-forms',
          body: {
            'action': 'export',
            'form_id': filters['p_form_id'],
            'format': 'zip',
            'submission_ids': rows.map((r) => r['id']).toList(),
          },
        )
        .timeout(const Duration(seconds: 60));
    if (!mounted || widget.state.userId != identity) return;
    if (response.data is! List<int>) throw StateError('Invalid archive');
    await shareFormBytes(
      Uint8List.fromList(response.data as List<int>),
      'form-responses.zip',
      'application/zip',
    );
  }

  Future<void> dateFilter(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (!mounted || picked == null) return;
    if (start) {
      from = picked;
    } else {
      to = picked;
    }
    reload(reset: true);
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: widget.mine ? 'My responses' : 'Forms inbox',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ExpansionTile(
            title: const Text('Search, filter & export'),
            children: [
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'Search all answers',
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: () {
                      search = searchController.text.trim();
                      reload(reset: true);
                    },
                    icon: const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (v) {
                  search = v.trim();
                  reload(reset: true);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: status,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All statuses'),
                        ),
                        DropdownMenuItem(
                          value: 'new',
                          child: Text('Needs a reply'),
                        ),
                        DropdownMenuItem(
                          value: 'done',
                          child: Text('Completed'),
                        ),
                      ],
                      onChanged: (v) {
                        status = v!;
                        reload(reset: true);
                      },
                    ),
                  ),
                  if (!widget.mine)
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: kind,
                        items: [
                          for (final value in [
                            'all',
                            'contact',
                            'madrassah',
                            'itikaaf',
                            'custom',
                          ])
                            DropdownMenuItem(
                              value: value,
                              child: Text(value == 'all' ? 'All forms' : value),
                            ),
                        ],
                        onChanged: (v) {
                          kind = v!;
                          formId = null;
                          reload(reset: true);
                        },
                      ),
                    ),
                ],
              ),
              if (!widget.mine)
                FutureBuilder<List<Record>>(
                  future: definitions,
                  builder: (context, snapshot) => DropdownButton<String>(
                    isExpanded: true,
                    value: formId ?? '',
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All custom forms'),
                      ),
                      for (final f in snapshot.data ?? <Record>[])
                        DropdownMenuItem(
                          value: '${f['id']}',
                          child: Text('${f['title']}'),
                        ),
                    ],
                    onChanged: (v) {
                      formId = v == '' ? null : v;
                      if (formId != null) kind = 'custom';
                      reload(reset: true);
                    },
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => dateFilter(true),
                    child: Text(
                      from == null ? 'From date' : 'From ${dateKey(from!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => dateFilter(false),
                    child: Text(to == null ? 'To date' : 'To ${dateKey(to!)}'),
                  ),
                  if (from != null || to != null)
                    TextButton(
                      onPressed: () {
                        from = null;
                        to = null;
                        reload(reset: true);
                      },
                      child: const Text('Clear dates'),
                    ),
                  FilterChip(
                    label: const Text('Oldest first'),
                    selected: oldest,
                    onSelected: (v) {
                      oldest = v;
                      reload(reset: true);
                    },
                  ),
                  AsyncButton(
                    label: 'Export all matching CSV',
                    onPressed: () => export(false),
                  ),
                  if (!widget.mine)
                    AsyncButton(
                      label: 'Download files ZIP',
                      onPressed: () => export(true),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Record>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: reload,
                    child: const Text('Could not load responses. Retry'),
                  ),
                );
              }
              final result = snapshot.data!, rows = records(result['rows']);
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${result['total'] ?? 0} matching · ${result['new_count'] ?? 0} need a reply · ${result['done_count'] ?? 0} completed',
                  ),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No responses match this view.'),
                    ),
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${row['schema_snapshot']?['title'] ?? row['kind']}',
                        ),
                        subtitle: Text(
                          '${row['payload']?['name'] ?? row['payload']?['attendee_name'] ?? ''}\n${formatWorkspaceDate(row['created_at'])} · ${row['status'] == 'done' ? 'Completed' : 'Needs a reply'}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showPrivatePage(
                          context,
                          widget.state,
                          FormConversationPage(
                            widget.state,
                            submissionId: '${row['id']}',
                            staff: !widget.mine,
                            onSaved: reload,
                          ),
                        ),
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
                      Text('Page ${page + 1}'),
                      TextButton(
                        onPressed:
                            (page + 1) * 25 >= (result['total'] as num? ?? 0)
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

class FormConversationPage extends StatefulWidget {
  final AppState state;
  final String submissionId;
  final bool staff;
  final VoidCallback? onSaved;
  const FormConversationPage(
    this.state, {
    super.key,
    required this.submissionId,
    required this.staff,
    this.onSaved,
  });
  @override
  State<FormConversationPage> createState() => _FormConversationPageState();
}

class _FormConversationPageState extends State<FormConversationPage> {
  final reply = TextEditingController();
  bool internal = false;
  late Future<Record> request = load();
  Future<Record> load() async {
    final response = Record.from(
      await widget.state.client!
          .from('form_submissions')
          .select()
          .eq('id', widget.submissionId)
          .single()
          .timeout(const Duration(seconds: 20)),
    );
    if (response['kind'] != 'custom') {
      return {'response': response, 'replies': [], 'attachments': []};
    }
    final membership = widget.staff
        ? records(
            await widget.state.client!
                .from('custom_form_staff')
                .select('role')
                .eq('form_id', response['custom_form_id'])
                .eq('user_id', widget.state.userId!)
                .limit(1),
          )
        : <Record>[];
    final staff =
        widget.staff &&
        (can(widget.state.profile, 'forms_custom') ||
            can(widget.state.profile, 'forms_manage') ||
            membership.isNotEmpty);
    final related = await Future.wait([
      widget.state.client!
          .from('form_replies')
          .select()
          .eq('submission_id', widget.submissionId)
          .order('created_at')
          .limit(500),
      widget.state.client!
          .from('form_attachments')
          .select()
          .eq('submission_id', widget.submissionId)
          .order('created_at')
          .limit(5),
    ]).timeout(const Duration(seconds: 20));
    return {
      'response': response,
      'replies': related[0],
      'attachments': related[1],
      'staff': staff,
    };
  }

  void reload() {
    if (mounted) setState(() => request = load());
    widget.onSaved?.call();
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Form response',
    actions: [
      IconButton(
        tooltip: 'Refresh',
        onPressed: reload,
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: FutureBuilder<Record>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('Could not open this response. Retry'),
            ),
          );
        }
        final result = snapshot.data!,
            response = Record.from(result['response']),
            payload = Record.from(response['payload']);
        final custom = response['kind'] == 'custom';
        final staff =
            widget.staff &&
            (custom
                ? result['staff'] == true
                : can(widget.state.profile, 'forms_${response['kind']}'));
        final fields = records(
          response['schema_snapshot']?['schema']?['fields'] ??
              response['schema_snapshot']?['fields'],
        );
        final labels = {
          for (final field in fields) '${field['id']}': '${field['label']}',
        };
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${response['schema_snapshot']?['title'] ?? response['kind']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${formatWorkspaceDate(response['created_at'])} · ${response['status'] == 'done' ? 'Completed' : 'Needs a reply'}',
            ),
            for (final entry in payload.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SelectableText(
                  '${labels[entry.key] ?? entry.key.replaceAll('_', ' ')}\n${entry.value is List ? (entry.value as List).join(', ') : entry.value}',
                ),
              ),
            for (final file in records(result['attachments']))
              AsyncButton(
                label: 'Open ${file['file_name']}',
                onPressed: () async {
                  final download = await formsAction(widget.state, {
                    'action': 'download',
                    'attachment_id': file['id'],
                  });
                  if (context.mounted) {
                    await openLink(context, '${download['url']}');
                  }
                },
              ),
            if (staff)
              Wrap(
                spacing: 10,
                children: [
                  AsyncButton(
                    label: response['status'] == 'done'
                        ? 'Reopen'
                        : 'Mark completed',
                    onPressed: () async {
                      if (custom) {
                        await widget.state.client!.rpc(
                          'set_custom_form_status',
                          params: {
                            'p_submission_id': response['id'],
                            'p_status': response['status'] == 'done'
                                ? 'new'
                                : 'done',
                          },
                        );
                      } else {
                        await widget.state.client!
                            .from('form_submissions')
                            .update({
                              'status': response['status'] == 'done'
                                  ? 'new'
                                  : 'done',
                            })
                            .eq('id', response['id'])
                            .select('id')
                            .single();
                      }
                      reload();
                    },
                  ),
                  TextButton(
                    onPressed: () => showPrivatePage(
                      context,
                      widget.state,
                      custom
                          ? CustomAssignPage(widget.state, response: response)
                          : CreateTaskPage(widget.state, form: response),
                    ),
                    child: const Text('Assign action'),
                  ),
                ],
              ),
            ActionTile(
              icon: Icons.receipt_long_outlined,
              title: 'Fees & payments',
              subtitle: 'Charges, outstanding balances and receipts',
              onTap: () => showPrivatePage(
                context,
                widget.state,
                FeeLedgerPage(
                  widget.state,
                  formId: widget.submissionId,
                  canManage: staff,
                ),
              ),
            ),
            if (custom && staff)
              FormEmailPanel(
                widget.state,
                submissionId: widget.submissionId,
                initialRecipient: '${payload['email'] ?? ''}',
                onChanged: reload,
              ),
            if (payload['email'] is String)
              TextButton(
                onPressed: () => openLink(
                  context,
                  Uri(scheme: 'mailto', path: '${payload['email']}').toString(),
                ),
                child: const Text('Draft email'),
              ),
            if (payload['phone'] is String)
              TextButton(
                onPressed: () => openLink(
                  context,
                  Uri(scheme: 'tel', path: '${payload['phone']}').toString(),
                ),
                child: const Text('Call'),
              ),
            if (custom) ...[
              const SectionTitle('Conversation'),
              for (final message in records(result['replies']))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${message['author_kind'] == 'email'
                              ? 'Email reply — sender not verified'
                              : message['internal'] == true
                              ? 'Staff note'
                              : message['author_id'] == widget.state.userId
                              ? 'You'
                              : 'Reply'} · ${formatWorkspaceDate(message['created_at'])}',
                        ),
                        SelectableText('${message['body']}'),
                      ],
                    ),
                  ),
                ),
              TextField(
                controller: reply,
                maxLength: 6000,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: internal ? 'Internal staff note' : 'Reply',
                ),
              ),
              if (staff)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Internal note'),
                  subtitle: const Text(
                    'Visible only to staff with access to this form',
                  ),
                  value: internal,
                  onChanged: (v) => setState(() => internal = v),
                ),
              AsyncButton(
                label: internal ? 'Save note' : 'Send reply',
                onPressed: () async {
                  if (reply.text.trim().isEmpty) {
                    notice(context, 'Write a reply first.');
                    return;
                  }
                  await widget.state.client!
                      .rpc(
                        'reply_custom_form',
                        params: {
                          'p_submission_id': widget.submissionId,
                          'p_body': reply.text.trim(),
                          'p_internal': staff && internal,
                        },
                      )
                      .timeout(const Duration(seconds: 20));
                  reply.clear();
                  reload();
                },
              ),
            ],
          ],
        );
      },
    ),
  );
}

class CustomAssignPage extends StatefulWidget {
  final AppState state;
  final Record response;
  const CustomAssignPage(this.state, {super.key, required this.response});
  @override
  State<CustomAssignPage> createState() => _CustomAssignPageState();
}

class _CustomAssignPageState extends State<CustomAssignPage> {
  final title = TextEditingController(text: 'Reply to enquiry');
  String? assigned;
  DateTime? due;
  late Future<List<Record>> people = load();
  Future<List<Record>> load() async => records(
    await widget.state.client!
        .rpc(
          'custom_form_assignees',
          params: {'p_form_id': widget.response['custom_form_id']},
        )
        .timeout(const Duration(seconds: 20)),
  );
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Assign action',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Action template'),
          items: [
            for (final option in [
              'Call back',
              'Chase payment',
              'Confirm payment',
              'Request an image',
              'Reply to enquiry',
            ])
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (v) => title.text = v!,
        ),
        TextField(
          controller: title,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Action'),
        ),
        FutureBuilder<List<Record>>(
          future: people,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() => people = load()),
                child: const Text('Could not load people. Retry'),
              );
            }
            return DropdownButtonFormField<String>(
              initialValue: assigned,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Responsible person',
              ),
              items: [
                for (final person in snapshot.data!)
                  DropdownMenuItem(
                    value: '${person['id']}',
                    child: Text('${person['display_name']}'),
                  ),
              ],
              onChanged: (v) => assigned = v,
            );
          },
        ),
        TextButton(
          onPressed: () async {
            final value = await pickWorkspaceDate(context, initial: due);
            if (mounted && value != null) setState(() => due = value);
          },
          child: Text(due == null ? 'Add due date' : formatWorkspaceDate(due)),
        ),
        AsyncButton(
          label: 'Assign task',
          onPressed: () async {
            if (assigned == null || title.text.trim().isEmpty) {
              notice(context, 'Choose a person and action.');
              return;
            }
            await widget.state.client!
                .rpc(
                  'assign_custom_form_task',
                  params: {
                    'p_submission_id': widget.response['id'],
                    'p_assigned_to': assigned,
                    'p_title': title.text.trim(),
                    'p_due_at': due?.toUtc().toIso8601String(),
                  },
                )
                .timeout(const Duration(seconds: 20));
            if (context.mounted) {
              notice(context, 'Task assigned.');
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    ),
  );
}

class FormDefinitionsPage extends StatefulWidget {
  final AppState state;
  const FormDefinitionsPage(this.state, {super.key});
  @override
  State<FormDefinitionsPage> createState() => _FormDefinitionsPageState();
}

class _FormDefinitionsPageState extends State<FormDefinitionsPage> {
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async {
    final all = records(
      await widget.state.client!
          .from('custom_forms')
          .select()
          .order('updated_at', ascending: false)
          .limit(100),
    );
    if (can(widget.state.profile, 'forms_manage')) return all;
    final roles = records(
      await widget.state.client!
          .from('custom_form_staff')
          .select('form_id')
          .eq('user_id', widget.state.userId!)
          .eq('role', 'manager'),
    );
    final ids = roles.map((r) => r['form_id']).toSet();
    return all.where((r) => ids.contains(r['id'])).toList();
  }

  void edit([Record? definition]) => showPrivatePage(
    context,
    widget.state,
    FormBuilderPage(
      widget.state,
      definition: definition,
      onSaved: () {
        if (mounted) setState(() => request = load());
      },
    ),
  );
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Manage forms',
    actions: [
      if (can(widget.state.profile, 'forms_manage'))
        IconButton(
          tooltip: 'Create form',
          onPressed: edit,
          icon: const Icon(Icons.add),
        ),
    ],
    child: FutureBuilder<List<Record>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => request = load()),
              child: const Text('Could not load forms. Retry'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (snapshot.data!.isEmpty)
              Text(
                can(widget.state.profile, 'forms_manage')
                    ? 'Create your first form with the + button.'
                    : 'No forms have been assigned to you to manage.',
              ),
            for (final definition in snapshot.data!)
              ActionTile(
                icon: Icons.dynamic_form_outlined,
                title: '${definition['title']}',
                subtitle: definition['enabled'] == true
                    ? definition['published_version'] == null
                          ? 'Draft'
                          : 'Published v${definition['published_version']}'
                    : 'Closed',
                onTap: () => edit(definition),
              ),
          ],
        );
      },
    ),
  );
}

class FormBuilderPage extends StatefulWidget {
  final AppState state;
  final Record? definition;
  final VoidCallback onSaved;
  const FormBuilderPage(
    this.state, {
    super.key,
    this.definition,
    required this.onSaved,
  });
  @override
  State<FormBuilderPage> createState() => _FormBuilderPageState();
}

class _FormBuilderPageState extends State<FormBuilderPage> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: '${widget.definition?['title'] ?? ''}',
  );
  late final slug = TextEditingController(
    text: '${widget.definition?['slug'] ?? ''}',
  );
  late final description = TextEditingController(
    text: '${widget.definition?['description'] ?? ''}',
  );
  late final taskTitle = TextEditingController(
    text: '${widget.definition?['task_title'] ?? 'Reply to form response'}',
  );
  late final dueHours = TextEditingController(
    text: '${widget.definition?['due_hours'] ?? 48}',
  );
  late final fields = records(widget.definition?['schema']?['fields']);
  late String? id = widget.definition?['id'];
  late bool enabled = widget.definition?['enabled'] ?? true;
  bool saving = false;
  final managers = <String>{}, responsible = <String>{}, watchers = <String>{};
  late Future<List<Record>> people = load();
  Future<List<Record>> load() async {
    if (id != null) {
      final assignments = records(
        await widget.state.client!
            .from('custom_form_staff')
            .select('user_id,role')
            .eq('form_id', id!),
      );
      managers.clear();
      responsible.clear();
      watchers.clear();
      for (final row in assignments) {
        final set = row['role'] == 'manager'
            ? managers
            : row['role'] == 'responsible'
            ? responsible
            : watchers;
        set.add('${row['user_id']}');
      }
    }
    return records(
      await widget.state.client!
          .rpc('custom_form_members', params: {'p_form_id': id})
          .timeout(const Duration(seconds: 20)),
    );
  }

  @override
  void dispose() {
    title.dispose();
    slug.dispose();
    description.dispose();
    taskTitle.dispose();
    dueHours.dispose();
    super.dispose();
  }

  Future<void> editField([int? index]) async {
    if (index == null && fields.length >= 40) {
      notice(context, 'A form can have up to 40 questions.');
      return;
    }
    final result = await Navigator.of(context).push<Record>(
      MaterialPageRoute(
        builder: (_) => AccountGate(
          widget.state,
          child: FieldEditorPage(
            field: index == null ? null : fields[index],
            previousFields: fields.take(index ?? fields.length).toList(),
            existingIds: fields
                .asMap()
                .entries
                .where((e) => e.key != index)
                .map((e) => '${e.value['id']}')
                .toSet(),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          fields.add(result);
        } else {
          fields[index] = result;
        }
      });
    }
  }

  Future<void> save(bool publish) async {
    if (saving || !form.currentState!.validate()) return;
    if (fields.isEmpty) {
      notice(context, 'Add at least one question.');
      return;
    }
    if (fields.where((f) => ['image', 'file'].contains(f['type'])).length > 5) {
      notice(context, 'Use no more than five upload questions.');
      return;
    }
    if (publish && responsible.isEmpty) {
      notice(
        context,
        'Choose at least one responsible person before publishing.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      final saved = await widget.state.client!
          .rpc(
            'save_custom_form',
            params: {
              'p_form': {
                if (id != null) 'id': id,
                'slug': slug.text.trim(),
                'title': title.text.trim(),
                'description': description.text.trim(),
                'schema': {'fields': fields},
                'enabled': enabled,
                'task_title': taskTitle.text.trim(),
                'due_hours': int.parse(dueHours.text),
                'manager_ids': managers.toList(),
                'responsible_ids': responsible.toList(),
                'watcher_ids': watchers.toList(),
              },
            },
          )
          .timeout(const Duration(seconds: 25));
      id = '$saved';
      widget.onSaved();
      if (publish) {
        await widget.state.client!
            .rpc('publish_custom_form', params: {'p_form_id': id})
            .timeout(const Duration(seconds: 25));
        widget.onSaved();
      }
      if (mounted) {
        notice(
          context,
          publish
              ? 'Form published.'
              : 'Draft saved. Publish when you are ready to update the public form.',
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget rolePicker(String label, Set<String> selected, List<Record> rows) =>
      ExpansionTile(
        title: Text('$label (${selected.length})'),
        children: [
          for (final person in rows)
            CheckboxListTile(
              title: Text('${person['display_name']}'),
              value: selected.contains('${person['id']}'),
              onChanged: (v) => setState(() {
                if (v == true) {
                  selected.add('${person['id']}');
                } else {
                  selected.remove('${person['id']}');
                }
              }),
            ),
        ],
      );
  @override
  Widget build(BuildContext context) => ContentPage(
    title: id == null ? 'Create form' : 'Edit form',
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
                decoration: const InputDecoration(labelText: 'Form title'),
                validator: (v) =>
                    v?.trim().isEmpty ?? true ? 'Add a title.' : null,
              ),
              TextFormField(
                controller: slug,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Form link name',
                  hintText: 'volunteer-registration',
                ),
                validator: (v) =>
                    RegExp(
                      r'^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$',
                    ).hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Use 3–80 lowercase letters, numbers or hyphens.',
              ),
              TextFormField(
                controller: description,
                maxLength: 2000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Introduction'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept responses when published'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
              const SectionTitle('Questions'),
              for (final entry in fields.asMap().entries)
                Card(
                  child: ListTile(
                    title: Text('${entry.key + 1}. ${entry.value['label']}'),
                    subtitle: Text(
                      '${entry.value['type']}${entry.value['required'] == true ? ' · Required' : ''}${entry.value['show_when'] != null ? ' · Conditional' : ''}',
                    ),
                    onTap: () => editField(entry.key),
                    trailing: IconButton(
                      tooltip: 'Remove question',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        final dependent = fields.any(
                          (f) => f['show_when']?['field'] == entry.value['id'],
                        );
                        if (dependent) {
                          notice(
                            context,
                            'Remove conditions that use this question first.',
                          );
                          return;
                        }
                        setState(() => fields.removeAt(entry.key));
                      },
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: editField,
                icon: const Icon(Icons.add),
                label: const Text('Add question'),
              ),
              const SectionTitle(
                'People & actions',
                subtitle:
                    'Responsible people get a task for every response. Watchers get an update.',
              ),
              TextFormField(
                controller: taskTitle,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Automatic task title',
                ),
                validator: (v) =>
                    v?.trim().isEmpty ?? true ? 'Add an action title.' : null,
              ),
              TextFormField(
                controller: dueHours,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Task due after (hours)',
                ),
                validator: (v) {
                  final hours = int.tryParse(v ?? '');
                  return hours != null && hours >= 1 && hours <= 8760
                      ? null
                      : 'Enter 1–8760 hours.';
                },
              ),
              FutureBuilder<List<Record>>(
                future: people,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return TextButton(
                      onPressed: () => setState(() => people = load()),
                      child: const Text('Could not load routing. Retry'),
                    );
                  }
                  final rows = snapshot.data!;
                  return Column(
                    children: [
                      rolePicker('Form managers', managers, rows),
                      rolePicker('Responsible people', responsible, rows),
                      rolePicker('Notify only', watchers, rows),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        children: [
                          AsyncButton(
                            label: saving ? 'Saving…' : 'Save draft',
                            onPressed: () => save(false),
                          ),
                          AsyncButton(
                            label: saving ? 'Saving…' : 'Save & publish',
                            onPressed: () => save(true),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class FieldEditorPage extends StatefulWidget {
  final Record? field;
  final List<Record> previousFields;
  final Set<String> existingIds;
  const FieldEditorPage({
    super.key,
    this.field,
    required this.previousFields,
    required this.existingIds,
  });
  @override
  State<FieldEditorPage> createState() => _FieldEditorPageState();
}

class _FieldEditorPageState extends State<FieldEditorPage> {
  final form = GlobalKey<FormState>();
  late final label = TextEditingController(
    text: '${widget.field?['label'] ?? ''}',
  );
  late final id = TextEditingController(
    text:
        '${widget.field?['id'] ?? 'question_${widget.existingIds.length + 1}'}',
  );
  late final options = TextEditingController(
    text: List<String>.from(widget.field?['options'] ?? []).join('\n'),
  );
  late final conditionValue = TextEditingController(
    text: '${widget.field?['show_when']?['value'] ?? ''}',
  );
  late String type = widget.field?['type'] ?? 'text',
      operator = widget.field?['show_when']?['operator'] ?? 'equals';
  late bool requiredAnswer = widget.field?['required'] == true;
  late String? condition = widget.field?['show_when']?['field'];
  @override
  void dispose() {
    label.dispose();
    id.dispose();
    options.dispose();
    conditionValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.previousFields
        .where(
          (f) =>
              !['file', 'image', 'multiselect'].contains(f['type']) &&
              f['show_when'] == null,
        )
        .toList();
    final source = choices.where((f) => f['id'] == condition).firstOrNull;
    return ContentPage(
      title: 'Question',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: label,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Question label',
                  ),
                  validator: (v) =>
                      v?.trim().isEmpty ?? true ? 'Add a label.' : null,
                ),
                TextFormField(
                  controller: id,
                  readOnly: widget.field != null,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Answer key'),
                  validator: (v) =>
                      RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(v ?? '') &&
                          !widget.existingIds.contains(v)
                      ? null
                      : 'Use a unique key with lowercase letters, numbers and underscores.',
                ),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Answer type'),
                  items: [
                    for (final value in customFieldTypes)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Required answer'),
                  value: requiredAnswer,
                  onChanged: (v) => setState(() => requiredAnswer = v),
                ),
                if (['select', 'multiselect'].contains(type))
                  TextFormField(
                    controller: options,
                    minLines: 3,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Choices (one per line)',
                    ),
                    validator: (v) {
                      final values = (v ?? '')
                          .split('\n')
                          .map((v) => v.trim())
                          .where((v) => v.isNotEmpty)
                          .toList();
                      return values.isNotEmpty &&
                              values.length <= 50 &&
                              values.toSet().length == values.length &&
                              values.every((v) => v.length <= 120)
                          ? null
                          : 'Add 1–50 unique choices, up to 120 characters each.';
                    },
                  ),
                const SectionTitle('Show this question'),
                DropdownButtonFormField<String>(
                  initialValue: condition ?? '',
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Always')),
                    for (final field in choices)
                      DropdownMenuItem(
                        value: '${field['id']}',
                        child: Text('When ${field['label']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    condition = v == '' ? null : v;
                    conditionValue.clear();
                  }),
                ),
                if (condition != null) ...[
                  DropdownButtonFormField<String>(
                    initialValue: operator,
                    items: const [
                      DropdownMenuItem(value: 'equals', child: Text('Equals')),
                      DropdownMenuItem(
                        value: 'not_equals',
                        child: Text('Does not equal'),
                      ),
                    ],
                    onChanged: (v) => operator = v!,
                  ),
                  if (source?['type'] == 'checkbox')
                    DropdownButtonFormField<String>(
                      initialValue:
                          ['true', 'false'].contains(conditionValue.text)
                          ? conditionValue.text
                          : null,
                      decoration: const InputDecoration(labelText: 'Answer is'),
                      items: const [
                        DropdownMenuItem(value: 'true', child: Text('Checked')),
                        DropdownMenuItem(
                          value: 'false',
                          child: Text('Not checked'),
                        ),
                      ],
                      onChanged: (v) => conditionValue.text = v!,
                      validator: (v) => v == null ? 'Choose an answer.' : null,
                    )
                  else
                    TextFormField(
                      controller: conditionValue,
                      decoration: const InputDecoration(
                        labelText: 'Answer value',
                      ),
                      keyboardType: source?['type'] == 'number'
                          ? TextInputType.number
                          : TextInputType.text,
                      validator: (v) =>
                          (v?.isEmpty ?? true) ||
                              (source?['type'] == 'number' &&
                                  num.tryParse(v ?? '') == null)
                          ? 'Add a valid condition value.'
                          : null,
                    ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    if (!form.currentState!.validate()) return;
                    Navigator.of(context).pop(<String, dynamic>{
                      'id': id.text.trim(),
                      'type': type,
                      'label': label.text.trim(),
                      'required': requiredAnswer,
                      if (['select', 'multiselect'].contains(type))
                        'options': options.text
                            .split('\n')
                            .map((v) => v.trim())
                            .where((v) => v.isNotEmpty)
                            .toList(),
                      if (condition != null)
                        'show_when': {
                          'field': condition,
                          'operator': operator,
                          'value': source?['type'] == 'checkbox'
                              ? conditionValue.text == 'true'
                              : source?['type'] == 'number'
                              ? num.parse(conditionValue.text)
                              : conditionValue.text,
                        },
                    });
                  },
                  child: const Text('Save question'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
