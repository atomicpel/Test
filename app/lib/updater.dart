import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'store.dart';
import 'widgets_common.dart';

/// Описание версии с сервера (/app/version.json).
class UpdateInfo {
  final String version;
  final int build;
  final int size;
  final String sha256;
  final Uri url;
  const UpdateInfo(this.version, this.build, this.size, this.sha256, this.url);

  String get sizeText => '${(size / 1048576).toStringAsFixed(1)} МБ';
}

/// Обновления приложения с собственного сервера: проверка версии,
/// загрузка APK с проверкой контрольной суммы и запуск установки.
class Updater {
  static const _ch = MethodChannel('ru.atomicpel.cycle/native');
  static const _autoEvery = Duration(hours: 6);
  static bool _busy = false;

  /// Установленная версия: (название, номер сборки).
  static Future<({String name, int code})?> current() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('appVersion');
      if (m == null) return null;
      return (
        name: '${m['name'] ?? ''}',
        code: (m['code'] as num?)?.toInt() ?? 0
      );
    } catch (e) {
      debugPrint('appVersion: $e');
      return null;
    }
  }

  static String? _base(Store s) {
    final u = s.serverUrl.trim();
    if (u.isEmpty) return null;
    return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  /// Есть ли версия новее установленной. null — нет обновления или нет связи.
  static Future<UpdateInfo?> check(Store s) async {
    final base = _base(s);
    final cur = await current();
    if (base == null || cur == null) return null;
    final r = await http
        .get(Uri.parse('$base/app/version.json'))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final build = (j['build'] as num?)?.toInt() ?? 0;
    if (build <= cur.code) return null;
    final url = Uri.parse(base).resolve('${j['url'] ?? '/app/MyCycle.apk'}');
    return UpdateInfo('${j['version'] ?? build}', build,
        (j['size'] as num?)?.toInt() ?? 0, '${j['sha256'] ?? ''}', url);
  }

  /// Загрузка APK во временную папку приложения с прогрессом 0..1.
  static Future<File> download(UpdateInfo u, void Function(double) onProgress) async {
    final dir = Directory('${Directory.systemTemp.path}/updates');
    await dir.create(recursive: true);
    final file = File('${dir.path}/MyCycle.apk');
    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', u.url))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw HttpException('Сервер ответил ${resp.statusCode}');
      }
      final total = resp.contentLength ?? u.size;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      final digest = sha256.convert(await file.readAsBytes()).toString();
      if (u.sha256.isNotEmpty && digest != u.sha256) {
        await file.delete();
        throw const FormatException('Файл повреждён при загрузке, попробуйте ещё раз');
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Запуск системной установки. false — нужно разрешить установку
  /// из этого приложения (открыт экран настроек).
  static Future<bool> install(File f) async {
    final r = await _ch.invokeMethod<String>('installApk', {'path': f.path});
    return r == 'ok';
  }

  /// Тихая проверка при запуске/возврате в приложение (не чаще раза в 6 часов).
  static Future<void> autoCheck(BuildContext context, Store s) async {
    if (_busy) return;
    final last = s.local<int>('updCheckedAt', 0);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < _autoEvery.inMilliseconds) return;
    _busy = true;
    try {
      final u = await check(s);
      s.setLocal('updCheckedAt', now);
      if (u == null || s.local<int>('updSkip', 0) == u.build) return;
      if (context.mounted) await showUpdateDialog(context, s, u);
    } catch (e) {
      debugPrint('update check: $e');
    } finally {
      _busy = false;
    }
  }

  /// Проверка по кнопке в настройках.
  static Future<void> manualCheck(BuildContext context, Store s) async {
    if (_base(s) == null) {
      showSnack(context, 'Сначала подключите свой сервер в разделе «Синхронизация»');
      return;
    }
    try {
      final u = await check(s);
      if (!context.mounted) return;
      if (u == null) {
        showSnack(context, 'Установлена последняя версия');
      } else {
        await showUpdateDialog(context, s, u);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Не удалось проверить: сервер недоступен');
    }
  }
}

Future<void> showUpdateDialog(BuildContext context, Store s, UpdateInfo u) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(store: s, info: u),
  );
}

class _UpdateDialog extends StatefulWidget {
  final Store store;
  final UpdateInfo info;
  const _UpdateDialog({required this.store, required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null — ещё не начали
  String? _error;
  File? _file;

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final f = _file ??
          await Updater.download(widget.info, (p) {
            if (mounted) setState(() => _progress = p);
          });
      _file = f;
      if (!mounted) return;
      setState(() => _progress = 1);
      final ok = await Updater.install(f);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _progress = null;
          _error = 'Разрешите установку из приложения «Мой цикл» '
              'в открывшихся настройках, вернитесь и нажмите «Установить».';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = e is FormatException ? e.message : 'Не удалось скачать: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = widget.info;
    final loading = _progress != null;
    return AlertDialog(
      title: const Text('Доступно обновление'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Версия ${u.version}${u.size > 0 ? ' · ${u.sizeText}' : ''}',
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 6),
          Text('Загружается с вашего сервера. Записи сохранятся.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: _progress! > 0 ? _progress : null, minHeight: 6),
                      ),
                      const SizedBox(height: 6),
                      Text(_progress! >= 1
                          ? 'Открываю установку…'
                          : 'Загрузка ${(_progress! * 100).round()}%'),
                    ]),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: loading
              ? null
              : () {
                  widget.store.setLocal('updSkip', u.build);
                  Navigator.of(context).pop();
                },
          child: const Text('Позже'),
        ),
        FilledButton(
          onPressed: loading ? null : _start,
          child: Text(_file != null ? 'Установить' : 'Обновить'),
        ),
      ],
    );
  }
}
