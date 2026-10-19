// Логика цикла: группировка отмеченных дней в периоды и прогноз.
// Все даты — DateTime.utc(год, месяц, день) без времени.
import 'dart:math' as math;

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

/// Номер дня от 1970-01-01 (для виджета).
int epochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

class Period {
  final DateTime start;
  final DateTime end;
  const Period(this.start, this.end);
  int get length => daysBetween(start, end) + 1;
  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

enum DayKind { none, period, predicted, fertile, ovulation }

enum Fertility { low, medium, high }

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

/// Лютеиновая фаза: овуляция за столько дней до следующих месячных.
const kLuteal = 14;

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
    final w = math.pow(kDecay, xs.length - 1 - i).toDouble();
    sw += w;
    sx += w * xs[i];
  }
  final mean = sx / sw;
  var sv = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final w = math.pow(kDecay, xs.length - 1 - i).toDouble();
    sv += w * (xs[i] - mean) * (xs[i] - mean);
  }
  final sd = xs.length < 3 ? 0.0 : math.sqrt(sv / sw);
  return (mean: mean.round(), spread: sd.round());
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

/// Сведения об одном дне: день цикла, сколько до овуляции и т.д.
class DayInfo {
  final DateTime cycleStart;
  final int cycleDay; // с 1
  final int? periodDay; // N-й день месячных (по отметкам)
  final bool predictedPeriod;
  final int? daysToPeriod;
  final int? daysToFertile;
  final int? daysToOvulation;
  final DateTime? ovulation;
  final Fertility fertility;
  final DayKind kind;
  final bool pms;

  const DayInfo({
    required this.cycleStart,
    required this.cycleDay,
    required this.periodDay,
    required this.predictedPeriod,
    required this.daysToPeriod,
    required this.daysToFertile,
    required this.daysToOvulation,
    required this.ovulation,
    required this.fertility,
    required this.kind,
    required this.pms,
  });
}

/// Строка истории: период и длина цикла (null — текущий цикл).
class CycleRow {
  final Period period;
  final int? length;
  const CycleRow(this.period, this.length);
}

class Forecast {
  final List<Period> periods; // прошлые, по возрастанию
  final int cycleLength;
  final int periodLength;
  final int cyclesUsed; // по скольким циклам посчитано (0 — предварительно)
  final int cycleSpread; // ± дней (0 — неизвестно)
  final List<Period> predicted;
  final int delay; // дней задержки (0 — нет)
  final DateTime now;
  final Map<DateTime, DayKind> _marks;
  final Set<DateTime> _periodDays;
  final Set<DateTime> pmsDays;

  Forecast._(
      this.periods,
      this.cycleLength,
      this.periodLength,
      this.cyclesUsed,
      this.cycleSpread,
      this.predicted,
      this.delay,
      this.now,
      this._marks,
      this._periodDays,
      this.pmsDays);

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

  bool isPms(DateTime d) => pmsDays.contains(dateOnly(d));

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

  /// Ближайшее начало фертильного окна не раньше [from].
  DateTime? nextFertileStart(DateTime from) {
    final ov = nextOvulation(from);
    if (ov == null) return null;
    final s = addDays(ov, -5);
    return s.isBefore(from) ? null : s;
  }

  /// История циклов, новые сверху.
  List<CycleRow> get rows => [
        for (var i = periods.length - 1; i >= 0; i--)
          CycleRow(
              periods[i],
              i + 1 < periods.length
                  ? daysBetween(periods[i].start, periods[i + 1].start)
                  : null)
      ];

  /// Сведения о любом дне, начиная с первых отмеченных месячных.
  DayInfo? info(DateTime d) {
    d = dateOnly(d);
    if (periods.isEmpty || d.isBefore(periods.first.start)) return null;
    final starts = <DateTime>[
      ...periods.map((p) => p.start),
      ...predicted.map((p) => p.start),
    ];
    DateTime s = starts.first;
    DateTime? next;
    for (final x in starts) {
      if (!x.isAfter(d)) {
        s = x;
      } else {
        next = x;
        break;
      }
    }
    // Ожидаемый конец цикла: фактическое начало следующего или прогноз
    final actualIdx = periods.indexWhere((p) => p.start == s);
    DateTime nominalNext;
    if (actualIdx >= 0 && actualIdx + 1 < periods.length) {
      nominalNext = periods[actualIdx + 1].start;
    } else {
      nominalNext = addDays(s, cycleLength);
    }
    final ov = addDays(nominalNext, -kLuteal);
    final kind = kindOf(d);
    int? periodDay;
    if (kind == DayKind.period) {
      final p = periods.where((p) => p.contains(d));
      if (p.isNotEmpty) periodDay = daysBetween(p.first.start, d) + 1;
    }
    Fertility fert = Fertility.low;
    final toOv = daysBetween(d, ov);
    if (kind != DayKind.period && kind != DayKind.predicted) {
      if (toOv >= 0 && toOv <= 2) {
        fert = Fertility.high;
      } else if ((toOv >= 3 && toOv <= 5) || toOv == -1) {
        fert = Fertility.medium;
      }
    }
    final fertStart = addDays(ov, -5);
    return DayInfo(
      cycleStart: s,
      cycleDay: daysBetween(s, d) + 1,
      periodDay: periodDay,
      predictedPeriod: kind == DayKind.predicted,
      daysToPeriod: next == null ? null : daysBetween(d, next),
      daysToFertile: d.isBefore(fertStart) ? daysBetween(d, fertStart) : null,
      daysToOvulation: d.isBefore(ov) ? toOv : null,
      ovulation: ov,
      fertility: fert,
      kind: kind,
      pms: isPms(d),
    );
  }

  /// Длины последних [n] завершённых циклов (по порядку).
  List<int> recentCycleLengths([int n = 10]) {
    final l = cycleLengths;
    return l.length > n ? l.sublist(l.length - n) : l;
  }

  /// Длины последних [n] месячных (без текущих, если они ещё идут).
  List<int> recentPeriodLengths([int n = 10]) {
    final done =
        periods.where((p) => p.end.isBefore(addDays(now, -1))).toList();
    final l = done.map((p) => p.length).toList();
    return l.length > n ? l.sublist(l.length - n) : l;
  }

  /// Цикл регулярный, если разброс последних циклов не больше 7 дней.
  bool? get regular {
    final l = recentCycleLengths();
    if (l.length < 3) return null;
    return l.reduce(math.max) - l.reduce(math.min) <= 7;
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
  final pms = <DateTime>{};
  var delay = 0;

  void markFertile(DateTime ov) {
    for (var k = -5; k <= 1; k++) {
      final d = addDays(ov, k);
      if (days.contains(d)) continue;
      if (marks[d] == DayKind.predicted) continue;
      marks[d] = k == 0 ? DayKind.ovulation : DayKind.fertile;
    }
  }

  // Прошлые циклы: овуляция за 14 дней до фактического начала следующих
  for (var i = 0; i + 1 < periods.length; i++) {
    final len = daysBetween(periods[i].start, periods[i + 1].start);
    if (len < 18 || len > 60) continue;
    markFertile(addDays(periods[i + 1].start, -kLuteal));
  }

  if (periods.isNotEmpty) {
    final last = periods.last;
    var next = addDays(last.start, cycle);
    if (t.isAfter(next) && !last.contains(t)) {
      delay = daysBetween(next, t);
      next = t;
    }
    final cycleStarts = <DateTime>[if (delay == 0) last.start];
    for (var i = 0; i < count; i++) {
      final s = addDays(next, i * cycle);
      final p = Period(s, addDays(s, periodLen - 1));
      predicted.add(p);
      cycleStarts.add(s);
      for (var d = p.start; !d.isAfter(p.end); d = addDays(d, 1)) {
        if (!days.contains(d)) marks[d] = DayKind.predicted;
      }
      for (var k = 1; k <= 3; k++) {
        final d = addDays(s, -k);
        if (!days.contains(d)) pms.add(d);
      }
    }
    for (final s in cycleStarts) {
      markFertile(addDays(s, cycle - kLuteal));
    }
  }

  return Forecast._(periods, cycle, periodLen, cycles.length, spread,
      predicted, delay, t, marks, days, pms);
}

/// Беременность по первому дню последних месячных (ПДМ).
class Pregnancy {
  final DateTime lmp;
  const Pregnancy(this.lmp);

  /// Предполагаемая дата родов: ПДМ + 280 дней.
  DateTime get due => addDays(lmp, 280);

  static Pregnancy fromDue(DateTime due) => Pregnancy(addDays(due, -280));

  int daysPregnant(DateTime d) => daysBetween(lmp, d);
  int week(DateTime d) => daysPregnant(d) ~/ 7;
  int dayOfWeek(DateTime d) => daysPregnant(d) % 7;
  int daysLeft(DateTime d) => daysBetween(d, due);
  int trimester(DateTime d) {
    final w = week(d);
    return w < 13 ? 1 : (w < 27 ? 2 : 3);
  }
}
