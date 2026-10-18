import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'ui_common.dart';

class SettingsPage extends StatefulWidget {
  final Store store;
  const SettingsPage({super.key, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _showToken = false;
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.store.serverUrl);
    _token = TextEditingController(text: widget.store.token);
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _connect(String url, String token) async {
    FocusScope.of(context).unfocus();
    _url.text = url;
    _token.text = token;
    await widget.store.setServer(url, token);
    _snack(widget.store.syncError == null
        ? 'Подключено, данные синхронизированы'
        : 'Ошибка: ${widget.store.syncError}');
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final code = Store.parseCode(data?.text ?? '');
    if (code == null) {
      _snack('В буфере нет кода подключения. Скопируйте его целиком — '
          'строку вида https://адрес#токен');
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
    final f = s.forecast;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Синхронизация', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!s.syncConfigured) ...[
            Text(
              'Сервер ставится один раз на ваш VPS скриптом '
              'install-cycle-server.sh. В конце он покажет код подключения — '
              'строку вида https://адрес#токен. Скопируйте её и нажмите '
              'кнопку ниже. На втором телефоне — то же самое.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: s.syncing ? null : _pasteCode,
              icon: const Icon(Icons.content_paste),
              label: const Text('Вставить код подключения'),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  s.syncError == null ? Icons.cloud_done : Icons.cloud_off,
                  color: s.syncError == null
                      ? Colors.green
                      : theme.colorScheme.error),
              title: Text(Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl),
              subtitle: Text(_lastSyncText(),
                  style: TextStyle(
                      color: s.syncError != null
                          ? theme.colorScheme.error
                          : null)),
            ),
            if (s.pendingCount > 0)
              Text('Не отправлено изменений: ${s.pendingCount}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: s.syncing ? null : s.sync,
                icon: const Icon(Icons.sync),
                label: const Text('Синхронизировать'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: s.connectionCode));
                  _snack('Код скопирован. Перешлите его себе на второй '
                      'телефон и вставьте там в настройках.');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Код для второго телефона'),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _manual = !_manual),
            icon: Icon(_manual ? Icons.expand_less : Icons.expand_more),
            label: Text(s.syncConfigured
                ? 'Изменить адрес или токен'
                : 'Ввести адрес и токен вручную'),
          ),
          if (_manual) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Адрес сервера',
                hintText: 'https://cycle.atomicpel.cloud-ip.cc',
                helperText: 'Домен, который вы указали при установке сервера',
                border: OutlineInputBorder(),
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
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: s.syncing
                  ? null
                  : () => _connect(_url.text, _token.text),
              child: const Text('Сохранить и синхронизировать'),
            ),
          ],
          const Divider(height: 40),
          Text('Как считается прогноз', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            f.tentative
                ? 'Пока записан меньше чем один полный цикл, поэтому прогноз '
                    'предварительный (стандартные ${daysWord(f.cycleLength)}). '
                    'Как только будет отмечено начало следующих месячных '
                    '(или добавлены прошлые периоды во вкладке «История»), '
                    'всё пересчитается по вашим записям.'
                : 'Сейчас: цикл ${daysWord(f.cycleLength)}'
                    '${f.cycleSpread > 0 ? ' (±${f.cycleSpread})' : ''}, '
                    'месячные ${daysWord(f.periodLength)} — посчитано по '
                    '${f.cyclesUsed} ${plural(f.cyclesUsed, 'циклу', 'циклам', 'циклам')}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Всё считается автоматически по отмеченным дням: берутся '
            'последние 12 циклов, свежие весят больше старых, а явные '
            'выбросы (например, пропущенная отметка, из-за которой два '
            'цикла слились в один) не учитываются. Овуляция — за 14 дней '
            'до ожидаемых месячных.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 40),
          Text(
            'Данные хранятся на телефоне и на вашем сервере. '
            'Прогноз приблизительный, не заменяет консультацию врача '
            'и не годится как метод контрацепции.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
