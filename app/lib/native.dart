import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'reminders.dart';
import 'store.dart';

/// Свой небольшой канал к Android (код в MainActivity.kt):
/// виджет, «Поделиться», настройки приложения.
class Native {
  static const _ch = MethodChannel('ru.atomicpel.cycle/native');

  static Future<void> _call(String m, [Map<String, Object?>? a]) async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod(m, a);
    } catch (e) {
      debugPrint('native $m: $e');
    }
  }

  static Future<void> share(String text, {String subject = ''}) =>
      _call('share', {'text': text, 'subject': subject});

  static Future<void> openAppSettings() => _call('openAppSettings');

  static Future<void> updateWidget(Store s) {
    final f = s.forecast;
    final preg = s.pregnancy;
    final last = f.last;
    return _call('updateWidget', {
      'mode': preg != null ? 'preg' : (last == null ? 'none' : 'cycle'),
      'lastStart': last == null ? -1 : epochDay(last.start),
      'lastEnd': last == null ? -1 : epochDay(last.end),
      'periodLen': f.periodLength,
      'nextStart': f.nextStart == null ? -1 : epochDay(f.nextStart!),
      'cycleLen': f.cycleLength,
      'lmp': preg == null ? -1 : epochDay(preg.lmp),
      'secret': s.secretNotifications,
      'ring': s.local<int>('ringColor', 0xFFD2A679),
    });
  }
}

/// Следит за данными и после изменений обновляет напоминания и виджет.
class AppServices {
  final Store store;
  Timer? _t;
  String _lastKey = '';

  AppServices(this.store) {
    store.addListener(_onChange);
    _run();
  }

  void _onChange() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1500), _run);
  }

  Future<void> _run() async {
    // Не перепланируем, если ничего важного не поменялось
    final f = store.forecast;
    final logs = store.loggedDays;
    final key = [
      f.periods.length,
      f.last?.start,
      f.last?.end,
      f.cycleLength,
      f.periodLength,
      f.delay,
      store.reminders.toString(),
      store.secretNotifications,
      store.pregnancyLmp,
      logs.isEmpty ? null : logs.first.key,
      dateOnly(DateTime.now()),
    ].join('|');
    if (key == _lastKey) return;
    _lastKey = key;
    await Reminders.reschedule(store);
    await Native.updateWidget(store);
  }

  /// Принудительно (например, при возвращении в приложение).
  Future<void> refresh() {
    _lastKey = '';
    return _run();
  }

  void dispose() {
    _t?.cancel();
    store.removeListener(_onChange);
  }
}
