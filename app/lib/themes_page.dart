import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'store.dart';
import 'ui_common.dart';
import 'widgets_common.dart';

class ThemesPage extends StatelessWidget {
  final Store store;
  const ThemesPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Center(child: Text('Темы', style: theme.appBarTheme.titleTextStyle)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                title: Text('Тёмный режим', style: theme.textTheme.titleLarge),
                value: store.dark,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  store.setLocal('dark', v);
                },
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (var i = 0; i < appThemes.length; i++)
                    Stagger(
                      index: i,
                      child: _ThemeCard(
                        spec: appThemes[i],
                        selected: store.themeId == appThemes[i].id,
                        dark: store.dark,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          store.setLocal('theme', appThemes[i].id);
                          store.setLocal('ringColor', appThemes[i].ring.toARGB32());
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeSpec spec;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  const _ThemeCard(
      {required this.spec,
      required this.selected,
      required this.dark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      child: Column(children: [
        Expanded(
          child: AnimatedContainer(
            duration: motion(context, 250),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? theme.colorScheme.primary : AppColors.of(context).cardBorder,
                  width: selected ? 3 : 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: dark ? spec.headerDark : spec.headerLight),
                if (spec.asset != null)
                  Image.asset(spec.asset!, fit: BoxFit.cover, alignment: Alignment.topLeft),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 46,
                  child: ClipPath(
                    clipper: _Wave(),
                    child: Container(color: spec.ring),
                  ),
                ),
                Center(
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: motion(context, 300),
                    curve: Curves.easeOutBack,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.check, color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(spec.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }
}

class _Wave extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, s.height * 0.55)
    ..cubicTo(s.width * 0.3, s.height * 0.05, s.width * 0.65, s.height * 0.6,
        s.width, s.height * 0.1)
    ..lineTo(s.width, s.height)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(_Wave old) => false;
}
