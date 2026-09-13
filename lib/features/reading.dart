import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import 'tasbih.dart';

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
                  'Continue · Surah ${state.preferences.getInt('quran.surah') ?? 1} →',
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

class LibraryPage extends StatelessWidget {
  final AppState state;
  final String collection, title;
  const LibraryPage(this.state, this.collection, this.title, {super.key});
  @override
  Widget build(BuildContext context) {
    final entries = state.library
        .where((r) => r['collection'] == collection)
        .toList();
    return ContentPage(
      title: title,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (entries.isEmpty)
            const Text(
              'The centre has not published readings in this collection yet.',
            ),
          for (final entry in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${entry['title'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if ('${entry['arabic'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: SelectableText(
                          entry['arabic'],
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(fontSize: 28, height: 1.9),
                        ),
                      ),
                    if ('${entry['text'] ?? entry['body'] ?? ''}'.isNotEmpty)
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
            ),
        ],
      ),
    );
  }
}

class QuranPage extends StatefulWidget {
  final AppState state;
  const QuranPage(this.state, {super.key});
  @override
  State<QuranPage> createState() => _QuranPageState();
}

class _QuranPageState extends State<QuranPage> {
  late int surah = (widget.state.preferences.getInt('quran.surah') ?? 1).clamp(
    1,
    114,
  );
  late double font = widget.state.preferences.getDouble('quran.font') ?? 28;
  bool english = true;
  late Future<List<Record>> request = load();
  Future<List<Record>> load() async {
    final response = await http
        .get(
          Uri.https(
            'api.alquran.cloud',
            '/v1/surah/$surah/editions/quran-uthmani,en.sahih',
          ),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw StateError('Reading unavailable');
    final data = records(jsonDecode(response.body)['data']);
    if (data.length != 2) throw StateError('Incomplete reading');
    return data;
  }

  void change(int value) {
    setState(() {
      surah = value;
      request = load();
    });
    widget.state.preferences.setInt('quran.surah', value);
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'The Noble Qur’an',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: surah,
                  items: [
                    for (var n = 1; n <= 114; n++)
                      DropdownMenuItem(value: n, child: Text('Surah $n')),
                  ],
                  onChanged: (n) {
                    if (n != null) change(n);
                  },
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
        SwitchListTile(
          title: const Text('English meaning'),
          value: english,
          onChanged: (v) => setState(() => english = v),
        ),
        Expanded(
          child: FutureBuilder<List<Record>>(
            future: request,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      request = load();
                    }),
                    child: const Text('Could not load this surah. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final arabic = records(snapshot.data![0]['ayahs']);
              final translation = records(snapshot.data![1]['ayahs']);
              return ListView.builder(
                key: ValueKey(surah),
                padding: const EdgeInsets.all(20),
                itemCount: arabic.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        '${snapshot.data![0]['englishName']} · ${snapshot.data![0]['name']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    );
                  }
                  final a = arabic[index - 1];
                  final meaning = translation
                      .where((t) => t['numberInSurah'] == a['numberInSurah'])
                      .firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '$surah:${a['numberInSurah']}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        SelectableText(
                          '${a['text']}',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(fontSize: font, height: 2),
                        ),
                        if (english && meaning != null)
                          SelectableText(
                            '${meaning['text']}',
                            style: const TextStyle(height: 1.6),
                          ),
                        const Divider(),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
