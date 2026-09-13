import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/radio_controller.dart';
import '../core/app_state.dart';
import 'sermons.dart';
import '../widgets/common.dart';

class RadioPage extends StatelessWidget {
  final RadioController radio;
  final AppState? state;
  const RadioPage(this.radio, {super.key, this.state});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: radio,
    builder: (context, _) => ContentPage(
      title: radio.currentTitle,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.radio_outlined, size: 100, color: Color(0xffd6af62)),
          const SizedBox(height: 24),
          Text(
            radio.organisation.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            radio.isRadio ? 'Listen wherever you are' : radio.currentTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: radio.busy
                ? null
                : radio.playing
                ? radio.stop
                : radio.play,
            icon: Icon(radio.playing ? Icons.stop : Icons.play_arrow),
            label: Text(
              radio.busy
                  ? 'Connecting…'
                  : radio.playing
                  ? 'Stop audio'
                  : 'Play live radio',
            ),
          ),
          if (radio.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(radio.error!),
            ),
          if (state != null)
            ActionTile(
              icon: Icons.headphones_outlined,
              title: 'Talks & reflections',
              subtitle: 'Recordings, summaries and reviewed quotes',
              onTap: () => showPage(context, SermonArchivePage(state!, radio)),
            ),
          const SectionTitle(
            'Sleep timer',
            subtitle: 'Stop the stream automatically',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final minutes in [0, 15, 30, 60, 90])
                ActionChip(
                  label: Text(minutes == 0 ? 'Off' : '$minutes min'),
                  onPressed: () => radio.sleepAfter(minutes),
                ),
            ],
          ),
          if (radio.stopAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Stops at ${DateFormat('h:mm a').format(radio.stopAt!)}',
              ),
            ),
        ],
      ),
    ),
  );
}
