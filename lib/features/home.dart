import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/radio_controller.dart';
import '../widgets/common.dart';
import 'education.dart';
import 'forms.dart';
import 'qibla.dart';
import 'radio.dart';

class HomeView extends StatelessWidget {
  final AppState state;
  final RadioController radio;
  final void Function(int) navigate;
  const HomeView(this.state, this.radio, this.navigate, {super.key});
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: state.refresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: [
              Positioned.fill(
                child: ContentImage(
                  state.image(state.branding['hero']) ??
                      'assets/brand/hero.jpg',
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .25),
                        const Color(0xee10213a),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      state.organisation.location.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xffe8c780),
                        letterSpacing: 1.6,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'A place for faith.\nA home for community.',
                      style: TextStyle(
                        fontSize: 32,
                        color: Colors.white,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Worship. Learn. Grow. Together.',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => showPage(context, RadioPage(radio)),
                      icon: const Icon(Icons.radio, size: 18),
                      label: const Text('Listen to radio'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (state.stale)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Some updates could not be loaded. Pull down to retry.',
            ),
          ),
        const SizedBox(height: 12),
        PrayerCard(state),
        for (final a in state.announcements)
          Card(
            child: ListTile(
              title: Text('${a['title'] ?? 'Announcement'}'),
              subtitle: Text('${a['body'] ?? a['message'] ?? ''}'),
            ),
          ),
        const SectionTitle('Make time for what matters'),
        ActionTile(
          icon: Icons.menu_book_outlined,
          title: 'Reading',
          subtitle: 'Qur’an, salawat & more',
          onTap: () => navigate(1),
        ),
        ActionTile(
          icon: Icons.school_outlined,
          title: 'Learn',
          subtitle: 'Adult courses & weekly gatherings',
          onTap: () => navigate(2),
        ),
        ActionTile(
          icon: Icons.explore_outlined,
          title: 'Qibla',
          subtitle: 'Find the direction of prayer',
          onTap: () => showPage(context, const QiblaPage()),
        ),
        const SectionTitle(
          'What’s on',
          subtitle: 'Gatherings, learning and community',
        ),
        for (final p in state.programmes.where(
          (p) =>
              (p['groups'] as List? ?? []).contains('home') &&
              p['kind'] != 'announcement',
        ))
          ProgrammeCard(state, p),
        for (final event in state.events)
          Card(
            child: ListTile(
              title: Text('${event['title']}'),
              subtitle: Text(
                '${event['event_date']}\n${event['description'] ?? ''}',
              ),
            ),
          ),
        if (state.livestream['enabled'] == true &&
            safeWebUrl('${state.livestream['youtube_url']}'))
          ActionTile(
            icon: Icons.live_tv,
            title: 'Watch broadcast',
            subtitle: 'Open the centre’s livestream',
            onTap: () => openLink(context, state.livestream['youtube_url']),
          ),
        ActionTile(
          icon: Icons.mail_outline,
          title: 'Get in touch',
          subtitle: 'Questions & enquiries',
          onTap: () => showPage(context, EnquiryPage(state)),
        ),
      ],
    ),
  );
}

class PrayerCard extends StatelessWidget {
  final AppState state;
  const PrayerCard(this.state, {super.key});
  @override
  Widget build(BuildContext context) {
    final day = state.todayPrayers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.nightlight_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Prayer times')),
                Text(state.today.substring(5)),
              ],
            ),
            const SizedBox(height: 14),
            if (day == null)
              Text(
                state.loading
                    ? 'Loading the timetable…'
                    : 'Today’s timetable is not available yet.',
              )
            else ...[
              const Row(
                children: [
                  Expanded(child: Text('Prayer')),
                  Expanded(child: Text('Begins')),
                  Expanded(child: Text('Jama’ah')),
                ],
              ),
              for (final p in prayerNames.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.value)),
                      Expanded(
                        child: Text(displayTime(day['${p.key}_begins'])),
                      ),
                      Expanded(child: Text(displayTime(day['${p.key}_jamah']))),
                    ],
                  ),
                ),
              if (centreNow(state.organisation.timeZone).weekday == 5) ...[
                const Divider(),
                Text('First Jumu’ah: ${displayTime(day['jummah_1_jamah'])}'),
                Text('Second Jumu’ah: ${displayTime(day['jummah_2_jamah'])}'),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
