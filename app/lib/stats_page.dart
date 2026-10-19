import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'charts.dart';
import 'cycle.dart';
import 'day_entry.dart';
import 'history_edit_page.dart';
import 'report_page.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

class StatsPage extends StatelessWidget {
  final Store store;
  final void Function(DateTime) onOpenDay;
  const StatsPage({super.key, required this.store, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            const TabBar(tabs: [
              Tab(text: 'Циклы'),
              Tab(text: 'Графики'),
              Tab(text: 'Хронология'),
            ]),
            Expanded(
              child: TabBarView(children: [
                _CyclesTab(store: store),
                _ChartsTab(store: store, onOpenDay: onOpenDay),
                _TimelineTab(store: store, onOpenDay: onOpenDay),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

String _rangeLabel(List<int> l) {
  if (l.isEmpty) return '—';
  final a = l.reduce(math.min), b = l.reduce(math.max);
  return a == b ? daysWord(a) : '$a–$b ${plural(b, 'день', 'дня', 'дней')}';
}

class _Status extends StatelessWidget {
  final bool ok;
  final String okText;
  final String badText;
  const _Status({required this.ok, required this.okText, required this.badText});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ok ? Icons.check_circle : Icons.error,
          size: 22, color: ok ? const Color(0xFF4CAF7A) : const Color(0xFFE5B53A)),
      const SizedBox(width: 6),
      Text(ok ? okText : badText,
          style: const TextStyle(
              fontFamily: kFont, fontWeight: FontWeight.w700, fontSize: 15)),
    ]);
  }
}

class _CyclesTab extends StatefulWidget {
  final Store store;
  const _CyclesTab({required this.store});

  @override
  State<_CyclesTab> createState() => _CyclesTabState();
}

class _CyclesTabState extends State<_CyclesTab>
    with AutomaticKeepAliveClientMixin {
  int _show = 6;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final f = widget.store.forecast;
        final rows = f.rows;
        final cycles = f.recentCycleLengths();
        final periods = f.recentPeriodLengths();
        final t = today();
        final cards = <Widget>[];

        if (f.periods.isEmpty) {
          cards.add(AppCard(
            child: Column(children: [
              const Text('📅', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text('Здесь появится статистика',
                  style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Отметьте месячные или перенесите историю — кнопка ниже.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => HistoryEditPage(store: widget.store))),
                child: const Text('Добавить прошлые месячные'),
              ),
            ]),
          ));
        } else {
          final lastCycle = cycles.isEmpty ? null : cycles.last;
          final lastPeriod = periods.isEmpty ? null : periods.last;
          cards.add(Row(children: [
            Expanded(
              child: _SmallCard(
                title: 'Последний цикл',
                icon: '🔄',
                value: lastCycle == null ? '—' : daysWord(lastCycle),
                status: lastCycle == null
                    ? null
                    : _Status(
                        ok: lastCycle >= 21 && lastCycle <= 35,
                        okText: 'НОРМА',
                        badText: 'ВНЕ НОРМЫ'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SmallCard(
                title: 'Последние месячные',
                icon: '🩸',
                value: lastPeriod == null ? '—' : daysWord(lastPeriod),
                status: lastPeriod == null
                    ? null
                    : _Status(
                        ok: lastPeriod >= 2 && lastPeriod <= 7,
                        okText: 'НОРМА',
                        badText: 'ВНЕ НОРМЫ'),
              ),
            ),
          ]));
          if (cycles.length >= 2) {
            cards.add(_ChartCard(
              title: 'Длительность цикла',
              chart: BarChart(
                values: cycles,
                barColor: theme.colorScheme.onSurface.withValues(alpha: 0.18),
                lineColor: theme.colorScheme.primary,
                average: f.cycleLength,
                averageLabel: daysWord(f.cycleLength),
              ),
              footer: _rangeLabel(cycles),
              status: f.regular == null
                  ? null
                  : _Status(
                      ok: f.regular!, okText: 'РЕГУЛЯРНЫЙ', badText: 'НЕРЕГУЛЯРНЫЙ'),
            ));
          }
          if (periods.length >= 2) {
            cards.add(_ChartCard(
              title: 'Длительность месячных',
              chart: BarChart(
                values: periods,
                barColor: Palette.period.withValues(alpha: 0.55),
                lineColor: theme.colorScheme.primary,
                average: f.periodLength,
                averageLabel: daysWord(f.periodLength),
              ),
              footer: _rangeLabel(periods),
              status: _Status(
                  ok: periods.every((x) => x >= 2 && x <= 8),
                  okText: 'НОРМА',
                  badText: 'ЕСТЬ ОТКЛОНЕНИЯ'),
            ));
          }
          if (widget.store.pregnancy == null) {
            cards.add(AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text('Вероятность забеременеть',
                          style: theme.textTheme.titleLarge)),
                  Text('7 дней',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ]),
                const SizedBox(height: 16),
                FertilityBars(days: [
                  for (var i = 0; i < 7; i++)
                    MapEntry(addDays(t, i),
                        f.info(addDays(t, i))?.fertility ?? Fertility.low)
                ]),
              ]),
            ));
          }
          cards.add(AppCard(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ReportPage(store: widget.store))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Отчёт для врача', style: theme.textTheme.titleLarge),
                    const SizedBox(width: 8),
                    Icon(Icons.favorite, color: theme.colorScheme.primary, size: 22),
                  ]),
                  const SizedBox(height: 6),
                  Text('Циклы, симптомы, настроение, обильность и лекарства — одной страницей.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
                ]),
              ),
              const Text('🩺', style: TextStyle(fontSize: 46)),
            ]),
          ));
          // История циклов
          final maxDays = math.max(
              35,
              rows.take(_show).fold<int>(
                  0, (m, r) => math.max(m, r.length ?? daysBetween(r.period.start, t) + 1)));
          cards.add(AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('История циклов', style: theme.textTheme.titleLarge)),
                TextButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => HistoryEditPage(store: widget.store))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Редактировать'),
                    Icon(Icons.chevron_right),
                  ]),
                ),
              ]),
              Divider(color: c.cardBorder),
              const SizedBox(height: 8),
              Wrap(spacing: 14, runSpacing: 8, children: [
                const DotLabel(Palette.period, 'месячные'),
                const DotLabel(Palette.fertile, 'фертильный день'),
                DotLabel(Palette.ovulation(theme.brightness), 'день овуляции'),
              ]),
              const SizedBox(height: 10),
              for (final r in rows.take(_show)) ...[
                Divider(color: c.cardBorder, height: 28),
                _CycleRowView(row: r, f: f, maxDays: maxDays),
              ],
              if (rows.length > _show)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _show += 12),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Смотреть ещё'),
                      Icon(Icons.expand_more),
                    ]),
                  ),
                ),
            ]),
          ));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            for (var i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Stagger(index: i, child: cards[i]),
              ),
          ],
        );
      },
    );
  }
}

class _SmallCard extends StatelessWidget {
  final String title;
  final String icon;
  final String value;
  final Widget? status;
  const _SmallCard(
      {required this.title, required this.icon, required this.value, this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.15))),
          Text(icon, style: const TextStyle(fontSize: 26)),
        ]),
        const SizedBox(height: 10),
        Text(value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 28)),
        if (status != null) ...[const SizedBox(height: 8), status!],
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget chart;
  final String footer;
  final Widget? status;
  const _ChartCard(
      {required this.title, required this.chart, required this.footer, this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        chart,
        Divider(color: c.cardBorder, height: 30),
        Row(children: [
          Expanded(
              child: Text(footer,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))),
          if (status != null) status!,
        ]),
      ]),
    );
  }
}

class _CycleRowView extends StatelessWidget {
  final CycleRow row;
  final Forecast f;
  final int maxDays;
  const _CycleRowView({required this.row, required this.f, required this.maxDays});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final t = today();
    final p = row.period;
    final len = row.length ?? daysBetween(p.start, t) + 1;
    final end = row.length == null ? null : addDays(p.start, row.length! - 1);
    String d(DateTime x) => '${x.day} ${monthsShort[x.month - 1]}';
    final kinds = [for (var i = 0; i < len; i++) f.kindOf(addDays(p.start, i))];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(end == null ? '${d(p.start)} — сейчас' : '${d(p.start)} — ${d(end)}',
          style: theme.textTheme.titleMedium),
      const SizedBox(height: 10),
      DayStrip(kinds: kinds, maxDays: maxDays),
      const SizedBox(height: 8),
      Text('${daysWord(p.length)} — месячные, ${daysWord(len)} — цикл',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
    ]);
  }
}

// ---------------------------------------------------------------- графики

class _ChartsTab extends StatelessWidget {
  final Store store;
  final void Function(DateTime) onOpenDay;
  const _ChartsTab({required this.store, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final logs = store.loggedDays;
        final t = today();
        final recent = logs.where((e) => daysBetween(e.key, t) <= 90).toList();
        Map<String, int> count(List<String> Function(DayData) f) {
          final m = <String, int>{};
          for (final e in recent) {
            for (final id in f(e.value)) {
              m[id] = (m[id] ?? 0) + 1;
            }
          }
          return m;
        }

        List<({String emoji, String label, int count})> top(
            Map<String, int> m, List<Opt> base) {
          final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return [
            for (final e in l.take(6))
              (
                emoji: optById(base, e.key).emoji,
                label: optById(base, e.key).label,
                count: e.value
              )
          ];
        }

        final sym = top(count((d) => d.symptoms), symptomOptions);
        final mood = top(count((d) => d.moods), moodOptions);
        final intim = top(count((d) => d.intimacy), intimacyOptions);
        final meds = top(count((d) => d.meds), const []);
        final temps = [
          for (final e in logs.reversed)
            if (e.value.temp != null && daysBetween(e.key, t) <= 120)
              MapEntry(e.key, e.value.temp!)
        ];
        final weights = [
          for (final e in logs.reversed)
            if (e.value.weight != null) MapEntry(e.key, e.value.weight!)
        ];
        final flows = [
          for (final e in logs.reversed)
            if (e.value.flow > 0 && daysBetween(e.key, t) <= 60) e
        ];
        final notes = store.notes.take(3).toList();

        final theme = Theme.of(context);
        Widget empty(String title) => _EmptyChart(
            title: title, onLog: () => onOpenDay(DateTime.now()));

        final cards = <Widget>[
          if (store.calShow('intimacy'))
            intim.isEmpty
                ? empty('Сексуальная активность')
                : AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Сексуальная активность', style: theme.textTheme.titleLarge),
                      Text('за 3 месяца',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.of(context).muted)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 18, runSpacing: 12, children: [
                        for (final e in intim)
                          Column(children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(e.emoji, style: const TextStyle(fontSize: 34)),
                              Text(' ×${e.count}', style: theme.textTheme.headlineSmall),
                            ]),
                            SizedBox(
                                width: 110,
                                child: Text(e.label,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall)),
                          ]),
                      ]),
                    ]),
                  ),
          sym.isEmpty
              ? empty('Симптомы')
              : _FreqCard(title: 'Симптомы', items: sym, color: Palette.predicted),
          mood.isEmpty
              ? empty('Настроение')
              : _FreqCard(title: 'Настроение', items: mood, color: theme.colorScheme.primary),
          flows.isEmpty
              ? empty('Обильность месячных')
              : AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Обильность месячных', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    for (final e in flows.reversed.take(7))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(
                              width: 90,
                              child: Text(fmtDate(e.key),
                                  style: theme.textTheme.bodyMedium)),
                          FlowDrops(value: e.value.flow, size: 26),
                        ]),
                      ),
                  ]),
                ),
          temps.length < 2
              ? empty('Температура')
              : _LineCard(title: 'Температура, °C', points: temps, color: Palette.predicted, digits: 2),
          weights.length < 2
              ? empty('Вес')
              : _LineCard(title: 'Вес, кг', points: weights, color: theme.colorScheme.primary, digits: 1),
          meds.isEmpty
              ? empty('Медицинские препараты')
              : _FreqCard(title: 'Медицинские препараты', items: meds, color: Palette.fertile),
          notes.isEmpty
              ? empty('Заметки')
              : AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Заметки', style: theme.textTheme.titleLarge),
                    for (final n in notes) ...[
                      const SizedBox(height: 12),
                      Text(fmtDate(n.key, year: true),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.of(context).muted)),
                      Text(n.value, style: theme.textTheme.bodyLarge),
                    ],
                  ]),
                ),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            for (var i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Stagger(index: i, child: cards[i]),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String title;
  final VoidCallback onLog;
  const _EmptyChart({required this.title, required this.onLog});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Для этого графика требуется больше данных',
            style: theme.textTheme.bodyLarge?.copyWith(color: c.muted)),
        Divider(color: c.cardBorder, height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: onLog, child: const Text('Отметить')),
        ),
      ]),
    );
  }
}

class _FreqCard extends StatelessWidget {
  final String title;
  final List<({String emoji, String label, int count})> items;
  final Color color;
  const _FreqCard({required this.title, required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleLarge),
        Text('чаще всего за 3 месяца',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.of(context).muted)),
        const SizedBox(height: 8),
        FrequencyBars(items: items, color: color),
      ]),
    );
  }
}

class _LineCard extends StatelessWidget {
  final String title;
  final List<MapEntry<DateTime, double>> points;
  final Color color;
  final int digits;
  const _LineCard(
      {required this.title, required this.points, required this.color, required this.digits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = points.last;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
          Text(last.value.toStringAsFixed(digits).replaceAll('.', ','),
              style: theme.textTheme.headlineSmall?.copyWith(color: color)),
        ]),
        const SizedBox(height: 12),
        LineChart(points: points, color: color, digits: digits),
      ]),
    );
  }
}

// ---------------------------------------------------------------- хронология

class _TimelineTab extends StatelessWidget {
  final Store store;
  final void Function(DateTime) onOpenDay;
  const _TimelineTab({required this.store, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final days = store.loggedDays;
        final theme = Theme.of(context);
        if (days.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Здесь будут все отмеченные дни',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: AppColors.of(context).muted)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          itemCount: days.length,
          itemBuilder: (context, i) => Stagger(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TimelineCard(
                  store: store,
                  day: days[i].key,
                  data: days[i].value,
                  onTap: () => onOpenDay(days[i].key)),
            ),
          ),
        );
      },
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final Store store;
  final DateTime day;
  final DayData data;
  final VoidCallback onTap;
  const _TimelineCard(
      {required this.store, required this.day, required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final f = store.forecast;
    final info = f.info(day);
    final lines = <Widget>[];
    void line(String s, {Color? color}) => lines.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(s, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
        ));
    Color bar = c.cardBorder;
    if (info != null) {
      if (info.periodDay != null) {
        line('${info.periodDay}-й день месячных');
        bar = Palette.period;
      } else if (info.fertility != Fertility.low) {
        line(info.kind == DayKind.ovulation ? 'День овуляции' : 'Фертильное окно');
        line('Вероятность беременности от средней до высокой',
            color: theme.colorScheme.primary);
        bar = Palette.fertile;
      } else {
        line('Нефертильный день');
      }
      if (info.daysToFertile != null && info.fertility == Fertility.low) {
        line('${daysWord(info.daysToFertile!)} до фертильности');
      }
      if (info.daysToOvulation != null) {
        line('${daysWord(info.daysToOvulation!)} до овуляции');
      }
      line('${info.cycleDay}-й день цикла');
    }
    final items = <(String, Widget)>[];
    if (data.flow > 0) items.add(('Обильность месячных', FlowDrops(value: data.flow, size: 24)));
    Widget chips(List<String> ids, List<Opt> base) => Wrap(spacing: 10, runSpacing: 4, children: [
          for (final id in ids)
            Text('${optById(base, id).emoji} ${optById(base, id).label}',
                style: theme.textTheme.bodyLarge),
        ]);
    if (data.intimacy.isNotEmpty && store.calShow('intimacy')) {
      items.add(('Сексуальная активность', chips(data.intimacy, intimacyOptions)));
    }
    if (data.symptoms.isNotEmpty) items.add(('Симптомы', chips(data.symptoms, symptomOptions)));
    if (data.moods.isNotEmpty) items.add(('Настроение', chips(data.moods, moodOptions)));
    if (data.pill) items.add(('Контрацепция', Text('💊 Таблетка принята', style: theme.textTheme.bodyLarge)));
    if (data.meds.isNotEmpty) items.add(('Препараты', chips(data.meds, const [])));
    if (data.temp != null) {
      items.add(('Температура',
          Text('${data.temp!.toStringAsFixed(2).replaceAll('.', ',')} °C', style: theme.textTheme.bodyLarge)));
    }
    if (data.weight != null) {
      items.add(('Вес',
          Text('${data.weight!.toStringAsFixed(1).replaceAll('.', ',')} кг', style: theme.textTheme.bodyLarge)));
    }
    if (data.note.trim().isNotEmpty) items.add(('Заметка', Text(data.note, style: theme.textTheme.bodyLarge)));

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 74,
            child: Column(children: [
              Text(day.day.toString().padLeft(2, '0'),
                  style: theme.textTheme.displayLarge?.copyWith(fontSize: 46, fontWeight: FontWeight.w400)),
              Text(monthsShort[day.month - 1],
                  style: theme.textTheme.titleLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w500)),
              Text('${day.year}',
                  style: theme.textTheme.titleMedium?.copyWith(color: c.muted, fontWeight: FontWeight.w500)),
            ]),
          ),
          Container(
            width: 4,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...lines,
              for (final it in items) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 112,
                    child: Text(it.$1,
                        style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
                  ),
                  Expanded(child: it.$2),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
