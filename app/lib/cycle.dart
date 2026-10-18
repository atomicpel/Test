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

/// Стандартные значения — только пока записей не хватает для расчёта.
const kStdCycle = 28;
const kStdPeriod = 5;

/// Сколько последних циклов учитывать и насколько быстро «стареют» старые.
const kHistoryWindow = 12;
const kDecay = 0.8;

int _median(List<int> xs) {
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : ((s[m - 1] + s[m]) / 2).round();
}

/// Взвешенное среднее и разброс: самое свежее значение весит 1,
/// предыдущее 0.8, ещё раньше 0.64 и т.д.
({int mean, int spread}) _weighted(List<int> xs) {
  var sw = 0.0, sx = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final w = _pow(kDecay, xs.length - 1 - i);
    sw += w;
    sx += w * xs[i];
  }
  final mean = sx / sw;
  var sv = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final w = _pow(kDecay, xs.length - 1 - i);
    sv += w * (xs[i] - mean) * (xs[i] - mean);
  }
  final sd = xs.length < 3 ? 0.0 : _sqrt(sv / sw);
  return (mean: mean.round(), spread: sd.round());
}

double _pow(double b, int e) {
  var r = 1.0;
  for (var i = 0; i < e; i++) {
    r *= b;
  }
  return r;
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  var r = x;
  for (var i = 0; i < 30; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

/// Циклы, пригодные для расчёта: последние [kHistoryWindow], без выбросов.
/// Выброс — цикл, сильно отличающийся от медианы (например, когда
/// пропущена отметка и два цикла слились в один).
List<int> usableCycles(List<int> all) {
  final plausible = all.where((c) => c >= 15 && c <= 90).toList();
  final recent = plausible.length > kHistoryWindow
      ? plausible.sublist(plausible.length - kHistoryWindow)
      : plausible;
  if (recent.length < 3) return recent;
  final m = _median(recent);
  final tol = (m * 0.25).round() < 7 ? 7 : (m * 0.25).round();
  final ok = recent.where((c) => (c - m).abs() <= tol).toList();
  return ok.isEmpty ? recent : ok;
}

class Forecast {
  final List<Period> periods; // прошлые, по возрастанию
  final int cycleLength;
  final int periodLength;
  final int cyclesUsed; // по скольким циклам посчитано (0 — предварительно)
  final int cycleSpread; // ± дней (0 — неизвестно)
  final List<Period> predicted;
  final int delay; // дней задержки (0 — нет)
  final Map<DateTime, DayKind> _marks;
  final Set<DateTime> _periodDays;

  Forecast._(this.periods, this.cycleLength, this.periodLength,
      this.cyclesUsed, this.cycleSpread, this.predicted, this.delay,
      this._marks, this._periodDays);

  /// Прогноз предварительный: записей пока меньше двух периодов.
  bool get tentative => cyclesUsed == 0;
  bool get cycleFromHistory => !tentative;

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
  DateTime? now,
  int count = 12,
}) {
  final t = dateOnly(now ?? DateTime.now());
  final days = periodDays.map(dateOnly).toSet();
  final periods = groupPeriods(days);

  // Длина цикла — только из записей
  final all = <int>[
    for (var i = 1; i < periods.length; i++)
      daysBetween(periods[i - 1].start, periods[i].start)
  ];
  final cycles = usableCycles(all);
  final cw = cycles.isEmpty ? null : _weighted(cycles);
  final cycle = cw?.mean ?? kStdCycle;
  final spread = cw?.spread ?? 0;

  // Длина месячных — по завершённым периодам (последний может ещё идти)
  final finished =
      periods.where((p) => p.end.isBefore(addDays(t, -1))).toList();
  var lens = finished.map((p) => p.length).where((l) => l <= 12).toList();
  if (lens.length > kHistoryWindow) {
    lens = lens.sublist(lens.length - kHistoryWindow);
  }
  final rawLen = lens.isEmpty ? kStdPeriod : _weighted(lens).mean;
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
    // Овуляция — за 14 дней до следующих месячных, фертильно 5 дней до и 1 после
    for (final s in cycleStarts) {
      final ov = addDays(s, cycle - 14);
      for (var k = -5; k <= 1; k++) {
        final d = addDays(ov, k);
        if (marks[d] != DayKind.predicted && !days.contains(d)) {
          marks[d] = k == 0 ? DayKind.ovulation : DayKind.fertile;
        }
      }
    }
  }

  return Forecast._(periods, cycle, periodLen, cycles.length, spread,
      predicted, delay, marks, days);
}
