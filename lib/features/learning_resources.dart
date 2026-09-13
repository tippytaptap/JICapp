import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'workspace.dart';

const courseFileTypes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'mp4': 'video/mp4',
};

class CourseResourcesPage extends StatelessWidget {
  final AppState state;
  final String courseId;
  final bool teacher;
  const CourseResourcesPage(
    this.state,
    this.courseId,
    this.teacher, {
    super.key,
  });
  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Course resources',
    child: PaginatedRecords(
      loader: (page) async => records(
        await state.client!
            .from('learning_resources')
            .select()
            .eq('course_id', courseId)
            .order('created_at', ascending: false)
            .order('id')
            .range(page * 25, page * 25 + 24)
            .timeout(const Duration(seconds: 20)),
      ),
      emptyText: 'No resources have been published for this course yet.',
      header: teacher
          ? FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add a resource'),
              onPressed: () => showPrivatePage(
                context,
                state,
                _ResourceEditor(state, courseId),
              ),
            )
          : null,
      itemBuilder: (row) =>
          _ResourceCard(state, row, teacher, key: ValueKey(row['id'])),
    ),
  );
}

class _ResourceCard extends StatefulWidget {
  final AppState state;
  final Record resource;
  final bool teacher;
  const _ResourceCard(this.state, this.resource, this.teacher, {super.key});
  @override
  State<_ResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends State<_ResourceCard> {
  late bool published = widget.resource['published'] == true;
  bool deleted = false;
  @override
  void didUpdateWidget(covariant _ResourceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource != widget.resource) {
      published = widget.resource['published'] == true;
      deleted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resource;
    if (deleted) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${r['title']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if ('${r['description'] ?? ''}'.isNotEmpty)
              Text('${r['description']}'),
            Text(published ? 'Published to course' : 'Staff draft'),
            AsyncButton(
              label: r['object_path'] == null
                  ? 'Open link'
                  : 'Open ${r['file_name'] ?? 'file'}',
              onPressed: () async {
                final account = widget.state.userId;
                // Refresh authorization before opening a previously displayed resource.
                final fresh = await widget.state.client!
                    .from('learning_resources')
                    .select('url,object_path')
                    .eq('id', r['id'])
                    .single()
                    .timeout(const Duration(seconds: 20));
                if (!mounted || account != widget.state.userId) return;
                final url =
                    fresh['url'] as String? ??
                    await widget.state.client!.storage
                        .from('course-resources')
                        .createSignedUrl(
                          fresh['object_path'],
                          60,
                          download: r['file_name'],
                        );
                if (context.mounted && account == widget.state.userId) {
                  await openLink(context, url);
                }
              },
            ),
            if (widget.teacher)
              Wrap(
                spacing: 8,
                children: [
                  AsyncButton(
                    label: published ? 'Unpublish' : 'Publish',
                    onPressed: () async {
                      await widget.state.client!
                          .from('learning_resources')
                          .update({'published': !published})
                          .eq('id', r['id'])
                          .select('id')
                          .single()
                          .timeout(const Duration(seconds: 20));
                      if (mounted) setState(() => published = !published);
                    },
                  ),
                  TextButton(
                    onPressed: () async {
                      final account = widget.state.userId;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Remove this resource?'),
                          content: const Text(
                            'It will disappear from the course.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Keep'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true ||
                          !mounted ||
                          account != widget.state.userId) {
                        return;
                      }
                      try {
                        await widget.state.client!
                            .from('learning_resources')
                            .delete()
                            .eq('id', r['id'])
                            .select('id')
                            .single();
                        if (r['object_path'] != null &&
                            account == widget.state.userId) {
                          try {
                            await widget.state.client!.storage
                                .from('course-resources')
                                .remove([r['object_path']]);
                          } catch (_) {
                            /* Owner maintenance removes retained private objects. */
                          }
                        }
                        if (mounted) setState(() => deleted = true);
                      } catch (_) {
                        if (context.mounted) {
                          notice(context, 'Could not remove the resource.');
                        }
                      }
                    },
                    child: const Text('Remove'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ResourceEditor extends StatefulWidget {
  final AppState state;
  final String courseId;
  const _ResourceEditor(this.state, this.courseId);
  @override
  State<_ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends State<_ResourceEditor> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      url = TextEditingController();
  PlatformFile? file;
  bool busy = false, published = false;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    url.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (file == null && !safeWebUrl(url.text.trim())) {
      notice(context, 'Choose a file or enter a valid HTTPS link.');
      return;
    }
    setState(() => busy = true);
    String? path;
    final user = widget.state.userId;
    try {
      if (user == null) throw StateError('Sign in again');
      final Record values = {
        'course_id': widget.courseId,
        'title': title.text.trim(),
        'description': description.text.trim(),
        'published': published,
      };
      if (file != null) {
        final selected = file!;
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in selected.readAsByteStream()) {
          if (buffer.length + chunk.length > 25 * 1024 * 1024) {
            throw StateError('File too large');
          }
          buffer.add(chunk);
        }
        if (!mounted || user != widget.state.userId) {
          throw StateError('Account changed');
        }
        final bytes = buffer.takeBytes();
        final mime =
            courseFileTypes[selected.name.split('.').last.toLowerCase()];
        if (bytes.isEmpty || mime == null) throw StateError('Unsupported file');
        final random = Random.secure();
        final id = base64UrlEncode(
          List.generate(24, (_) => random.nextInt(256)),
        ).replaceAll('=', '');
        path = '${widget.courseId}/$user/$id';
        await widget.state.client!.storage
            .from('course-resources')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: mime, upsert: false),
            )
            .timeout(const Duration(minutes: 2));
        values.addAll({
          'object_path': path,
          'file_name': selected.name
              .replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_')
              .substring(0, min(selected.name.length, 200)),
          'mime_type': mime,
        });
      } else {
        values['url'] = url.text.trim();
      }
      if (!mounted || user != widget.state.userId) {
        throw StateError('Account changed');
      }
      await widget.state.client!
          .from('learning_resources')
          .insert(values)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 20));
      path = null;
      if (mounted) {
        notice(context, 'Resource saved. Refresh the course list to see it.');
        Navigator.pop(context);
      }
    } catch (_) {
      if (path != null && user == widget.state.userId) {
        try {
          await widget.state.client!.storage.from('course-resources').remove([
            path,
          ]);
        } catch (_) {}
      }
      if (mounted) {
        notice(
          context,
          'The resource could not be saved. Check the file and your access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Add course resource',
    child: AbsorbPointer(
      absorbing: busy,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a title' : null,
            ),
            TextFormField(
              controller: description,
              minLines: 3,
              maxLines: 6,
              maxLength: 6000,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextFormField(
              controller: url,
              enabled: file == null,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'HTTPS resource link',
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: Text(
                file?.name ?? 'Choose PDF, image, audio or video (25 MB)',
              ),
              onPressed: () async {
                final selected = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: courseFileTypes.keys.toList(),
                );
                if (selected == null || !mounted || !context.mounted) return;
                final size = selected.lengthSync();
                if (size != null && (size > 25 * 1024 * 1024 || size == 0)) {
                  notice(context, 'Choose a file smaller than 25 MB.');
                  return;
                }
                setState(() => file = selected);
              },
            ),
            if (file != null)
              TextButton(
                onPressed: () => setState(() => file = null),
                child: const Text('Use a link instead'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Publish to the course'),
              value: published,
              onChanged: (v) => setState(() => published = v),
            ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Uploading and saving…' : 'Save resource'),
            ),
          ],
        ),
      ),
    ),
  );
}
