import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'calendar_page.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'store.dart';
import 'ui_common.dart';

final List<String> startupErrors = [];

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      startupErrors.add(details.exceptionAsString());
      FlutterError.presentError(details);
    };
    ErrorWidget.builder = (details) => Material(
          color: Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text('Ошибка:\n${details.exceptionAsString()}\n\n${details.stack}',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        );
    runApp(const CycleApp());
  }, (e, st) {
    startupErrors.add('$e\n$st');
  });
}

class CycleApp extends StatelessWidget {
  /// Готовое хранилище (для скриншотов); обычно null — загружается с диска.
  final Store? store;
  final ThemeMode themeMode;
  final int initialTab;
  const CycleApp(
      {super.key,
      this.store,
      this.themeMode = ThemeMode.system,
      this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой цикл',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: store != null
          ? HomeShell(store: store!, initialTab: initialTab)
          : const _Loader(),
    );
  }
}

/// Сначала показываем экран, потом загружаем данные — так ошибка
/// загрузки видна на экране, а не превращается в чёрный экран.
class _Loader extends StatefulWidget {
  const _Loader();

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  late Future<Store> _future = Store.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Store>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) return HomeShell(store: snap.data!);
        if (snap.hasError) {
          return Scaffold(
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                const Text('Не удалось загрузить данные',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SelectableText('${snap.error}\n\n${snap.stackTrace}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _future = Store.load()),
                  child: const Text('Повторить'),
                ),
              ]),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  final Store store;
  final int initialTab;
  const HomeShell({super.key, required this.store, this.initialTab = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.sync();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final pages = [
          CalendarPage(store: widget.store),
          HistoryPage(store: widget.store),
          SettingsPage(store: widget.store),
        ];
        return Scaffold(
          body: _FadeThroughStack(index: _tab, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            animationDuration: motion(context, 400),
            onDestinationSelected: (i) {
              if (i != _tab) HapticFeedback.selectionClick();
              setState(() => _tab = i);
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month),
                  label: 'Календарь'),
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'История'),
              NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Настройки'),
            ],
          ),
        );
      },
    );
  }
}

/// Вкладки сохраняют состояние (как IndexedStack), но сменяются плавно:
/// старая гаснет, новая проявляется с лёгким подъёмом.
class _FadeThroughStack extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const _FadeThroughStack({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    final dur = motion(context, 260);
    return Stack(fit: StackFit.expand, children: [
      for (var i = 0; i < children.length; i++)
        IgnorePointer(
          ignoring: i != index,
          child: ExcludeSemantics(
            excluding: i != index,
            child: AnimatedOpacity(
              opacity: i == index ? 1 : 0,
              duration: dur,
              curve: i == index ? Curves.easeOut : Curves.easeIn,
              child: AnimatedSlide(
                offset: i == index ? Offset.zero : const Offset(0, 0.015),
                duration: dur,
                curve: Curves.easeOutCubic,
                // анимации внутри скрытых вкладок не крутятся зря
                child: TickerMode(enabled: i == index, child: children[i]),
              ),
            ),
          ),
        ),
    ]);
  }
}
