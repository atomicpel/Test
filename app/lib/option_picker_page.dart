import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'day_entry.dart';
import 'ui_common.dart';

/// Полный список с поиском и отметками (симптомы, настроение).
class OptionPickerPage extends StatefulWidget {
  final String title;
  final List<Opt> options;
  final List<String> selected;
  final ValueChanged<String> onAddCustom;
  const OptionPickerPage(
      {super.key,
      required this.title,
      required this.options,
      required this.selected,
      required this.onAddCustom});

  @override
  State<OptionPickerPage> createState() => _OptionPickerPageState();
}

class _OptionPickerPageState extends State<OptionPickerPage> {
  late final Set<String> _sel = widget.selected.toSet();
  late final List<Opt> _opts = [...widget.options];
  bool _search = false;
  String _q = '';

  Future<void> _add() async {
    final c = TextEditingController(text: _q);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Свой пункт'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Добавить')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    widget.onAddCustom(name);
    final o = optById(const [], 'c:${name.trim()}');
    setState(() {
      if (!_opts.any((x) => x.id == o.id)) _opts.add(o);
      _sel.add(o.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final list = _q.isEmpty
        ? _opts
        : _opts
            .where((o) => o.label.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: motion(context, 250),
          child: _search
              ? TextField(
                  key: const ValueKey('s'),
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Поиск', filled: false, border: InputBorder.none,
                      enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                  onChanged: (v) => setState(() => _q = v),
                )
              : Text(widget.title, key: const ValueKey('t')),
        ),
        actions: [
          IconButton(
            tooltip: _search ? 'Закрыть поиск' : 'Поиск',
            icon: Icon(_search ? Icons.close : Icons.search, size: 28),
            onPressed: () => setState(() {
              _search = !_search;
              if (!_search) _q = '';
            }),
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: list.length + 1,
        separatorBuilder: (_, __) => Divider(color: c.cardBorder),
        itemBuilder: (context, i) {
          if (i == list.length) {
            return ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: theme.colorScheme.primary, size: 30),
              title: Text('Добавить свой пункт',
                  style: TextStyle(color: theme.colorScheme.primary)),
              onTap: _add,
            );
          }
          final o = list[i];
          final on = _sel.contains(o.id);
          return ListTile(
            minVerticalPadding: 14,
            leading: AnimatedScale(
              scale: on ? 1.15 : 1,
              duration: motion(context, 250),
              curve: Curves.easeOutBack,
              child: Text(o.emoji, style: const TextStyle(fontSize: 32)),
            ),
            title: Text(o.label),
            trailing: Checkbox(
              value: on,
              onChanged: (_) => _toggle(o.id),
            ),
            onTap: () => _toggle(o.id),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: c.card,
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Закрыть')),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  // порядок: как в справочнике
                  final res =
                      _opts.where((o) => _sel.contains(o.id)).map((o) => o.id).toList();
                  for (final id in _sel) {
                    if (!res.contains(id)) res.add(id);
                  }
                  Navigator.pop(context, res);
                },
                child: const Text('Сохранить'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));
  }
}
