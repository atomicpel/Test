import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'day_entry.dart';
import 'option_picker_page.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

/// Запись дня: неделя сверху, ниже разделы.
class DayLogPage extends StatefulWidget {
  final Store store;
  final DateTime initial;
  const DayLogPage({super.key, required this.store, required this.initial});

  @override
  State<DayLogPage> createState() => _DayLogPageState();
}

class _DayLogPageState extends State<DayLogPage> {
  late DateTime _day = dateOnly(widget.initial);
  int _dir = 1;

  void _select(DateTime d) {
    d = dateOnly(d);
    if (d == _day) return;
    HapticFeedback.selectionClick();
    setState(() {
      _dir = d.isAfter(_day) ? 1 : -1;
      _day = d;
    });
  }

  Future<void> _pickDate() async {
    final t = today();
    final p = await showDatePicker(
      context: context,
      initialDate: DateTime(_day.year, _day.month, _day.day),
      firstDate: DateTime(t.year - 10),
      lastDate: DateTime(t.year + 1, 12, 31),
    );
    if (p != null) _select(p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Закрыть',
          icon: const Icon(Icons.close, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: motion(context, 250),
                child: Text(
                  _day.year == today().year ? fmtDate(_day) : fmtDate(_day, year: true),
                  key: ValueKey(_day),
                  style: theme.appBarTheme.titleTextStyle,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 30),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        _WeekStrip(store: widget.store, selected: _day, onSelect: _select),
        const SizedBox(height: 6),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => AnimatedSwitcher(
              duration: motion(context, 320),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, a) {
                final incoming = child.key == ValueKey(_day);
                final dx = incoming ? 0.12 * _dir : -0.12 * _dir;
                return FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                        .animate(a),
                    child: child,
                  ),
                );
              },
              child: _DayContent(
                  key: ValueKey(_day), store: widget.store, day: _day),
            ),
          ),
        ),
      ]),
    );
  }
}

class _WeekStrip extends StatefulWidget {
  final Store store;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _WeekStrip(
      {required this.store, required this.selected, required this.onSelect});

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<_WeekStrip> {
  static const _base = 2000;
  late final DateTime _anchor = _monday(today());
  late final PageController _pc =
      PageController(initialPage: _base + _weekIndex(widget.selected));

  static DateTime _monday(DateTime d) => addDays(d, -(d.weekday - 1));
  int _weekIndex(DateTime d) => daysBetween(_anchor, _monday(d)) ~/ 7;

  @override
  void didUpdateWidget(_WeekStrip old) {
    super.didUpdateWidget(old);
    final target = _base + _weekIndex(widget.selected);
    if (_pc.hasClients && _pc.page?.round() != target) {
      _pc.animateToPage(target,
          duration: motion(context, 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final accent = theme.colorScheme.primary;
    final t = today();
    return Column(children: [
      Row(children: [
        for (final w in weekdaysShort)
          Expanded(
              child: Center(
                  child: Text(w,
                      style: TextStyle(
                          fontFamily: kFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.muted)))),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 62,
        child: PageView.builder(
          controller: _pc,
          itemBuilder: (context, p) {
            final monday = addDays(_anchor, (p - _base) * 7);
            return ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(child: () {
                    final d = addDays(monday, i);
                    final sel = d == widget.selected;
                    final period = widget.store.isPeriod(d);
                    final future = d.isAfter(t);
                    return Pressable(
                      onTap: () => widget.onSelect(d),
                      child: Column(children: [
                        AnimatedContainer(
                          duration: motion(context, 260),
                          curve: Curves.easeOutBack,
                          width: sel ? 50 : 44,
                          height: sel ? 50 : 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sel ? accent : Colors.transparent,
                            border: d == t && !sel
                                ? Border.all(color: accent, width: 2)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text('${d.day}',
                              style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? theme.colorScheme.onPrimary
                                    : (future
                                        ? c.muted
                                        : theme.colorScheme.onSurface),
                              )),
                        ),
                        const SizedBox(height: 3),
                        AnimatedOpacity(
                          opacity: period ? 1 : 0,
                          duration: motion(context, 200),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                                color: Palette.period, shape: BoxShape.circle),
                          ),
                        ),
                      ]),
                    );
                  }()),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

class _DayContent extends StatelessWidget {
  final Store store;
  final DateTime day;
  const _DayContent({super.key, required this.store, required this.day});

  @override
  Widget build(BuildContext context) {
    final data = store.day(day);
    final sections = store.sections;
    final children = <Widget>[
      _CycleCard(store: store, day: day, data: data),
    ];
    for (final id in sections) {
      final w = _section(context, id, data);
      if (w != null) children.add(w);
    }
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 40),
      child: OutlinedButton(
        onPressed: () => _customize(context),
        child: const Text('Настроить список'),
      ),
    ));
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        for (var i = 0; i < children.length; i++)
          Stagger(index: i, child: children[i]),
      ],
    );
  }

  void _patch(Map<String, dynamic> m) => store.patchDay(day, m);

  List<String> _toggle(List<String> list, String id) {
    final l = list.toList();
    l.contains(id) ? l.remove(id) : l.add(id);
    return l;
  }

  Widget? _section(BuildContext context, String id, DayData data) {
    switch (id) {
      case 'flow':
        if (!data.period) return null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Обильность месячных'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              FlowDrops(value: data.flow, onChanged: (v) => _patch({'f': v})),
              const SizedBox(width: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion(context, 200),
                  child: Text(
                    data.flow == 0 ? 'Не отмечено' : flowLabels[data.flow - 1],
                    key: ValueKey(data.flow),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ]),
          ),
        ]);
      case 'intimacy':
        if (!store.calShow('intimacy')) return null;
        return _OptionsRow(
          title: 'Сексуальная активность',
          options: intimacyOptions,
          selected: data.intimacy,
          onToggle: (o) => _patch({'x': _toggle(data.intimacy, o)}),
        );
      case 'symptoms':
        return _OptionsRow(
          title: 'Симптомы',
          options: [
            ...symptomOptions,
            ...store.custom('s').map((id) => optById(const [], id)),
          ],
          selected: data.symptoms,
          onToggle: (o) => _patch({'s': _toggle(data.symptoms, o)}),
          onShowAll: () => _openPicker(context, 'Симптомы', 's',
              [...symptomOptions, ...store.custom('s').map((id) => optById(const [], id))],
              data.symptoms),
        );
      case 'moods':
        return _OptionsRow(
          title: 'Настроение',
          options: [
            ...moodOptions,
            ...store.custom('m').map((id) => optById(const [], id)),
          ],
          selected: data.moods,
          onToggle: (o) => _patch({'m': _toggle(data.moods, o)}),
          onShowAll: () => _openPicker(context, 'Настроение', 'm',
              [...moodOptions, ...store.custom('m').map((id) => optById(const [], id))],
              data.moods),
        );
      case 'pill':
        return _ContraceptionSection(store: store, day: day);
      case 'notes':
        return _NoteSection(store: store, day: day, initial: data.note);
      case 'meds':
        return _MedsSection(store: store, day: day, data: data);
      case 'temp':
        return _ValueRow(
          title: 'Температура',
          value: data.temp == null
              ? null
              : '${data.temp!.toStringAsFixed(2).replaceAll('.', ',')} °C',
          onTap: () => _editNumber(context,
              title: 'Базальная температура',
              unit: '°C',
              min: 35.0,
              max: 39.0,
              step: 0.05,
              digits: 2,
              initial: data.temp ?? 36.6,
              onSave: (v) => _patch({'t': v})),
        );
      case 'weight':
        return _ValueRow(
          title: 'Вес',
          value: data.weight == null
              ? null
              : '${data.weight!.toStringAsFixed(1).replaceAll('.', ',')} кг',
          onTap: () => _editNumber(context,
              title: 'Вес',
              unit: 'кг',
              min: 30,
              max: 150,
              step: 0.1,
              digits: 1,
              initial: data.weight ?? _lastWeight() ?? 60,
              onSave: (v) => _patch({'w': v})),
        );
    }
    return null;
  }

  double? _lastWeight() {
    for (final e in store.loggedDays) {
      if (e.value.weight != null) return e.value.weight;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context, String title, String key,
      List<Opt> options, List<String> selected) async {
    final res = await Navigator.of(context).push<List<String>>(MaterialPageRoute(
      builder: (_) => OptionPickerPage(
        title: title,
        options: options,
        selected: selected,
        onAddCustom: (label) => store.addCustom(key, label),
      ),
    ));
    if (res != null) _patch({key: res});
  }

  Future<void> _editNumber(BuildContext context,
      {required String title,
      required String unit,
      required double min,
      required double max,
      required double step,
      required int digits,
      required double initial,
      required ValueChanged<double?> onSave}) async {
    var v = initial.clamp(min, max).toDouble();
    final res = await showModalBottomSheet<double?>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final theme = Theme.of(c);
          void bump(double d) => set(() {
                v = ((v + d) / step).round() * step;
                v = v.clamp(min, max).toDouble();
                HapticFeedback.selectionClick();
              });
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton.filledTonal(
                      onPressed: () => bump(-step), icon: const Icon(Icons.remove)),
                  SizedBox(
                    width: 190,
                    child: Text(
                      '${v.toStringAsFixed(digits).replaceAll('.', ',')} $unit',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayLarge?.copyWith(fontSize: 40),
                    ),
                  ),
                  IconButton.filledTonal(
                      onPressed: () => bump(step), icon: const Icon(Icons.add)),
                ]),
                Slider(
                  value: v,
                  min: min,
                  max: max,
                  divisions: ((max - min) / step).round(),
                  onChanged: (x) => set(() => v = x),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c, double.nan),
                      child: const Text('Удалить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(c, v),
                      child: const Text('Сохранить'),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    if (res == null) return;
    onSave(res.isNaN ? null : double.parse(res.toStringAsFixed(digits)));
  }

  void _customize(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => ListenableBuilder(
        listenable: store,
        builder: (c, _) {
          final visible = store.sections;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Что показывать', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final s in allSections)
                  SwitchListTile(
                    title: Text(s.title),
                    value: visible.contains(s.id),
                    onChanged: (on) {
                      final l = allSections
                          .map((x) => x.id)
                          .where((id) => id == s.id ? on : visible.contains(id))
                          .toList();
                      store.setSetting('sections', l);
                    },
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Карточка «Мой цикл»: отметка месячных и сведения о дне.
class _CycleCard extends StatelessWidget {
  final Store store;
  final DateTime day;
  final DayData data;
  const _CycleCard({required this.store, required this.day, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final f = store.forecast;
    final t = today();
    final isToday = day == t;
    final future = day.isAfter(t);
    final info = f.info(day);
    final preg = store.pregnancy;

    final lines = <Widget>[];
    void line(String s, {Color? color}) => lines.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(s,
              style: theme.textTheme.bodyLarge?.copyWith(color: color)),
        ));

    if (preg != null && !day.isBefore(preg.lmp)) {
      final w = preg.week(day);
      line('$w-я неделя беременности, ${preg.dayOfWeek(day)} дн.');
      final left = preg.daysLeft(day);
      if (left >= 0) line('До родов ${daysWord(left)}');
      line('${preg.trimester(day)}-й триместр');
    } else if (info != null) {
      if (info.periodDay != null) {
        line('${info.periodDay}-й день месячных');
      } else if (info.predictedPeriod) {
        line('Ожидаются месячные', color: Palette.predicted);
      } else if (info.kind == DayKind.ovulation) {
        line('День овуляции (прогноз)');
        line('Вероятность беременности высокая',
            color: theme.colorScheme.primary);
      } else if (info.fertility != Fertility.low) {
        line('Фертильное окно');
        line('Вероятность беременности от средней до высокой',
            color: theme.colorScheme.primary);
      } else {
        line('Нефертильный день');
      }
      if (isToday && f.delay > 0) line(daysWordGen(f.delay, 'задержки'));
      if (info.daysToFertile != null && info.fertility == Fertility.low) {
        line('${daysWord(info.daysToFertile!)} до фертильности');
      }
      if (info.daysToOvulation != null) {
        line('${daysWord(info.daysToOvulation!)} до овуляции');
      }
      line('${info.cycleDay}-й день цикла');
      if (info.daysToPeriod != null &&
          info.periodDay == null &&
          !info.predictedPeriod &&
          info.daysToPeriod! > 0) {
        line('${daysWord(info.daysToPeriod!)} до месячных');
      }
      if (info.pms) line('Возможен ПМС', color: Palette.pms);
    } else {
      line('Отметьте первые месячные, чтобы появился прогноз');
    }

    final last = f.last;
    final inLast = last != null && last.contains(day);
    final canEnd = data.period && inLast && day != last?.end;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('Мой цикл', style: theme.textTheme.titleLarge),
          ),
          InkWell(
            onTap: future && !data.period
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    if (data.period) {
                      store.patchDay(day, {'p': false, 'f': 0});
                    } else if (f.periods.any((p) =>
                        daysBetween(p.end, day) == 1 || daysBetween(day, p.start) == 1)) {
                      // рядом с уже отмеченными — добавляем один день
                      store.patchDay(day, {'p': true});
                    } else {
                      store.markPeriod(day, f.periodLength);
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.period
                              ? 'Месячные в этот день'
                              : (isToday
                                  ? 'Месячные начинаются сегодня'
                                  : 'Месячные начались в этот день'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.period
                              ? 'Коснитесь, чтобы снять отметку'
                              : (future
                                  ? 'Будущий день — отметить пока нельзя'
                                  : 'Коснитесь здесь, если месячные начались!'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                        ),
                      ]),
                ),
                const SizedBox(width: 12),
                _Check(on: data.period, color: Palette.period),
              ]),
            ),
          ),
          if (canEnd)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    store.endPeriodOn(day);
                    showSnack(context, 'Отмечено: закончились ${fmtDate(day)}');
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Закончились в этот день'),
                ),
              ),
            ),
          Divider(color: c.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: IntrinsicHeight(
              child: Row(children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: data.period
                        ? Palette.period
                        : (info?.fertility == Fertility.low || info == null
                            ? c.cardBorder
                            : Palette.fertile),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: lines),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

String daysWordGen(int n, String what) =>
    '$n ${plural(n, 'день', 'дня', 'дней')} $what';

/// Круглая галочка, как радиокнопка в оригинале.
class _Check extends StatelessWidget {
  final bool on;
  final Color color;
  const _Check({required this.on, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AnimatedContainer(
      duration: motion(context, 260),
      curve: Curves.easeOutBack,
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? color : Colors.transparent,
        border: Border.all(color: on ? color : c.muted, width: 2),
      ),
      child: AnimatedScale(
        scale: on ? 1 : 0,
        duration: motion(context, 260),
        curve: Curves.easeOutBack,
        child: const Icon(Icons.check, color: Colors.white, size: 22),
      ),
    );
  }
}

class _OptionsRow extends StatelessWidget {
  final String title;
  final List<Opt> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback? onShowAll;
  const _OptionsRow(
      {required this.title,
      required this.options,
      required this.selected,
      required this.onToggle,
      this.onShowAll});

  @override
  Widget build(BuildContext context) {
    // Выбранные — первыми, затем остальные по порядку
    final ordered = [
      ...options.where((o) => selected.contains(o.id)),
      ...selected
          .where((id) => !options.any((o) => o.id == id))
          .map((id) => optById(const [], id)),
      ...options.where((o) => !selected.contains(o.id)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(title,
          action: onShowAll == null ? null : 'Показать все', onAction: onShowAll),
      SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: ordered.length,
          separatorBuilder: (_, __) => const SizedBox(width: 2),
          itemBuilder: (context, i) {
            final o = ordered[i];
            return OptionTile(
              opt: o,
              selected: selected.contains(o.id),
              onTap: () => onToggle(o.id),
            );
          },
        ),
      ),
    ]);
  }
}

class _ContraceptionSection extends StatelessWidget {
  final Store store;
  final DateTime day;
  const _ContraceptionSection({required this.store, required this.day});

  @override
  Widget build(BuildContext context) {
    final method = store.contraception;
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    Widget body;
    if (method == 'pill') {
      final yesterday = addDays(day, -1);
      body = Row(children: [
        const SizedBox(width: 12),
        OptionTile(
          opt: const Opt('y', '💊', 'Вчерашняя таблетка'),
          selected: store.day(yesterday).pill,
          onTap: () => store.patchDay(yesterday, {'pl': !store.day(yesterday).pill}),
        ),
        OptionTile(
          opt: const Opt('t', '💊', 'Сегодняшняя таблетка'),
          selected: store.day(day).pill,
          onTap: () => store.patchDay(day, {'pl': !store.day(day).pill}),
        ),
      ]);
    } else {
      final m = method == null
          ? null
          : contraceptionMethods.firstWhere((o) => o.id == method,
              orElse: () => contraceptionMethods.first);
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
          m == null
              ? 'Не отслеживается. Выберите метод в настройках.'
              : '${m.emoji}  ${m.label}',
          style: theme.textTheme.bodyLarge?.copyWith(color: m == null ? c.muted : null),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Контрацепция',
          action: 'Настроить',
          onAction: () => _chooseMethod(context)),
      body,
    ]);
  }

  void _chooseMethod(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Метод контрацепции', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final o in [const Opt('', '🚫', 'Не отслеживать'), ...contraceptionMethods])
            ListTile(
              leading: Text(o.emoji, style: const TextStyle(fontSize: 26)),
              title: Text(o.label),
              trailing: (store.contraception ?? '') == o.id
                  ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary)
                  : null,
              onTap: () {
                store.setSetting('contra', o.id.isEmpty ? null : o.id);
                Navigator.pop(c);
              },
            ),
        ]),
      ),
    );
  }
}

class _NoteSection extends StatefulWidget {
  final Store store;
  final DateTime day;
  final String initial;
  const _NoteSection(
      {required this.store, required this.day, required this.initial});

  @override
  State<_NoteSection> createState() => _NoteSectionState();
}

class _NoteSectionState extends State<_NoteSection> {
  late final _c = TextEditingController(text: widget.initial);
  Timer? _t;

  void _save() {
    if (_c.text.trim() != widget.store.day(widget.day).note) {
      widget.store.patchDay(widget.day, {'n': _c.text});
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    final store = widget.store, day = widget.day, text = _c.text;
    if (text.trim() != store.day(day).note) {
      Future.microtask(() => store.patchDay(day, {'n': text}));
    }
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Заметки'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _c,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'Самочувствие, события, что угодно…'),
          onChanged: (_) {
            _t?.cancel();
            _t = Timer(const Duration(milliseconds: 900), _save);
          },
        ),
      ),
    ]);
  }
}

class _MedsSection extends StatelessWidget {
  final Store store;
  final DateTime day;
  final DayData data;
  const _MedsSection(
      {required this.store, required this.day, required this.data});

  @override
  Widget build(BuildContext context) {
    final all = {...store.custom('md'), ...data.meds}.toList();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Медицинские препараты',
          action: 'Добавить', onAction: () => _add(context)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: all.isEmpty
            ? Text('Добавьте препарат, который принимаете — дальше он будет в списке.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.of(context).muted))
            : Wrap(spacing: 8, runSpacing: 8, children: [
                for (final id in all)
                  FilterChip(
                    label: Text(optById(const [], id).label),
                    selected: data.meds.contains(id),
                    onSelected: (on) {
                      HapticFeedback.selectionClick();
                      final l = data.meds.toList();
                      on ? l.add(id) : l.remove(id);
                      store.patchDay(day, {'md': l});
                    },
                  ),
              ]),
      ),
    ]);
  }

  Future<void> _add(BuildContext context) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Препарат'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Например, «Но-шпа»'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Добавить')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    store.addCustom('md', name);
    final id = 'c:${name.trim()}';
    if (!data.meds.contains(id)) store.patchDay(day, {'md': [...data.meds, id]});
  }
}

class _ValueRow extends StatelessWidget {
  final String title;
  final String? value;
  final VoidCallback onTap;
  const _ValueRow({required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          AnimatedSwitcher(
            duration: motion(context, 200),
            child: Text(value ?? 'Добавить',
                key: ValueKey(value),
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: value == null ? c.muted : theme.colorScheme.primary,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: theme.colorScheme.primary),
        ]),
      ),
    );
  }
}
