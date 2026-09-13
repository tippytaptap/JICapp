import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:community_app/features/tasbih.dart';

void main() {
  testWidgets('Tasbih saves the count and supports undo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(home: TasbihPage(preferences)));
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(preferences.getInt('tasbih.count'), 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(preferences.getInt('tasbih.count'), 0);
    expect(tester.takeException(), isNull);
  });
}
