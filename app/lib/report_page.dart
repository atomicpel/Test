import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'day_entry.dart';
import 'native.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

/// Отчёт для врача: сводка по последним циклам одной страницей.
class ReportPage extends StatelessWidget {
  final Store store;
  const ReportPage({super.key, required this.store});

  String buildText() {
    final f = store.forecast;
    final b = StringBuffer();
    final now = today();
    b.writeln('Отчёт о цикле — ${fmtDate(now, year: true)}');
    if (store.name.isNotEmpty) b.writeln('Имя: ${store.name}');
    b.writeln();
    final rows = f.rows.take(6).toList();
    if (rows.isEmpty) {
      b.writeln('Записей о месячных пока нет.');
      return b.toString();
    }
    b.writeln('Последние месячные:');
    for (final r in rows) {
      b.writeln('• ${fmtDate(r.period.start, year: true)} — ${daysWord(r.period.length)}'
          '${r.length == null ? ' (текущий цикл)' : ', цикл ${daysWord(r.length!)}'}');
    }
    final cl = f.recentCycleLengths(6);
    if (cl.isNotEmpty) {
      b.writeln();
      b.writeln('Длина цикла: ${cl.reduce(math.min)}–${cl.reduce(math.max)} дн., '
          'в среднем ${daysWord(f.cycleLength)}');
      if (f.regular != null) {
        b.writeln('Регулярность: ${f.regular! ? 'регулярный' : 'нерегулярный'} '
            '(разброс ${cl.reduce(math.max) - cl.reduce(math.min)} дн.)');
      }
    }
    b.writeln('Длительность месячных: в среднем ${daysWord(f.periodLength)}');
    if (f.delay > 0) b.writeln('Сейчас задержка: ${daysWord(f.delay)}');
    final c = store.contraception;
    if (c != null) {
      b.writeln('Контрацепция: ${optById(contraceptionMethods, c).label}');
    }
    final since = rows.last.period.start;
    final logs = store.loggedDays.where((e) => !e.key.isBefore(since));
    Map<String, int> cnt(List<String> Function(DayData) g) {
      final m = <String, int>{};
      for (final e in logs) {
        for (final id in g(e.value)) {
          m[id] = (m[id] ?? 0) + 1;
        }
      }
      return m;
    }

    void section(String title, Map<String, int> m, List<Opt> base) {
      if (m.isEmpty) return;
      final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      b.writeln();
      b.writeln('$title (за период отчёта):');
      for (final e in l.take(10)) {
        b.writeln('• ${optById(base, e.key).label} — ${e.value} раз');
      }
    }

    section('Симптомы', cnt((d) => d.symptoms), symptomOptions);
    section('Настроение', cnt((d) => d.moods), moodOptions);
    section('Препараты', cnt((d) => d.meds), const []);
    final flows = logs.where((e) => e.value.flow > 0).toList();
    if (flows.isNotEmpty) {
      final heavy = flows.where((e) => e.value.flow >= 3).length;
      b.writeln();
      b.writeln('Обильность: отмечено ${daysWord(flows.length)}, из них обильных — $heavy');
    }
    b.writeln();
    b.writeln('Составлено приложением «Мой цикл». Прогнозы приблизительные.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = buildText();
    final theme = Theme.of(context);
    final paragraphs = text.trim().split('\n\n');
    return Scaffold(
      appBar: AppBar(title: const Text('Отчёт для врача')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          for (var i = 0; i < paragraphs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Stagger(
                index: i,
                child: AppCard(
                  child: SelectableText(paragraphs[i],
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: i == 0 ? FontWeight.w700 : null)),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  showSnack(context, 'Отчёт скопирован');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Копировать'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Native.share(text, subject: 'Отчёт о цикле'),
                icon: const Icon(Icons.share),
                label: const Text('Отправить'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
