import 'dart:convert';
import 'dart:io';

/// Простое хранилище ключ-значение в JSON-файле внутри папки приложения.
/// Без нативных плагинов: на Android Directory.systemTemp — это
/// /data/user/0/<пакет>/cache, данные кладём рядом, в .../files.
class Prefs {
  final File? _file;
  final Map<String, dynamic> _data;

  Prefs._(this._file, this._data);

  /// Хранилище только в памяти — для тестов и скриншотов.
  Prefs.memory() : _file = null, _data = {};

  static Future<Prefs> open() async {
    Directory dir;
    try {
      dir = Directory('${Directory.systemTemp.parent.path}/files');
      if (!await dir.exists()) await dir.create(recursive: true);
      // проверяем, что туда можно писать
      final probe = File('${dir.path}/.probe');
      await probe.writeAsString('1');
      await probe.delete();
    } catch (_) {
      dir = Directory('${Directory.systemTemp.path}/my_cycle');
      if (!await dir.exists()) await dir.create(recursive: true);
    }
    return openAt(dir);
  }

  static Future<Prefs> openAt(Directory dir) async {
    final file = File('${dir.path}/my_cycle.json');
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Повреждённый файл: пробуем резервную копию
        final bak = File('${file.path}.bak');
        if (await bak.exists()) {
          try {
            data = jsonDecode(await bak.readAsString()) as Map<String, dynamic>;
          } catch (_) {}
        }
      }
    }
    return Prefs._(file, data);
  }

  String? getString(String k) => _data[k] as String?;
  int? getInt(String k) => (_data[k] as num?)?.toInt();

  Future<void> setString(String k, String v) => _set(k, v);
  Future<void> setInt(String k, int v) => _set(k, v);

  Future<void> _set(String k, Object v) {
    _data[k] = v;
    return _flush();
  }

  Future<void>? _pending;
  bool _again = false;

  /// Пишем во временный файл и переименовываем — файл не побьётся,
  /// даже если приложение закроют во время записи.
  Future<void> _flush() {
    final file = _file;
    if (file == null) return Future.value();
    if (_pending != null) {
      _again = true;
      return _pending!;
    }
    _pending = () async {
      do {
        _again = false;
        final text = jsonEncode(_data);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(text, flush: true);
        if (await file.exists()) {
          await file.copy('${file.path}.bak');
        }
        await tmp.rename(file.path);
      } while (_again);
    }();
    return _pending!.whenComplete(() => _pending = null);
  }
}
