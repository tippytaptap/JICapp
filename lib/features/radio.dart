import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/radio_controller.dart';
import '../widgets/common.dart';

class RadioPage extends StatelessWidget {
  final RadioController radio;
  const RadioPage(this.radio, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: radio,
    builder: (context, _) => ContentPage(
      title: 'Live radio',
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
          const Text('Listen wherever you are', textAlign: TextAlign.center),
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
                  ? 'Stop radio'
                  : 'Play radio',
            ),
          ),
          if (radio.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(radio.error!),
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
