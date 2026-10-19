import 'package:cycle_app/cycle.dart';
import 'package:cycle_app/day_entry.dart';
import 'package:cycle_app/prefs.dart';
import 'package:cycle_app/reminders.dart';
import 'package:cycle_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

Set<DateTime> mark(DateTime start, int len) =>
    {for (var i = 0; i < len; i++) addDays(start, i)};

void main() {
  test('импорт списка дат', () {
    final s = Store.loadFrom(Prefs.memory());
    final r = s.importText('''
2025-09-13 5
15.10.2025 7
2025-11-10 7
мусор без даты
2026-08-23 5
''');
    expect(r.error, isNull);
    expect(r.periods, 4);
    final f = s.forecast;
    expect(f.periods.length, 4);
    expect(f.periods.first.start, d(2025, 9, 13));
    expect(f.periods.first.length, 5);
    expect(f.periods[1].length, 7);
  });

  test('экспорт и импорт обратно', () {
    final a = Store.loadFrom(Prefs.memory());
    a.markPeriod(d(2026, 9, 1), 4);
    a.patchDay(d(2026, 9, 2), {'f': 3, 's': ['cramps'], 'n': 'тест'});
    a.setSetting('contra', 'pill');
    final json = a.exportJson();
    final b = Store.loadFrom(Prefs.memory());
    final r = b.importText(json);
    expect(r.error, isNull);
    expect(b.day(d(2026, 9, 2)).flow, 3);
    expect(b.day(d(2026, 9, 2)).symptoms, ['cramps']);
    expect(b.day(d(2026, 9, 2)).note, 'тест');
    expect(b.contraception, 'pill');
    expect(b.forecast.periods.single.length, 4);
  });

  test('пустые значения удаляются из записи', () {
    final s = Store.loadFrom(Prefs.memory());
    s.patchDay(d(2026, 1, 1), {'s': ['a'], 'f': 2});
    s.patchDay(d(2026, 1, 1), {'s': <String>[], 'f': 0});
    expect(s.day(d(2026, 1, 1)).isEmpty, isTrue);
    expect(s.loggedDays, isEmpty);
  });

  test('удаление всех данных', () {
    final s = Store.loadFrom(Prefs.memory());
    s.markPeriod(d(2026, 1, 1), 5);
    s.deleteAll();
    expect(s.forecast.periods, isEmpty);
  });

  test('сведения о дне: день цикла, овуляция, фертильность', () {
    final days = <DateTime>{...mark(d(2026, 7, 1), 5), ...mark(d(2026, 7, 31), 5)};
    final f = computeForecast(days, now: d(2026, 8, 5));
    // цикл 30: следующие 30.08, овуляция 16.08
    final i = f.info(d(2026, 8, 10))!;
    expect(i.cycleDay, 11);
    expect(i.daysToOvulation, 6);
    expect(i.fertility, Fertility.low);
    expect(f.info(d(2026, 8, 15))!.fertility, Fertility.high);
    expect(f.info(d(2026, 8, 12))!.fertility, Fertility.medium);
    expect(f.info(d(2026, 7, 3))!.periodDay, 3);
    // в прошлом цикле овуляция за 14 дней до 31.07
    expect(f.kindOf(d(2026, 7, 17)), DayKind.ovulation);
    expect(f.info(d(2026, 6, 1)), isNull);
  });

  test('ПМС — за 3 дня до ожидаемых месячных', () {
    final f = computeForecast({...mark(d(2026, 9, 1), 5), ...mark(d(2026, 9, 29), 5)},
        now: d(2026, 10, 5));
    expect(f.nextStart, d(2026, 10, 27));
    expect(f.isPms(d(2026, 10, 24)), isTrue);
    expect(f.isPms(d(2026, 10, 23)), isFalse);
  });

  test('напоминания: расписание по прогнозу', () {
    final f = computeForecast({...mark(d(2026, 9, 1), 5), ...mark(d(2026, 9, 29), 5)},
        now: d(2026, 10, 5));
    final r = Map<String, dynamic>.from(defaultReminders)
      ..['pill'] = true
      ..['ovulation'] = true;
    final now = DateTime(2026, 10, 5, 12, 0);
    final notes = planReminders(f: f, r: r, now: now, secret: false);
    final soon = notes.firstWhere((n) => n.id == 100);
    expect(soon.when, DateTime(2026, 10, 25, 9, 0));
    expect(soon.title, 'Скоро месячные');
    final start = notes.firstWhere((n) => n.id == 101);
    expect(start.when, DateTime(2026, 10, 27, 9, 0));
    final pill = notes.firstWhere((n) => n.id == 1);
    expect(pill.daily, isTrue);
    expect(pill.when, DateTime(2026, 10, 5, 21, 0));
    // овуляция 13.10 → напоминание 12.10
    expect(notes.any((n) => n.id == 201 && n.when == DateTime(2026, 10, 12, 9, 0)), isTrue);
    // всё в будущем
    expect(notes.every((n) => n.when.isAfter(now)), isTrue);

    final secret = planReminders(f: f, r: r, now: now, secret: true);
    expect(secret.every((n) => !n.body.contains('месячн') && !n.title.contains('месячн')), isTrue);
  });

  test('напоминания в режиме беременности — без цикла', () {
    final f = computeForecast(mark(d(2026, 9, 1), 5), now: d(2026, 10, 5));
    final notes = planReminders(
        f: f, r: Map<String, dynamic>.from(defaultReminders), now: DateTime(2026, 10, 5), secret: false, pregnant: true);
    expect(notes.where((n) => n.id >= 100), isEmpty);
  });

  test('беременность: недели и дата родов', () {
    final p = Pregnancy(d(2026, 1, 1));
    expect(p.due, d(2026, 10, 8));
    expect(p.week(d(2026, 3, 1)), 8);
    expect(Pregnancy.fromDue(d(2026, 10, 8)).lmp, d(2026, 1, 1));
  });

  test('регулярность цикла', () {
    final f = computeForecast({
      ...mark(d(2026, 1, 1), 5),
      ...mark(d(2026, 1, 29), 5),
      ...mark(d(2026, 2, 26), 5),
      ...mark(d(2026, 4, 17), 5), // 50
    }, now: d(2026, 4, 25));
    expect(f.regular, isFalse);
  });

  test('свои пункты', () {
    final s = Store.loadFrom(Prefs.memory());
    s.addCustom('s', 'Мигрень с аурой');
    expect(s.custom('s'), ['c:Мигрень с аурой']);
    expect(optById(symptomOptions, 'c:Мигрень с аурой').label, 'Мигрень с аурой');
  });
}
