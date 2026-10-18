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
      final lines = text.split(RegExp(r'\s+')).where((l) => l.isNotEmpty).toList();
      if (lines.length != 2) return null;
      url = lines[0];
      tok = lines[1];
    }
    url = url.trim();
    tok = tok.trim();
    if (tok.length < 16 || !RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(tok)) return null;
    if (!url.contains('.') || url.contains(' ')) return null;
    return (url: url, token: tok);
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

  Forecast get forecast => _forecastCache ??= computeForecast(periodDays);

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
