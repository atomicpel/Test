import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'day_entry.dart';
import 'ui_common.dart';

/// Пружинит при нажатии: чуть сжимается и возвращается.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.scale = 0.94});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: motion(context, _down ? 90 : 260),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

/// Карточка с рамкой, как в оригинале.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final body = Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cardBorder),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          borderRadius: BorderRadius.circular(18), onTap: onTap, child: body),
    );
  }
}

/// Заголовок раздела с действием справа («Показать все ›»).
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 8, 6),
      child: Row(children: [
        Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(action!),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 22),
            ]),
          ),
      ]),
    );
  }
}

/// Круглая плитка с эмодзи и подписью. При выборе — подсветка и «прыжок».
class OptionTile extends StatefulWidget {
  final Opt opt;
  final bool selected;
  final VoidCallback onTap;
  final double size;
  const OptionTile(
      {super.key,
      required this.opt,
      required this.selected,
      required this.onTap,
      this.size = 64});

  @override
  State<OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<OptionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(OptionTile old) {
    super.didUpdateWidget(old);
    if (!old.selected && widget.selected &&
        MediaQuery.maybeDisableAnimationsOf(context) != true) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final accent = theme.colorScheme.primary;
    final s = widget.size;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.opt.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: SizedBox(
          width: s + 30,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: _pop,
              builder: (context, child) {
                final v = _pop.value;
                final sc = 1 + 0.22 * math.sin(math.pi * v) * (1 - v * 0.5);
                return Transform.scale(scale: sc, child: child);
              },
              child: Stack(clipBehavior: Clip.none, children: [
                AnimatedContainer(
                  duration: motion(context, 220),
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected
                        ? accent.withValues(alpha: 0.22)
                        : theme.colorScheme.surfaceContainer,
                    border: Border.all(
                        color: widget.selected ? accent : c.cardBorder,
                        width: widget.selected ? 2.5 : 1),
                  ),
                  alignment: Alignment.center,
                  child: Text(widget.opt.emoji,
                      style: TextStyle(fontSize: s * 0.46)),
                ),
                Positioned(
                  right: -2,
                  top: -2,
                  child: AnimatedScale(
                    scale: widget.selected ? 1 : 0,
                    duration: motion(context, 260),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: theme.scaffoldBackgroundColor, width: 2)),
                      child: Icon(Icons.check,
                          size: 14, color: theme.colorScheme.onPrimary),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              widget.opt.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.selected
                      ? theme.colorScheme.onSurface
                      : c.muted),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Капли обильности 1..4: заполняются по очереди с анимацией.
class FlowDrops extends StatelessWidget {
  final int value;
  final ValueChanged<int>? onChanged;
  final double size;
  const FlowDrops(
      {super.key, required this.value, this.onChanged, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 4; i++)
        Semantics(
          button: onChanged != null,
          label: flowLabels[i - 1],
          selected: value >= i,
          child: Pressable(
            onTap: onChanged == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onChanged!(value == i ? 0 : i);
                  },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.08),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: value >= i ? 1.0 : 0.0),
                duration: motion(context, 260 + i * 60),
                curve: Curves.easeOutBack,
                builder: (context, v, _) => CustomPaint(
                  size: Size(size * 0.72, size),
                  painter: _DropPainter(v, Palette.period, c.muted),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _DropPainter extends CustomPainter {
  final double fill;
  final Color color;
  final Color empty;
  _DropPainter(this.fill, this.color, this.empty);

  Path _drop(Size s) {
    final w = s.width, h = s.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.62, h * 0.22, w, h * 0.45, w, h * 0.66)
      ..arcToPoint(Offset(0, h * 0.66),
          radius: Radius.circular(w / 2), clockwise: true)
      ..cubicTo(0, h * 0.45, w * 0.38, h * 0.22, w / 2, 0)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _drop(size);
    canvas.drawPath(p, Paint()..color = empty.withValues(alpha: 0.35));
    if (fill > 0) {
      canvas.save();
      canvas.clipPath(p);
      final top = size.height * (1 - fill.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTRB(0, top, size.width, size.height),
          Paint()..color = color);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DropPainter o) => o.fill != fill || o.color != color;
}

/// Строка с цветной точкой (легенда, пояснения).
class DotLabel extends StatelessWidget {
  final Color color;
  final String text;
  final bool outline;
  const DotLabel(this.color, this.text, {super.key, this.outline = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: outline ? Colors.transparent : color,
          border: outline ? Border.all(color: color, width: 2.2) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(text, style: theme.textTheme.bodyMedium),
    ]);
  }
}

/// Страница с плавным появлением содержимого (каскадом).
class Stagger extends StatelessWidget {
  final int index;
  final Widget child;
  const Stagger({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final d = motion(context, 380 + 60 * math.min(index, 8));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: d,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
