import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cycle.dart';
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

class Store extends ChangeNotifier {
  final Prefs _prefs;
  final Map<String, Rec> _recs;
  int _lastRev;
  String serverUrl;
  String token;
  DateTime? lastSync;
  String? syncError;
  bool syncing = false;

  Timer? _debounce;
  Forecast? _forecastCache;

  Store._(this._prefs, this._recs, this._lastRev, this.serverUrl, this.token,
      this.lastSync);

  static Future<Store> load() async {
    final p = await Prefs.open();
    final recs = <String, Rec>{};
    final raw = p.getString('recs');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((k, v) => recs[k] = Rec.fromJson(v as Map<String, dynamic>));
    }
    final ls = p.getInt('lastSync');
    return Store._(
      p,
      recs,
      p.getInt('lastRev') ?? 0,
      p.getString('server') ?? '',
      p.getString('token') ?? '',
      ls == null ? null : DateTime.fromMillisecondsSinceEpoch(ls),
    );
  }

  bool get syncConfigured => serverUrl.isNotEmpty && token.isNotEmpty;
  int get pendingCount => _recs.values.where((r) => r.dirty).length;

  // ---------- данные ----------

  Map<String, dynamic> _dayValue(DateTime d) {
    final r = _recs['day:${dayKey(d)}'];
    if (r == null || r.deleted || r.value is! Map) return {};
    return Map<String, dynamic>.from(r.value as Map);
  }

  bool isPeriod(DateTime d) => _dayValue(d)['p'] == true;
  String noteFor(DateTime d) => (_dayValue(d)['n'] as String?) ?? '';

  Set<DateTime> get periodDays {
    final s = <DateTime>{};
    _recs.forEach((k, r) {
      if (k.startsWith('day:') && !r.deleted && r.value is Map &&
          (r.value as Map)['p'] == true) {
        s.add(parseDayKey(k.substring(4)));
      }
    });
    return s;
  }

  List<MapEntry<DateTime, String>> get notes {
    final res = <MapEntry<DateTime, String>>[];
    _recs.forEach((k, r) {
      if (k.startsWith('day:') && !r.deleted && r.value is Map) {
        final n = (r.value as Map)['n'];
        if (n is String && n.trim().isNotEmpty) {
          res.add(MapEntry(parseDayKey(k.substring(4)), n));
        }
      }
    });
    res.sort((a, b) => b.key.compareTo(a.key));
    return res;
  }

  Map<String, dynamic> get _settings {
    final r = _recs['settings'];
    if (r == null || r.deleted || r.value is! Map) return {};
    return Map<String, dynamic>.from(r.value as Map);
  }

  int get defaultCycle => (_settings['cycle'] as num?)?.toInt() ?? 28;
  int get defaultPeriod => (_settings['period'] as num?)?.toInt() ?? 5;

  Forecast get forecast => _forecastCache ??= computeForecast(periodDays,
      defaultCycle: defaultCycle, defaultPeriod: defaultPeriod);

  void _put(String key, Object? value, {bool deleted = false}) {
    _recs[key] = Rec(value, DateTime.now().millisecondsSinceEpoch,
        deleted: deleted, dirty: true);
  }

  void _setDayNoSave(DateTime d, {bool? period, String? note}) {
    final v = _dayValue(d);
    if (period != null) v['p'] = period;
    if (note != null) v['n'] = note.trim();
    final empty = v['p'] != true && ((v['n'] as String?) ?? '').isEmpty;
    _put('day:${dayKey(d)}', empty ? null : v, deleted: empty);
  }

  void setDay(DateTime d, {bool? period, String? note}) {
    _setDayNoSave(d, period: period, note: note);
    _changed();
  }

  /// Отмечает [length] дней месячных начиная с [start].
  void markPeriod(DateTime start, int length) {
    for (var i = 0; i < length; i++) {
      _setDayNoSave(addDays(start, i), period: true);
    }
    _changed();
  }

  void clearPeriod(Period p) {
    for (var d = p.start; !d.isAfter(p.end); d = addDays(d, 1)) {
      if (isPeriod(d)) _setDayNoSave(d, period: false);
    }
    _changed();
  }

  void setDefaults({int? cycle, int? period}) {
    final v = _settings;
    if (cycle != null) v['cycle'] = cycle;
    if (period != null) v['period'] = period;
    _put('settings', v);
    _changed();
  }

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
      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

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
