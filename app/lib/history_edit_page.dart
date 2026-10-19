import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

/// Список всех месячных: добавить прошлые, удалить, импортировать.
class HistoryEditPage extends StatelessWidget {
  final Store store;
  const HistoryEditPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final f = store.forecast;
        final rows = f.rows;
        final theme = Theme.of(context);
        final c = AppColors.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('История месячных'),
            actions: [
              IconButton(
                tooltip: 'Импорт',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => showImportSheet(context, store),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => addPastPeriod(context, store),
            icon: const Icon(Icons.add),
            label: const Text('Добавить'),
          ),
          body: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Добавьте даты прошлых месячных кнопкой ниже или вставьте список через «Импорт».',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(color: c.muted),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return Dismissible(
                      key: ValueKey(r.period.start),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(18)),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _confirm(context, r.period),
                      onDismissed: (_) => store.clearPeriod(r.period),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                                color: Palette.period, shape: BoxShape.circle),
                            child: const Icon(Icons.water_drop, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fmtDate(r.period.start, year: true),
                                      style: theme.textTheme.titleMedium),
                                  Text(
                                    '${daysWord(r.period.length)}'
                                    '${r.length == null ? ', текущий цикл' : ', цикл ${daysWord(r.length!)}'}',
                                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                                  ),
                                ]),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            icon: Icon(Icons.delete_outline, color: c.muted),
                            onPressed: () async {
                              if (await _confirm(context, r.period) == true) {
                                store.clearPeriod(r.period);
                              }
                            },
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<bool?> _confirm(BuildContext context, Period p) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Удалить месячные?'),
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
}

/// Добавить прошлые месячные: дата начала и длительность.
Future<void> addPastPeriod(BuildContext context, Store store) async {
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
          const Text('Сколько дней длились?'),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
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
          ]),
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
    if (context.mounted) showSnack(context, 'Добавлено. Можно добавить ещё.');
  }
}

/// Импорт: вставить список дат или JSON из экспорта.
Future<void> showImportSheet(BuildContext context, Store store) async {
  final c = TextEditingController();
  final clip = await Clipboard.getData(Clipboard.kTextPlain);
  if (clip?.text != null && RegExp(r'\d{4}-\d{2}-\d{2}|\d{2}\.\d{2}\.\d{4}|^\s*\{').hasMatch(clip!.text!)) {
    c.text = clip.text!;
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Импорт истории', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Вставьте даты начала месячных и длительность — по одной на строку, '
          'например «2026-08-23 5» или «23.08.2026 5». Подойдёт и файл экспорта.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '2026-08-23 5\n2026-07-23 5'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            final r = store.importText(c.text);
            Navigator.pop(ctx);
            showSnack(
                context,
                r.error ??
                    (r.periods > 0
                        ? 'Добавлено месячных: ${r.periods}'
                        : 'Загружено дней: ${r.days}'));
          },
          child: const Text('Импортировать'),
        ),
      ]),
    ),
  );
}
