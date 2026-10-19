import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'cycle.dart';
import 'day_log_page.dart';
import 'home_page.dart';
import 'lock.dart';
import 'native.dart';
import 'prefs.dart';
import 'reminders.dart';
import 'updater.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'store.dart';
import 'themes_page.dart';
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
    // Режим самопроверки на эмуляторе: adb ... --es route /smoke
    final smoke = PlatformDispatcher.instance.defaultRouteName == '/smoke';
    runApp(CycleApp(store: smoke ? smokeStore() : null, smoke: smoke));
  }, (e, st) {
    startupErrors.add('$e\n$st');
    debugPrint('uncaught: $e\n$st');
  });
}

/// Пример данных: пять прошлых циклов, последние месячные — 9 дней назад.
Store sampleStore() {
  final s = Store.loadFrom(Prefs.memory());
  final t = today();
  const cycles = [29, 28, 30, 29, 28];
  var start = addDays(t, -9 - cycles.fold<int>(0, (a, b) => a + b));
  for (final c in cycles) {
    s.markPeriod(start, 5);
    s.patchDay(start, {'f': 3});
    s.patchDay(addDays(start, 1), {
      'f': 2,
      's': ['cramps', 'fatigue'],
      'm': ['sad']
    });
    start = addDays(start, c);
  }
  s.markPeriod(start, 5);
  s.patchDay(start, {
    'f': 4,
    's': ['cramps', 'back'],
    'm': ['irritable']
  });
  s.patchDay(addDays(t, -2), {
    'n': 'Болела голова',
    's': ['headache'],
    'm': ['calm', 'sleepy'],
    'x': ['protected'],
    't': 36.6,
    'w': 58.4,
  });
  s.patchDay(addDays(t, -30), {'w': 58.9, 't': 36.5});
  s.patchDay(addDays(t, -15), {'w': 58.6, 't': 36.9});
  s.setSetting('contra', 'pill');
  s.patchDay(addDays(t, -1), {'pl': true});
  return s;
}

Store smokeStore() {
  final s = sampleStore();
  for (final k in [
    'soon', 'start', 'end', 'fertile', 'ovulation', 'pill', 'note', 'weekly'
  ]) {
    s.setReminder(k, true);
  }
  return s;
}

class CycleApp extends StatefulWidget {
  /// Готовое хранилище (скриншоты, самопроверка); обычно null — с диска.
  final Store? store;
  final bool smoke;
  final int initialTab;
  final bool? darkOverride;
  final String? themeOverride;
  const CycleApp(
      {super.key,
      this.store,
      this.smoke = false,
      this.initialTab = 0,
      this.darkOverride,
      this.themeOverride});

  @override
  State<CycleApp> createState() => _CycleAppState();
}

class _CycleAppState extends State<CycleApp> {
  Store? _store;
  Object? _error;
  StackTrace? _stack;
  final _themes = <String, ThemeData>{};
  String _themeKey = '';

  @override
  void initState() {
    super.initState();
    if (widget.store != null) {
      _store = widget.store;
      _store!.addListener(_onStore);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final s = await Store.load();
      s.addListener(_onStore);
      setState(() => _store = s);
    } catch (e, st) {
      setState(() {
        _error = e;
        _stack = st;
      });
    }
  }

  void _onStore() {
    final s = _store!;
    final k =
        '${widget.themeOverride ?? s.themeId}|${widget.darkOverride ?? s.dark}|${s.textScale}';
    if (k != _themeKey) setState(() => _themeKey = k);
  }

  ThemeData _theme(Brightness b, AppThemeSpec spec) =>
      _themes.putIfAbsent('${spec.id}|$b', () => buildTheme(b, spec));

  @override
  Widget build(BuildContext context) {
    final s = _store;
    final spec = themeById(widget.themeOverride ?? s?.themeId ?? 'cats');
    final dark = widget.darkOverride ?? s?.dark ?? true;
    Widget home;
    if (s != null) {
      home = LockGate(
        store: s,
        child: HomeShell(
            store: s, initialTab: widget.initialTab, smoke: widget.smoke),
      );
    } else if (_error != null) {
      home = Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Не удалось загрузить данные',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText('$_error\n\n$_stack',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() => _error = null);
                _load();
              },
              child: const Text('Повторить'),
            ),
          ]),
        ),
      );
    } else {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return MaterialApp(
      title: 'Мой цикл',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _theme(Brightness.light, spec),
      darkTheme: _theme(Brightness.dark, spec),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 450),
      themeAnimationCurve: Curves.easeOutCubic,
      builder: (context, child) {
        Widget c = ThemeSpecScope(spec: spec, child: child!);
        final k = s?.textScale ?? 0;
        if (k > 0) {
          c = MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(k)),
            child: c,
          );
        }
        return c;
      },
      home: home,
    );
  }
}

class HomeShell extends StatefulWidget {
  final Store store;
  final int initialTab;
  final bool smoke;
  const HomeShell(
      {super.key, required this.store, this.initialTab = 0, this.smoke = false});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;
  late final AppServices _services = AppServices(widget.store);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.sync();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  Future<void> _firstRun() async {
    final s = widget.store;
    if (widget.smoke) {
      await Reminders.requestPermission();
      await _services.refresh();
      await Reminders.test(s, seconds: 8);
      return;
    }
    // Один раз спрашиваем разрешение на уведомления
    if (!s.local<bool>('askedNotif', false)) {
      s.setLocal('askedNotif', true);
      await Reminders.requestPermission();
      await _services.refresh();
    }
    if (s.local<int>('ringColor', 0) == 0) {
      s.setLocal('ringColor', themeById(s.themeId).ring.toARGB32());
    }
    if (mounted) await Updater.autoCheck(context, s);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.sync();
      _services.refresh();
      if (!widget.smoke) Updater.autoCheck(context, widget.store);
    }
  }

  void _openDay(DateTime d) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: motion(context, 450),
      reverseTransitionDuration: motion(context, 350),
      pageBuilder: (_, __, ___) => DayLogPage(store: widget.store, initial: d),
      transitionsBuilder: (_, a, b, child) => SharedAxisTransition(
        animation: a,
        secondaryAnimation: b,
        transitionType: SharedAxisTransitionType.vertical,
        child: child,
      ),
    ));
  }

  void _select(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
          store: widget.store, onThemes: () => _select(2), onOpenDay: _openDay),
      StatsPage(store: widget.store, onOpenDay: _openDay),
      ThemesPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Scaffold(
        extendBody: true,
        body: _FadeThroughStack(index: _tab, children: pages),
        floatingActionButton: _Fab(onTap: () => _openDay(DateTime.now())),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _BottomBar(index: _tab, onTap: _select),
      ),
    );
  }
}

/// Вкладки сохраняют состояние, но сменяются плавно (fade through).
class _FadeThroughStack extends StatelessWidget {
  final int index;
  final List<Widget> children;
  const _FadeThroughStack({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    final dur = motion(context, 300);
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
              child: AnimatedScale(
                scale: i == index ? 1 : 0.97,
                duration: dur,
                curve: Curves.easeOutCubic,
                child: TickerMode(enabled: i == index, child: children[i]),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Fab extends StatefulWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});

  @override
  State<_Fab> createState() => _FabState();
}

class _FabState extends State<_Fab> {
  double _turns = 0;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Записать сегодняшний день',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() => _turns += 0.25);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: motion(context, 180),
          curve: Curves.easeOutBack,
          child: Container(
            width: kFabSize,
            height: kFabSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: AnimatedRotation(
              turns: _turns,
              duration: motion(context, 400),
              curve: Curves.easeOutBack,
              child:
                  Icon(Icons.add, size: 32, color: theme.colorScheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const items = [
      (Icons.calendar_month, 'Календарь'),
      (Icons.bar_chart_rounded, 'Статистика'),
      (Icons.palette, 'Темы'),
      (Icons.settings, 'Настройки'),
    ];
    Widget item(int i) => Expanded(
          child: _NavItem(
            icon: items[i].$1,
            label: items[i].$2,
            selected: index == i,
            onTap: () => onTap(i),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          child: SizedBox(
          height: kBarHeight,
          child: Row(children: [
            item(0),
            item(1),
            const SizedBox(width: kFabSize + 12),
            item(2),
            item(3),
          ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : AppColors.of(context).muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: motion(context, 300),
            curve: Curves.easeOutBack,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: color),
              duration: motion(context, 250),
              builder: (context, c, _) => Icon(icon, color: c, size: 23),
            ),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: motion(context, 250),
            style: TextStyle(
                fontFamily: kFont,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: color),
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
          ),
        ]),
      ),
    );
  }
}
