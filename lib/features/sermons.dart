import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/radio_controller.dart';
import '../widgets/common.dart';

const sermonFields =
    'id,title,speaker,summary,transcript,quotes,audio_path,published_at';
String talkTimestamp(dynamic value) {
  final seconds = value is num ? value.toInt() : 0;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class SermonArchivePage extends StatefulWidget {
  final AppState state;
  final RadioController radio;
  const SermonArchivePage(this.state, this.radio, {super.key});
  @override
  State<SermonArchivePage> createState() => _SermonArchivePageState();
}

class _SermonArchivePageState extends State<SermonArchivePage> {
  final search = TextEditingController();
  int page = 0;
  String query = '';
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async {
    final client = widget.state.client;
    if (client == null) return [];
    var result = client
        .from('sermon_publications')
        .select('id,title,speaker,summary,published_at');
    if (query.isNotEmpty) {
      final escaped = query.replaceAllMapped(
        RegExp(r'[%_\\]'),
        (m) => '\\${m[0]}',
      );
      result = result.ilike('title', '%$escaped%');
    }
    return records(
      await result
          .order('published_at', ascending: false)
          .range(page * 10, page * 10 + 9)
          .timeout(const Duration(seconds: 20)),
    );
  }

  void reload() => setState(() => request = load());
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Talks & reflections',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            maxLength: 80,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search talk titles',
              counterText: '',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  query = search.text.trim();
                  page = 0;
                  reload();
                },
              ),
            ),
            onSubmitted: (value) {
              query = value.trim();
              page = 0;
              reload();
            },
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
                    child: const Text('Could not load talks. Retry'),
                  ),
                );
              }
              final rows = snapshot.data ?? [];
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No published talks yet.'),
                    ),
                  for (final talk in rows)
                    ActionTile(
                      icon: Icons.headphones_outlined,
                      title: '${talk['title']}',
                      subtitle: '${talk['speaker']}',
                      onTap: () async {
                        try {
                          final detail = await widget.state.client!
                              .from('sermon_publications')
                              .select(sermonFields)
                              .eq('id', talk['id'])
                              .single()
                              .timeout(const Duration(seconds: 20));
                          if (context.mounted) {
                            showPage(
                              context,
                              SermonPage(widget.state, widget.radio, detail),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            notice(
                              context,
                              'This talk is unavailable. Please refresh.',
                            );
                          }
                        }
                      },
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: page > 0
                            ? () {
                                page--;
                                reload();
                              }
                            : null,
                        child: const Text('Previous'),
                      ),
                      Text('Page ${page + 1}'),
                      TextButton(
                        onPressed: rows.length == 10
                            ? () {
                                page++;
                                reload();
                              }
                            : null,
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

class SermonPage extends StatefulWidget {
  final AppState state;
  final RadioController radio;
  final Record talk;
  const SermonPage(this.state, this.radio, this.talk, {super.key});
  @override
  State<SermonPage> createState() => _SermonPageState();
}

class _SermonPageState extends State<SermonPage> {
  bool loading = false;
  String? audioUrl;
  Future<void> play({int? seconds}) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final url = await widget.state.client!.storage
          .from('sermon-recordings')
          .createSignedUrl('${widget.talk['audio_path']}', 3600)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      audioUrl = url;
      await widget.radio.playRecording(url, '${widget.talk['title']}');
      if (seconds != null) {
        await widget.radio.player.seek(Duration(seconds: seconds));
      }
    } catch (_) {
      if (mounted) {
        notice(context, 'The recording could not play. Please try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final talk = widget.talk, segments = records(widget.talk['transcript']);
    return ContentPage(
      title: '${talk['title']}',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${talk['speaker']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: widget.radio,
            builder: (context, _) {
              final mine =
                  audioUrl != null && widget.radio.sourceUrl == audioUrl;
              return Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: loading ? null : () => play(),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(loading ? 'Opening…' : 'Listen to talk'),
                  ),
                  if (mine && widget.radio.playing)
                    OutlinedButton.icon(
                      onPressed: widget.radio.stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                ],
              );
            },
          ),
          const SectionTitle('Summary'),
          SelectableText('${talk['summary']}'),
          const SectionTitle('Transcript'),
          ExpansionTile(
            title: Text('${segments.length} passages'),
            children: [
              for (final segment in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton(
                        onPressed: loading
                            ? null
                            : () => play(
                                seconds: (segment['start'] as num).toInt(),
                              ),
                        child: Text(
                          'Listen from ${talkTimestamp(segment['start'])}',
                        ),
                      ),
                      SelectableText('${segment['text']}'),
                    ],
                  ),
                ),
            ],
          ),
          if (records(talk['quotes']).isNotEmpty)
            const SectionTitle('Reviewed quotes'),
          for (final quote in records(talk['quotes']))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '“${quote['text']}”',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text('${quote['reference'] ?? talk['speaker']}'),
                    if (safeWebUrl('${quote['source_url']}'))
                      TextButton(
                        onPressed: () =>
                            openLink(context, '${quote['source_url']}'),
                        child: const Text('Verified reference source'),
                      ),
                    AsyncButton(
                      label: 'Share quote image',
                      onPressed: () => shareTalkQuote(context, quote, talk),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> shareTalkQuote(
  BuildContext context,
  Record quote,
  Record talk,
) async {
  final text = '${quote['text']}';
  if (text.isEmpty || text.length > 400) throw StateError('Invalid quote');
  final painter = TextPainter(
    text: TextSpan(
      text: '“$text”',
      style: const TextStyle(
        fontSize: 46,
        color: Color(0xfffffaf0),
        height: 1.5,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 900);
  final height = (painter.height + 500).clamp(1080, 2400).toInt();
  final recorder = ui.PictureRecorder();
  // Keep the recorder and drawing canvas paired so no widget screenshots or private UI are shared.
  final drawing = Canvas(recorder);
  drawing.drawRect(
    Rect.fromLTWH(0, 0, 1080, height.toDouble()),
    Paint()..color = const Color(0xff101c2c),
  );
  drawing.drawLine(
    const Offset(80, 80),
    const Offset(1000, 80),
    Paint()
      ..color = const Color(0xffd39f27)
      ..strokeWidth = 3,
  );
  painter.paint(drawing, const Offset(90, 250));
  void label(String text, double y, double size) {
    final labelPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: const Color(0xffd39f27)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 900);
    labelPainter.paint(drawing, Offset(90, y));
    labelPainter.dispose();
  }

  label('${talk['title']}', 130, 30);
  label('${talk['speaker']}', height - 200, 30);
  label(
    '${quote['reference'] ?? 'Reviewed transcript excerpt'}',
    height - 140,
    24,
  );
  final picture = recorder.endRecording(),
      image = await recorderImage(picture, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  painter.dispose();
  if (data == null || !context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          data.buffer.asUint8List(),
          mimeType: 'image/png',
          name: 'talk-quote.png',
        ),
      ],
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

Future<ui.Image> recorderImage(ui.Picture picture, int height) =>
    picture.toImage(1080, height);
