import 'package:cycle_app/cycle.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

Set<DateTime> mark(DateTime start, int len) =>
    {for (var i = 0; i < len; i++) addDays(start, i)};

void main() {
  test('группировка с пропуском одного дня', () {
    final p = groupPeriods([d(2026, 1, 1), d(2026, 1, 2), d(2026, 1, 4), d(2026, 1, 20)]);
    expect(p.length, 2);
    expect(p[0].length, 4);
    expect(p[1].start, d(2026, 1, 20));
  });

  test('без истории — значения по умолчанию', () {
    final f = computeForecast({}, now: d(2026, 10, 18));
    expect(f.cycleLength, 28);
    expect(f.predicted, isEmpty);
    expect(f.kindOf(d(2026, 10, 18)), DayKind.none);
  });

  test('средний цикл и прогноз', () {
    final days = <DateTime>{
      ...mark(d(2026, 7, 1), 5),
      ...mark(d(2026, 7, 31), 5), // 30
      ...mark(d(2026, 8, 30), 5), // 30
      ...mark(d(2026, 9, 29), 5), // 30
    };
    final f = computeForecast(days, now: d(2026, 10, 10));
    expect(f.cycleLength, 30);
    expect(f.periodLength, 5);
    expect(f.delay, 0);
    expect(f.nextStart, d(2026, 10, 29));
    expect(f.kindOf(d(2026, 10, 29)), DayKind.predicted);
    expect(f.kindOf(d(2026, 11, 2)), DayKind.predicted);
    // овуляция: 29.09 + 30 - 14 = 15.10
    expect(f.kindOf(d(2026, 10, 15)), DayKind.ovulation);
    expect(f.kindOf(d(2026, 10, 12)), DayKind.fertile);
    expect(f.kindOf(d(2026, 10, 1)), DayKind.period);
  });

  test('задержка сдвигает прогноз на сегодня', () {
    final days = <DateTime>{...mark(d(2026, 9, 1), 5), ...mark(d(2026, 9, 29), 5)};
    final f = computeForecast(days, now: d(2026, 11, 1));
    expect(f.cycleLength, 28);
    expect(f.delay, 5); // ожидались 27.10
    expect(f.nextStart, d(2026, 11, 1));
  });

  test('слишком длинные паузы не портят средний цикл', () {
    final days = <DateTime>{
      ...mark(d(2025, 1, 1), 5),
      ...mark(d(2026, 8, 1), 5), // 577 дней — игнор
      ...mark(d(2026, 8, 29), 5), // 28
    };
    final f = computeForecast(days, now: d(2026, 9, 5));
    expect(f.cycleLength, 28);
  });

  test('dayKey и обратно', () {
    expect(dayKey(d(2026, 3, 7)), '2026-03-07');
    expect(parseDayKey('2026-03-07'), d(2026, 3, 7));
  });
}
