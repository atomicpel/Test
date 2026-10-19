import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';

/// История: каждый цикл — полоска. Длина полоски — длина цикла,
/// гранатовая часть — месячные. Так сразу видно, как меняются циклы.
class HistoryPage extends StatelessWidget {
  final Store store;
  const HistoryPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final f = store.forecast;
    final theme = Theme.of(context);
    final periods = f.periods;
    final t = today();

    final rows = <_CycleRow>[];
    for (var i = periods.length - 1; i >= 0; i--) {
      final p = periods[i];
      final next = i + 1 < periods.length ? periods[i + 1] : null;
      rows.add(_CycleRow(
        period: p,
        length: next == null ? null : daysBetween(p.start, next.start),
        elapsed: next == null ? daysBetween(p.start, t) + 1 : null,
        expected: f.cycleLength,
      ));
    }
    final maxDays = rows.fold<int>(
        40, (m, r) => math.max(m, r.length ?? math.max(r.elapsed!, r.expected)));

    return Scaffold(
      appBar: AppBar(title: const Text('История')),
      floatingActionButton: periods.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addPast(context),
              icon: const Icon(Icons.add),
              label: const Text('Прошлые месячные'),
            ),
      body: periods.isEmpty
          ? _empty(context)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
              children: [
                Text(
                  f.tentative
                      ? 'Пока записаны только одни месячные. Добавьте прошлые '
                          'периоды — прогноз сразу станет точнее.'
                      : 'Цикл обычно длится ${daysWord(f.cycleLength)}'
                          '${f.cycleSpread > 0 ? ', разброс ±${daysWord(f.cycleSpread)}' : ''}. '
                          'Месячные — ${daysWord(f.periodLength)}.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                for (final r in rows)
                  _CycleTile(
                    row: r,
                    maxDays: maxDays,
                    onTap: () => _confirmDelete(context, r.period),
                  ),
                const SizedBox(height: 8),
                Text('Нажмите на строку, чтобы удалить период.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.water_drop_outlined,
              size: 48, color: Palette.period.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text('Записей пока нет',
              style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Перенесите даты месячных со старого телефона. '
            'Чем больше циклов, тем точнее прогноз.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _addPast(context),
            icon: const Icon(Icons.add),
            label: const Text('Добавить месячные'),
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Period p) async {
    HapticFeedback.selectionClick();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить период?'),
        content: Text('${fmtDate(p.start, year: true)}, ${daysWord(p.length)}. '
            'Прогноз пересчитается.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok == true) store.clearPeriod(p);
  }

  Future<void> _addPast(BuildContext context) async {
    final t = today();
    final start = await showDatePicker(
      context: context,
      initialDate: DateTime(t.year, t.month, t.day - 28),
      firstDate: DateTime(t.year - 10),
      lastDate: DateTime(t.year, t.month, t.day),
      helpText: 'Первый день месячных',
    );
    if (start == null || !context.mounted) return;
    var len = store.forecast.periodLength;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('С ${fmtDate(dateOnly(start), year: true)}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Сколько дней длились?',
                style: Theme.of(c).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                    onPressed: len > 1 ? () => set(() => len--) : null,
                    icon: const Icon(Icons.remove)),
                SizedBox(
                  width: 110,
                  child: Text(daysWord(len),
                      textAlign: TextAlign.center,
                      style: Theme.of(c).textTheme.titleLarge),
                ),
                IconButton.filledTonal(
                    onPressed: len < 12 ? () => set(() => len++) : null,
                    icon: const Icon(Icons.add)),
              ],
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      store.markPeriod(dateOnly(start), len);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Добавлено. Можно добавить следующие.')));
      }
    }
  }
}

class _CycleRow {
  final Period period;
  final int? length; // завершённый цикл
  final int? elapsed; // текущий цикл: сколько дней прошло
  final int expected;
  const _CycleRow(
      {required this.period,
      required this.length,
      required this.elapsed,
      required this.expected});
}

class _CycleTile extends StatelessWidget {
  final _CycleRow row;
  final int maxDays;
  final VoidCallback onTap;
  const _CycleTile(
      {required this.row, required this.maxDays, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final p = row.period;
    final current = row.length == null;
    final showYear = p.start.year != today().year;
    return Semantics(
      button: true,
      label: '${fmtDate(p.start, year: true)}, месячные ${daysWord(p.length)}, '
          '${current ? 'текущий цикл, ${row.elapsed}-й день' : 'цикл ${daysWord(row.length!)}'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.start.day} ${monthsShort[p.start.month - 1]}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (showYear || current)
                    Text(current ? 'сейчас' : '${p.start.year}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: current
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                double px(int days) => w * days / maxDays;
                final total = row.length ?? row.expected;
                final done = row.length ?? math.min(row.elapsed!, total);
                return SizedBox(
                  height: 18,
                  child: Stack(children: [
                    // ожидаемая длина текущего цикла — контур
                    if (current)
                      Container(
                        width: px(math.max(total, row.elapsed!)),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: fg.withValues(alpha: 0.18), width: 1.5),
                        ),
                      ),
                    Container(
                      width: px(current ? row.elapsed! : done),
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: current ? 0.16 : 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    Container(
                      width: px(math.min(p.length, current ? row.elapsed! : done)),
                      decoration: BoxDecoration(
                        color: Palette.period,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ]),
                );
              }),
            ),
            SizedBox(
              width: 56,
              child: Text(
                current ? '${row.elapsed}-й' : '${row.length}',
                textAlign: TextAlign.right,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: kDisplay,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: current ? theme.colorScheme.onSurfaceVariant : fg),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
