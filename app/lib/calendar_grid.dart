import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cycle.dart';
import 'store.dart';
import 'ui_common.dart';

/// Месячный календарь с листанием. Периоды рисуются «капсулами»
/// через несколько дней, как в привычном приложении.
class MonthCalendar extends StatefulWidget {
  final Store store;
  final void Function(DateTime) onDayTap;
  /// Высота строки календаря — подбирается так, чтобы всё влезло в экран.
  final double cellH;
  const MonthCalendar(
      {super.key, required this.store, required this.onDayTap, this.cellH = 46});

  /// Высота всего календаря (заголовок, дни недели и 6 строк).
  static double heightFor(double cellH) => _titleH + 6 + _weekH + 4 + 6 * cellH;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

const _base = 1200;
const _titleH = 38.0;
const _weekH = 18.0;

class _MonthCalendarState extends State<MonthCalendar> {
  final _pages = PageController(initialPage: _base);
  int _page = _base;

  DateTime _monthOf(int page) {
    final t = today();
    return DateTime.utc(t.year, t.month + (page - _base), 1);
  }

  void _go(int page) => _pages.animateToPage(page,
      duration: motion(context, 420), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final m = _monthOf(_page);
    final c = AppColors.of(context);
    final cellH = widget.cellH;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Column(children: [
      SizedBox(
        height: _titleH,
        child: Row(children: [
        IconButton(
            tooltip: 'Предыдущий месяц',
            visualDensity: VisualDensity.compact,
            onPressed: () => _go(_page - 1),
            icon: Icon(Icons.chevron_left, color: accent, size: 28)),
        Expanded(
          child: GestureDetector(
            onTap: () => _go(_base),
            child: AnimatedSwitcher(
              duration: motion(context, 300),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                    scale: Tween<double>(begin: 0.85, end: 1).animate(a),
                    child: child),
              ),
              child: Text(
                '${monthsNom[m.month - 1]} ${m.year} г.',
                key: ValueKey(_page),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: kFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: accent),
              ),
            ),
          ),
        ),
        IconButton(
            tooltip: 'Следующий месяц',
            visualDensity: VisualDensity.compact,
            onPressed: () => _go(_page + 1),
            icon: Icon(Icons.chevron_right, color: accent, size: 28)),
      ]),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: _weekH,
        child: Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(weekdaysShort[i],
                  style: TextStyle(
                      fontFamily: kFont,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.muted)),
            ),
          ),
      ]),
      ),
      const SizedBox(height: 4),
      SizedBox(
        height: 6 * cellH,
        child: PageView.builder(
          controller: _pages,
          onPageChanged: (p) {
            HapticFeedback.selectionClick();
            setState(() => _page = p);
          },
          itemBuilder: (context, p) => _MonthGrid(
            key: ValueKey(p),
            month: _monthOf(p),
            store: widget.store,
            onTap: widget.onDayTap,
            cellH: cellH,
          ),
        ),
      ),
    ]),
    );
  }
}

enum _Grp { none, period, predicted, fertile }

_Grp _grp(DayKind k, bool showFert) => switch (k) {
      DayKind.period => _Grp.period,
      DayKind.predicted => _Grp.predicted,
      DayKind.fertile || DayKind.ovulation => showFert ? _Grp.fertile : _Grp.none,
      DayKind.none => _Grp.none,
    };

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Store store;
  final void Function(DateTime) onTap;
  final double cellH;
  const _MonthGrid(
      {super.key,
      required this.month,
      required this.store,
      required this.onTap,
      required this.cellH});

  @override
  Widget build(BuildContext context) {
    final f = store.forecast;
    final preg = store.pregnancy != null;
    final showFert = store.calShow('fertility') && !preg;
    final lead = month.weekday - 1;
    final start = addDays(month, -lead);
    final t = today();
    _Grp g(DateTime d) {
      final k = f.kindOf(d);
      if (preg && k != DayKind.period) return _Grp.none;
      return _grp(k, showFert);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion(context, 650),
      curve: Curves.easeOutCubic,
      builder: (context, prog, _) => Column(children: [
        for (var r = 0; r < 6; r++)
          _WeekRow(
            days: [for (var c = 0; c < 7; c++) addDays(start, r * 7 + c)],
            month: month.month,
            groups: [for (var c = 0; c < 7; c++) g(addDays(start, r * 7 + c))],
            prevGroup: g(addDays(start, r * 7 - 1)),
            nextGroup: g(addDays(start, r * 7 + 7)),
            today: t,
            f: f,
            store: store,
            progress: prog,
            onTap: onTap,
            preg: preg,
            cellH: cellH,
          ),
      ]),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final List<DateTime> days;
  final int month;
  final List<_Grp> groups;
  final _Grp prevGroup;
  final _Grp nextGroup;
  final DateTime today;
  final Forecast f;
  final Store store;
  final double progress;
  final void Function(DateTime) onTap;
  final bool preg;
  final double cellH;

  const _WeekRow({
    required this.cellH,
    required this.days,
    required this.month,
    required this.groups,
    required this.prevGroup,
    required this.nextGroup,
    required this.today,
    required this.f,
    required this.store,
    required this.progress,
    required this.onTap,
    required this.preg,
  });

  double get _mark => cellH * 0.84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final b = theme.brightness;
    final showIntim = store.calShow('intimacy');
    final showPill = store.calShow('pill');
    return SizedBox(
      height: cellH,
      child: CustomPaint(
        painter: _CapsulePainter(
          groups: groups,
          ovulation: [
            for (final d in days)
              !preg && store.calShow('fertility') && f.kindOf(d) == DayKind.ovulation
          ],
          prevGroup: prevGroup,
          nextGroup: nextGroup,
          progress: progress,
          ovColor: Palette.ovulation(b),
          h: _mark,
        ),
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: _cell(context, i, c, showIntim, showPill)),
        ]),
      ),
    );
  }

  Widget _cell(BuildContext context, int i, AppColors c, bool showIntim,
      bool showPill) {
    final theme = Theme.of(context);
    final d = days[i];
    final inMonth = d.month == month;
    final isToday = d == today;
    final grp = groups[i];
    final data = store.day(d);
    final isOv = f.kindOf(d) == DayKind.ovulation && store.calShow('fertility') && !preg;
    Color textColor = inMonth ? theme.colorScheme.onSurface : c.muted.withValues(alpha: 0.6);
    if (grp == _Grp.period || isOv) textColor = Colors.white;
    final markers = <Widget>[
      if (showIntim && data.intimacy.isNotEmpty)
        const Icon(Icons.favorite, size: 9, color: Palette.intimacy),
      if (showPill && data.pill) _dot(Palette.pill),
      if (data.note.trim().isNotEmpty || data.symptoms.isNotEmpty || data.moods.isNotEmpty)
        _dot(grp == _Grp.period ? Colors.white70 : c.muted),
      if (!preg && f.isPms(d) && store.calShow('fertility') && grp == _Grp.none)
        _dot(Palette.pms),
    ];
    return Semantics(
      button: true,
      label: '${d.day} ${monthsGen[d.month - 1]}${isToday ? ', сегодня' : ''}',
      excludeSemantics: true,
      child: InkResponse(
        radius: cellH * 0.5,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(d);
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          store.patchDay(d, {'p': !store.isPeriod(d)});
        },
        child: Stack(alignment: Alignment.center, children: [
          if (isToday)
            AnimatedContainer(
              duration: motion(context, 300),
              width: _mark,
              height: _mark,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: grp == _Grp.period ? Colors.transparent : Palette.today,
                border: grp == _Grp.period
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
              ),
            ),
          Text('${d.day}',
              style: TextStyle(
                fontFamily: kFont,
                fontSize: (cellH * 0.37).clamp(13.0, 18.0),
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday && grp != _Grp.period ? Colors.white : textColor,
              )),
          if (markers.isNotEmpty)
            Positioned(
              bottom: cellH * 0.07,
              child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in markers.take(3))
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: m)
                  ]),
            ),
        ]),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 5, height: 5, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class _CapsulePainter extends CustomPainter {
  final List<_Grp> groups;
  final List<bool> ovulation;
  final _Grp prevGroup;
  final _Grp nextGroup;
  final double progress;
  final Color ovColor;
  final double h;

  _CapsulePainter({
    required this.h,
    required this.groups,
    required this.ovulation,
    required this.prevGroup,
    required this.nextGroup,
    required this.progress,
    required this.ovColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / 7;
    final top = (size.height - h) / 2;
    var i = 0;
    while (i < 7) {
      final g = groups[i];
      if (g == _Grp.none) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < 7 && groups[j + 1] == g) {
        j++;
      }
      final openLeft = i == 0 && prevGroup == g;
      final openRight = j == 6 && nextGroup == g;
      final x0 = openLeft ? -h : i * cw + 3;
      final fullX1 = openRight ? size.width + h : (j + 1) * cw - 3;
      // капсула «вырастает» слева направо
      final x1 = x0 + (fullX1 - x0) * progress;
      final rect = RRect.fromLTRBR(
          x0, top, x1 < x0 + h ? x0 + h * progress : x1, top + h,
          const Radius.circular(h / 2));
      final double opacity =
          progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress);
      switch (g) {
        case _Grp.period:
          canvas.drawRRect(
              rect, Paint()..color = Palette.period.withValues(alpha: opacity));
        case _Grp.predicted:
          canvas.drawRRect(
              rect.deflate(1.2),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..color = Palette.predicted.withValues(alpha: opacity));
        case _Grp.fertile:
          canvas.drawRRect(
              rect.deflate(1.2),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..color = Palette.fertile.withValues(alpha: opacity));
        case _Grp.none:
          break;
      }
      i = j + 1;
    }
    for (var k = 0; k < 7; k++) {
      if (!ovulation[k]) continue;
      final cx = k * cw + cw / 2;
      canvas.drawCircle(Offset(cx, size.height / 2), (h / 2 - 3) * progress,
          Paint()..color = ovColor);
    }
  }

  @override
  bool shouldRepaint(_CapsulePainter o) =>
      o.progress != progress ||
      o.h != h ||
      o.prevGroup != prevGroup ||
      o.nextGroup != nextGroup ||
      o.ovColor != ovColor ||
      !_eq(o.groups, groups) ||
      !_eqb(o.ovulation, ovulation);

  static bool _eq(List<_Grp> a, List<_Grp> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _eqb(List<bool> a, List<bool> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
