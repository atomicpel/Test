import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'cycle_ring.dart';
import 'store.dart';
import 'ui_common.dart';

class CalendarPage extends StatefulWidget {
  final Store store;
  const CalendarPage({super.key, required this.store});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const _base = 1200; // страница текущего месяца
  final _pages = PageController(initialPage: _base);
  int _page = _base;

  DateTime _monthOf(int page) {
    final t = today();
    return DateTime.utc(t.year, t.month + (page - _base), 1);
  }

  void _go(int page) => _pages.animateToPage(page,
      duration: motion(context, 380), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final f = store.forecast;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: store.sync,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(children: [
                  Text('Мой цикл', style: theme.appBarTheme.titleTextStyle),
                  const Spacer(),
                  _SyncIndicator(store: store),
                ]),
              ),
              const SizedBox(height: 8),
              Center(child: CycleRing(forecast: f)),
              const SizedBox(height: 18),
              _Status(store: store, f: f),
              const SizedBox(height: 26),
              _calendarPanel(context, f),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendarPanel(BuildContext context, Forecast f) {
    final theme = Theme.of(context);
    final month = _monthOf(_page);
    final off = _page != _base;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: motion(context, 260),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                          begin: const Offset(0, 0.35), end: Offset.zero)
                      .animate(a),
                  child: child,
                ),
              ),
              layoutBuilder: (cur, prev) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...prev, if (cur != null) cur]),
              child: Text(
                '${monthsNom[month.month - 1]} ${month.year}',
                key: ValueKey(_page),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          AnimatedScale(
            scale: off ? 1 : 0,
            duration: motion(context, 200),
            curve: Curves.easeOutBack,
            child: TextButton(
              onPressed: off ? () => _go(_base) : null,
              child: const Text('Сегодня'),
            ),
          ),
          IconButton(
              tooltip: 'Предыдущий месяц',
              onPressed: () => _go(_page - 1),
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              tooltip: 'Следующий месяц',
              onPressed: () => _go(_page + 1),
              icon: const Icon(Icons.chevron_right)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(weekdaysShort[i],
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: i >= 5
                            ? theme.colorScheme.primary.withValues(alpha: 0.8)
                            : theme.colorScheme.onSurfaceVariant)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 6 * _cellH,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: (p) {
              HapticFeedback.selectionClick();
              setState(() => _page = p);
            },
            itemBuilder: (context, p) => _MonthGrid(
              month: _monthOf(p),
              store: widget.store,
              f: f,
              onTap: (d) => _openDay(context, d),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _Legend(),
      ]),
    );
  }

  Future<void> _openDay(BuildContext context, DateTime d) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DaySheet(store: widget.store, day: d),
    );
  }
}

const _cellH = 50.0;

class _SyncIndicator extends StatefulWidget {
  final Store store;
  const _SyncIndicator({required this.store});

  @override
  State<_SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<_SyncIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (!store.syncConfigured) return const SizedBox(height: 48);
    if (store.syncing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
    final err = store.syncError;
    final theme = Theme.of(context);
    return IconButton(
      tooltip: store.syncing ? 'Синхронизация' : (err ?? 'Синхронизировано'),
      onPressed: store.syncing
          ? null
          : () async {
              await store.sync();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(store.syncError ?? 'Синхронизировано')));
              }
            },
      icon: AnimatedSwitcher(
        duration: motion(context, 200),
        child: store.syncing
            ? RotationTransition(
                key: const ValueKey('s'),
                turns: Tween(begin: 0.0, end: -1.0).animate(_spin),
                child: const Icon(Icons.sync))
            : Icon(
                err == null ? Icons.cloud_done_outlined : Icons.cloud_off,
                key: ValueKey(err == null),
                color: err == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final Store store;
  final Forecast f;
  const _Status({required this.store, required this.f});

  @override
  Widget build(BuildContext context) {
    final t = today();
    final theme = Theme.of(context);
    final last = f.last;
    final pm = f.cycleSpread > 0 ? ', ±${daysWord(f.cycleSpread)}' : '';
    final inPeriod = last != null && last.contains(t);
    final lastEnd = last?.end ?? t;

    String big;
    String small;
    if (last == null) {
      big = 'Отметьте первые месячные';
      small = 'Нажмите «Начались сегодня» или выберите день в календаре. '
          'Прошлые периоды добавляются во вкладке «История».';
    } else if (last.contains(t)) {
      big = 'Месячные, ${daysBetween(last.start, t) + 1}-й день';
      small = 'Следующие ожидаются ${fmtDate(f.nextStart!)}$pm';
    } else if (f.delay > 0) {
      big = 'Задержка ${daysWord(f.delay)}';
      small = 'Ожидались ${fmtDate(addDays(last.start, f.cycleLength))}';
    } else {
      final left = daysBetween(t, f.nextStart!);
      big = left == 0
          ? 'Месячные ожидаются сегодня'
          : 'До месячных ${daysWord(left)}';
      small = 'Ожидаются ${fmtDate(f.nextStart!)}$pm';
    }

    final kind = f.kindOf(t);
    final ov = f.nextOvulation(t);
    String? fertile;
    if (kind == DayKind.ovulation) {
      fertile = 'Сегодня день овуляции';
    } else if (kind == DayKind.fertile) {
      fertile = 'Сегодня фертильный день';
    } else if (ov != null && last != null && !inPeriod) {
      fertile = 'Овуляция около ${fmtDate(ov)}';
    }

    String? basis;
    if (last != null) {
      basis = f.tentative
          ? 'Прогноз предварительный: уточнится после следующих месячных'
          : 'Посчитано по ${f.cyclesUsed} '
              '${plural(f.cyclesUsed, 'циклу', 'циклам', 'циклам')}: '
              'цикл ${daysWord(f.cycleLength)}, месячные ${daysWord(f.periodLength)}';
    }

    Widget fade(Widget child, Object key) => AnimatedSwitcher(
          duration: motion(context, 280),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                  .animate(a),
              child: c,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(key), child: child),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(children: [
        fade(
          Text(big,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall),
          big,
        ),
        const SizedBox(height: 8),
        Text(small,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (fertile != null) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: Palette.fertile, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(fertile,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: motion(context, 240),
          transitionBuilder: (c, a) => FadeTransition(
              opacity: a, child: ScaleTransition(scale: a, child: c)),
          child: !inPeriod
              ? FilledButton.icon(
                  key: const ValueKey('start'),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
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
              : OutlinedButton.icon(
                  key: const ValueKey('end'),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    for (var d = addDays(t, 1);
                        !d.isAfter(lastEnd);
                        d = addDays(d, 1)) {
                      store.setDay(d, period: false);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Отмечено: закончились сегодня')));
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Закончились сегодня'),
                ),
        ),
        if (basis != null) ...[
          const SizedBox(height: 14),
          Text(basis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ]),
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
    final t = today();
    final lead = month.weekday - 1; // понедельник — первый
    final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
    Widget cell(int r, int c) {
      final day = r * 7 + c - lead + 1;
      if (day < 1 || day > daysInMonth) return const SizedBox();
      final d = DateTime.utc(month.year, month.month, day);
      return _DayCell(
        day: day,
        kind: f.kindOf(d),
        isToday: d == t,
        hasNote: store.noteFor(d).isNotEmpty,
        onTap: () => onTap(d),
      );
    }

    return Column(children: [
      for (var r = 0; r < 6; r++)
        SizedBox(
          height: _cellH,
          child: Row(children: [
            for (var c = 0; c < 7; c++) Expanded(child: cell(r, c)),
          ]),
        ),
    ]);
  }
}

/// Ячейка дня. При смене типа дня (например, отметили месячные)
/// ячейка коротко «пульсирует», чтобы было видно, что изменилось.
class _DayCell extends StatefulWidget {
  final int day;
  final DayKind kind;
  final bool isToday;
  final bool hasNote;
  final VoidCallback onTap;
  const _DayCell(
      {required this.day,
      required this.kind,
      required this.isToday,
      required this.hasNote,
      required this.onTap});

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360));

  @override
  void didUpdateWidget(_DayCell old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind &&
        MediaQuery.maybeDisableAnimationsOf(context) != true) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final kind = widget.kind;
    final color = kindColor(kind);

    Color fill = Colors.transparent;
    Border? border;
    Color textColor = fg;
    switch (kind) {
      case DayKind.period:
        fill = Palette.period;
        textColor = Colors.white;
      case DayKind.ovulation:
        fill = Palette.ovulation;
        textColor = Colors.white;
      case DayKind.predicted:
        fill = color!.withValues(alpha: 0.16);
        border = Border.all(color: color, width: 2);
      case DayKind.fertile:
        fill = Palette.fertileFill(theme.brightness);
        textColor = Palette.fertileText(theme.brightness);
      case DayKind.none:
        break;
    }
    if (widget.isToday && border == null) {
      border = Border.all(
          color: kind == DayKind.period || kind == DayKind.ovulation
              ? theme.colorScheme.surface
              : fg,
          width: 2);
    }

    return Semantics(
      button: true,
      label: '${widget.day}${widget.isToday ? ', сегодня' : ''}',
      child: InkResponse(
        onTap: widget.onTap,
        radius: 24,
        child: AnimatedBuilder(
          animation: _pop,
          builder: (context, child) => Transform.scale(
            scale: 1 + 0.18 * math.sin(math.pi * _pop.value),
            child: child,
          ),
          child: Stack(alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: motion(context, 240),
              curve: Curves.easeOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: fill, shape: BoxShape.circle, border: border),
              alignment: Alignment.center,
              child: AnimatedDefaultTextStyle(
                duration: motion(context, 240),
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: textColor,
                  fontWeight:
                      widget.isToday ? FontWeight.w700 : FontWeight.w500,
                  height: 1,
                ),
                child: Text('${widget.day}'),
              ),
            ),
            if (widget.hasNote)
              Positioned(
                bottom: 2,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.55),
                      shape: BoxShape.circle),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(String text, BoxDecoration deco) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 14, height: 14, decoration: deco),
            const SizedBox(width: 6),
            Text(text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        item('Месячные',
            const BoxDecoration(color: Palette.period, shape: BoxShape.circle)),
        item(
            'Прогноз',
            BoxDecoration(
                color: Palette.predicted.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Palette.predicted, width: 2))),
        item(
            'Фертильные',
            BoxDecoration(
                color: Palette.fertileFill(theme.brightness),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Palette.fertile.withValues(alpha: 0.6), width: 1))),
        item('Овуляция',
            const BoxDecoration(color: Palette.ovulation, shape: BoxShape.circle)),
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
    final theme = Theme.of(context);
    final isFuture = d.isAfter(today());
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = store.forecast;
        final len = f.periodLength;
        final on = store.isPeriod(d);
        final kind = f.kindOf(d);
        final hint = switch (kind) {
          DayKind.predicted => 'По прогнозу — месячные',
          DayKind.fertile => 'По прогнозу — фертильный день',
          DayKind.ovulation => 'По прогнозу — день овуляции',
          _ => null,
        };
        final mq = MediaQuery.of(context);
        final bottom = math.max(mq.viewInsets.bottom, mq.viewPadding.bottom);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fmtDate(d, year: d.year != today().year),
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                  d == today()
                      ? 'сегодня, ${weekdaysFull[d.weekday - 1]}'
                      : weekdaysFull[d.weekday - 1],
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (hint != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: kindColor(kind), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(hint, style: theme.textTheme.bodyMedium),
                ]),
              ],
              const SizedBox(height: 18),
              _PeriodToggle(
                on: on,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  store.setDay(d, period: v);
                },
              ),
              AnimatedSize(
                duration: motion(context, 220),
                curve: Curves.easeOut,
                child: !on && !isFuture
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            store.markPeriod(d, len);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.water_drop_outlined),
                          label: Text('Начались в этот день: ${daysWord(len)}'),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _note,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Заметка: самочувствие, лекарства…',
                ),
              ),
              const SizedBox(height: 16),
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

/// Крупный переключатель «Месячные»: заливается гранатом при включении.
class _PeriodToggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _PeriodToggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = on ? Colors.white : theme.colorScheme.onSurface;
    final dur = motion(context, 260);
    return Semantics(
      toggled: on,
      label: 'Месячные в этот день',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(!on),
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: on ? Palette.period : theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              AnimatedSwitcher(
                duration: dur,
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  on ? Icons.water_drop : Icons.water_drop_outlined,
                  key: ValueKey(on),
                  color: on ? Colors.white : Palette.period,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: dur,
                  style: theme.textTheme.titleMedium!.copyWith(color: fg),
                  child: const Text('Месячные в этот день'),
                ),
              ),
              AnimatedContainer(
                duration: dur,
                curve: Curves.easeOut,
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(3),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: on
                      ? Colors.white.withValues(alpha: 0.3)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: on
                        ? Colors.white
                        : theme.colorScheme.surfaceContainerLow,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
