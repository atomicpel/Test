import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'day_entry.dart';
import 'history_edit_page.dart';
import 'lock.dart';
import 'native.dart';
import 'reminders.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

void _push(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));

class SettingsPage extends StatelessWidget {
  final Store store;
  const SettingsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final tiles = <Widget>[
              Center(child: Text('Настройки', style: theme.appBarTheme.titleTextStyle)),
              const _Header(Icons.water_drop, 'Мой цикл'),
              _Tile('Как считается прогноз', onTap: () => _push(context, ForecastInfoPage(store: store))),
              _Tile('Контрацепция',
                  subtitle: store.contraception == null
                      ? 'Не отслеживается'
                      : optById(contraceptionMethods, store.contraception!).label,
                  onTap: () => _push(context, ContraceptionPage(store: store))),
              _Tile('Беременность',
                  subtitle: store.pregnancy == null
                      ? 'Режим выключен'
                      : 'Дата родов ${fmtDate(store.pregnancy!.due, year: true)}',
                  onTap: () => _push(context, PregnancyPage(store: store))),
              _Tile('Стиль календаря', onTap: () => _push(context, CalendarStylePage(store: store))),
              _Tile('История месячных', onTap: () => _push(context, HistoryEditPage(store: store))),
              const _Header(Icons.notifications, 'Напоминания'),
              _Tile('Напоминания', subtitle: 'Месячные, овуляция, таблетки, записи',
                  onTap: () => _push(context, RemindersPage(store: store))),
              _Tile('Секретные напоминания',
                  subtitle: store.secretNotifications ? 'Включены' : 'Выключены',
                  onTap: () => _push(context, SecretPage(store: store))),
              const _Header(Icons.star, 'Индивидуальные настройки'),
              _Tile('Ваше имя',
                  subtitle: store.name.isEmpty ? null : store.name,
                  onTap: () => _editName(context)),
              _Tile('Размер шрифта',
                  subtitle: fontScaleLabel(store.textScale),
                  onTap: () => _push(context, FontSizePage(store: store))),
              _Tile('Безопасный вход (PIN-код)',
                  subtitle: pinEnabled(store) ? 'Включён' : 'Выключен',
                  onTap: () => _push(context, SecurityPage(store: store))),
              _Tile('Виджет на главном экране', onTap: () => _push(context, const WidgetInfoPage())),
              const _Header(Icons.folder, 'Мои данные'),
              _Tile('Синхронизация',
                  subtitle: store.syncConfigured
                      ? (store.syncError ?? 'Подключено')
                      : 'Не настроена',
                  onTap: () => _push(context, SyncPage(store: store))),
              _Tile('Импорт истории', onTap: () => showImportSheet(context, store)),
              _Tile('Резервная копия (экспорт)',
                  subtitle: 'Отправить файл с данными, например себе в мессенджер',
                  onTap: () => Native.share(store.exportJson(), subject: 'Мой цикл — резервная копия')),
              _Tile('Удалить данные из приложения', danger: true, onTap: () => _deleteAll(context)),
              const _Header(Icons.info_outline, 'О приложении'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  'Данные хранятся на телефоне и на вашем сервере. Прогноз '
                  'приблизительный, не заменяет консультацию врача и не годится '
                  'как метод контрацепции.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.of(context).muted),
                ),
              ),
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                for (var i = 0; i < tiles.length; i++) Stagger(index: i, child: tiles[i]),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final c = TextEditingController(text: store.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ваше имя'),
        content: TextField(
            controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (v != null) store.setSetting('name', v.trim().isEmpty ? null : v.trim());
  }

  Future<void> _deleteAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить все данные?'),
        content: const Text(
            'Будут удалены все отметки и записи — на этом телефоне, на сервере и на '
            'втором телефоне после синхронизации. Отменить нельзя. '
            'Сначала можно сделать резервную копию.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Удалить', style: TextStyle(color: Theme.of(c).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      store.deleteAll();
      if (context.mounted) showSnack(context, 'Данные удалены');
    }
  }
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String title;
  const _Header(this.icon, this.title);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
      child: Row(children: [
        Icon(icon, color: accent, size: 19),
        const SizedBox(width: 10),
        Text(title,
            style: TextStyle(
                fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w700, color: accent)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _Tile(this.title, {this.subtitle, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      ListTile(
        title: Text(title,
            style: danger ? TextStyle(color: theme.colorScheme.error) : null),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Icon(Icons.chevron_right, color: theme.colorScheme.primary, size: 20),
        onTap: onTap,
      ),
      Divider(height: 1, color: AppColors.of(context).cardBorder, indent: 16),
    ]);
  }
}

/// Простая страница настроек с заголовком.
class _Page extends StatelessWidget {
  final String title;
  final Store store;
  final List<Widget> Function(BuildContext) children;
  const _Page({required this.title, required this.store, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final ch = children(context);
          return ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [for (var i = 0; i < ch.length; i++) Stagger(index: i, child: ch[i])],
          );
        },
      ),
    );
  }
}

Widget _note(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.of(context).muted)),
    );

// ---------------------------------------------------------------- прогноз

class ForecastInfoPage extends StatelessWidget {
  final Store store;
  const ForecastInfoPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Прогноз',
      store: store,
      children: (context) {
        final f = store.forecast;
        final theme = Theme.of(context);
        return [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppCard(
              child: Text(
                f.tentative
                    ? 'Пока записан меньше чем один полный цикл, поэтому прогноз '
                        'предварительный (стандартные ${daysWord(f.cycleLength)}). '
                        'Как только будет отмечено начало следующих месячных или '
                        'добавлены прошлые, всё пересчитается по вашим записям.'
                    : 'Сейчас: цикл ${daysWord(f.cycleLength)}'
                        '${f.cycleSpread > 0 ? ' (±${f.cycleSpread})' : ''}, '
                        'месячные ${daysWord(f.periodLength)} — посчитано по '
                        '${f.cyclesUsed} ${plural(f.cyclesUsed, 'циклу', 'циклам', 'циклам')}.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          _note(context,
              'Всё считается автоматически по отмеченным дням: берутся последние '
              '12 циклов, свежие весят больше старых, а явные выбросы (например, '
              'пропущенная отметка, из-за которой два цикла слились в один) не '
              'учитываются.'),
          _note(context,
              'Овуляция — за 14 дней до ожидаемых месячных. Фертильные дни — '
              '5 дней до овуляции и день после. ПМС — 3 дня перед месячными.'),
        ];
      },
    );
  }
}

// ---------------------------------------------------------------- контрацепция

class ContraceptionPage extends StatelessWidget {
  final Store store;
  const ContraceptionPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Контрацепция',
      store: store,
      children: (context) => [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Отслеживать контрацепцию'),
          value: store.contraception != null,
          onChanged: (v) => store.setSetting('contra', v ? 'pill' : null),
        ),
        if (store.contraception != null) ...[
          _note(context, 'Метод контрацепции'),
          for (final o in contraceptionMethods)
            RadioListTile<String>(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: o.id,
              groupValue: store.contraception,
              onChanged: (v) => store.setSetting('contra', v),
              title: Text('${o.emoji}  ${o.label}'),
            ),
          if (store.pillTracking)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('Напоминание о таблетке'),
              subtitle: Text(store.reminders['pill'] == true
                  ? 'Каждый день в ${store.reminders['pillTime']}'
                  : 'Выключено'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(context, RemindersPage(store: store)),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- беременность

class PregnancyPage extends StatelessWidget {
  final Store store;
  const PregnancyPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Беременность',
      store: store,
      children: (context) {
        final p = store.pregnancy;
        final t = today();
        return [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Режим беременности'),
            subtitle: const Text('Вместо прогноза месячных — неделя беременности и время до родов'),
            value: p != null,
            onChanged: (v) async {
              if (!v) {
                store.setSetting('pregLmp', null);
                return;
              }
              final lmp = store.forecast.last?.start ?? t;
              final due = await showDatePicker(
                context: context,
                initialDate: DateTime(addDays(lmp, 280).year, addDays(lmp, 280).month,
                    addDays(lmp, 280).day),
                firstDate: DateTime(t.year - 1),
                lastDate: DateTime(t.year + 1, 12, 31),
                helpText: 'Предполагаемая дата родов',
              );
              if (due != null) {
                store.setSetting('pregLmp', dayKey(Pregnancy.fromDue(dateOnly(due)).lmp));
              }
            },
          ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.week(t)}-я неделя, ${p.trimester(t)}-й триместр',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text('Дата родов: ${fmtDate(p.due, year: true)}',
                      style: Theme.of(context).textTheme.bodyLarge),
                  Text('Осталось: ${daysWord(p.daysLeft(t).clamp(0, 400).toInt())}',
                      style: Theme.of(context).textTheme.bodyLarge),
                ]),
              ),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Уведомление о задержке'),
            subtitle: Text(
                'Если задержка больше ${store.reminders['delayDays']} дней'),
            value: store.reminders['delay'] == true,
            onChanged: (v) => _setReminder(context, store, 'delay', v),
          ),
        ];
      },
    );
  }
}

// ---------------------------------------------------------------- стиль календаря

class CalendarStylePage extends StatelessWidget {
  final Store store;
  const CalendarStylePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    Widget sw(String key, String title, String sub) => SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(title),
          subtitle: Text(sub),
          value: store.calShow(key),
          onChanged: (v) => store.setCalShow(key, v),
        );
    return _Page(
      title: 'Стиль календаря',
      store: store,
      children: (context) => [
        sw('intimacy', 'Журнал интимных отношений',
            'Отмечать дни, когда были интимные отношения'),
        sw('fertility', 'Фертильность и овуляция',
            'Показывать фертильные дни, овуляцию и ПМС'),
        sw('pill', 'Противозачаточные таблетки',
            'Показывать в календаре дни, когда таблетка принята'),
      ],
    );
  }
}

// ---------------------------------------------------------------- напоминания

Future<void> _setReminder(
    BuildContext context, Store store, String key, Object value) async {
  store.setReminder(key, value);
  if (value == true) {
    final ok = await Reminders.requestPermission();
    if (!ok && context.mounted) {
      showSnack(context, 'Уведомления запрещены — разрешите их в настройках телефона');
    }
  }
}

class RemindersPage extends StatefulWidget {
  final Store store;
  const RemindersPage({super.key, required this.store});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> with WidgetsBindingObserver {
  bool? _enabled;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final e = await Reminders.enabled();
    final p = await Reminders.pending();
    if (mounted) setState(() {
      _enabled = e;
      _pending = p.length;
    });
  }

  Future<void> _time(String key) async {
    final cur = '${widget.store.reminders[key]}'.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(cur[0]) ?? 9, minute: int.tryParse(cur.last) ?? 0),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) {
      widget.store.setReminder(
          key, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = Theme.of(context);
    return _Page(
      title: 'Напоминания',
      store: store,
      children: (context) {
        final r = store.reminders;
        Widget sw(String key, String title, String sub, {Widget? trailing}) => Column(children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                title: Text(title),
                subtitle: Text(sub),
                value: r[key] == true,
                onChanged: (v) => _setReminder(context, store, key, v),
              ),
              if (trailing != null)
                AnimatedSize(
                  duration: motion(context, 220),
                  child: r[key] == true ? trailing : const SizedBox(width: double.infinity),
                ),
            ]);
        Widget timeTile(String key, String label) => ListTile(
              contentPadding: const EdgeInsets.only(left: 36, right: 20),
              title: Text(label),
              trailing: Text('${r[key]}',
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
              onTap: () => _time(key),
            );
        Widget stepper(String key, String label, int min, int max) => ListTile(
              contentPadding: const EdgeInsets.only(left: 36, right: 8),
              title: Text(label),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    onPressed: (r[key] as num) > min
                        ? () => store.setReminder(key, (r[key] as num).toInt() - 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline)),
                Text('${r[key]}', style: theme.textTheme.titleMedium),
                IconButton(
                    onPressed: (r[key] as num) < max
                        ? () => store.setReminder(key, (r[key] as num).toInt() + 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline)),
              ]),
            );
        return [
          if (_enabled == false)
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Уведомления выключены', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text('Без разрешения напоминания не придут.'),
                  const SizedBox(height: 10),
                  Row(children: [
                    FilledButton(
                      onPressed: () async {
                        await Reminders.requestPermission();
                        _check();
                      },
                      child: const Text('Разрешить'),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                        onPressed: Native.openAppSettings,
                        child: const Text('Настройки')),
                  ]),
                ]),
              ),
            ),
          const _Header(Icons.water_drop, 'Фазы цикла'),
          sw('soon', 'Скоро месячные', 'За несколько дней до ожидаемой даты',
              trailing: stepper('soonDays', 'За сколько дней', 1, 5)),
          sw('start', 'В день начала', 'Напомнить отметить начало месячных'),
          sw('end', 'Окончание месячных', 'Напомнить отметить последний день'),
          sw('fertile', 'Фертильные дни', 'За день до начала фертильного окна'),
          sw('ovulation', 'Овуляция', 'За день до ожидаемой овуляции'),
          timeTile('time', 'Время напоминаний о цикле'),
          sw('delay', 'Задержка', 'Если месячные не начались вовремя',
              trailing: stepper('delayDays', 'Через сколько дней задержки', 3, 30)),
          const _Header(Icons.medication, 'Таблетки и лекарства'),
          sw('pill', 'Противозачаточная таблетка', 'Каждый день',
              trailing: timeTile('pillTime', 'Время')),
          sw('meds', 'Лекарства', 'Каждый день',
              trailing: Column(children: [
                timeTile('medsTime', 'Время'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 0, 20, 8),
                  child: TextFormField(
                    initialValue: '${r['medsText']}',
                    decoration: const InputDecoration(hintText: 'Текст напоминания'),
                    onChanged: (v) => store.setReminder('medsText', v),
                  ),
                ),
              ])),
          const _Header(Icons.edit_note, 'Записи'),
          sw('note', 'Ежедневная заметка', 'Напоминать отметить самочувствие',
              trailing: timeTile('noteTime', 'Время')),
          sw('weekly', 'Если давно не было записей', 'Через неделю без записей'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton.icon(
              onPressed: () async {
                await Reminders.requestPermission();
                await Reminders.test(store);
                if (context.mounted) {
                  showSnack(context, 'Через 5 секунд придёт пробное уведомление');
                }
              },
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Проверить уведомление'),
            ),
          ),
          _note(context, 'Сейчас запланировано: $_pending.'),
          _note(context,
              'На Xiaomi и других телефонах с жёсткой экономией батареи разрешите '
              'приложению автозапуск и уберите ограничения батареи — иначе система '
              'может не показать напоминание вовремя.'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: Native.openAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Открыть настройки приложения'),
              ),
            ),
          ),
        ];
      },
    );
  }
}

// ---------------------------------------------------------------- шрифт

const fontScales = <(double, String)>[
  (0, 'Как в настройках телефона'),
  (0.8, 'Мелкий'),
  (0.9, 'Уменьшенный'),
  (1.0, 'Обычный'),
  (1.1, 'Крупный'),
];

String fontScaleLabel(double k) =>
    fontScales.firstWhere((e) => e.$1 == k, orElse: () => (k, '×$k')).$2;

class FontSizePage extends StatelessWidget {
  final Store store;
  const FontSizePage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Page(
      title: 'Размер шрифта',
      store: store,
      children: (context) => [
        _note(context,
            'Меняет размер текста во всём приложении. Изменение видно сразу.'),
        for (final (k, label) in fontScales)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(label),
            trailing: AnimatedSwitcher(
              duration: motion(context, 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: store.textScale == k
                  ? Icon(Icons.check_circle,
                      key: const ValueKey(true), color: theme.colorScheme.primary)
                  : const Icon(Icons.circle_outlined,
                      key: ValueKey(false), color: Colors.transparent),
            ),
            onTap: () => store.setLocal('textScale', k == 0 ? null : k),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Пример', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('20 дней до месячных', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('8 ноября, ±1 день',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.of(context).muted)),
              ]),
          ),
        ),
      ],
    );
  }
}

class SecretPage extends StatelessWidget {
  final Store store;
  const SecretPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    Widget card(bool secret, String text) {
      final sel = store.secretNotifications == secret;
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            store.setLocal('secret', secret);
          },
          child: AnimatedContainer(
            duration: motion(context, 220),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.of(context).card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: sel ? theme.colorScheme.primary : AppColors.of(context).cardBorder,
                  width: sel ? 2.5 : 1),
            ),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: secret ? Colors.grey : Palette.period,
                child: const Icon(Icons.circle_outlined, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Мой цикл', style: theme.textTheme.titleMedium),
                  Text(text, style: theme.textTheme.bodyMedium),
                ]),
              ),
              Radio<bool>(value: secret, groupValue: store.secretNotifications, onChanged: (_) {
                store.setLocal('secret', secret);
              }),
            ]),
          ),
        ),
      );
    }

    return _Page(
      title: 'Секретные напоминания',
      store: store,
      children: (context) => [
        _note(context, 'Выберите, как выглядят уведомления и виджет'),
        card(false, 'Месячные ожидаются в пятницу'),
        card(true, 'Ваше напоминание. Нажмите, чтобы посмотреть'),
      ],
    );
  }
}

// ---------------------------------------------------------------- защита

class SecurityPage extends StatefulWidget {
  final Store store;
  const SecurityPage({super.key, required this.store});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool _bioAvail = false;

  @override
  void initState() {
    super.initState();
    biometricAvailable().then((v) {
      if (mounted) setState(() => _bioAvail = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return _Page(
      title: 'Безопасный вход',
      store: store,
      children: (context) => [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('PIN-код'),
          subtitle: const Text('Спрашивать PIN при входе в приложение'),
          value: pinEnabled(store),
          onChanged: (v) async {
            if (v) {
              final pin = await setupPin(context);
              if (pin != null) {
                setPin(store, pin);
                if (context.mounted) showPinHint(context);
              }
            } else {
              setPin(store, null);
            }
          },
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: const Text('Отпечаток пальца или лицо'),
          subtitle: Text(_bioAvail
              ? 'Вместо PIN, если устройство поддерживает'
              : 'На этом телефоне недоступно или не настроено'),
          value: store.local<bool>('bio', false),
          onChanged: !pinEnabled(store) || !_bioAvail
              ? null
              : (v) async {
                  if (v && !await tryBiometric()) return;
                  store.setLocal('bio', v);
                },
        ),
        _note(context,
            'PIN хранится только на этом телефоне. Если забудете его — переустановите '
            'приложение и подключите сервер заново: данные вернутся.'),
      ],
    );
  }
}

class WidgetInfoPage extends StatelessWidget {
  const WidgetInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      'Нажмите и подержите пустое место на рабочем столе.',
      'Выберите «Виджеты».',
      'Найдите «Мой цикл» и перетащите виджет на экран.',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Виджет')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              color: const Color(0xFF2B2B2F),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: ThemeSpecScope.of(context).ring, width: 6),
            ),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Мой цикл', style: TextStyle(color: Colors.white70, fontFamily: kFont)),
              Text('12 дн.',
                  style: TextStyle(
                      color: Colors.white, fontSize: 38, fontFamily: kFont, fontWeight: FontWeight.w300)),
              Text('до месячных', style: TextStyle(color: Colors.white70, fontFamily: kFont)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < steps.length; i++)
          ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(steps[i], style: theme.textTheme.bodyLarge),
          ),
        _note(context,
            'Виджет обновляется сам каждый день. В режиме секретных напоминаний '
            'на нём не пишется слово «месячные».'),
      ]),
    );
  }
}

// ---------------------------------------------------------------- синхронизация

class SyncPage extends StatefulWidget {
  final Store store;
  const SyncPage({super.key, required this.store});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late final TextEditingController _url =
      TextEditingController(text: widget.store.serverUrl);
  late final TextEditingController _token =
      TextEditingController(text: widget.store.token);
  bool _showToken = false;
  bool _manual = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect(String url, String token) async {
    FocusScope.of(context).unfocus();
    _url.text = url;
    _token.text = token;
    await widget.store.setServer(url, token);
    if (mounted) {
      showSnack(
          context,
          widget.store.syncError == null
              ? 'Подключено, данные синхронизированы'
              : 'Ошибка: ${widget.store.syncError}');
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final code = Store.parseCode(data?.text ?? '');
    if (code == null) {
      if (mounted) {
        showSnack(context,
            'В буфере нет кода подключения. Скопируйте строку вида https://адрес#токен');
      }
      return;
    }
    await _connect(code.url, code.token);
  }

  String _lastSyncText() {
    final s = widget.store;
    if (s.syncing) return 'Синхронизация…';
    if (s.syncError != null) return 'Ошибка: ${s.syncError}';
    final l = s.lastSync;
    if (l == null) return 'Ещё не синхронизировалось';
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return 'Синхронизировано: ${l.day} ${monthsGen[l.month - 1]}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final theme = Theme.of(context);
    return _Page(
      title: 'Синхронизация',
      store: s,
      children: (context) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!s.syncConfigured) ...[
              Text(
                'Сервер ставится один раз на ваш VPS скриптом install-cycle-server.sh. '
                'В конце он покажет код подключения — строку вида https://адрес#токен. '
                'Скопируйте её и нажмите кнопку ниже. На втором телефоне — то же самое.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: s.syncing ? null : _pasteCode,
                icon: const Icon(Icons.content_paste),
                label: const Text('Вставить код подключения'),
              ),
            ] else ...[
              AppCard(
                child: Row(children: [
                  Icon(s.syncError == null ? Icons.cloud_done : Icons.cloud_off,
                      color: s.syncError == null ? theme.colorScheme.primary : theme.colorScheme.error,
                      size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl,
                          style: theme.textTheme.titleMedium),
                      Text(_lastSyncText(), style: theme.textTheme.bodyMedium),
                      if (s.pendingCount > 0)
                        Text('Не отправлено изменений: ${s.pendingCount}',
                            style: theme.textTheme.bodySmall),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: s.syncing ? null : s.sync,
                icon: const Icon(Icons.sync),
                label: const Text('Синхронизировать'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.connectionCode));
                  if (context.mounted) {
                    showSnack(context,
                        'Код скопирован. Перешлите его на второй телефон и вставьте там.');
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Код для второго телефона'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _manual = !_manual),
              icon: Icon(_manual ? Icons.expand_less : Icons.expand_more),
              label: Text(s.syncConfigured
                  ? 'Изменить адрес или токен'
                  : 'Ввести адрес и токен вручную'),
            ),
            AnimatedSize(
              duration: motion(context, 250),
              child: !_manual
                  ? const SizedBox(width: double.infinity)
                  : Column(children: [
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Адрес сервера',
                          hintText: 'https://cycle.atomicpel.cloud-ip.cc',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _token,
                        obscureText: !_showToken,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Токен',
                          helperText: 'На сервере: sudo cat /etc/cycle-sync.env',
                          suffixIcon: IconButton(
                            icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showToken = !_showToken),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: s.syncing ? null : () => _connect(_url.text, _token.text),
                          child: const Text('Сохранить и синхронизировать'),
                        ),
                      ),
                    ]),
            ),
          ]),
        ),
      ],
    );
  }
}
