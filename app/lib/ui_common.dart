import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import 'cycle.dart';

const monthsNom = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'
];
const monthsGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];
const monthsShort = [
  'янв.', 'февр.', 'март', 'апр.', 'май', 'июнь',
  'июль', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'
];
const weekdaysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
const weekdaysFull = [
  'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота',
  'воскресенье'
];

String fmtDate(DateTime d, {bool year = false}) =>
    '${d.day} ${monthsGen[d.month - 1]}${year ? ' ${d.year}' : ''}';

String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

// неразрывный пробел: «5 дней» не разрывается между строк
String daysWord(int n) => '$n ${plural(n, 'день', 'дня', 'дней')}';

/// Шрифт приложения — Nunito (мягкий, округлый).
const kFont = 'Nunito';

/// Смысловые цвета календаря — одинаковые во всех темах.
class Palette {
  static const period = Color(0xFFC24D76); // отмеченные месячные
  static const predicted = Color(0xFFE88FAA); // прогноз месячных (контур)
  static const fertile = Color(0xFF9C9AE0); // фертильные дни (контур)
  static const ovulationDark = Color(0xFF555BA0);
  static const ovulationLight = Color(0xFF8C92E2);
  static const today = Color(0xFFE47C9D);
  static const pms = Color(0xFFE88FAA);
  static const intimacy = Color(0xFFE0456E);
  static const pill = Color(0xFF8EA7E9);

  static Color ovulation(Brightness b) =>
      b == Brightness.dark ? ovulationDark : ovulationLight;
}

Color? kindColor(DayKind k, [Brightness b = Brightness.dark]) => switch (k) {
      DayKind.period => Palette.period,
      DayKind.predicted => Palette.predicted,
      DayKind.fertile => Palette.fertile,
      DayKind.ovulation => Palette.ovulation(b),
      DayKind.none => null,
    };

/// Тема оформления: картинка в шапке, цвет кольца, акцент.
class AppThemeSpec {
  final String id;
  final String name;
  final String? asset;
  final Color ring;
  final Color accent;
  final Color headerDark;
  final Color headerLight;
  const AppThemeSpec(this.id, this.name, this.asset, this.ring, this.accent,
      this.headerDark, this.headerLight);
}

const appThemes = <AppThemeSpec>[
  AppThemeSpec('cats', 'Котики', 'assets/themes/cats.webp', Color(0xFFD2A679),
      Color(0xFF8EA7E9), Color(0xFF232326), Color(0xFFF1ECE6)),
  AppThemeSpec('night', 'Ночное небо', 'assets/themes/night.webp',
      Color(0xFFE8A0B4), Color(0xFFA99BEA), Color(0xFF1E1F33), Color(0xFFE7E5F4)),
  AppThemeSpec('flowers', 'Цветы', 'assets/themes/flowers.webp',
      Color(0xFFD46A8C), Color(0xFFE58FA7), Color(0xFF2A2327), Color(0xFFFBEFF3)),
  AppThemeSpec('bunnies', 'Зайчики', 'assets/themes/bunnies.webp',
      Color(0xFFE7B7C4), Color(0xFFC6A3E2), Color(0xFF292628), Color(0xFFF7EEF1)),
  AppThemeSpec('leaves', 'Листья', 'assets/themes/leaves.webp',
      Color(0xFF8FB59A), Color(0xFF7FB59E), Color(0xFF1E2421), Color(0xFFEAF2EC)),
  AppThemeSpec('shapes', 'Формы', 'assets/themes/shapes.webp',
      Color(0xFFE39B6B), Color(0xFFE39B6B), Color(0xFF2B2523), Color(0xFFF6ECE3)),
  AppThemeSpec('plain', 'Без рисунка', null, Color(0xFF8EA7E9),
      Color(0xFF8EA7E9), Color(0xFF232326), Color(0xFFF4F3F7)),
];

AppThemeSpec themeById(String id) =>
    appThemes.firstWhere((t) => t.id == id, orElse: () => appThemes.first);

/// Доступ к текущей теме из любого виджета.
class ThemeSpecScope extends InheritedWidget {
  final AppThemeSpec spec;
  const ThemeSpecScope({super.key, required this.spec, required super.child});

  static AppThemeSpec of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeSpecScope>()?.spec ??
      appThemes.first;

  @override
  bool updateShouldNotify(ThemeSpecScope old) => old.spec.id != spec.id;
}

/// Дополнительные цвета, которых нет в ColorScheme.
class AppColors extends ThemeExtension<AppColors> {
  final Color card;
  final Color cardBorder;
  final Color muted;
  final Color header;
  const AppColors(this.card, this.cardBorder, this.muted, this.header);

  static AppColors of(BuildContext c) => Theme.of(c).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      Color.lerp(card, other.card, t)!,
      Color.lerp(cardBorder, other.cardBorder, t)!,
      Color.lerp(muted, other.muted, t)!,
      Color.lerp(header, other.header, t)!,
    );
  }
}

/// Длительность анимации с учётом системной настройки «убрать анимации».
Duration motion(BuildContext context, int ms) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true
        ? Duration.zero
        : Duration(milliseconds: ms);

ThemeData buildTheme(Brightness b, AppThemeSpec spec) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF222225) : const Color(0xFFF6F5F8);
  final card = dark ? const Color(0xFF2B2B2F) : Colors.white;
  final border = dark ? const Color(0xFF3A3A40) : const Color(0xFFE4E2E8);
  final fg = dark ? const Color(0xFFF2F2F5) : const Color(0xFF242428);
  final muted = dark ? const Color(0xFFA1A1AA) : const Color(0xFF72717A);
  final accent = spec.accent;
  final onAccent = const Color(0xFF1B1B22);

  final scheme =
      ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: accent,
    onPrimary: onAccent,
    secondary: spec.ring,
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: muted,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: dark ? const Color(0xFF2F2F34) : const Color(0xFFF0EEF3),
    surfaceContainerHigh: dark ? const Color(0xFF36363C) : const Color(0xFFE9E7EE),
    surfaceContainerHighest:
        dark ? const Color(0xFF3E3E45) : const Color(0xFFE1DFE7),
    outline: border,
    outlineVariant: border,
    error: const Color(0xFFE5566F),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    fontFamily: kFont,
    scaffoldBackgroundColor: bg,
    splashFactory: InkSparkle.splashFactory,
  );
  final t = base.textTheme;
  final text = t.copyWith(
    displayLarge: t.displayLarge?.copyWith(
        fontWeight: FontWeight.w300, fontSize: 72, height: 1, letterSpacing: -1),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 21),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
    bodyLarge: t.bodyLarge?.copyWith(fontSize: 16.5, height: 1.35),
    bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
  );

  return base.copyWith(
    textTheme: text,
    extensions: [
      AppColors(card, border, muted, dark ? spec.headerDark : spec.headerLight)
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: kFont, fontSize: 22, fontWeight: FontWeight.w700, color: fg),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        minimumSize: const Size(64, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        minimumSize: const Size(64, 54),
        side: BorderSide(color: border),
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
            fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : (dark ? Colors.white : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
          ? accent.withValues(alpha: 0.45)
          : (dark ? const Color(0xFF3A3A40) : const Color(0xFFD9D7DE))),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : muted),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent),
      checkColor: WidgetStateProperty.all(onAccent),
      shape: const CircleBorder(),
      side: BorderSide(color: muted, width: 1.6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: fg.withValues(alpha: 0.25),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: TextStyle(
          fontFamily: kFont, fontSize: 21, fontWeight: FontWeight.w700, color: fg),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: card,
      headerForegroundColor: fg,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFF2F2F5) : const Color(0xFF2B2B2F),
      contentTextStyle: TextStyle(
          fontFamily: kFont,
          color: dark ? const Color(0xFF222225) : Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: muted,
      indicatorColor: accent,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(
          fontFamily: kFont, fontSize: 18, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(
          fontFamily: kFont, fontSize: 18, fontWeight: FontWeight.w600),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: accent, width: 4),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        insets: const EdgeInsets.symmetric(horizontal: 18),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: accent,
      titleTextStyle: TextStyle(
          fontFamily: kFont, fontSize: 17, fontWeight: FontWeight.w600, color: fg),
      subtitleTextStyle:
          TextStyle(fontFamily: kFont, fontSize: 14.5, color: muted, height: 1.3),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SharedAxisPageTransitionsBuilder(
          transitionType: SharedAxisTransitionType.horizontal),
    }),
  );
}
