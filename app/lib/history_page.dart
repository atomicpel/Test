import 'package:flutter/material.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';

class HistoryPage extends StatelessWidget {
  final Store store;
  const HistoryPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final f = store.forecast;
    final periods = f.periods.reversed.toList();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('История')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPast(context),
        icon: const Icon(Icons.add),
        label: const Text('Прошлый период'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: _stat(context, 'Средний цикл',
                    f.tentative ? '—' : daysWord(f.cycleLength))),
                Expanded(child: _stat(context, 'Разброс',
                    f.cycleSpread > 0 ? '±${daysWord(f.cycleSpread)}' : '—')),
                Expanded(child: _stat(context, 'Месячные', daysWord(f.periodLength))),
              ]),
            ),
          ),
          if (periods.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Пока пусто. Перенесите даты со старого телефона кнопкой '
                '«Прошлый период» — чем больше циклов, тем точнее прогноз.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (var i = 0; i < periods.length; i++)
            _row(context, periods[i],
                i + 1 < periods.length ? periods[i + 1] : null),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String title, String value) => Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _row(BuildContext context, Period p, Period? prev) {
    final cycle = prev == null ? null : daysBetween(prev.start, p.start);
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Palette.period,
          child: Icon(Icons.water_drop, color: Colors.white, size: 20),
        ),
        title: Text('${fmtDate(p.start, year: true)} — ${daysWord(p.length)}'),
        subtitle: Text(cycle == null ? 'первый записанный' : 'цикл ${daysWord(cycle)}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Удалить период?'),
                content: Text('${fmtDate(p.start, year: true)}, ${daysWord(p.length)}'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
                ],
              ),
            );
            if (ok == true) store.clearPeriod(p);
          },
        ),
      ),
    );
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
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: len > 1 ? () => set(() => len--) : null,
                  icon: const Icon(Icons.remove_circle_outline)),
              Text(daysWord(len), style: Theme.of(c).textTheme.titleLarge),
              IconButton(
                  onPressed: len < 12 ? () => set(() => len++) : null,
                  icon: const Icon(Icons.add_circle_outline)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Добавить')),
          ],
        ),
      ),
    );
    if (ok == true) {
      store.markPeriod(dateOnly(start), len);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Добавлено. Можно добавить следующий.')));
      }
    }
  }
}
