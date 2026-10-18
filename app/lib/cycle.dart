// Логика цикла: группировка отмеченных дней в периоды и прогноз.
// Все даты — DateTime.utc(год, месяц, день) без времени.

DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime today() => dateOnly(DateTime.now());

String _two(int v) => v.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime parseDayKey(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

int daysBetween(DateTime a, DateTime b) =>
    dateOnly(b).difference(dateOnly(a)).inDays;

DateTime addDays(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);

class Period {
  final DateTime start;
  final DateTime end;
  const Period(this.start, this.end);
  int get length => daysBetween(start, end) + 1;
  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

enum DayKind { none, period, predicted, fertile, ovulation }

/// Склеивает отмеченные дни в периоды. Дни с разрывом не больше [maxGap]
/// пропущенных дней считаются одним периодом.
List<Period> groupPeriods(Iterable<DateTime> days, {int maxGap = 1}) {
  final sorted = days.map(dateOnly).toSet().toList()..sort();
  final result = <Period>[];
  for (final d in sorted) {
    if (result.isNotEmpty && daysBetween(result.last.end, d) <= maxGap + 1) {
      result[result.length - 1] = Period(result.last.start, d);
    } else {
      result.add(Period(d, d));
    }
  }
  return result;
}

int _avg(List<int> xs) =>
    (xs.reduce((a, b) => a + b) / xs.length).round();

class Forecast {
  final List<Period> periods; // прошлые, по возрастанию
  final int cycleLength;
  final int periodLength;
  final bool cycleFromHistory;
  final List<Period> predicted;
  final int delay; // дней задержки (0 — нет)
  final Map<DateTime, DayKind> _marks;
  final Set<DateTime> _periodDays;

  Forecast._(this.periods, this.cycleLength, this.periodLength,
      this.cycleFromHistory, this.predicted, this.delay, this._marks,
      this._periodDays);

  /// Длины прошлых циклов (между началами соседних периодов).
  List<int> get cycleLengths => [
        for (var i = 1; i < periods.length; i++)
          daysBetween(periods[i - 1].start, periods[i].start)
      ];

  DayKind kindOf(DateTime d) {
    d = dateOnly(d);
    if (_periodDays.contains(d)) return DayKind.period;
    return _marks[d] ?? DayKind.none;
  }

  Period? get last => periods.isEmpty ? null : periods.last;
  DateTime? get nextStart => predicted.isEmpty ? null : predicted.first.start;

  /// Ближайшая овуляция не раньше [from].
  DateTime? nextOvulation(DateTime from) {
    final dates = _marks.entries
        .where((e) => e.value == DayKind.ovulation && !e.key.isBefore(from))
        .map((e) => e.key)
        .toList()
      ..sort();
    return dates.isEmpty ? null : dates.first;
  }
}

Forecast computeForecast(
  Set<DateTime> periodDays, {
  int defaultCycle = 28,
  int defaultPeriod = 5,
  DateTime? now,
  int count = 12,
}) {
  final t = dateOnly(now ?? DateTime.now());
  final days = periodDays.map(dateOnly).toSet();
  final periods = groupPeriods(days);

  final cycles = <int>[
    for (var i = 1; i < periods.length; i++)
      daysBetween(periods[i - 1].start, periods[i].start)
  ].where((c) => c >= 18 && c <= 60).toList();
  final recentCycles =
      cycles.length > 6 ? cycles.sublist(cycles.length - 6) : cycles;
  final cycle = recentCycles.isEmpty ? defaultCycle : _avg(recentCycles);

  // Длина периода: по завершённым периодам (последний может ещё идти)
  final finished = periods.where((p) => p.end.isBefore(addDays(t, -1))).toList();
  final lens = finished.map((p) => p.length).where((l) => l >= 1 && l <= 12).toList();
  final recentLens = lens.length > 6 ? lens.sublist(lens.length - 6) : lens;
  final rawLen = recentLens.isEmpty ? defaultPeriod : _avg(recentLens);
  final int periodLen = rawLen < 1 ? 1 : (rawLen > 12 ? 12 : rawLen);

  final marks = <DateTime, DayKind>{};
  final predicted = <Period>[];
  var delay = 0;

  if (periods.isNotEmpty) {
    final last = periods.last;
    var next = addDays(last.start, cycle);
    if (t.isAfter(next) && !last.contains(t)) {
      delay = daysBetween(next, t);
      next = t;
    }
    // Фертильное окно текущего цикла (если задержки нет)
    final cycleStarts = <DateTime>[if (delay == 0) last.start];
    for (var i = 0; i < count; i++) {
      final s = addDays(next, i * cycle);
      final p = Period(s, addDays(s, periodLen - 1));
      predicted.add(p);
      cycleStarts.add(s);
      for (var d = p.start; !d.isAfter(p.end); d = addDays(d, 1)) {
        marks[d] = DayKind.predicted;
      }
    }
    for (final s in cycleStarts) {
      final ov = addDays(s, cycle - 14);
      for (var k = -5; k <= 1; k++) {
        final d = addDays(ov, k);
        if (marks[d] != DayKind.predicted) {
          marks[d] = k == 0 ? DayKind.ovulation : DayKind.fertile;
        }
      }
    }
  }

  return Forecast._(periods, cycle, periodLen, recentCycles.isNotEmpty,
      predicted, delay, marks, days);
}
