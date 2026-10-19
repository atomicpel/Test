import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'calendar_grid.dart';
import 'cycle_circle.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

/// Главный экран: иллюстрация с кругом и календарь под ней.
class HomePage extends StatefulWidget {
  final Store store;
  final VoidCallback onThemes;
  final void Function(DateTime) onOpenDay;
  const HomePage(
      {super.key,
      required this.store,
      required this.onThemes,
      required this.onOpenDay});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final circle = math.min(w * 0.68, 300.0);
    final headerH = mq.padding.top + circle + 76;
    final store = widget.store;
    return RefreshIndicator(
      onRefresh: store.sync,
      edgeOffset: mq.padding.top,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: headerH,
            child: Stack(clipBehavior: Clip.none, children: [
              // Иллюстрация уезжает медленнее, чем список (параллакс)
              Positioned(
                top: -_offset * 0.45,
                left: 0,
                right: 0,
                height: headerH + 40,
                child: _HeaderArt(height: headerH + 40),
              ),
              Positioned(
                top: mq.padding.top + 36 + _offset * 0.12,
                left: 0,
                right: 0,
                child: Center(
                  child: _Appear(
                    child: CycleCircle(
                      store: store,
                      size: circle,
                      onLog: () => widget.onOpenDay(DateTime.now()),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: mq.padding.top + 8,
                right: 12,
                child: _RoundButton(
                    icon: Icons.palette_outlined,
                    tooltip: 'Темы',
                    onTap: widget.onThemes),
              ),
              if (store.syncConfigured)
                Positioned(
                  top: mq.padding.top + 8,
                  left: 12,
                  child: _SyncBadge(store: store),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: MonthCalendar(store: store, onDayTap: widget.onOpenDay),
          ),
          const SizedBox(height: 10),
          const _Legend(),
          const SizedBox(height: 110),
        ],
      ),
    );
  }
}

/// Плавное появление круга при запуске.
class _Appear extends StatelessWidget {
  final Widget child;
  const _Appear({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion(context, 700),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
      ),
      child: child,
    );
  }
}

class _HeaderArt extends StatelessWidget {
  final double height;
  const _HeaderArt({required this.height});

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.of(context);
    final c = AppColors.of(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(fit: StackFit.expand, children: [
      AnimatedContainer(duration: motion(context, 500), color: c.header),
      AnimatedSwitcher(
        duration: motion(context, 600),
        child: spec.asset == null
            ? const SizedBox.expand(key: ValueKey('none'))
            : Image.asset(
                spec.asset!,
                key: ValueKey(spec.id),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                width: double.infinity,
                height: height,
                gaplessPlayback: true,
              ),
      ),
      // мягкий переход иллюстрации в фон страницы
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 90,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bg.withValues(alpha: 0), bg],
            ),
          ),
        ),
      ),
    ]);
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.scaffoldBackgroundColor.withValues(alpha: 0.75),
            border: Border.all(color: AppColors.of(context).cardBorder),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 28),
        ),
      ),
    );
  }
}

class _SyncBadge extends StatefulWidget {
  final Store store;
  const _SyncBadge({required this.store});

  @override
  State<_SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<_SyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (s.syncing) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
    final theme = Theme.of(context);
    final err = s.syncError;
    return Tooltip(
      message: s.syncing ? 'Синхронизация' : (err ?? 'Синхронизировано'),
      child: Pressable(
        onTap: s.syncing
            ? null
            : () async {
                await s.sync();
                if (context.mounted) {
                  showSnack(context, s.syncError ?? 'Синхронизировано');
                }
              },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.scaffoldBackgroundColor.withValues(alpha: 0.75),
            border: Border.all(color: AppColors.of(context).cardBorder),
          ),
          child: s.syncing
              ? RotationTransition(
                  turns: Tween<double>(begin: 0, end: -1).animate(_spin),
                  child: Icon(Icons.sync, color: theme.colorScheme.primary))
              : Icon(err == null ? Icons.cloud_done_outlined : Icons.cloud_off,
                  color: err == null
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          const DotLabel(Palette.period, 'Месячные'),
          const DotLabel(Palette.predicted, 'Прогноз', outline: true),
          const DotLabel(Palette.fertile, 'Фертильные', outline: true),
          DotLabel(Palette.ovulation(b), 'Овуляция'),
        ],
      ),
    );
  }
}
