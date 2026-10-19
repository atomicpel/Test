import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cycle.dart';
import 'ui_common.dart';

/// Кольцо текущего цикла: каждый день — отдельный сегмент, цвет по типу дня,
/// метка «сегодня» на своём месте. При открытии кольцо прорисовывается
/// по часовой стрелке, а метка доезжает до сегодняшнего дня.
class CycleRing extends StatefulWidget {
  final Forecast forecast;
  final double size;
  const CycleRing({super.key, required this.forecast, this.size = 248});

  @override
  State<CycleRing> createState() => _CycleRingState();
}

class _RingData {
  final DateTime? start;
  final List<DayKind> kinds;
  final int todayIndex; // -1 — нет данных
  final int expected; // ожидаемая длина цикла
  const _RingData(this.start, this.kinds, this.todayIndex, this.expected);

  static _RingData of(Forecast f) {
    final last = f.last;
    final t = today();
    if (last == null) return const _RingData(null, [], -1, 0);
    final dayIdx = daysBetween(last.start, t);
    final n = math.max(f.cycleLength, dayIdx + 1);
    return _RingData(
      last.start,
      [for (var i = 0; i < n; i++) f.kindOf(addDays(last.start, i))],
      dayIdx,
      f.cycleLength,
    );
  }
}

class _CycleRingState extends State<CycleRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late _RingData _data = _RingData.of(widget.forecast);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else if (_c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(CycleRing old) {
    super.didUpdateWidget(old);
    final next = _RingData.of(widget.forecast);
    final restart = next.start != _data.start;
    _data = next;
    // Новый цикл (отметили начало месячных) — прорисовываем заново
    if (restart && MediaQuery.maybeDisableAnimationsOf(context) != true) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final d = _data;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final int dayNow = d.todayIndex < 0
              ? 0
              : math.min(d.todayIndex + 1,
                  math.max(1, (1 + d.todayIndex * t).round()));
          return CustomPaint(
            painter: _RingPainter(
              kinds: d.kinds,
              todayIndex: d.todayIndex,
              expected: d.expected,
              progress: t,
              track: fg.withValues(alpha: 0.09),
              trackPast: fg.withValues(alpha: 0.22),
              knobFill: theme.colorScheme.surface,
              knobStroke: fg,
            ),
            child: Center(
              child: d.todayIndex < 0
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.water_drop_outlined,
                          size: 40, color: fg.withValues(alpha: 0.35)),
                      const SizedBox(height: 8),
                      Text('Нет записей',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ])
                  : Semantics(
                      label: 'День цикла ${d.todayIndex + 1}',
                      excludeSemantics: true,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$dayNow',
                            style: theme.textTheme.displayLarge
                                ?.copyWith(color: fg, height: 1)),
                        const SizedBox(height: 6),
                        Text('день цикла',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ]),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<DayKind> kinds;
  final int todayIndex;
  final int expected;
  final double progress;
  final Color track, trackPast, knobFill, knobStroke;

  _RingPainter({
    required this.kinds,
    required this.todayIndex,
    required this.expected,
    required this.progress,
    required this.track,
    required this.trackPast,
    required this.knobFill,
    required this.knobStroke,
  });

  static const _stroke = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 18;
    final rect = Rect.fromCircle(center: c, radius: r);

    if (kinds.isEmpty) {
      // Пустое кольцо пунктиром
      final p = Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round;
      const n = 28;
      const step = 2 * math.pi / n;
      for (var i = 0; i < n; i++) {
        canvas.drawArc(rect, -math.pi / 2 + i * step + step * 0.3, step * 0.4,
            false, p);
      }
      return;
    }

    final n = kinds.length;
    final step = 2 * math.pi / n;
    final gap = math.min(step * 0.34, 0.06);
    final shown = progress * n; // сколько сегментов уже прорисовано

    for (var i = 0; i < n; i++) {
      final double vis = math.min(1.0, math.max(0.0, shown - i));
      if (vis <= 0) break;
      final kind = kinds[i];
      final overdue = i >= expected; // дни задержки
      Color color;
      if (kind == DayKind.none) {
        color = overdue
            ? Palette.period.withValues(alpha: 0.35)
            : (i <= todayIndex ? trackPast : track);
      } else {
        color = kindColor(kind)!;
      }
      final p = Paint()
        ..color = color.withValues(alpha: color.a * vis)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = kind == DayKind.ovulation ? _stroke + 7 : _stroke;
      final start = -math.pi / 2 + i * step + gap / 2;
      final sweep = math.max(step - gap, 0.001);
      // Скругление концов «съедает» часть промежутка — компенсируем
      final capAngle = (p.strokeWidth / 2) / r;
      final s2 = start + capAngle;
      final w2 = sweep - 2 * capAngle;
      if (w2 > 0) {
        canvas.drawArc(rect, s2, w2, false, p);
      } else {
        final a = start + sweep / 2;
        canvas.drawCircle(
            c + Offset(math.cos(a), math.sin(a)) * r,
            p.strokeWidth / 2,
            Paint()..color = p.color);
      }
    }

    // Метка «сегодня» едет по кольцу вместе с прорисовкой
    if (todayIndex >= 0) {
      final pos = (todayIndex + 0.5) * progress;
      final a = -math.pi / 2 + pos * step;
      final kc = kindColor(kinds[math.min(todayIndex, n - 1)]);
      final o = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(
          o,
          15,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(o, 13, Paint()..color = knobFill);
      canvas.drawCircle(
          o,
          13,
          Paint()
            ..color = knobStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5);
      if (kc != null) canvas.drawCircle(o, 6, Paint()..color = kc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.todayIndex != todayIndex ||
      old.expected != expected ||
      old.track != track ||
      old.knobStroke != knobStroke ||
      !_sameKinds(old.kinds, kinds);

  static bool _sameKinds(List<DayKind> a, List<DayKind> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
