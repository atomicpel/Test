import 'package:flutter/material.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';

class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month; // первое число показываемого месяца

  @override
  void initState() {
    super.initState();
    final t = today();
    _month = DateTime.utc(t.year, t.month, 1);
  }

  void _shift(int m) =>
      setState(() => _month = DateTime.utc(_month.year, _month.month + m, 1));

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final f = store.forecast;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой цикл'),
        actions: [_SyncIndicator(store: store)],
      ),
      body: RefreshIndicator(
        onRefresh: store.sync,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            _StatusCard(store: store, f: f),
            const SizedBox(height: 12),
            GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) _shift(1);
                if (v > 200) _shift(-1);
              },
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  child: Column(children: [
                    Row(children: [
                      IconButton(
                          onPressed: () => _shift(-1),
                          icon: const Icon(Icons.chevron_left)),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            final t = today();
                            _month = DateTime.utc(t.year, t.month, 1);
                          }),
                          child: Text(
                            '${monthsNom[_month.month - 1]} ${_month.year}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                      IconButton(
                          onPressed: () => _shift(1),
                          icon: const Icon(Icons.chevron_right)),
                    ]),
                    _MonthGrid(
                      month: _month,
                      store: store,
                      f: f,
                      onTap: (d) => _openDay(context, d),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const _Legend(),
          ],
        ),
      ),
    );
  }

  Future<void> _openDay(BuildContext context, DateTime d) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DaySheet(store: widget.store, day: d),
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  final Store store;
  const _SyncIndicator({required this.store});

  @override
  Widget build(BuildContext context) {
    if (!store.syncConfigured) return const SizedBox();
    if (store.syncing) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final err = store.syncError;
    return IconButton(
      tooltip: err ?? 'Синхронизировано',
      onPressed: () async {
        await store.sync();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(store.syncError ?? 'Синхронизировано')));
        }
      },
      icon: Icon(err == null ? Icons.cloud_done_outlined : Icons.cloud_off,
          color: err == null ? null : Theme.of(context).colorScheme.error),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Store store;
  final Forecast f;
  const _StatusCard({required this.store, required this.f});

  @override
  Widget build(BuildContext context) {
    final t = today();
    final theme = Theme.of(context);
    String big;
    String small = '';
    final last = f.last;
    final pm = f.cycleSpread > 0 ? ' (±${daysWord(f.cycleSpread)})' : '';

    if (last == null) {
      big = 'Отметьте первый день месячных';
      small = 'Нажмите на день в календаре. Прошлые периоды можно добавить '
          'во вкладке «История».';
    } else if (last.contains(t)) {
      big = 'Месячные: ${daysBetween(last.start, t) + 1}-й день';
      small = 'Следующие ≈ ${fmtDate(f.nextStart!)}$pm';
    } else if (f.delay > 0) {
      big = 'Задержка ${daysWord(f.delay)}';
      small = 'Ожидались ${fmtDate(addDays(last.start, f.cycleLength))}';
    } else {
      final left = daysBetween(t, f.nextStart!);
      big = left == 0
          ? 'Месячные ожидаются сегодня'
          : 'До месячных ${daysWord(left)}';
      small = 'День цикла ${daysBetween(last.start, t) + 1} · '
          'ожидаются ${fmtDate(f.nextStart!)}$pm';
    }

    final kind = f.kindOf(t);
    final ov = f.nextOvulation(t);
    String? extra;
    if (kind == DayKind.ovulation) {
      extra = 'Сегодня — день овуляции (прогноз)';
    } else if (kind == DayKind.fertile) {
      extra = 'Сегодня фертильный день (прогноз)';
    } else if (ov != null && last != null) {
      extra = 'Овуляция ≈ ${fmtDate(ov)}';
    }

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(big,
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600)),
            if (small.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(small,
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            ],
            if (extra != null) ...[
              const SizedBox(height: 4),
              Text(extra,
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
            ],
            if (last != null) ...[
              const SizedBox(height: 10),
              Text(
                f.tentative
                    ? 'Прогноз предварительный — уточнится, когда отметите '
                        'начало следующих месячных или добавите прошлые '
                        'периоды в «Истории»'
                    : 'Цикл ${daysWord(f.cycleLength)} · месячные '
                        '${daysWord(f.periodLength)} · по '
                        '${f.cyclesUsed} ${plural(f.cyclesUsed, 'циклу', 'циклам', 'циклам')}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
            const SizedBox(height: 12),
            if (last == null || !last.contains(t))
              FilledButton.icon(
                onPressed: () {
                  store.markPeriod(t, f.periodLength);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Отмечено ${daysWord(f.periodLength)} с сегодняшнего. '
                        'Лишние дни можно снять в календаре.'),
                  ));
                },
                icon: const Icon(Icons.water_drop),
                label: const Text('Начались сегодня'),
              )
            else
              OutlinedButton.icon(
                onPressed: () {
                  // Закончились: снимаем отметки после сегодняшнего дня
                  for (var d = addDays(t, 1);
                      !d.isAfter(last.end);
                      d = addDays(d, 1)) {
                    store.setDay(d, period: false);
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Закончились сегодня'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Store store;
  final Forecast f;
  final void Function(DateTime) onTap;
  const _MonthGrid(
      {required this.month,
      required this.store,
      required this.f,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = today();
    final first = month;
    final lead = first.weekday - 1; // понедельник — первый
    final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(children: [
      Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(weekdaysShort[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: i >= 5
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      for (var r = 0; r < rows; r++)
        Row(children: [
          for (var c = 0; c < 7; c++)
            Expanded(child: _cell(context, r * 7 + c - lead + 1, daysInMonth, t)),
        ]),
    ]);
  }

  Widget _cell(BuildContext context, int day, int daysInMonth, DateTime t) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 46);
    final theme = Theme.of(context);
    final d = DateTime.utc(month.year, month.month, day);
    final kind = f.kindOf(d);
    final color = kindColor(kind);
    final isToday = d == t;
    final hasNote = store.noteFor(d).isNotEmpty;

    BoxDecoration deco;
    Color textColor = theme.colorScheme.onSurface;
    switch (kind) {
      case DayKind.period:
      case DayKind.ovulation:
        deco = BoxDecoration(color: color, shape: BoxShape.circle);
        textColor = Colors.white;
      case DayKind.predicted:
        deco = BoxDecoration(
            shape: BoxShape.circle,
            color: color!.withValues(alpha: 0.18),
            border: Border.all(color: color, width: 2));
      case DayKind.fertile:
        deco = BoxDecoration(
            shape: BoxShape.circle, color: color!.withValues(alpha: 0.35));
      case DayKind.none:
        deco = const BoxDecoration(shape: BoxShape.circle);
    }
    if (isToday && kind == DayKind.none) {
      deco = BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.primary, width: 2));
    }

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onTap(d),
      child: SizedBox(
        height: 46,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 38,
            height: 38,
            decoration: deco,
            alignment: Alignment.center,
            child: Text('$day',
                style: TextStyle(
                  color: textColor,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                  decoration: isToday && kind != DayKind.none
                      ? TextDecoration.underline
                      : null,
                  decorationColor: textColor,
                )),
          ),
          if (hasNote)
            Positioned(
              bottom: 1,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary, shape: BoxShape.circle),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String text, {bool outline = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: outline ? c.withValues(alpha: 0.18) : c,
                border: outline ? Border.all(color: c, width: 2) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(text, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        item(Palette.period, 'Месячные'),
        item(Palette.predicted, 'Прогноз', outline: true),
        item(Palette.fertile.withValues(alpha: 0.6), 'Фертильные дни'),
        item(Palette.ovulation, 'Овуляция'),
      ],
    );
  }
}

/// Нижняя панель для одного дня.
class DaySheet extends StatefulWidget {
  final Store store;
  final DateTime day;
  const DaySheet({super.key, required this.store, required this.day});

  @override
  State<DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<DaySheet> {
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.store.noteFor(widget.day));
  }

  @override
  void dispose() {
    final n = _note.text.trim();
    final store = widget.store;
    final day = widget.day;
    if (n != store.noteFor(day)) {
      // после закрытия панели, чтобы не перестраивать дерево во время dispose
      Future.microtask(() => store.setDay(day, note: n));
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final d = widget.day;
    final isFuture = d.isAfter(today());
    final len = store.forecast.periodLength;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final on = store.isPeriod(d);
        final mq = MediaQuery.of(context);
        final bottom = mq.viewInsets.bottom > mq.viewPadding.bottom
            ? mq.viewInsets.bottom
            : mq.viewPadding.bottom;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fmtDate(d, year: true),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Месячные в этот день'),
                value: on,
                onChanged: (v) => store.setDay(d, period: v),
              ),
              if (!on && !isFuture)
                OutlinedButton.icon(
                  onPressed: () {
                    store.markPeriod(d, len);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.water_drop_outlined),
                  label: Text('Начало месячных (отметить ${daysWord(len)})'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Заметка',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
      },
    );
  }
}
