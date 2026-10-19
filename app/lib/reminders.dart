import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'cycle.dart';
import 'store.dart';

/// Запланированное уведомление.
class PlannedNote {
  final int id;
  final DateTime when; // местное время
  final String title;
  final String body;
  final bool daily; // повторять каждый день в это время
  const PlannedNote(this.id, this.when, this.title, this.body,
      {this.daily = false});

  @override
  String toString() => '$id ${when.toIso8601String()} $title${daily ? ' (ежедневно)' : ''}';
}

({int h, int m}) _hm(Object? s, String def) {
  final str = (s is String && s.contains(':')) ? s : def;
  final p = str.split(':');
  return (h: int.tryParse(p[0]) ?? 9, m: int.tryParse(p[1]) ?? 0);
}

DateTime _at(DateTime day, ({int h, int m}) t) =>
    DateTime(day.year, day.month, day.day, t.h, t.m);

const _months = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];

String _days(int n) {
  final m10 = n % 10, m100 = n % 100;
  final w = (m10 == 1 && m100 != 11)
      ? 'день'
      : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14))
          ? 'дня'
          : 'дней';
  return '$n $w';
}

/// Составляет список уведомлений по прогнозу и настройкам.
/// Чистая функция — без обращения к телефону, её легко проверить тестом.
List<PlannedNote> planReminders({
  required Forecast f,
  required Map<String, dynamic> r,
  required DateTime now,
  required bool secret,
  bool pregnant = false,
  DateTime? lastLog,
  int cycles = 3,
}) {
  final out = <PlannedNote>[];
  final cycleTime = _hm(r['time'], '09:00');
  String t(String title) => secret ? 'Мой цикл' : title;
  String b(String body) =>
      secret ? 'Ваше напоминание. Нажмите, чтобы посмотреть' : body;
  void add(int id, DateTime when, String title, String body) {
    if (when.isAfter(now)) out.add(PlannedNote(id, when, t(title), b(body)));
  }

  if (!pregnant && f.periods.isNotEmpty) {
    final int soonDays =
        math.min(7, math.max(1, ((r['soonDays'] as num?) ?? 2).toInt()));
    for (var i = 0; i < f.predicted.length && i < cycles; i++) {
      final p = f.predicted[i];
      if (f.delay > 0 && i == 0) continue; // при задержке — отдельное
      final base = 100 + i * 10;
      if (r['soon'] == true) {
        final d = addDays(p.start, -soonDays);
        add(base, _at(d, cycleTime), 'Скоро месячные',
            'Ожидаются через ${_days(soonDays)}, ${p.start.day} ${_months[p.start.month - 1]}.');
      }
      if (r['start'] == true) {
        add(base + 1, _at(p.start, cycleTime), 'Месячные ожидаются сегодня',
            'Если начались — отметьте в приложении.');
      }
      if (r['end'] == true) {
        add(base + 2, _at(p.end, (h: 20, m: 0)), 'Месячные закончились?',
            'Отметьте последний день — прогноз станет точнее.');
      }
    }
    // Окончание текущих месячных
    final last = f.last!;
    final todayD = dateOnly(now);
    if (r['end'] == true && last.contains(todayD)) {
      final expectedEnd = addDays(last.start, f.periodLength - 1);
      add(99, _at(expectedEnd, (h: 20, m: 0)), 'Месячные закончились?',
          'Отметьте последний день — прогноз станет точнее.');
    }
    // Фертильность и овуляция
    var from = todayD;
    for (var i = 0; i < cycles; i++) {
      final ov = f.nextOvulation(from);
      if (ov == null) break;
      if (r['fertile'] == true) {
        add(200 + i * 2, _at(addDays(ov, -6), cycleTime),
            'Завтра начинаются фертильные дни', 'Вероятность беременности выше обычного.');
      }
      if (r['ovulation'] == true) {
        add(201 + i * 2, _at(addDays(ov, -1), cycleTime), 'Завтра ожидается овуляция',
            'По прогнозу приложения.');
      }
      from = addDays(ov, 1);
    }
    // Задержка
    if (r['delay'] == true && f.periods.isNotEmpty) {
      final dd = ((r['delayDays'] as num?) ?? 15).toInt();
      final expected = addDays(last.start, f.cycleLength);
      final when = addDays(expected, dd);
      add(5, _at(when, cycleTime), 'Цикл задерживается',
          'Задержка ${_days(dd)}. Если нужно — сделайте тест.');
    }
  }

  // Ежедневные
  if (r['pill'] == true) {
    final tm = _hm(r['pillTime'], '21:00');
    out.add(PlannedNote(1, _nextAt(now, tm), t('Время принять таблетку'),
        b('Отметьте приём в приложении.'),
        daily: true));
  }
  if (r['meds'] == true) {
    final tm = _hm(r['medsTime'], '09:00');
    final text = '${r['medsText'] ?? ''}'.trim();
    out.add(PlannedNote(2, _nextAt(now, tm), t('Время принять лекарство'),
        b(text.isEmpty ? 'Не забудьте про лекарство.' : text),
        daily: true));
  }
  if (r['note'] == true) {
    final tm = _hm(r['noteTime'], '21:00');
    out.add(PlannedNote(3, _nextAt(now, tm), t('Как прошёл день?'),
        b('Отметьте самочувствие и настроение.'),
        daily: true));
  }
  if (r['weekly'] == true) {
    final base = lastLog ?? dateOnly(now);
    var when = _at(addDays(base, 7), (h: 19, m: 0));
    if (!when.isAfter(now)) when = _at(addDays(dateOnly(now), 7), (h: 19, m: 0));
    out.add(PlannedNote(4, when, t('Давно не было записей'),
        b('Загляните и отметьте самочувствие.')));
  }
  return out;
}

DateTime _nextAt(DateTime now, ({int h, int m}) t) {
  var d = DateTime(now.year, now.month, now.day, t.h, t.m);
  if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
  return d;
}

/// Работа с системными уведомлениями.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'cycle_reminders',
    'Напоминания',
    channelDescription: 'Напоминания о цикле, таблетках и записях',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    color: Color(0xFF8EA7E9),
  );

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notifications init: $e');
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Запрашивает разрешение на уведомления (Android 13+).
  static Future<bool> requestPermission() async {
    await init();
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async {
    await init();
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  static tz.TZDateTime _tz(DateTime local) => tz.TZDateTime.from(local, tz.UTC);

  static Future<void> _schedule(PlannedNote n) async {
    final details = const NotificationDetails(android: _channel);
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          scheduledDate: _tz(n.when),
          notificationDetails: details,
          androidScheduleMode: mode,
          matchDateTimeComponents: n.daily ? DateTimeComponents.time : null,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (e) {
      // Нет разрешения на точные будильники — ставим неточное
      await go(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Перепланирует все уведомления.
  static Future<int> apply(List<PlannedNote> notes) async {
    await init();
    if (!_ready) return 0;
    try {
      await _plugin.cancelAll();
      for (final n in notes) {
        await _schedule(n);
      }
      return notes.length;
    } catch (e) {
      debugPrint('notifications schedule: $e');
      return 0;
    }
  }

  /// Пробное уведомление через [seconds] секунд.
  static Future<void> test(Store store, {int seconds = 5}) async {
    await init();
    final secret = store.secretNotifications;
    await _schedule(PlannedNote(
      9,
      DateTime.now().add(Duration(seconds: seconds)),
      secret ? 'Мой цикл' : 'Проверка напоминаний',
      secret ? 'Ваше напоминание. Нажмите, чтобы посмотреть' : 'Уведомления работают.',
    ));
  }

  static Future<List<PendingNotificationRequest>> pending() async {
    await init();
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (_) {
      return const [];
    }
  }

  /// Перепланировать по текущим данным.
  static Future<int> reschedule(Store store) {
    final logs = store.loggedDays;
    final notes = planReminders(
      f: store.forecast,
      r: store.reminders,
      now: DateTime.now(),
      secret: store.secretNotifications,
      pregnant: store.pregnancy != null,
      lastLog: logs.isEmpty ? null : logs.first.key,
    );
    return apply(notes);
  }
}
