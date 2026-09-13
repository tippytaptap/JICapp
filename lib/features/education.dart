import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../widgets/common.dart';

class EducationView extends StatefulWidget {
  final AppState state;
  const EducationView(this.state, {super.key});
  @override
  State<EducationView> createState() => _EducationViewState();
}

class _EducationViewState extends State<EducationView> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final programmes = state.programmes
        .where(
          (p) =>
              adultProgramme(p) &&
              (p['groups'] as List? ?? []).contains('education') &&
              p['kind'] != 'announcement',
        )
        .toList();
    final sessions = weeklySessions(programmes);
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        const SectionTitle(
          'Learn & grow',
          subtitle: 'Adult classes, courses and open gatherings',
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Overview')),
            ButtonSegment(value: 1, label: Text('Courses')),
            ButtonSegment(value: 2, label: Text('This week')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        if (tab != 2) ...[
          const SectionTitle('Courses & gatherings'),
          if (programmes.isEmpty)
            const Text('New courses will appear here when published.'),
          for (final p in programmes) ProgrammeCard(state, p),
        ],
        if (tab != 1) ...[
          const SectionTitle(
            'Weekly schedule',
            subtitle: 'Times published by the centre',
          ),
          if (sessions.isEmpty)
            const Text('No weekly times have been published yet.'),
          for (var d = 1; d <= 7; d++)
            if (sessions.any((s) => s['day'] == d))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        days[d - 1],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final s in sessions.where((s) => s['day'] == d))
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${s['title']}\n${s['relativeTo'] == 'maghrib' ? 'After Maghrib · see the prayer timetable' : displayTime(s['time'])}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
        const SectionTitle('Student learning'),
        const Text(
          'For your courses, progress, class registers or meeting requests, open your account. Madrasah pupil records are in their own portal.',
        ),
      ],
    );
  }
}

class ProgrammeCard extends StatelessWidget {
  final AppState state;
  final Record programme;
  const ProgrammeCard(this.state, this.programme, {super.key});
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => showPage(
        context,
        ContentPage(
          title: '${programme['title']}',
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              InteractiveViewer(
                child: ContentImage(
                  state.image(programme['image']),
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Text('${programme['subtitle'] ?? ''}'),
              Text('${programme['schedule'] ?? ''}'),
              const SizedBox(height: 16),
              Text('${programme['detail'] ?? ''}'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => openLink(
                  context,
                  Uri.parse(
                    state.organisation.website,
                  ).resolve('${programme['to'] ?? '/contact'}').toString(),
                ),
                child: const Text('Course details & enquiries'),
              ),
            ],
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ContentImage(
            state.image(programme['image']),
            height: 240,
            fit: BoxFit.contain,
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${programme['title']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('${programme['schedule'] ?? ''}'),
                const SizedBox(height: 12),
                const Text('View programme →'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
