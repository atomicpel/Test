import 'package:cycle_app/cycle.dart';
import 'package:cycle_app/store.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

Set<DateTime> mark(DateTime start, int len) =>
    {for (var i = 0; i < len; i++) addDays(start, i)};

/// Периоды по списку длин циклов, начиная с [first].
Set<DateTime> history(DateTime first, List<int> cycles, {int len = 5}) {
  final days = <DateTime>{...mark(first, len)};
  var s = first;
  for (final c in cycles) {
    s = addDays(s, c);
    days.addAll(mark(s, len));
  }
  return days;
}

void main() {
  test('группировка с пропуском одного дня', () {
    final p = groupPeriods([d(2026, 1, 1), d(2026, 1, 2), d(2026, 1, 4), d(2026, 1, 20)]);
    expect(p.length, 2);
    expect(p[0].length, 4);
    expect(p[1].start, d(2026, 1, 20));
  });

  test('без записей — прогноза нет', () {
    final f = computeForecast({}, now: d(2026, 10, 18));
    expect(f.tentative, isTrue);
    expect(f.predicted, isEmpty);
    expect(f.kindOf(d(2026, 10, 18)), DayKind.none);
  });

  test('один период — прогноз предварительный', () {
    final f = computeForecast(mark(d(2026, 10, 1), 5), now: d(2026, 10, 10));
    expect(f.tentative, isTrue);
    expect(f.predicted, isNotEmpty);
  });

  test('цикл и длина месячных берутся из записей', () {
    final f = computeForecast(history(d(2026, 7, 1), [30, 30, 30], len: 4),
        now: d(2026, 10, 10));
    expect(f.tentative, isFalse);
    expect(f.cycleLength, 30);
    expect(f.periodLength, 4);
    expect(f.cyclesUsed, 3);
    expect(f.delay, 0);
    expect(f.nextStart, d(2026, 10, 29));
    expect(f.kindOf(d(2026, 10, 29)), DayKind.predicted);
    expect(f.kindOf(d(2026, 11, 1)), DayKind.predicted);
    expect(f.kindOf(d(2026, 11, 2)), isNot(DayKind.predicted));
    // овуляция: 29.09 + 30 - 14 = 15.10
    expect(f.kindOf(d(2026, 10, 15)), DayKind.ovulation);
    expect(f.kindOf(d(2026, 10, 12)), DayKind.fertile);
    expect(f.kindOf(d(2026, 10, 1)), DayKind.period);
  });

  test('свежие циклы весят больше старых', () {
    // раньше было 26, последние три — 30: прогноз ближе к 30, чем простое среднее 28
    final f = computeForecast(history(d(2026, 1, 1), [26, 26, 26, 30, 30, 30]),
        now: d(2026, 7, 20));
    expect(f.cycleLength, 29);
    expect(f.cycleSpread, greaterThan(0));
  });

  test('пропущенная отметка (двойной цикл) не портит расчёт', () {
    final f = computeForecast(history(d(2026, 1, 1), [28, 29, 58, 28, 28]),
        now: d(2026, 6, 20));
    expect(f.cyclesUsed, 4);
    expect(f.cycleLength, 28);
  });

  test('учитываются только последние 12 циклов', () {
    final cycles = [...List.filled(10, 35), ...List.filled(12, 27)];
    final f = computeForecast(history(d(2024, 1, 1), cycles), now: d(2025, 11, 20));
    expect(f.cycleLength, 27);
    expect(f.cycleSpread, 0);
  });

  test('задержка сдвигает прогноз на сегодня', () {
    final f = computeForecast(history(d(2026, 9, 1), [28]), now: d(2026, 11, 1));
    expect(f.cycleLength, 28);
    expect(f.delay, 5); // ожидались 27.10
    expect(f.nextStart, d(2026, 11, 1));
  });

  test('огромные паузы не учитываются', () {
    final days = <DateTime>{
      ...mark(d(2025, 1, 1), 5),
      ...mark(d(2026, 8, 1), 5),
      ...mark(d(2026, 8, 29), 5), // 28
    };
    final f = computeForecast(days, now: d(2026, 9, 5));
    expect(f.cycleLength, 28);
    expect(f.cyclesUsed, 1);
  });

  test('dayKey и обратно', () {
    expect(dayKey(d(2026, 3, 7)), '2026-03-07');
    expect(parseDayKey('2026-03-07'), d(2026, 3, 7));
  });

  test('код подключения', () {
    final c = Store.parseCode(
        ' https://cycle.atomicpel.cloud-ip.cc#AbCdEfGh_ijklmnop-1234 ');
    expect(c?.url, 'https://cycle.atomicpel.cloud-ip.cc');
    expect(c?.token, 'AbCdEfGh_ijklmnop-1234');
    final two = Store.parseCode('cycle.example.ru\nAbCdEfGh_ijklmnop-1234');
    expect(two?.url, 'cycle.example.ru');
    expect(Store.parseCode('привет'), isNull);
    expect(Store.parseCode('https://x.ru#short'), isNull);
  });
}
