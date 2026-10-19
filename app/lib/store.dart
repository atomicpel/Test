import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cycle.dart';
import 'day_entry.dart';
import 'prefs.dart';

/// Одна запись, синхронизируемая с сервером.
class Rec {
  Object? value;
  int updatedAt;
  bool deleted;
  bool dirty;

  Rec(this.value, this.updatedAt, {this.deleted = false, this.dirty = false});

  Map<String, dynamic> toJson() =>
      {'v': value, 'u': updatedAt, 'x': deleted, 'd': dirty};

  factory Rec.fromJson(Map<String, dynamic> j) => Rec(
        j['v'],
        (j['u'] as num).toInt(),
        deleted: j['x'] == true,
        dirty: j['d'] == true,
      );
}

/// Результат импорта.
class ImportResult {
  final int periods;
  final int days;
  final String? error;
  const ImportResult(this.periods, this.days, [this.error]);
}

/// Напоминания по умолчанию (настраиваются на каждом телефоне отдельно).
const defaultReminders = <String, dynamic>{
  'soon': true, // за N дней до месячных
  'soonDays': 2,
  'start': true, // в ожидаемый день
  'end': false, // напомнить отметить окончание
  'fertile': false,
  'ovulation': false,
  'pill': false,
  'pillTime': '21:00',
  'meds': false,
  'medsTime': '09:00',
  'medsText': '',
  'note': false,
  'noteTime': '21:00',
  'weekly': false,
  'delay': true,
  'delayDays': 15,
  'time': '09:00', // время напоминаний о цикле
};

class Store extends ChangeNotifier {
  final Prefs _prefs;
  final Map<String, Rec> _recs;
  int _lastRev;
  String serverUrl;
  String token;
  DateTime? lastSync;
  String? syncError;
  bool syncing = false;
  final Map<String, dynamic> _local;

  Timer? _debounce;
  Forecast? _forecastCache;

  Store._(this._prefs, this._recs, this._lastRev, this.serverUrl, this.token,
      this.lastSync, this._local);

  static Future<Store> load() async => loadFrom(await Prefs.open());

  static Store loadFrom(Prefs p) {
    final recs = <String, Rec>{};
    final raw = p.getString('recs');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((k, v) => recs[k] = Rec.fromJson(v as Map<String, dynamic>));
    }
    final ls = p.getInt('lastSync');
    Map<String, dynamic> local = {};
    final lr = p.getString('local');
    if (lr != null) {
      try {
        local = Map<String, dynamic>.from(jsonDecode(lr) as Map);
      } catch (_) {}
    }
    return Store._(
      p,
      recs,
      p.getInt('lastRev') ?? 0,
      p.getString('server') ?? '',
      p.getString('token') ?? '',
      ls == null ? null : DateTime.fromMillisecondsSinceEpoch(ls),
      local,
    );
  }

  /// Одна строка «адрес#токен» — удобно передать на второй телефон.
  String get connectionCode => syncConfigured ? '$serverUrl#$token' : '';

  /// Разбирает код подключения. Понимает «адрес#токен» и две строки
  /// «адрес» и «токен». Возвращает null, если это не код.
  static ({String url, String token})? parseCode(String raw) {
    final text = raw.trim();
    String url, tok;
    if (text.contains('#')) {
      final i = text.indexOf('#');
      url = text.substring(0, i);
      tok = text.substring(i + 1);
    } else {
      final lines =
          text.split(RegExp(r'\s+')).where((l) => l.isNotEmpty).toList();
      if (lines.length != 2) return null;
      url = lines[0];
      tok = lines[1];
    }
    url = url.trim();
    tok = tok.trim();
    if (tok.length < 16 || !RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(tok)) {
      return null;
    }
    if (!url.contains('.') || url.contains(' ')) return null;
    return (url: url, token: tok);
  }

  bool get syncConfigured => serverUrl.isNotEmpty && token.isNotEmpty;
  int get pendingCount => _recs.values.where((r) => r.dirty).length;

  // ---------- записи дней ----------

  Map<String, dynamic> _dayValue(DateTime d) {
    final r = _recs['day:${dayKey(d)}'];
    if (r == null || r.deleted || r.value is! Map) return {};
    return Map<String, dynamic>.from(r.value as Map);
  }

  DayData day(DateTime d) => DayData(_dayValue(d));

  bool isPeriod(DateTime d) => _dayValue(d)['p'] == true;
  String noteFor(DateTime d) => (_dayValue(d)['n'] as String?) ?? '';

  Set<DateTime> get periodDays {
    final s = <DateTime>{};
    _recs.forEach((k, r) {
      if (k.startsWith('day:') &&
          !r.deleted &&
          r.value is Map &&
          (r.value as Map)['p'] == true) {
        s.add(parseDayKey(k.substring(4)));
      }
    });
    return s;
  }

  /// Все дни с записями (кроме одной только отметки месячных), новые сверху.
  List<MapEntry<DateTime, DayData>> get loggedDays {
    final res = <MapEntry<DateTime, DayData>>[];
    _recs.forEach((k, r) {
      if (k.startsWith('day:') && !r.deleted && r.value is Map) {
        final dd = DayData(Map<String, dynamic>.from(r.value as Map));
        if (dd.hasLog || dd.period) {
          res.add(MapEntry(parseDayKey(k.substring(4)), dd));
        }
      }
    });
    res.sort((a, b) => b.key.compareTo(a.key));
    return res;
  }

  List<MapEntry<DateTime, String>> get notes => [
        for (final e in loggedDays)
          if (e.value.note.trim().isNotEmpty) MapEntry(e.key, e.value.note)
      ];

  Forecast get forecast => _forecastCache ??= computeForecast(periodDays);

  void _put(String key, Object? value, {bool deleted = false}) {
    _recs[key] = Rec(value, DateTime.now().millisecondsSinceEpoch,
        deleted: deleted, dirty: true);
  }

  void _patchNoSave(DateTime d, Map<String, dynamic> changes) {
    final v = DayData.merge(_dayValue(d), changes);
    final empty = DayData(v).isEmpty;
    _put('day:${dayKey(d)}', empty ? null : v, deleted: empty);
  }

  /// Меняет поля записи дня. null/пустое значение удаляет поле.
  void patchDay(DateTime d, Map<String, dynamic> changes) {
    _patchNoSave(dateOnly(d), changes);
    _changed();
  }

  void setDay(DateTime d, {bool? period, String? note}) {
    patchDay(d, {
      if (period != null) 'p': period,
      if (note != null) 'n': note,
    });
  }

  /// Отмечает [length] дней месячных начиная с [start].
  void markPeriod(DateTime start, int length) {
    for (var i = 0; i < length; i++) {
      _patchNoSave(addDays(start, i), {'p': true});
    }
    _changed();
  }

  void clearPeriod(Period p) {
    for (var d = p.start; !d.isAfter(p.end); d = addDays(d, 1)) {
      if (isPeriod(d)) _patchNoSave(d, {'p': false, 'f': 0});
    }
    _changed();
  }

  /// Месячные закончились в день [d]: снимаем отметки после него.
  void endPeriodOn(DateTime d) {
    final last = forecast.last;
    if (last == null) return;
    for (var x = addDays(d, 1); !x.isAfter(last.end); x = addDays(x, 1)) {
      _patchNoSave(x, {'p': false, 'f': 0});
    }
    _changed();
  }

  // ---------- общие настройки (синхронизируются) ----------

  Map<String, dynamic> get _settings {
    final r = _recs['settings'];
    if (r == null || r.deleted || r.value is! Map) return {};
    return Map<String, dynamic>.from(r.value as Map);
  }

  T setting<T>(String key, T def) {
    final v = _settings[key];
    return v is T ? v : def;
  }

  void setSetting(String key, Object? value) {
    final s = _settings;
    if (value == null) {
      s.remove(key);
    } else {
      s[key] = value;
    }
    _put('settings', s);
    _changed();
  }

  String get name => setting<String>('name', '');
  String? get contraception => _settings['contra'] as String?;
  bool get pillTracking => contraception == 'pill';

  DateTime? get pregnancyLmp {
    final v = _settings['pregLmp'];
    return v is String ? parseDayKey(v) : null;
  }

  Pregnancy? get pregnancy =>
      pregnancyLmp == null ? null : Pregnancy(pregnancyLmp!);

  /// Что показывать в календаре: интим, фертильность, таблетки.
  bool calShow(String key) {
    final m = _settings['cal'];
    if (m is Map && m[key] is bool) return m[key] as bool;
    return true;
  }

  void setCalShow(String key, bool v) {
    final m = Map<String, dynamic>.from((_settings['cal'] as Map?) ?? {});
    m[key] = v;
    setSetting('cal', m);
  }

  /// Видимые разделы записи дня по порядку.
  List<String> get sections {
    final v = _settings['sections'];
    if (v is List) return v.map((e) => '$e').toList();
    return allSections.map((s) => s.id).toList();
  }

  /// Свои пункты: 's' — симптомы, 'm' — настроение, 'md' — лекарства.
  List<String> custom(String kind) {
    final m = _settings['custom'];
    if (m is Map && m[kind] is List) {
      return (m[kind] as List).map((e) => '$e').toList();
    }
    return const [];
  }

  void addCustom(String kind, String label) {
    final m = Map<String, dynamic>.from((_settings['custom'] as Map?) ?? {});
    final list = custom(kind).toList();
    final id = 'c:${label.trim()}';
    if (label.trim().isEmpty || list.contains(id)) return;
    list.add(id);
    m[kind] = list;
    setSetting('custom', m);
  }

  // ---------- настройки этого телефона (не синхронизируются) ----------

  T local<T>(String key, T def) {
    final v = _local[key];
    return v is T ? v : def;
  }

  void setLocal(String key, Object? value) {
    if (value == null) {
      _local.remove(key);
    } else {
      _local[key] = value;
    }
    _prefs.setString('local', jsonEncode(_local));
    notifyListeners();
  }

  String get themeId => local<String>('theme', 'cats');
  bool get dark => local<bool>('dark', true);
  bool get secretNotifications => local<bool>('secret', false);

  Map<String, dynamic> get reminders {
    final m = Map<String, dynamic>.from(defaultReminders);
    final saved = _local['reminders'];
    if (saved is Map) m.addAll(Map<String, dynamic>.from(saved));
    return m;
  }

  void setReminder(String key, Object value) {
    final m = Map<String, dynamic>.from((_local['reminders'] as Map?) ?? {});
    m[key] = value;
    setLocal('reminders', m);
  }

  // ---------- общие изменения ----------

  void _changed() {
    _forecastCache = null;
    _save();
    notifyListeners();
    if (syncConfigured) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), sync);
    }
  }

  void _save() {
    _prefs.setString(
        'recs', jsonEncode(_recs.map((k, v) => MapEntry(k, v.toJson()))));
    _prefs.setInt('lastRev', _lastRev);
  }

  // ---------- импорт, экспорт, удаление ----------

  /// Экспорт всех записей в JSON (можно потом импортировать обратно).
  String exportJson() {
    final days = <String, dynamic>{};
    _recs.forEach((k, r) {
      if (k.startsWith('day:') && !r.deleted && r.value != null) {
        days[k.substring(4)] = r.value;
      }
    });
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'my-cycle',
      'version': 1,
      'exported': DateTime.now().toIso8601String(),
      'settings': _settings,
      'days': days,
    });
  }

  /// Импорт: JSON из экспорта или строки «ГГГГ-ММ-ДД длительность»
  /// (также «ДД.ММ.ГГГГ 5»). Существующие записи не стираются.
  ImportResult importText(String text) {
    final t = text.trim();
    if (t.isEmpty) return const ImportResult(0, 0, 'Пусто');
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t) as Map<String, dynamic>;
        final days = (m['days'] as Map?) ?? {};
        var n = 0;
        days.forEach((k, v) {
          if (v is Map) {
            final d = parseDayKey('$k');
            _patchNoSave(d, Map<String, dynamic>.from(v));
            n++;
          }
        });
        final st = m['settings'];
        if (st is Map && _settings.isEmpty) {
          _put('settings', Map<String, dynamic>.from(st));
        }
        _changed();
        return ImportResult(0, n);
      } catch (e) {
        return const ImportResult(0, 0, 'Не удалось прочитать JSON');
      }
    }
    final re = RegExp(
        r'(\d{4})-(\d{1,2})-(\d{1,2})|(\d{1,2})\.(\d{1,2})\.(\d{4})');
    var periods = 0;
    for (final line in t.split(RegExp(r'[\r\n;]+'))) {
      final mm = re.firstMatch(line);
      if (mm == null) continue;
      DateTime d;
      if (mm.group(1) != null) {
        d = DateTime.utc(int.parse(mm.group(1)!), int.parse(mm.group(2)!),
            int.parse(mm.group(3)!));
      } else {
        d = DateTime.utc(int.parse(mm.group(6)!), int.parse(mm.group(5)!),
            int.parse(mm.group(4)!));
      }
      final rest = line.substring(mm.end);
      final lm = RegExp(r'\d+').firstMatch(rest);
      var len = lm == null ? forecast.periodLength : int.parse(lm.group(0)!);
      if (len < 1 || len > 12) len = forecast.periodLength;
      for (var i = 0; i < len; i++) {
        _patchNoSave(addDays(d, i), {'p': true});
      }
      periods++;
    }
    if (periods == 0) {
      return const ImportResult(0, 0, 'Не нашёл дат. Формат: 2026-08-23 5');
    }
    _changed();
    return ImportResult(periods, 0);
  }

  /// Удаляет все записи (на сервере тоже — через синхронизацию).
  void deleteAll() {
    final keys = _recs.keys.toList();
    for (final k in keys) {
      if (k.startsWith('day:') || k == 'settings') {
        _put(k, null, deleted: true);
      }
    }
    _changed();
  }

  // ---------- синхронизация ----------

  Future<void> setServer(String url, String tok) async {
    url = url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isNotEmpty && !url.startsWith('http')) url = 'https://$url';
    final changed = url != serverUrl;
    serverUrl = url;
    token = tok.trim();
    await _prefs.setString('server', serverUrl);
    await _prefs.setString('token', token);
    if (changed) {
      // Новый сервер: забираем всё заново и отправляем всё своё
      _lastRev = 0;
      for (final r in _recs.values) {
        r.dirty = true;
      }
      _save();
    }
    notifyListeners();
    await sync();
  }

  Future<void> sync() async {
    if (!syncConfigured || syncing) return;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final sent = <String, int>{};
      final changes = <Map<String, dynamic>>[];
      _recs.forEach((k, r) {
        if (r.dirty) {
          sent[k] = r.updatedAt;
          changes.add({
            'key': k,
            'value': r.value,
            'updated_at': r.updatedAt,
            'deleted': r.deleted,
          });
        }
      });
      final resp = await http
          .post(
            Uri.parse('$serverUrl/api/sync'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'since': _lastRev, 'changes': changes}),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 401) throw 'Неверный токен';
      if (resp.statusCode != 200) throw 'Ошибка сервера ${resp.statusCode}';
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

      sent.forEach((k, u) {
        final r = _recs[k];
        if (r != null && r.updatedAt == u) r.dirty = false;
      });
      for (final c in (body['changes'] as List)) {
        final m = c as Map<String, dynamic>;
        final key = m['key'] as String;
        final u = (m['updated_at'] as num).toInt();
        final local = _recs[key];
        if (local == null || !local.dirty || u >= local.updatedAt) {
          _recs[key] = Rec(m['value'], u, deleted: m['deleted'] == true);
        }
      }
      _lastRev = (body['rev'] as num).toInt();
      lastSync = DateTime.now();
      await _prefs.setInt('lastSync', lastSync!.millisecondsSinceEpoch);
      _forecastCache = null;
      _save();
    } on TimeoutException {
      syncError = 'Сервер не отвечает';
    } catch (e) {
      syncError = e is String ? e : 'Нет связи с сервером';
      debugPrint('sync error: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
