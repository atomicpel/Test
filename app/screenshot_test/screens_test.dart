// Скриншоты экранов для проверки оформления. Запускается в сборке:
//   flutter test screenshot_test --update-goldens
// Картинки попадают в screenshot_test/out/ и прикладываются к релизу.
import 'dart:io';

import 'package:cycle_app/cycle.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/prefs.dart';
import 'package:cycle_app/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    if (!File(f).existsSync()) continue;
    l.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await l.load();
}

/// Пример данных: пять прошлых циклов, последние месячные начались 9 дней назад.
Store _sample() {
  final s = Store.loadFrom(Prefs.memory());
  final t = today();
  const cycles = [29, 28, 30, 29, 28];
  var start = addDays(t, -9 - cycles.fold<int>(0, (a, b) => a + b));
  for (final c in cycles) {
    s.markPeriod(start, 5);
    start = addDays(start, c);
  }
  s.markPeriod(start, 5);
  s.setDay(addDays(t, -2), note: 'Болела голова');
  return s;
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await expectLater(find.byType(CycleApp), matchesGoldenFile('out/$name.png'));
}

void main() {
  setUpAll(() async {
    await _font('Unbounded', [
      'fonts/Unbounded-Medium.ttf',
      'fonts/Unbounded-SemiBold.ttf',
      'fonts/Unbounded-Bold.ttf',
    ]);
    await _font('Golos', [
      'fonts/Golos-Regular.ttf',
      'fonts/Golos-Medium.ttf',
      'fonts/Golos-SemiBold.ttf',
      'fonts/Golos-Bold.ttf',
    ]);
    await _font('MaterialIcons', ['screenshot_test/MaterialIcons-Regular.otf']);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final m = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('календарь $m', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(CycleApp(store: _sample(), themeMode: mode));
      await _shot(tester, '1_calendar_$m');
      await tester.drag(find.byType(ListView).first, const Offset(0, -560));
      await _shot(tester, '2_calendar_scrolled_$m');
      final t = today();
      await tester.tap(find.byWidgetPredicate((w) =>
          w is Semantics && w.properties.label == '${t.day}, сегодня'));
      await _shot(tester, '3_day_$m');
    });

    testWidgets('история $m', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
          CycleApp(store: _sample(), themeMode: mode, initialTab: 1));
      await _shot(tester, '4_history_$m');
    });

    testWidgets('настройки $m', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
          CycleApp(store: _sample(), themeMode: mode, initialTab: 2));
      await _shot(tester, '5_settings_$m');
    });

    testWidgets('пусто $m', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
          CycleApp(store: Store.loadFrom(Prefs.memory()), themeMode: mode));
      await _shot(tester, '6_empty_$m');
    });
  }
}
