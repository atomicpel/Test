import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Синхронизация', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Адрес сервера',
              hintText: 'https://cycle.example.ru',
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
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showToken = !_showToken),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: s.syncing
                ? null
                : () async {
                    FocusScope.of(context).unfocus();
                    await s.setServer(_url.text, _token.text);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(s.syncError == null
                            ? 'Готово, данные синхронизированы'
                            : 'Ошибка: ${s.syncError}')));
                  },
            icon: const Icon(Icons.sync),
            label: const Text('Сохранить и синхронизировать'),
          ),
          const SizedBox(height: 8),
          Text(_lastSyncText(),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: s.syncError != null ? theme.colorScheme.error : null)),
          if (s.pendingCount > 0)
            Text('Не отправлено изменений: ${s.pendingCount}',
                style: theme.textTheme.bodySmall),
          const Divider(height: 40),
          Text('Прогноз', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Используется, пока в истории меньше двух циклов. '
            'Дальше длина считается по последним шести циклам.',
            style: theme.textTheme.bodySmall,
          ),
          _stepper('Длина цикла', s.defaultCycle, 18, 60,
              (v) => s.setDefaults(cycle: v)),
          _stepper('Длина месячных', s.defaultPeriod, 1, 12,
              (v) => s.setDefaults(period: v)),
          const Divider(height: 40),
          Text(
            'Данные хранятся на телефоне и на вашем сервере. '
            'Прогноз приблизительный и не заменяет консультацию врача '
            'и не годится как метод контрацепции.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _stepper(String title, int value, int min, int max, void Function(int) set) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            onPressed: value > min ? () => set(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline)),
        SizedBox(
            width: 70,
            child: Text(daysWord(value), textAlign: TextAlign.center)),
        IconButton(
            onPressed: value < max ? () => set(value + 1) : null,
            icon: const Icon(Icons.add_circle_outline)),
      ]),
    );
  }
}
