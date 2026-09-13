import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/reading_store.dart';
import '../widgets/common.dart';
import 'tasbih.dart';
import 'sermons.dart';

class ReadingView extends StatelessWidget {
  final AppState state;
  const ReadingView(this.state, {super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
    children: [
      const SectionTitle(
        'A moment to reconnect',
        subtitle: 'Read, reflect and remember',
      ),
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showPage(context, QuranPage(state)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.menu_book, size: 40),
                const SizedBox(height: 24),
                Text(
                  'The Noble Qur’an',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Arabic with English meaning. Continue at your own pace.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Continue · Surah ${state.preferences.getInt('quran.surah') ?? 1}',
                ),
              ],
            ),
          ),
        ),
      ),
      const SectionTitle('Your reading library'),
      for (final entry in const {
        'dalail': ['Dala’il al-Khayrat', 'Daily salawat and reading'],
        'dhikr': ['Dhikr & du‘as', 'Morning, evening and everyday remembrance'],
        'hadith': ['Hadith', 'Collections with references'],
        'hizb': ['Awrad & Hizb', 'Regular litanies from your centre'],
        'guides': ['Prayer & learning guides', 'Resources from your centre'],
      }.entries)
        ActionTile(
          icon: Icons.auto_stories_outlined,
          title: entry.value[0],
          subtitle: entry.value[1],
          onTap: () =>
              showPage(context, LibraryPage(state, entry.key, entry.value[0])),
        ),
      ActionTile(
        icon: Icons.mic_none,
        title: 'Talks & reflections',
        subtitle: 'Published talks, transcripts and reviewed summaries',
        onTap: () => showPage(context, SermonArchivePage(state, state.radio)),
      ),
      const SectionTitle('Build a personal routine'),
      ActionTile(
        icon: Icons.touch_app_outlined,
        title: 'Tasbih',
        subtitle: 'Your counter, always within reach',
        onTap: () => showPage(context, TasbihPage(state.preferences)),
      ),
      ActionTile(
        icon: Icons.checklist,
        title: 'My Salah plan',
        subtitle: 'A private record on this device',
        onTap: () => showPage(context, const SalahPlanPage()),
      ),
    ],
  );
}

class LibraryPage extends StatefulWidget {
  final AppState state;
  final String collection, title;
  const LibraryPage(this.state, this.collection, this.title, {super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final store = ReadingStore(widget.state.preferences);
  List<Record> entries = [];
  bool loading = true, offline = false;
  String search = '';
  late double font = widget.state.preferences.getDouble('library.font') ?? 28;
  String get organisation => widget.state.organisation.website;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    List<Record> next = [];
    var cached = false;
    try {
      next = await store.savedLibrary(organisation);
      cached = next.isNotEmpty;
    } catch (_) {
      /* A storage failure must not hide an available live reading. */
    }
    try {
      if (widget.state.client == null) throw StateError('Offline');
      final row = await widget.state.client!
          .from('page_content')
          .select('content_value')
          .eq('content_key', 'reading_library')
          .maybeSingle()
          .timeout(const Duration(seconds: 20));
      dynamic value = row?['content_value'] ?? [];
      if (value is String) value = jsonDecode(value);
      next = ReadingStore.validateLibrary(value);
      cached = false;
      // A successful empty response also removes readings unpublished by staff.
      try {
        await store.saveLibrary(organisation, next);
      } catch (_) {}
    } catch (_) {
      if (next.isEmpty && widget.state.library.isNotEmpty) {
        next = ReadingStore.validateLibrary(widget.state.library);
        cached = true;
      }
    }
    if (mounted) {
      setState(() {
        entries = next
            .where((r) => r['collection'] == widget.collection)
            .toList();
        offline = cached;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = entries
        .where(
          (r) => readingSearch(
            '${r['title']} ${r['arabic'] ?? ''} ${r['text'] ?? r['body'] ?? ''} '
            '${r['reference'] ?? ''}',
          ).contains(readingSearch(search)),
        )
        .toList();
    return ContentPage(
      title: widget.title,
      actions: [
        IconButton(
          tooltip: 'Refresh readings',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search this collection',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
          ),
          if (offline)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Saved on this device. Connect to check for newer readings.',
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Smaller Arabic text',
                onPressed: font <= 20
                    ? null
                    : () {
                        setState(() => font -= 2);
                        widget.state.preferences.setDouble(
                          'library.font',
                          font,
                        );
                      },
                icon: const Icon(Icons.text_decrease),
              ),
              const Text('Reading size'),
              IconButton(
                tooltip: 'Larger Arabic text',
                onPressed: font >= 48
                    ? null
                    : () {
                        setState(() => font += 2);
                        widget.state.preferences.setDouble(
                          'library.font',
                          font,
                        );
                      },
                icon: const Icon(Icons.text_increase),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: visible.isEmpty ? 1 : visible.length,
              itemBuilder: (context, index) {
                if (visible.isEmpty) {
                  return Text(
                    loading
                        ? 'Opening your library…'
                        : entries.isEmpty
                        ? 'Your centre has not published readings in this collection yet. '
                              'Published readings are available here with their references and save for offline reading.'
                        : 'No readings match your search.',
                  );
                }
                final entry = visible[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          entry['title'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if ('${entry['arabic'] ?? ''}'.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: SelectableText(
                              entry['arabic'],
                              textDirection: TextDirection.rtl,
                              style: TextStyle(fontSize: font, height: 1.9),
                            ),
                          ),
                        if ('${entry['text'] ?? entry['body'] ?? ''}'
                            .isNotEmpty)
                          SelectableText(
                            '${entry['text'] ?? entry['body']}',
                            style: const TextStyle(height: 1.7),
                          ),
                        if ('${entry['reference'] ?? ''}'.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text('Reference: ${entry['reference']}'),
                          ),
                        if (safeWebUrl('${entry['source'] ?? entry['url']}'))
                          TextButton(
                            onPressed: () => openLink(
                              context,
                              '${entry['source'] ?? entry['url']}',
                            ),
                            child: const Text('Open source'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QuranPage extends StatefulWidget {
  final AppState state;
  final String? initialReference;
  const QuranPage(this.state, {this.initialReference, super.key});
  @override
  State<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<QuranPage> {
  late final store = ReadingStore(widget.state.preferences);
  late final initial =
      widget.initialReference != null &&
          ReadingStore.validReference(widget.initialReference!)
      ? widget.initialReference!
      : store.position;
  late int surah = int.parse(initial.split(':').first);
  late int firstAyah = int.parse(initial.split(':').last);
  late double font = (widget.state.preferences.getDouble('quran.font') ?? 28)
      .clamp(20, 48);
  late bool english = widget.state.preferences.getBool('quran.english') ?? true;
  late Future<QuranReading> request = store.read(surah);
  final scroll = ScrollController();
  final searchController = TextEditingController();
  String query = '';
  bool saving = false;
  Set<int> downloaded = {};
  static const pageSize = 10;
  @override
  void initState() {
    super.initState();
    refreshDownloads();
  }

  @override
  void dispose() {
    store.dispose();
    scroll.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> refreshDownloads() async {
    try {
      final values = await store.downloaded();
      if (mounted) setState(() => downloaded = values);
    } catch (_) {}
  }

  void change(int number, [int ayah = 1]) {
    setState(() {
      surah = number;
      firstAyah = ayah;
      query = '';
      searchController.clear();
      request = store.read(number);
    });
    unawaited(store.setPosition(number, ayah));
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void movePage(int ayah) {
    setState(() => firstAyah = ayah);
    unawaited(store.setPosition(surah, ayah));
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> selectSurah() async {
    final number = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SurahPicker(selected: surah, downloaded: downloaded),
    );
    if (number != null && mounted) change(number);
  }

  Future<void> bookmarks() async {
    final references = store.bookmarks.toList()
      ..sort((a, b) {
        final aa = a.split(':').map(int.parse).toList(),
            bb = b.split(':').map(int.parse).toList();
        return aa[0] == bb[0] ? aa[1].compareTo(bb[1]) : aa[0].compareTo(bb[0]);
      });
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SectionTitle('Your saved ayahs'),
            if (references.isEmpty)
              const Text('Use the bookmark beside any ayah to save it here.'),
            Expanded(
              child: ListView(
                children: [
                  for (final ref in references)
                    ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(
                        '${surahNames[int.parse(ref.split(':').first) - 1]} · $ref',
                      ),
                      onTap: () => Navigator.pop(c, ref),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      final parts = selected.split(':').map(int.parse).toList();
      change(parts[0], parts[1]);
    }
  }

  Future<void> save(QuranReading reading) async {
    setState(() => saving = true);
    try {
      await store.save(reading);
      await refreshDownloads();
      if (mounted) notice(context, 'Surah saved for offline reading.');
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not save. Check device storage and try again.');
      }
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> jumpToAyah() async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Go to ayah'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '1–${surahLengths[surah - 1]}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n > 0 && n <= surahLengths[surah - 1]) {
                Navigator.pop(c, n);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    // Dialog closing animation may still use its controller; defer disposal.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (value != null && mounted) {
      setState(() {
        query = '';
        searchController.clear();
      });
      movePage(value);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'The Noble Qur’an',
    actions: [
      IconButton(
        tooltip: 'Saved ayahs',
        onPressed: bookmarks,
        icon: const Icon(Icons.bookmarks_outlined),
      ),
      IconButton(
        tooltip: 'Offline downloads',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => QuranDownloadsPage(widget.state),
            ),
          );
          await refreshDownloads();
        },
        icon: const Icon(Icons.download_for_offline_outlined),
      ),
    ],
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: selectSurah,
                  icon: const Icon(Icons.unfold_more),
                  label: Text(
                    '$surah. ${surahNames[surah - 1]}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Smaller text',
                onPressed: font <= 20
                    ? null
                    : () {
                        setState(() => font -= 2);
                        widget.state.preferences.setDouble('quran.font', font);
                      },
                icon: const Icon(Icons.text_decrease),
              ),
              IconButton(
                tooltip: 'Larger text',
                onPressed: font >= 48
                    ? null
                    : () {
                        setState(() => font += 2);
                        widget.state.preferences.setDouble('quran.font', font);
                      },
                icon: const Icon(Icons.text_increase),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Search this surah',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('English meaning · Sahih International'),
          value: english,
          onChanged: (value) {
            setState(() => english = value);
            widget.state.preferences.setBool('quran.english', value);
          },
        ),
        Expanded(
          child: FutureBuilder<QuranReading>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This surah is not available on this device. Connect to read it or download it for later.',
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => request = store.read(surah)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!snapshot.hasData ||
                  snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final reading = snapshot.data!;
              final selected = query.trim().isEmpty
                  ? reading.ayahs.skip(firstAyah - 1).take(pageSize).toList()
                  : reading.ayahs.where((a) => a.matches(query)).toList();
              final marks = store.bookmarks;
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    reading.arabicName,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: saving || downloaded.contains(surah)
                            ? null
                            : () => save(reading),
                        icon: Icon(
                          downloaded.contains(surah)
                              ? Icons.offline_pin
                              : Icons.download,
                        ),
                        label: Text(
                          downloaded.contains(surah)
                              ? 'Saved offline'
                              : saving
                              ? 'Saving…'
                              : 'Save offline',
                        ),
                      ),
                      TextButton(
                        onPressed: jumpToAyah,
                        child: const Text('Go to ayah'),
                      ),
                    ],
                  ),
                  if (selected.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No ayahs match your search.'),
                    ),
                  for (final ayah in selected) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ayah.reference,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: marks.contains(ayah.reference)
                              ? 'Remove bookmark ${ayah.reference}'
                              : 'Bookmark ${ayah.reference}',
                          onPressed: () async {
                            try {
                              await store.toggleBookmark(ayah.reference);
                              if (mounted) setState(() {});
                            } catch (_) {
                              if (context.mounted) {
                                notice(
                                  context,
                                  'Could not save this bookmark.',
                                );
                              }
                            }
                          },
                          icon: Icon(
                            marks.contains(ayah.reference)
                                ? Icons.bookmark
                                : Icons.bookmark_outline,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Continue from ${ayah.reference} next time',
                          icon: const Icon(Icons.flag_outlined),
                          onPressed: () async {
                            await store.setPosition(surah, ayah.number);
                            if (context.mounted) {
                              notice(
                                context,
                                'Reading position saved at ${ayah.reference}.',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    SelectableText(
                      ayah.arabic,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: font, height: 2),
                    ),
                    if (english)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: SelectableText(
                          ayah.meaning,
                          style: const TextStyle(fontSize: 17, height: 1.7),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(),
                    ),
                  ],
                  if (query.trim().isEmpty)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: firstAyah > 1
                              ? () => movePage(
                                  (firstAyah - pageSize).clamp(
                                    1,
                                    reading.ayahs.length,
                                  ),
                                )
                              : surah > 1
                              ? () => change(surah - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          label: Text(
                            firstAyah > 1 ? 'Previous ayahs' : 'Previous surah',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed:
                              firstAyah + pageSize <= reading.ayahs.length
                              ? () => movePage(firstAyah + pageSize)
                              : surah < 114
                              ? () => change(surah + 1)
                              : null,
                          label: Text(
                            firstAyah + pageSize <= reading.ayahs.length
                                ? 'Next ayahs'
                                : 'Next surah',
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'Arabic: Uthmani edition. English meaning: Sahih International. '
                    'Provided by Al Quran Cloud. Arabic source: Tanzil Project. '
                    'Text is displayed as supplied by these editions.',
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => openLink(
                          context,
                          'https://alquran.cloud/terms-and-conditions',
                        ),
                        child: const Text('Sources & terms'),
                      ),
                      TextButton(
                        onPressed: () => openLink(
                          context,
                          'https://tanzil.net/docs/Text_License',
                        ),
                        child: const Text('Tanzil text licence'),
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

class _SurahPicker extends StatefulWidget {
  final int selected;
  final Set<int> downloaded;
  const _SurahPicker({required this.selected, required this.downloaded});
  @override
  State<_SurahPicker> createState() => _SurahPickerState();
}

class _SurahPickerState extends State<_SurahPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final numbers = List.generate(114, (i) => i + 1)
        .where(
          (n) => readingSearch(
            '$n ${surahNames[n - 1]}',
          ).contains(readingSearch(query)),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SectionTitle('Choose a surah'),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Surah name or number',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: numbers.length,
                itemBuilder: (context, index) {
                  final n = numbers[index];
                  return ListTile(
                    selected: widget.selected == n,
                    leading: Text('$n'),
                    title: Text(surahNames[n - 1]),
                    subtitle: Text('${surahLengths[n - 1]} ayahs'),
                    trailing: widget.downloaded.contains(n)
                        ? const Icon(Icons.offline_pin)
                        : null,
                    onTap: () => Navigator.pop(context, n),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuranDownloadsPage extends StatefulWidget {
  final AppState state;
  const QuranDownloadsPage(this.state, {super.key});
  @override
  State<QuranDownloadsPage> createState() => _QuranDownloadsPageState();
}

class _QuranDownloadsPageState extends State<QuranDownloadsPage> {
  late final store = ReadingStore(widget.state.preferences);
  Set<int> downloaded = {};
  bool busy = false, cancelled = false;
  String status = '', search = '';
  int completed = 0, total = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    cancelled = true;
    store.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final next = await store.downloaded();
      if (mounted) setState(() => downloaded = next);
    } catch (_) {
      if (mounted) setState(() => status = 'Could not open saved readings.');
    }
  }

  Future<void> download(List<int> numbers) async {
    if (busy) return;
    setState(() {
      busy = true;
      cancelled = false;
      completed = 0;
      total = numbers.length;
      status = '';
    });
    for (final n in numbers) {
      if (cancelled || !mounted) break;
      setState(() => status = 'Saving ${surahNames[n - 1]}…');
      try {
        final reading = await store.read(n);
        if (cancelled || !mounted) break;
        await store.save(reading);
        if (mounted) {
          setState(() {
            downloaded.add(n);
            completed++;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => status =
                'Download paused. Check your connection and free storage, then retry.',
          );
        }
        break;
      }
      // Sequential requests respect the source service. Saved surahs are skipped on resume.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (mounted) {
      setState(() {
        busy = false;
        if (cancelled) {
          status = 'Stopped. Completed downloads are kept.';
        } else if (completed == total) {
          status = 'All selected surahs are saved on this device.';
        }
      });
    }
  }

  Future<void> remove(int n) async {
    try {
      await store.remove(n);
      await refresh();
    } catch (_) {
      if (mounted) notice(context, 'Could not remove this download.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final numbers = List.generate(114, (i) => i + 1)
        .where(
          (n) => readingSearch(
            '$n ${surahNames[n - 1]}',
          ).contains(readingSearch(search)),
        )
        .toList();
    return ContentPage(
      title: 'Offline Qur’an',
      actions: [
        IconButton(
          tooltip: 'Remove all downloads',
          onPressed: busy || downloaded.isEmpty
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Remove all downloaded surahs?'),
                      content: const Text(
                        'Your bookmarks and reading position will stay saved.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Keep'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !mounted) return;
                  setState(() => busy = true);
                  try {
                    for (final n in downloaded.toList()) {
                      await store.remove(n);
                    }
                    await refresh();
                  } catch (_) {
                    if (context.mounted) {
                      notice(context, 'Some downloads could not be removed.');
                    }
                  }
                  if (mounted) {
                    setState(() {
                      busy = false;
                      status = '';
                    });
                  }
                },
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${downloaded.length} of 114 surahs saved'),
                const SizedBox(height: 8),
                const Text(
                  'Downloads include Arabic and English meaning. Choose surahs below or save all; '
                  'this uses your internet connection and device storage.',
                ),
                if (kIsWeb)
                  const Text(
                    'Browser space is limited. Use the installed app for the full offline library.',
                  ),
                const SizedBox(height: 12),
                if (busy) ...[
                  LinearProgressIndicator(
                    value: total == 0 ? 0 : completed / total,
                  ),
                  Text('$completed of $total · $status'),
                  TextButton(
                    onPressed: cancelled
                        ? null
                        : () => setState(() {
                            cancelled = true;
                            status = 'Stopping current download…';
                            store.cancelRequests();
                          }),
                    child: const Text('Stop download'),
                  ),
                ] else ...[
                  if (status.isNotEmpty) Text(status),
                  FilledButton.icon(
                    onPressed: downloaded.length == 114 || kIsWeb
                        ? null
                        : () => download(
                            List.generate(
                              114,
                              (i) => i + 1,
                            ).where((n) => !downloaded.contains(n)).toList(),
                          ),
                    icon: const Icon(Icons.download),
                    label: Text(
                      downloaded.isEmpty
                          ? 'Download all 114 surahs'
                          : 'Download remaining surahs',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Find a surah',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => search = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: numbers.length,
              itemBuilder: (context, index) {
                final n = numbers[index], saved = downloaded.contains(n);
                return ListTile(
                  leading: Text('$n'),
                  title: Text(surahNames[n - 1]),
                  subtitle: Text(
                    saved
                        ? 'Available offline'
                        : '${surahLengths[n - 1]} ayahs',
                  ),
                  trailing: IconButton(
                    tooltip: saved ? 'Remove download' : 'Download surah',
                    onPressed: busy
                        ? null
                        : () => saved ? remove(n) : download([n]),
                    icon: Icon(
                      saved ? Icons.delete_outline : Icons.download_outlined,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
