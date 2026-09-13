import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/core/watch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('community/watch');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({'tasbih.count': 20});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getIncomingCounter') {
            return jsonEncode({
              'sourceId': 'watch',
              'sessionId': 'local',
              'revision': 2,
              'count': 8,
              'target': 33,
            });
          }
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'incoming handoff never changes the local count without confirmation',
    () async {
      final snapshot = await WatchService.incomingCounter();
      expect(snapshot?.count, 8);
      expect(
        (await SharedPreferences.getInstance()).getInt('tasbih.count'),
        20,
      );
      expect(calls.map((c) => c.method), ['getIncomingCounter']);
      await WatchService.markImported(snapshot!);
      expect(calls.last.method, 'clearIncomingCounter');
      expect(calls.last.arguments, snapshot.raw);
    },
  );
  test(
    'parallel outgoing handoffs have ordered revisions without private data',
    () async {
      await Future.wait([
        WatchService.sendCounter(11, 33),
        WatchService.sendCounter(12, 99),
      ]);
      final payloads = calls
          .map((c) => jsonDecode(c.arguments as String) as Map<String, dynamic>)
          .toList();
      expect(payloads.map((p) => p['revision']), [1, 2]);
      expect(payloads.map((p) => p['count']), [11, 12]);
      expect(payloads.first.keys.toSet(), {
        'sourceId',
        'sessionId',
        'revision',
        'count',
        'target',
      });
    },
  );
  test('invalid counters and malformed snapshots are rejected', () async {
    expect(WatchService.sendCounter(-1, 33), throwsArgumentError);
    expect(WatchCounterSnapshot.parse('{"count":8}'), isNull);
    expect(
      WatchCounterSnapshot.parse(
        jsonEncode({
          'sourceId': '',
          'sessionId': 'local',
          'revision': 1,
          'count': 8,
          'target': 33,
        }),
      ),
      isNull,
    );
    expect(calls, isEmpty);
  });
}
