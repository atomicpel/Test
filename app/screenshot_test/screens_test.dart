// Скриншоты экранов для проверки оформления. Запускается в сборке:
//   flutter test screenshot_test --update-goldens
// Картинки попадают в screenshot_test/out/ и прикладываются к релизу.
import 'dart:io';

import 'package:cycle_app/lock.dart';
import 'package:cycle_app/main.dart';
import 'package:cycle_app/prefs.dart';
import 'package:cycle_app/store.dart';
import 'package:cycle_app/ui_common.dart';
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

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Future<void> _images(WidgetTester tester) async {
  final ctx = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final t in appThemes) {
      if (t.asset != null) await precacheImage(AssetImage(t.asset!), ctx);
    }
  });
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await expectLater(find.byType(CycleApp), matchesGoldenFile('out/$name.png'));
}

Future<void> _finish(WidgetTester tester) async {
  // дать отработать отложенным таймерам (обновление напоминаний)
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Finder _sem(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

void main() {
  setUpAll(() async {
    await _font('Nunito', [
      'fonts/Nunito-Light.ttf',
      'fonts/Nunito-Regular.ttf',
      'fonts/Nunito-SemiBold.ttf',
      'fonts/Nunito-Bold.ttf',
      'fonts/Nunito-ExtraBold.ttf',
    ]);
    await _font('MaterialIcons', ['screenshot_test/MaterialIcons-Regular.otf']);
  });

  testWidgets('главный экран и запись дня — тёмная, котики', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: sampleStore(), darkOverride: true, themeOverride: 'cats'));
    await _images(tester);
    await _shot(tester, '01_home_dark');
    await tester.drag(find.byType(ListView).first, const Offset(0, -480));
    await _shot(tester, '02_home_scrolled');
    await tester.drag(find.byType(PageView).first, const Offset(-400, 0));
    await tester.drag(find.byType(ListView).first, const Offset(0, 480));
    await _shot(tester, '03_home_page2');
    await tester.tap(_sem('Записать сегодняшний день'));
    await _shot(tester, '04_daylog');
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await _shot(tester, '05_daylog_scrolled');
    await _finish(tester);
  });

  testWidgets('главный экран — светлая, цветы', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: sampleStore(), darkOverride: false, themeOverride: 'flowers'));
    await _images(tester);
    await _shot(tester, '06_home_light_flowers');
    await _finish(tester);
  });

  testWidgets('главный экран — ночь и зайчики', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: sampleStore(), darkOverride: true, themeOverride: 'night'));
    await _images(tester);
    await _shot(tester, '07_home_night');
    await _finish(tester);
  });

  testWidgets('статистика', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: sampleStore(), darkOverride: true, initialTab: 1));
    await _images(tester);
    await _shot(tester, '08_stats_cycles');
    await tester.drag(find.byType(ListView).at(1), const Offset(0, -900));
    await _shot(tester, '09_stats_cycles_scrolled');
    await tester.tap(find.text('Графики'));
    await _shot(tester, '10_stats_charts');
    await tester.tap(find.text('Хронология'));
    await _shot(tester, '11_stats_timeline');
    await _finish(tester);
  });

  testWidgets('темы и настройки', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: sampleStore(), darkOverride: true, initialTab: 2));
    await _images(tester);
    await _shot(tester, '12_themes');
    await tester.tap(_sem('Настройки'));
    await _shot(tester, '13_settings');
    await tester.tap(find.text('Месячные, овуляция, таблетки, записи'));
    await _shot(tester, '14_reminders');
    await _finish(tester);
  });

  testWidgets('пусто и PIN', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(CycleApp(store: Store.loadFrom(Prefs.memory()), darkOverride: true));
    await _images(tester);
    await _shot(tester, '15_empty');
    await _finish(tester);
  });

  testWidgets('экран PIN', (tester) async {
    await _phone(tester);
    final s = sampleStore();
    setPin(s, '1234');
    await tester.pumpWidget(CycleApp(store: s, darkOverride: true));
    await _shot(tester, '16_pin');
    await _finish(tester);
  });
}
