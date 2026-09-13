import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models.dart';
import '../widgets/common.dart';

class TasbihPage extends StatefulWidget {
  final SharedPreferences preferences;
  const TasbihPage(this.preferences, {super.key});
  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage> {
  late int count = widget.preferences.getInt('tasbih.count') ?? 0;
  late int target = widget.preferences.getInt('tasbih.target') ?? 33;
  late bool vibration = widget.preferences.getBool('tasbih.vibration') ?? true;
  Future<void> change(int value) async {
    setState(() => count = value.clamp(0, 99999999));
    await widget.preferences.setInt('tasbih.count', count);
    if (vibration) await HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Tasbih',
    actions: [
      IconButton(
        tooltip: vibration ? 'Turn vibration off' : 'Turn vibration on',
        icon: Icon(vibration ? Icons.vibration : Icons.phone_android),
        onPressed: () {
          setState(() => vibration = !vibration);
          widget.preferences.setBool('tasbih.vibration', vibration);
        },
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionTitle(
          'A moment of remembrance',
          subtitle: 'Tap the circle to count',
        ),
        const SizedBox(height: 24),
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: Semantics(
              label: 'Tasbih count $count',
              button: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: const Color(0xffd6af62),
                  foregroundColor: const Color(0xff10213a),
                ),
                onPressed: () => change(count + 1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      child: Text(
                        '$count',
                        style: const TextStyle(fontSize: 64),
                      ),
                    ),
                    Text('of $target per round'),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final n in [33, 99, 100])
              ChoiceChip(
                label: Text('$n'),
                selected: target == n,
                onSelected: (_) {
                  setState(() => target = n);
                  widget.preferences.setInt('tasbih.target', n);
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          children: [
            TextButton.icon(
              onPressed: count == 0 ? null : () => change(count - 1),
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            TextButton.icon(
              onPressed: count == 0
                  ? null
                  : () async {
                      final reset = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Reset this count?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Keep count'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      );
                      if (reset == true) await change(0);
                    },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Your count is saved on this device.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class SalahPlanPage extends StatefulWidget {
  const SalahPlanPage({super.key});
  @override
  State<SalahPlanPage> createState() => _SalahPlanPageState();
}

class _SalahPlanPageState extends State<SalahPlanPage> {
  static const storage = FlutterSecureStorage();
  Record counts = {};
  bool ready = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      counts = Record.from(
        jsonDecode(await storage.read(key: 'personal.salah') ?? '{}'),
      );
      ready = true;
    } catch (_) {
      error = 'Your private record could not be opened.';
    }
    if (mounted) setState(() {});
  }

  Future<void> change(String key, int delta) async {
    if (busy) return;
    setState(() => busy = true);
    final next = {
      ...counts,
      key: (((counts[key] as num?)?.toInt() ?? 0) + delta).clamp(0, 999999),
    };
    try {
      await storage.write(key: 'personal.salah', value: jsonEncode(next));
      if (mounted) setState(() => counts = next);
    } catch (_) {
      if (mounted) notice(context, 'Could not save your record.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'My Salah plan',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'A private record of prayers you intend to make up. Add missed prayers; subtract after completing them. Stored on this device.',
        ),
        if (error != null) Text(error!),
        if (!ready && error == null) const LinearProgressIndicator(),
        if (ready)
          for (final p in prayerNames.entries)
            Card(
              child: ListTile(
                title: Text(p.value),
                subtitle: Text('${counts[p.key] ?? 0} remaining'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'One completed',
                      onPressed: busy || (counts[p.key] ?? 0) == 0
                          ? null
                          : () => change(p.key, -1),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: 'Add missed prayer',
                      onPressed: busy ? null : () => change(p.key, 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}
