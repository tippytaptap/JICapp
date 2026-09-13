import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models.dart';
import '../core/worship_store.dart';
import '../core/watch_service.dart';
import '../widgets/common.dart';

class TasbihPage extends StatefulWidget {
  final SharedPreferences preferences;
  const TasbihPage(this.preferences, {super.key});
  @override
  State<TasbihPage> createState() => _TasbihPageState();
}

class _TasbihPageState extends State<TasbihPage> {
  late int count = (widget.preferences.getInt('tasbih.count') ?? 0).clamp(
    0,
    99999999,
  );
  late int target = (widget.preferences.getInt('tasbih.target') ?? 33).clamp(
    1,
    999999,
  );
  late bool vibration = widget.preferences.getBool('tasbih.vibration') ?? false;
  late DhikrRoutine routine = DhikrRoutine.decode(
    widget.preferences.getString('tasbih.routine'),
  );
  Future<void> saving = Future.value();
  bool transferring = false;
  Future<void> watchTransfer({required bool importing}) async {
    if (transferring) return;
    setState(() => transferring = true);
    try {
      await saving;
      if (importing) {
        final snapshot = await WatchService.incomingCounter();
        if (!mounted) return;
        if (snapshot == null) {
          notice(context, 'Send your count from the watch first.');
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Use the watch count?'),
            content: Text(
              'Replace this circle with ${snapshot.count} and a round of ${snapshot.target}? '
              'Your daily routine total will stay as it is.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep phone count'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Use watch count'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        if (!await widget.preferences.setInt('tasbih.count', snapshot.count) ||
            !await widget.preferences.setInt(
              'tasbih.target',
              snapshot.target,
            )) {
          throw StateError('Could not save watch count');
        }
        if (mounted) {
          setState(() {
            count = snapshot.count;
            target = snapshot.target;
          });
        }
        await WatchService.markImported(snapshot);
        if (mounted) notice(context, 'Watch count imported.');
      } else {
        if (![33, 99, 100].contains(target)) {
          if (mounted) {
            notice(
              context,
              'Choose a round of 33, 99 or 100 to send to your watch.',
            );
          }
          return;
        }
        await WatchService.sendCounter(count, target);
        if (mounted) {
          notice(
            context,
            'Ready for watch. Choose Import phone count on your watch.',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Your paired watch is unavailable. Check the connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  void persistRoutine() {
    final value = routine.encode();
    saving = saving
        .then((_) async {
          if (!await widget.preferences.setString('tasbih.routine', value)) {
            throw StateError('Could not save');
          }
        })
        .catchError((Object error) {
          if (mounted) {
            notice(
              context,
              'Your routine could not be saved. Check device storage.',
            );
          }
        });
  }

  Future<void> change(int value, {bool reset = false}) async {
    final nextCount = value.clamp(0, 99999999);
    final delta = nextCount - count;
    setState(() => count = nextCount);
    if (!reset) routine = routine.count(delta, DateTime.now());
    final next = count;
    saving = saving
        .then((_) async {
          if (!await widget.preferences.setInt('tasbih.count', next)) {
            throw StateError('Could not save');
          }
        })
        .catchError((Object error) {
          if (mounted) {
            notice(
              context,
              'Your count could not be saved. Check device storage.',
            );
          }
        });
    if (routine.goal > 0) persistRoutine();
    if (vibration && delta > 0) {
      if (next % target == 0) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    }
    await saving;
  }

  Future<void> setDailyGoal() async {
    final controller = TextEditingController(
      text: routine.goal == 0 ? '' : '${routine.goal}',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Choose your daily goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Count per day',
            helperText: 'A personal goal you can change anytime',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 0),
            child: const Text('Turn off'),
          ),
          FilledButton(
            onPressed: () {
              final goal = int.tryParse(controller.text);
              if (goal != null && goal > 0 && goal <= 999999) {
                Navigator.pop(c, goal);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (result != null && mounted) {
      setState(() => routine = routine.setGoal(result, DateTime.now()));
      persistRoutine();
    }
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
                onPressed: transferring ? null : () => change(count + 1),
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
                      if (reset == true) await change(0, reset: true);
                    },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your daily routine',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (routine.goal == 0)
                  const Text(
                    'You can choose a daily goal. It is optional and stays on this device.',
                  )
                else ...[
                  Text(
                    '${routine.todayCount(DateTime.now())} of ${routine.goal} today',
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: (routine.todayCount(DateTime.now()) / routine.goal)
                        .clamp(0, 1),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${routine.streak(DateTime.now())} consecutive days reaching your chosen goal',
                  ),
                  const Text(
                    'Resetting the circle keeps today’s total. Undo removes one from today’s total.',
                  ),
                ],
                TextButton(
                  onPressed: setDailyGoal,
                  child: Text(
                    routine.goal == 0 ? 'Set a personal goal' : 'Change goal',
                  ),
                ),
                if (routine.days.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Recent days'),
                    children: [
                      for (final entry in routine.days.entries.take(14))
                        ListTile(
                          title: Text(entry.key),
                          trailing: Text(
                            '${entry.value['count']} / ${entry.value['goal']}',
                          ),
                        ),
                      TextButton(
                        onPressed: () async {
                          final clear = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Clear routine history?'),
                              content: const Text(
                                'Your circle count will stay as it is.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Keep'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                          if (clear == true && mounted) {
                            setState(
                              () => routine = DhikrRoutine(goal: routine.goal),
                            );
                            persistRoutine();
                          }
                        },
                        child: const Text('Clear routine history'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (WatchService.supported)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Continue with your watch'),
                  const Text(
                    'Phone and watch keep their own counts. Transfer a count when you choose.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: transferring
                            ? null
                            : () => watchTransfer(importing: false),
                        icon: const Icon(Icons.watch_outlined),
                        label: const Text('Send to watch'),
                      ),
                      TextButton.icon(
                        onPressed: transferring
                            ? null
                            : () => watchTransfer(importing: true),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Import from watch'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
  SalahRecord record = const SalahRecord();
  bool ready = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      record = SalahRecord.decode(await storage.read(key: 'personal.salah'));
      ready = true;
      error = null;
    } catch (_) {
      error =
          'Your private record could not be opened. It has not been replaced.';
    }
    if (mounted) setState(() {});
  }

  Future<void> save(SalahRecord next) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await storage.write(key: 'personal.salah', value: next.encode());
      if (mounted) setState(() => record = next);
    } catch (_) {
      if (mounted) notice(context, 'Could not save your private record.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add(String prayer) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Add ${prayerNames[prayer]} to your plan'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of prayers',
            helperText: 'Enter the number you want to record',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null &&
                  value > 0 &&
                  value + (record.remaining[prayer] ?? 0) <= 999999) {
                Navigator.pop(c, value);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (result != null && mounted) {
      await save(record.change(prayer, result, DateTime.now()));
    }
  }

  Future<void> goal() async {
    final controller = TextEditingController(
      text: record.dailyGoal == 0 ? '' : '${record.dailyGoal}',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Your daily plan'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Prayers to complete per day',
            helperText: 'Choose a comfortable number, up to 50',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 0),
            child: const Text('No daily goal'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0 && value <= 50) {
                Navigator.pop(c, value);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (result != null && mounted) await save(record.withGoal(result));
  }

  Future<void> clear() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your private Salah record?'),
        content: const Text(
          'This removes all remaining counts, your goal and history from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep record'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete record'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    try {
      await storage.delete(key: 'personal.salah');
      if (mounted) {
        setState(() {
          record = const SalahRecord();
          ready = true;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) notice(context, 'Could not delete your record.');
    }
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'My Salah plan',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'A private record of prayers you intend to make up, with a plan at your own pace. '
          'Only you add or complete entries. This record stays on this device and is not shared with staff.',
        ),
        if (error != null) ...[
          Text(error!),
          TextButton(onPressed: load, child: const Text('Try opening again')),
        ],
        if (!ready && error == null) const LinearProgressIndicator(),
        if (ready) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${record.total} remaining',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (record.dailyGoal > 0) ...[
                    Text(
                      '${record.completedToday(DateTime.now())} of ${record.dailyGoal} in today’s plan',
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value:
                          (record.completedToday(DateTime.now()) /
                                  record.dailyGoal)
                              .clamp(0, 1),
                    ),
                  ],
                  TextButton(
                    onPressed: busy ? null : goal,
                    child: Text(
                      record.dailyGoal == 0
                          ? 'Set an optional daily plan'
                          : 'Change daily plan',
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final prayer in prayerNames.entries)
            Card(
              child: ListTile(
                title: Text(prayer.value),
                subtitle: Text(
                  '${record.remaining[prayer.key] ?? 0} remaining',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Mark one ${prayer.value} completed',
                      onPressed:
                          busy || (record.remaining[prayer.key] ?? 0) == 0
                          ? null
                          : () => save(
                              record.change(prayer.key, -1, DateTime.now()),
                            ),
                      icon: const Icon(Icons.check_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Add ${prayer.value} to plan',
                      onPressed: busy ? null : () => add(prayer.key),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
          if (record.history.isNotEmpty) ...[
            TextButton.icon(
              onPressed: busy ? null : () => save(record.undo()),
              icon: const Icon(Icons.undo),
              label: const Text('Undo last entry'),
            ),
            ExpansionTile(
              title: const Text('Your recent entries'),
              children: [
                for (final entry in record.history.take(30))
                  ListTile(
                    title: Text(
                      '${prayerNames[entry['prayer']]} · ${entry['delta'] < 0 ? 'completed' : 'added'} ${entry['delta'].abs()}',
                    ),
                    subtitle: Text(
                      personalDate(DateTime.parse(entry['at']).toLocal()),
                    ),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 24),
        TextButton(
          onPressed: busy ? null : clear,
          child: const Text('Delete private record'),
        ),
      ],
    ),
  );
}
