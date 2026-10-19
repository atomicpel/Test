import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cycle.dart';
import 'ui_common.dart';

/// Плавный рост 0→1 при появлении (для графиков).
class Grow extends StatelessWidget {
  final Widget Function(double t) builder;
  final int ms;
  const Grow({super.key, required this.builder, this.ms = 900});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: motion(context, ms),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => builder(t),
      );
}

/// Столбики с линией среднего и подписями снизу.
class BarChart extends StatelessWidget {
  final List<int> values;
  final Color barColor;
  final Color lineColor;
  final int? average;
  final String? averageLabel;
  final double height;
  const BarChart({
    super.key,
    required this.values,
    required this.barColor,
    required this.lineColor,
    this.average,
    this.averageLabel,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).muted;
    final fg = Theme.of(context).colorScheme.onSurface;
    return Grow(
      builder: (t) => SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _BarPainter(values, barColor, lineColor, average,
              averageLabel, t, muted, fg),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<int> v;
  final Color bar, line, muted, fg;
  final int? avg;
  final String? avgLabel;
  final double t;
  _BarPainter(this.v, this.bar, this.line, this.avg, this.avgLabel, this.t,
      this.muted, this.fg);

  @override
  void paint(Canvas canvas, Size size) {
    if (v.isEmpty) return;
    const labelH = 26.0;
    const topPad = 26.0;
    final chartH = size.height - labelH - topPad;
    final maxV = math.max(v.reduce(math.max), avg ?? 0).toDouble() * 1.08;
    final minV = math.max(0.0, v.reduce(math.min) * 0.55);
    double y(num x) => topPad + chartH * (1 - (x - minV) / (maxV - minV));
    final n = v.length;
    final slot = size.width / n;
    final bw = math.min(slot * 0.5, 34.0);
    for (var i = 0; i < n; i++) {
      final cx = slot * i + slot / 2;
      final top = y(v[i]);
      final h = (topPad + chartH - top) * t;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - bw / 2, topPad + chartH - h, bw, h),
          const Radius.circular(9));
      canvas.drawRRect(r, Paint()..color = bar);
      final tp = TextPainter(
        text: TextSpan(
            text: '${v[i]}',
            style: TextStyle(
                fontFamily: kFont, fontSize: 16, color: muted, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, size.height - tp.height));
    }
    if (avg != null) {
      final ly = y(avg!) ;
      final lw = size.width * t;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, ly - 2, lw, 4), const Radius.circular(2)),
          Paint()..color = line);
      if (avgLabel != null) {
        final tp = TextPainter(
          text: TextSpan(
              text: avgLabel,
              style: TextStyle(
                  fontFamily: kFont,
                  fontSize: 16,
                  color: fg.withValues(alpha: t),
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width, ly - tp.height - 6));
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.t != t || o.v != v || o.bar != bar;
}

/// Полоска цикла по дням: месячные, фертильные, овуляция, остальные.
class DayStrip extends StatelessWidget {
  final List<DayKind> kinds;
  final int maxDays;
  const DayStrip({super.key, required this.kinds, required this.maxDays});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final other = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.13);
    return Grow(
      ms: 700,
      builder: (t) => SizedBox(
        height: 30,
        child: CustomPaint(
          size: Size.infinite,
          painter: _StripPainter(kinds, maxDays, t, other, Palette.ovulation(b)),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  final List<DayKind> kinds;
  final int maxDays;
  final double t;
  final Color other, ov;
  _StripPainter(this.kinds, this.maxDays, this.t, this.other, this.ov);

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / math.max(maxDays, kinds.length);
    final w = math.max(2.0, slot * 0.72);
    final shown = (kinds.length * t).ceil();
    for (var i = 0; i < shown; i++) {
      final k = kinds[i];
      final c = switch (k) {
        DayKind.period => Palette.period.withValues(alpha: 0.85),
        DayKind.fertile => Palette.fertile.withValues(alpha: 0.35),
        DayKind.ovulation => ov,
        DayKind.predicted => Palette.predicted.withValues(alpha: 0.4),
        DayKind.none => other,
      };
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(i * slot, 0, w, size.height),
              Radius.circular(w / 2)),
          Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_StripPainter o) => o.t != t || o.kinds != kinds;
}

/// Линия по датам (температура, вес).
class LineChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> points; // по возрастанию дат
  final Color color;
  final int digits;
  const LineChart(
      {super.key, required this.points, required this.color, this.digits = 1});

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).muted;
    return Grow(
      builder: (t) => SizedBox(
        height: 150,
        child: CustomPaint(
          size: Size.infinite,
          painter: _LinePainter(points, color, t, muted, digits),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<MapEntry<DateTime, double>> p;
  final Color color, muted;
  final double t;
  final int digits;
  _LinePainter(this.p, this.color, this.t, this.muted, this.digits);

  @override
  void paint(Canvas canvas, Size size) {
    if (p.length < 2) return;
    final minV = p.map((e) => e.value).reduce(math.min);
    final maxV = p.map((e) => e.value).reduce(math.max);
    final span = math.max(0.1, maxV - minV);
    final d0 = p.first.key, d1 = p.last.key;
    final days = math.max(1, daysBetween(d0, d1));
    const pad = 22.0;
    Offset at(MapEntry<DateTime, double> e) => Offset(
        pad + (size.width - 2 * pad) * daysBetween(d0, e.key) / days,
        14 + (size.height - 46) * (1 - (e.value - minV) / span));
    final path = Path();
    for (var i = 0; i < p.length; i++) {
      final o = at(p[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t, size.height));
    final area = Path.from(path)
      ..lineTo(at(p.last).dx, size.height - 30)
      ..lineTo(at(p.first).dx, size.height - 30)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round);
    for (final e in p) {
      canvas.drawCircle(at(e), 4, Paint()..color = color);
    }
    canvas.restore();
    void label(String s, Offset o) {
      final tp = TextPainter(
          text: TextSpan(
              text: s,
              style: TextStyle(fontFamily: kFont, fontSize: 13, color: muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, o);
    }

    label('${d0.day} ${monthsShort[d0.month - 1]}', Offset(0, size.height - 18));
    final l1 = '${d1.day} ${monthsShort[d1.month - 1]}';
    final tp = TextPainter(
        text: TextSpan(text: l1, style: TextStyle(fontFamily: kFont, fontSize: 13)),
        textDirection: TextDirection.ltr)
      ..layout();
    label(l1, Offset(size.width - tp.width, size.height - 18));
    label('макс ${maxV.toStringAsFixed(digits).replaceAll('.', ',')}', const Offset(0, 0));
  }

  @override
  bool shouldRepaint(_LinePainter o) => o.t != t || o.p != p;
}

/// Вероятность беременности на 7 дней: низ / ср / выс.
class FertilityBars extends StatelessWidget {
  final List<MapEntry<DateTime, Fertility>> days;
  const FertilityBars({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    return Grow(
      builder: (t) => SizedBox(
        height: 190,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          SizedBox(
            width: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in ['выс', 'ср', 'низ'])
                  Text(l, style: TextStyle(fontFamily: kFont, color: c.muted, fontSize: 15)),
                const SizedBox(height: 40),
              ],
            ),
          ),
          for (final e in days)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: (18 + 54.0 * e.value.index) * t,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: e.value == Fertility.low
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.15)
                        : (e.value == Fertility.medium
                            ? Palette.fertile
                            : Palette.ovulation(theme.brightness)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${e.key.day}',
                    style: TextStyle(
                        fontFamily: kFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface)),
                Text(monthsShort[e.key.month - 1],
                    style: TextStyle(fontFamily: kFont, fontSize: 13, color: c.muted)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Горизонтальные полоски частоты (симптомы, настроение).
class FrequencyBars extends StatelessWidget {
  final List<({String emoji, String label, int count})> items;
  final Color color;
  const FrequencyBars({super.key, required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxC = items.isEmpty ? 1 : items.map((e) => e.count).reduce(math.max);
    return Grow(
      builder: (t) => Column(children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Text(e.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, cs) => Container(
                      height: 10,
                      width: cs.maxWidth * (e.count / maxC) * t,
                      decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Text('×${e.count}',
                  style: theme.textTheme.titleMedium?.copyWith(color: color)),
            ]),
          ),
      ]),
    );
  }
}
