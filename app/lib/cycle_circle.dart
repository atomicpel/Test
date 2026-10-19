import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

/// Большой круг с толстым кольцом. Внутри — две страницы:
/// главная цифра (дни до месячных / задержка / день месячных)
/// и день цикла с вероятностью беременности.
class CycleCircle extends StatefulWidget {
  final Store store;
  final double size;
  final VoidCallback onLog;
  const CycleCircle(
      {super.key, required this.store, required this.size, required this.onLog});

  @override
  State<CycleCircle> createState() => _CycleCircleState();
}

class _CycleCircleState extends State<CycleCircle>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _burst = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  final _pages = PageController();
  int _page = 0;
  DateTime? _lastStart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _ring.value = 1;
    } else if (_ring.status == AnimationStatus.dismissed) {
      _ring.forward();
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    _burst.dispose();
    _pulse.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _celebrate() {
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return;
    _burst.forward(from: 0);
    _pulse.forward(from: 0);
    _ring.forward(from: 0);
  }

  void _markStart() {
    final s = widget.store;
    final t = today();
    final len = s.forecast.periodLength;
    HapticFeedback.mediumImpact();
    s.markPeriod(t, len);
    _celebrate();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Отмечено ${daysWord(len)} с сегодняшнего дня'),
        action: SnackBarAction(
          label: 'Отменить',
          onPressed: () => s.clearPeriod(Period(t, addDays(t, len - 1))),
        ),
      ));
  }

  void _markEnd() {
    HapticFeedback.mediumImpact();
    widget.store.endPeriodOn(today());
    _pulse.forward(from: 0);
    showSnack(context, 'Отмечено: месячные закончились сегодня');
  }

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.of(context);
    final theme = Theme.of(context);
    final f = widget.store.forecast;
    final last = f.last;
    if (_lastStart != null && last != null && last.start != _lastStart) {
      // новый цикл — кольцо прорисуется заново
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ring.isCompleted) _ring.forward(from: 0);
      });
    }
    _lastStart = last?.start;
    final d = widget.size;
    final stroke = d * 0.072;

    return AnimatedBuilder(
      animation: Listenable.merge([_ring, _pulse, _burst]),
      builder: (context, child) {
        final pulse = math.sin(math.pi * _pulse.value) * 0.05;
        return Transform.scale(
          scale: 1 + pulse,
          child: CustomPaint(
            painter: _RingPainter(
              progress: Curves.easeOutCubic.transform(_ring.value),
              color: spec.ring,
              fill: theme.scaffoldBackgroundColor,
              stroke: stroke,
            ),
            foregroundPainter: _BurstPainter(_burst.value, Palette.period),
            child: child,
          ),
        );
      },
      child: SizedBox.square(
        dimension: d,
        child: Padding(
          padding: EdgeInsets.all(stroke + d * 0.04),
          child: ClipOval(
            child: Stack(children: [
              PageView(
                controller: _pages,
                onPageChanged: (p) {
                  HapticFeedback.selectionClick();
                  setState(() => _page = p);
                },
                children: [
                  _mainPage(context, f),
                  _cyclePage(context, f),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: d * 0.07,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 2; i++)
                      AnimatedContainer(
                        duration: motion(context, 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 18 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context,
      {int? number,
      String? bigText,
      required String label,
      String? sub,
      required String button,
      required VoidCallback onButton,
      bool filled = false}) {
    final theme = Theme.of(context);
    final d = widget.size;
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: EdgeInsets.fromLTRB(d * 0.06, 0, d * 0.06, d * 0.12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (number != null)
            TweenAnimationBuilder<double>(
              key: ValueKey(number),
              tween: Tween<double>(begin: 0, end: number.toDouble()),
              duration: motion(context, 1100),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '${v.round()}',
                style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: d * 0.26, color: theme.colorScheme.onSurface),
              ),
            )
          else if (bigText != null)
            Text(bigText,
                style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: d * 0.13, color: theme.colorScheme.onSurface)),
          SizedBox(height: d * 0.01),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: number == null && bigText == null ? d * 0.068 : d * 0.075,
                  height: 1.15)),
          if (sub != null) ...[
            SizedBox(height: d * 0.012),
            Text(sub,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.of(context).muted, fontSize: d * 0.05)),
          ],
          SizedBox(height: d * 0.04),
          Pressable(
            onTap: onButton,
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: d * 0.07, vertical: d * 0.025),
              decoration: BoxDecoration(
                color: filled ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: accent, width: 2),
              ),
              child: Text(button,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: kFont,
                      fontWeight: FontWeight.w700,
                      fontSize: d * 0.058,
                      height: 1.1,
                      color: filled ? theme.colorScheme.onPrimary : accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainPage(BuildContext context, Forecast f) {
    final s = widget.store;
    final t = today();
    final preg = s.pregnancy;
    if (preg != null) {
      final w = preg.week(t);
      final left = preg.daysLeft(t);
      return _content(context,
          number: w,
          label: '${plural(w, 'неделя', 'недели', 'недель')} беременности',
          sub: left >= 0 ? 'до родов ${daysWord(left)}' : 'дата родов прошла',
          button: 'Записать день',
          onButton: widget.onLog);
    }
    final last = f.last;
    if (last == null) {
      return _content(context,
          label: 'Отметьте первый день месячных',
          button: 'Отметить месячные',
          filled: true,
          onButton: _markStart);
    }
    if (last.contains(t)) {
      final n = daysBetween(last.start, t) + 1;
      return _content(context,
          number: n,
          label: 'день месячных',
          sub: 'следующие ≈ ${fmtDate(f.nextStart!)}',
          button: 'Закончились',
          onButton: _markEnd);
    }
    if (f.delay > 0) {
      return _content(context,
          number: f.delay,
          label: plural(f.delay, 'день задержки', 'дня задержки', 'дней задержки'),
          button: 'Отметить месячные',
          onButton: _markStart);
    }
    final left = daysBetween(t, f.nextStart!);
    if (left == 0) {
      return _content(context,
          bigText: 'Сегодня',
          label: 'ожидаются месячные',
          button: 'Отметить месячные',
          onButton: _markStart);
    }
    return _content(context,
        number: left,
        label: plural(left, 'день до месячных', 'дня до месячных', 'дней до месячных'),
        sub: f.cycleSpread > 0
            ? '${fmtDate(f.nextStart!)}, ±${daysWord(f.cycleSpread)}'
            : fmtDate(f.nextStart!),
        button: 'Отметить месячные',
        onButton: _markStart);
  }

  Widget _cyclePage(BuildContext context, Forecast f) {
    final info = f.info(today());
    if (info == null || widget.store.pregnancy != null) {
      return _content(context,
          bigText: '•',
          label: 'Как вы себя чувствуете?',
          button: 'Записать день',
          onButton: widget.onLog);
    }
    final fert = switch (info.fertility) {
      Fertility.high => 'высокая вероятность беременности',
      Fertility.medium => 'средняя вероятность беременности',
      Fertility.low => 'низкая вероятность беременности',
    };
    String? sub = fert;
    if (info.kind == DayKind.ovulation) sub = 'сегодня овуляция (прогноз)';
    return _content(context,
        number: info.cycleDay,
        label: 'день цикла',
        sub: sub,
        button: 'Записать день',
        onButton: widget.onLog);
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color fill;
  final double stroke;
  _RingPainter(
      {required this.progress,
      required this.color,
      required this.fill,
      required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2;
    // тень под кругом
    canvas.drawCircle(
        c,
        r + stroke / 2,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(c, r + stroke / 2, Paint()..color = fill);
    // бледная дорожка и само кольцо
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = color.withValues(alpha: 0.18));
    if (progress > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
          2 * math.pi * progress, false, p..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color || o.fill != fill;
}

/// Капли, разлетающиеся от центра при отметке месячных.
class _BurstPainter extends CustomPainter {
  final double t;
  final Color color;
  _BurstPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final maxR = size.width * 0.62;
    final ease = Curves.easeOutCubic.transform(t);
    for (var i = 0; i < 14; i++) {
      final a = i * 2 * math.pi / 14 + (i.isEven ? 0.12 : -0.08);
      final dist = maxR * (0.45 + 0.55 * ease) * (i.isEven ? 1 : 0.86);
      final o = c + Offset(math.cos(a), math.sin(a)) * dist;
      final r = (i.isEven ? 7.0 : 5.0) * (1 - t * 0.6);
      final paint = Paint()..color = color.withValues(alpha: (1 - t) * 0.9);
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(a + math.pi / 2);
      final path = Path()
        ..moveTo(0, -r * 1.6)
        ..quadraticBezierTo(r, -r * 0.2, r, r * 0.3)
        ..arcToPoint(Offset(-r, r * 0.3), radius: Radius.circular(r))
        ..quadraticBezierTo(-r, -r * 0.2, 0, -r * 1.6)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}
